import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expense_tracker/services/database_service.dart';
import 'package:expense_tracker/models/treasure_jar.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/models/monthly_analysis.dart';
import 'package:expense_tracker/models/budget_alert.dart';
import 'package:expense_tracker/widgets/dashboard_spending_chart.dart';

void main() {
  late Directory folder;
  late Database db;
  final service = DatabaseService();
  const owner = 'jar-test-owner';
  final account = AppAccount(
      id: 'bank',
      name: 'Bank',
      kind: AccountKind.asset,
      subtype: AccountSubtype.bank,
      openingBalance: 100,
      currentBalance: 100,
      icon: 'B',
      colorValue: 0xFF000000);
  TreasureJar jar(String id, {String accountId = 'bank'}) => TreasureJar(
      id: id,
      name: id,
      accountId: accountId,
      targetCents: 50000,
      savedCents: 0);
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    folder = await Directory.systemTemp.createTemp('spendly-jars-test-');
    await databaseFactory.setDatabasesPath(folder.path);
    db = await service.database;
  });
  tearDownAll(() async {
    await db.close();
    if (folder.path.startsWith(Directory.systemTemp.path))
      await folder.delete(recursive: true);
  });
  setUp(() async {
    for (final table in [
      'jar_notifications',
      'jar_activity',
      'treasure_jars',
      'transactions',
      'accounts'
    ]) {
      await db.delete(table);
    }
    await service.insertAccount(account, userId: owner);
  });
  test(
      'failed deletion rolls back reservation and notice; foreign owners cannot release it',
      () async {
    await service.saveJar(jar('safe'), owner);
    await service.adjustJar('safe', owner, 2500);
    await service.deleteJar('safe', 'other-owner');
    expect((await service.getJars(owner)).single.savedCents, 2500);
    expect(await service.jarNotifications(owner), isEmpty);
    await db.execute(
        "CREATE TRIGGER fail_jar_delete BEFORE DELETE ON treasure_jars BEGIN SELECT RAISE(ABORT, 'failure'); END");
    try {
      await expectLater(
          service.deleteJar('safe', owner), throwsA(isA<DatabaseException>()));
      expect((await service.getJars(owner)).single.savedCents, 2500);
      expect(await service.jarNotifications(owner), isEmpty);
      expect(
          (await service.getAccounts(userId: owner))
              .firstWhere((a) => a.id == 'bank')
              .currentBalance,
          100);
    } finally {
      await db.execute('DROP TRIGGER fail_jar_delete');
    }
  });
  test(
      'reservations and releases persist without creating expenses or changing bank balance',
      () async {
    await service.saveJar(jar('holiday'), owner);
    await service.adjustJar('holiday', owner, 3000);
    expect((await service.getJars(owner)).single.savedCents, 3000);
    expect(
        (await service.getAccounts(userId: owner))
            .firstWhere((a) => a.id == 'bank')
            .currentBalance,
        100);
    expect(await service.getAllTransactions(userId: owner), isEmpty);
    await service.adjustJar('holiday', owner, -1000);
    expect((await service.getJars(owner)).single.savedCents, 2000);
    expect((await service.jarHistory('holiday', owner)).length, 2);
    expect(await service.getJars('someone-else'), isEmpty);
    await expectLater(
        service.adjustJar('holiday', 'someone-else', 100), throwsStateError);

    await service.deleteJar('holiday', owner);
    expect(await service.getJars(owner), isEmpty);
    expect(
        (await service.getAccounts(userId: owner))
            .firstWhere((a) => a.id == 'bank')
            .currentBalance,
        100);
    expect(await service.getAllTransactions(userId: owner), isEmpty);
    final notices = await service.jarNotifications(owner);
    expect(notices.single['message'], contains('RM 20.00 released to Bank'));
    expect(notices.single['isRead'], 0);
    expect(await service.jarNotifications('someone-else'), isEmpty);
    await service.deleteJar('holiday', owner);
    expect((await service.jarNotifications(owner)).length, 1);
    await service.readJarNotification(
        notices.single['id'] as String, 'someone-else');
    expect((await service.jarNotifications(owner)).single['isRead'], 0);
    await service.readJarNotification(notices.single['id'] as String, owner);
    expect((await service.jarNotifications(owner)).single['isRead'], 1);
  });
  test(
      'all jars share available funds and concurrent reservations cannot overdraw',
      () async {
    await service.saveJar(jar('a'), owner);
    await service.saveJar(jar('b'), owner);
    final outcomes = await Future.wait(['a', 'b'].map((id) async {
      try {
        await service.adjustJar(id, owner, 7000);
        return true;
      } on StateError {
        return false;
      }
    }));
    expect(outcomes.where((v) => v).length, 1);
    expect(
        (await service.getJars(owner)).fold<int>(0, (s, j) => s + j.savedCents),
        7000);
    final funded =
        (await service.getJars(owner)).firstWhere((j) => j.savedCents > 0);
    await expectLater(
        service.adjustJar(funded.id, owner, -7001), throwsStateError);
    await expectLater(
        service.deleteAccount('bank', userId: owner), throwsStateError);
    expect(
        (await service.getAccounts(userId: owner))
            .firstWhere((a) => a.id == 'bank')
            .currentBalance,
        100);
  });
  test(
      'jar source must be owned; editing a goal cannot overwrite reserved money',
      () async {
    await expectLater(
        service.saveJar(jar('bad'), 'someone-else'), throwsStateError);
    await service.saveJar(jar('a'), owner);
    await service.adjustJar('a', owner, 1000);
    await service.saveJar(
        TreasureJar(
            id: 'a',
            name: 'Renamed',
            accountId: 'bank',
            targetCents: 60000,
            savedCents: 999999),
        owner);
    expect((await service.getJars(owner)).single.savedCents, 1000);
  });
  test(
      'receipt total counts once; item notes and manual transactions reconcile across views',
      () async {
    final parent = TransactionModel(
        id: 'receipt',
        title: 'Bataras',
        amount: 46.5,
        type: TransactionType.expense,
        category: TransactionCategory.groceries,
        date: DateTime(2026, 10, 21),
        note: '1. Eggs (RM20)\n2. Mushrooms (RM7)\nTotal RM46.50',
        receiptImagePath: 'saved-receipt.jpg');
    await service.insertTransaction(parent, userId: owner);
    await service.insertTransaction(parent,
        userId: owner); // Same saved record, not a new ledger item.
    await service.insertTransaction(
        TransactionModel(
            id: 'manual',
            title: 'Fruit',
            amount: 7,
            type: TransactionType.expense,
            category: TransactionCategory.groceries,
            date: DateTime(2026, 10, 21)),
        userId: owner);
    final rows = await service.getAllTransactions(userId: owner);
    expect(rows.length, 2);
    final analysis = MonthlyAnalysis(rows, DateTime(2026, 10));
    expect(analysis.expense, 53.5);
    expect(
        analysis.categoryTotals.values.fold<double>(0, (s, c) => s + c.amount),
        53.5);
    expect(analysis.days[21]!.expense, 53.5);
    expect(
        spendingSeries(rows, anchor: DateTime(2026, 10, 21), yearly: false)
            .last,
        53.5);
    expect(spendingSeries(rows, anchor: DateTime(2026), yearly: true)[9], 53.5);
    expect(
        BudgetAlert.evaluate([
          BudgetModel(
              id: 'g',
              category: TransactionCategory.groceries,
              limit: 50,
              month: DateTime(2026, 10))
        ], rows)
            .single
            .spent,
        53.5);
  });
  test(
      'weekly totals cross month boundaries and yearly totals exclude other years and income',
      () {
    TransactionModel row(String id, DateTime date, double amount,
            {TransactionType type = TransactionType.expense}) =>
        TransactionModel(
            id: id,
            title: id,
            amount: amount,
            type: type,
            category: TransactionCategory.groceries,
            date: date);
    final rows = [
      row('a', DateTime(2026, 9, 30), 10),
      row('b', DateTime(2026, 10, 1), 20),
      row('c', DateTime(2025, 10, 1), 100),
      row('d', DateTime(2026, 10, 1), 1000, type: TransactionType.income)
    ];
    expect(
        spendingSeries(rows, anchor: DateTime(2026, 10, 2), yearly: false)
            .reduce((a, b) => a + b),
        30);
    expect(
        spendingSeries(rows, anchor: DateTime(2026), yearly: true)
            .reduce((a, b) => a + b),
        30);
  });
}
