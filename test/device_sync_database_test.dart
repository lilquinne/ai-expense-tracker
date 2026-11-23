import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expense_tracker/services/database_service.dart';
import 'package:expense_tracker/services/sync_merge.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/models/treasure_jar.dart';

void main() {
  late Directory folder;
  late Database db;
  final service = DatabaseService();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    folder = await Directory.systemTemp.createTemp('spendly-device-sync-');
    await databaseFactory.setDatabasesPath(folder.path);
    db = await service.database;
  });
  tearDownAll(() async {
    await db.close();
    await folder.delete(recursive: true);
  });
  setUp(() async {
    for (final table in [
      ...syncTables.reversed,
      'device_sync_state',
      'device_sync_backups',
      'pending_transaction_deletes'
    ]) {
      await db.delete(table, where: 'userId = ?', whereArgs: ['owner']);
    }
    await service.insertAccount(
        const AppAccount(
            id: 'bank',
            name: 'Bank',
            kind: AccountKind.asset,
            subtype: AccountSubtype.bank,
            openingBalance: 100,
            currentBalance: 100,
            icon: 'B',
            colorValue: 0),
        userId: 'owner');
  });
  test(
      'import updates totals exactly once, preserves receipt path and saves backup',
      () async {
    final tx = TransactionModel(
        id: 'expense',
        title: 'Groceries',
        amount: 10,
        type: TransactionType.expense,
        category: TransactionCategory.groceries,
        accountId: 'bank',
        date: DateTime(2026, 10, 27),
        receiptImagePath: '/phone/receipt.jpg');
    await service.saveConfirmedTransaction(tx, userId: 'owner');
    final captured = await service.exportSyncData('owner');
    expect(captured['transactions']!.single.containsKey('receiptImagePath'),
        false);
    final accepted = decodeSyncData(captured);
    accepted['transactions']!.single['title'] = 'Updated title';
    await service.applySyncData('owner', captured, accepted,
        ownsSession: () => true);
    await service.applySyncData('owner', accepted, accepted,
        ownsSession: () => true);
    final rows = await service.getAllTransactions(userId: 'owner');
    expect(rows.single.title, 'Updated title');
    expect(rows.single.receiptImagePath, '/phone/receipt.jpg');
    expect(
        (await service.getAccounts(userId: 'owner'))
            .firstWhere((a) => a.id == 'bank')
            .currentBalance,
        90);
    expect(
        (await db.query('device_sync_backups',
                where: 'userId = ?', whereArgs: ['owner']))
            .length,
        1);
  });
  test('jar history uses portable unique IDs and does not replay reservations',
      () async {
    await service.saveJar(
        const TreasureJar(
            id: 'jar',
            name: 'Trip',
            accountId: 'bank',
            targetCents: 10000,
            savedCents: 0),
        'owner');
    await service.adjustJar('jar', 'owner', 500);
    final captured = await service.exportSyncData('owner');
    expect(captured['jar_activity']!.single['id'], isA<String>());
    await service.applySyncData('owner', captured, captured,
        ownsSession: () => true);
    expect((await service.getJars('owner')).single.savedCents, 500);
    expect(
        (await service.jarHistory('jar', 'owner')).single['amountCents'], 500);
    expect(
        (await service.exportSyncData('owner'))['jar_activity']!.single['id'],
        captured['jar_activity']!.single['id']);
  });
  test('foreign record IDs and switched sessions rollback the complete import',
      () async {
    await db.insert('accounts', {
      'id': 'foreign',
      'userId': 'other',
      'name': 'Private',
      'kind': 0,
      'subtype': 0,
      'openingBalance': 5,
      'currentBalance': 5,
      'icon': 'B',
      'colorValue': 0
    });
    final captured = await service.exportSyncData('owner');
    final incoming = decodeSyncData(captured);
    incoming['accounts']!
        .add({...captured['accounts']!.single, 'id': 'foreign'});
    await expectLater(
        service.applySyncData('owner', captured, incoming,
            ownsSession: () => true),
        throwsStateError);
    expect(
        sameSyncValue(await service.exportSyncData('owner'), captured), true);
    expect(
        (await db.query('accounts', where: 'id = ?', whereArgs: ['foreign']))
            .single['userId'],
        'other');
    await expectLater(
        service.applySyncData('owner', captured, captured,
            ownsSession: () => false),
        throwsStateError);
    expect(await service.syncBaseline('owner'), isNull);
  });
  test('writes made during a cloud request survive the import', () async {
    final captured = await service.exportSyncData('owner');
    await service.saveConfirmedTransaction(
        TransactionModel(
            id: 'new',
            title: 'New',
            amount: 5,
            type: TransactionType.expense,
            category: TransactionCategory.groceries,
            accountId: 'bank',
            date: DateTime(2026, 10, 27)),
        userId: 'owner');
    expect(
        await service.applySyncData('owner', captured, captured,
            ownsSession: () => true),
        true);
    expect(
        (await service.getAllTransactions(userId: 'owner')).single.id, 'new');
    expect(
        (await service.getAccounts(userId: 'owner'))
            .firstWhere((a) => a.id == 'bank')
            .currentBalance,
        95);
  });
}
