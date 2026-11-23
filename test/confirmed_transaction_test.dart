import 'package:expense_tracker/models/split_bill.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:expense_tracker/services/supabase_sync_service.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expense_tracker/services/database_service.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/providers/expense_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = DatabaseService();
  late Directory folder;
  late Database db;
  const owner = 'confirmed-owner';
  TransactionModel expense(String id,
          {double amount = 10, String account = 'bank'}) =>
      TransactionModel(
          id: id,
          title: 'Shop',
          amount: amount,
          type: TransactionType.expense,
          category: TransactionCategory.groceries,
          accountId: account,
          date: DateTime(2026, 1, 12),
          note: '1. Eggs (RM7)\n2. Milk (RM3)');
  Future<double> balance(String id) async =>
      ((await db.query('accounts', where: 'id = ?', whereArgs: [id]))
              .single['currentBalance'] as num)
          .toDouble();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    folder = await Directory.systemTemp.createTemp('spendly-confirmed-test-');
    await databaseFactory.setDatabasesPath(folder.path);
    db = await service.database;
  });
  tearDownAll(() async {
    await db.close();
    if (folder.path.startsWith(Directory.systemTemp.path)) {
      await folder.delete(recursive: true);
    }
  });
  setUp(() async {
    await db.delete('transactions');
    await db.delete('accounts');
    for (final id in ['bank', 'second', 'credit']) {
      await service.insertAccount(
          AppAccount(
              id: id,
              name: id,
              kind: id == 'credit' ? AccountKind.liability : AccountKind.asset,
              subtype: AccountSubtype.bank,
              openingBalance: 100,
              currentBalance: 100,
              icon: 'B',
              colorValue: 0),
          userId: owner);
    }
  });
  test('one parent save changes balance once; same-ID replay is idempotent',
      () async {
    await service.saveConfirmedTransaction(expense('receipt'), userId: owner);
    await service.saveConfirmedTransaction(expense('receipt'), userId: owner);
    expect(await balance('bank'), 90);
    expect((await service.getAllTransactions(userId: owner)).length, 1);
    await expectLater(
        service.saveConfirmedTransaction(expense('receipt', amount: 20),
            userId: owner),
        throwsStateError);
    expect(await balance('bank'), 90);
  });
  test('edit reverses original account and deletion reverses only once',
      () async {
    await service.saveConfirmedTransaction(expense('a'), userId: owner);
    await service.saveConfirmedTransaction(
        expense('a', amount: 25, account: 'second').copyWith(
            date: DateTime(2026, 10, 22),
            category: TransactionCategory.shopping),
        userId: owner,
        editing: true);
    expect(await balance('bank'), 100);
    expect(await balance('second'), 75);
    await service.deleteConfirmedTransaction('a', userId: owner);
    await service.deleteConfirmedTransaction('a', userId: owner);
    expect(await balance('second'), 100);
  });
  test('SQLite failure rolls back balance and ledger together', () async {
    await db.execute(
        "CREATE TRIGGER reject_test BEFORE INSERT ON transactions BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    try {
      await expectLater(
          service.saveConfirmedTransaction(expense('a'), userId: owner),
          throwsA(isA<DatabaseException>()));
      expect(await balance('bank'), 100);
      expect(await service.getAllTransactions(userId: owner), isEmpty);
    } finally {
      await db.execute('DROP TRIGGER reject_test');
    }
  });
  test('failed edit and delete restore original persisted state', () async {
    await service.saveConfirmedTransaction(expense('a'), userId: owner);
    for (final operation in ['UPDATE', 'DELETE']) {
      await db.execute(
          "CREATE TRIGGER reject_test BEFORE $operation ON transactions BEGIN SELECT RAISE(ABORT, 'test failure'); END");
      try {
        await expectLater(
            operation == 'UPDATE'
                ? service.saveConfirmedTransaction(expense('a', amount: 40),
                    userId: owner, editing: true)
                : service.deleteConfirmedTransaction('a', userId: owner),
            throwsA(isA<DatabaseException>()));
        expect(await balance('bank'), 90);
        expect((await service.getAllTransactions(userId: owner)).single.amount,
            10);
      } finally {
        await db.execute('DROP TRIGGER reject_test');
      }
    }
  });
  test(
      'validates owner, account, amount and transaction category before writing',
      () async {
    for (final amount in <double>[
      double.nan,
      double.infinity,
      -1,
      0,
      .001,
      100000001
    ]) {
      await expectLater(
          service.saveConfirmedTransaction(expense('bad', amount: amount),
              userId: owner),
          throwsArgumentError);
    }
    await expectLater(
        service.saveConfirmedTransaction(expense('bad', account: 'missing'),
            userId: owner),
        throwsStateError);
    await expectLater(
        service.saveConfirmedTransaction(expense('bad'), userId: 'other'),
        throwsStateError);
    await expectLater(
        service.saveConfirmedTransaction(
            expense('bad').copyWith(category: TransactionCategory.salary),
            userId: owner),
        throwsArgumentError);
    expect(await balance('bank'), 100);
    expect(await service.getAllTransactions(userId: owner), isEmpty);
  });
  test('liability signs and manual income preserve existing account semantics',
      () async {
    await service.saveConfirmedTransaction(expense('a', account: 'credit'),
        userId: owner);
    expect(await balance('credit'), 110);
    await service.saveConfirmedTransaction(
        expense('income').copyWith(
            type: TransactionType.income, category: TransactionCategory.salary),
        userId: owner);
    expect(await balance('bank'), 110);
    await service.deleteConfirmedTransaction('a', userId: owner);
    expect(await balance('credit'), 100);
  });
  test('concurrent writes use persisted balances and normalize to sen',
      () async {
    await Future.wait(List.generate(
        10,
        (i) => service.saveConfirmedTransaction(expense('a$i', amount: .10),
            userId: owner)));
    expect(await balance('bank'), 99);
    final saved = await service.saveConfirmedTransaction(
        expense('rounded', amount: 1.239),
        userId: owner);
    expect(saved.amount, 1.24);
    expect(await balance('bank'), 97.76);
  });
  test(
      'foreign record IDs and missing edits cannot overwrite or create records',
      () async {
    await service.saveConfirmedTransaction(expense('a'), userId: owner);
    await expectLater(
        service.saveConfirmedTransaction(expense('a'),
            userId: 'other', editing: true),
        throwsStateError);
    await service.deleteConfirmedTransaction('a', userId: 'other');
    await expectLater(
        service.saveConfirmedTransaction(expense('missing'),
            userId: owner, editing: true),
        throwsStateError);
    expect(await balance('bank'), 90);
    expect((await service.getAllTransactions(userId: owner)).length, 1);
  });
  test('provider edits and deletes persisted records outside selected month',
      () async {
    SharedPreferences.setMockInitialValues({'currentUserId': owner});
    final provider = ExpenseProvider(initialize: false);
    await provider.reloadSession();
    await service.saveConfirmedTransaction(expense('old'), userId: owner);
    await provider.updateTransaction(expense('old', amount: 20));
    expect(await balance('bank'), 80);
    expect(
        provider.accounts.firstWhere((a) => a.id == 'bank').currentBalance, 80);
    await provider.deleteTransaction('old');
    expect(await balance('bank'), 100);
    expect(provider.chartRevision, 2);
    // Notifications run asynchronously; allow their safe no-plugin fallback.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    provider.dispose();
  });
  test('history stays visible when selected month has no transactions',
      () async {
    SharedPreferences.setMockInitialValues({'currentUserId': owner});
    await service.saveConfirmedTransaction(expense('previous-month'),
        userId: owner);
    await service.saveConfirmedTransaction(
        expense('older').copyWith(date: DateTime(2025, 12, 31)),
        userId: owner);
    await service.insertTransaction(expense('other-user'),
        userId: 'another-owner');
    final provider = ExpenseProvider(initialize: false);
    await provider.reloadSession();
    provider.setSelectedMonth(DateTime(2026, 2));
    await provider.loadData();
    expect(provider.transactions, isEmpty);
    expect(provider.totalExpense, 0);
    expect(
        provider.allTransactions.map((t) => t.id), ['previous-month', 'older']);
    expect(provider.recentTransactions.map((t) => t.id),
        ['previous-month', 'older']);
    await provider.deleteTransaction('previous-month');
    expect(provider.recentTransactions.single.id, 'older');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    provider.dispose();
  });
  test('home current-month totals stay independent of analytics month',
      () async {
    SharedPreferences.setMockInitialValues({'currentUserId': owner});
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1, 12);
    await service.saveConfirmedTransaction(
        expense('current', amount: .30).copyWith(date: now),
        userId: owner);
    await service.saveConfirmedTransaction(
        expense('past', amount: 12).copyWith(date: previous),
        userId: owner);
    final provider = ExpenseProvider(initialize: false);
    await provider.reloadSession();
    provider.setSelectedMonth(previous);
    await provider.loadData();
    expect(provider.totalExpense, 12);
    expect(provider.currentMonthExpense, .30);
    expect(provider.currentMonthTransactions.single.id, 'current');
    expect(provider.allTransactions.length, 2);
    expect(provider.recentTransactions.length, 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    provider.dispose();
  });
  test('credit-card repayment reduces bank and debt without a second expense',
      () async {
    await service.saveConfirmedTransaction(
        expense('card-purchase', amount: 12.35, account: 'credit'),
        userId: owner);
    await service.transfer(
        owner: owner,
        id: 'card-repayment',
        from: 'bank',
        to: 'credit',
        sen: 1235,
        date: DateTime(2026));
    expect(await balance('bank'), 87.65);
    expect(await balance('credit'), 100);
    final records = await service.getAllTransactions(userId: owner);
    expect(records.length, 1);
    expect(records.single.amount, 12.35);
    await service.undoTransfer(owner, 'card-repayment');
    expect(await balance('bank'), 100);
    expect(await balance('credit'), 112.35);
  });
  test('month query includes last microsecond and excludes next month',
      () async {
    await service.insertTransaction(
        expense('last')
            .copyWith(date: DateTime(2026, 1, 31, 23, 59, 59, 999, 999)),
        userId: owner);
    await service.insertTransaction(
        expense('next').copyWith(date: DateTime(2026, 2, 1)),
        userId: owner);
    expect(
        (await service.getTransactionsByMonth(DateTime(2026, 1), userId: owner))
            .map((t) => t.id),
        ['last']);
    await service.upsertBudget(
        BudgetModel(
            id: 'late-budget',
            category: TransactionCategory.groceries,
            limit: 10,
            month: DateTime(2026, 1, 31, 18)),
        userId: owner);
    expect(
        (await service.getBudgetsByMonth(DateTime(2026, 1), userId: owner))
            .map((b) => b.id),
        contains('late-budget'));
  });
  test('deletion persists owner-scoped retry in the ledger commit', () async {
    await db.delete('pending_transaction_deletes');
    await service.saveConfirmedTransaction(expense('retry'), userId: owner);
    await db.execute(
        "CREATE TRIGGER reject_delete BEFORE DELETE ON transactions BEGIN SELECT RAISE(ABORT, 'failure'); END");
    await expectLater(
        service.deleteConfirmedTransaction('retry', userId: owner),
        throwsA(isA<DatabaseException>()));
    expect(await db.query('pending_transaction_deletes'), isEmpty);
    expect(await balance('bank'), 90);
    await db.execute('DROP TRIGGER reject_delete');
    await service.deleteConfirmedTransaction('retry', userId: owner);
    expect((await db.query('pending_transaction_deletes')).single['userId'],
        owner);
    await service.deleteConfirmedTransaction('retry', userId: owner);
    expect((await db.query('pending_transaction_deletes')).length, 1);
    await service.saveConfirmedTransaction(expense('retry'), userId: owner);
    expect(await db.query('pending_transaction_deletes'), isEmpty);
  });
  test('provider distinguishes budgeted spending and uncapped usage', () async {
    SharedPreferences.setMockInitialValues({'currentUserId': owner});
    final month = DateTime.now();
    await db.delete('budgets');
    await service.upsertBudget(
        BudgetModel(
            id: 'budget',
            category: TransactionCategory.groceries,
            limit: 10,
            month: month),
        userId: owner);
    await service.insertTransaction(
        expense('g').copyWith(amount: 25, date: month),
        userId: owner);
    await service.insertTransaction(
        expense('u').copyWith(
            amount: 4.1, date: month, category: TransactionCategory.transport),
        userId: owner);
    final provider = ExpenseProvider(initialize: false);
    await provider.reloadSession();
    expect(provider.totalExpense, 29.1);
    expect(provider.budgetedSpending, 25);
    expect(provider.unbudgetedSpending, 4.1);
    expect(provider.getBudgetUsage(TransactionCategory.groceries), 2.5);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    provider.dispose();
  });
  test('cloud retries deletions, ignores stale snapshots and isolates owners',
      () async {
    await db.delete('pending_transaction_deletes');
    await service.saveConfirmedTransaction(expense('cloud-delete'),
        userId: owner);
    final stale = await service.getAllTransactions(userId: owner);
    await service.deleteConfirmedTransaction('cloud-delete', userId: owner);
    await db.insert(
        'pending_transaction_deletes', {'id': 'foreign', 'userId': 'other'});
    final requests = <http.Request>[];
    var fail = true;
    final client = SupabaseClient('https://example.supabase.co', 'test-key',
        accessToken: () async => 'test-token',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (fail)
            return http.Response('{"message":"offline"}', 400,
                request: request);
          return http.Response('[]', 200,
              request: request, headers: {'content-type': 'application/json'});
        }));
    var signedIn = true;
    final cloud =
        SupabaseSyncService.forTesting(client, (id) => signedIn && id == owner);
    await expectLater(cloud.syncLedger(userId: owner), throwsA(anything));
    expect(
        (await db.query('pending_transaction_deletes',
                where: 'userId = ?', whereArgs: [owner]))
            .length,
        1);
    fail = false;
    requests.clear();
    await cloud.syncTransactions(stale, userId: owner);
    expect(requests.length, 1);
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.queryParameters['user_id'], 'eq.$owner');
    expect(requests.single.url.queryParameters['id'], 'eq.cloud-delete');
    await service.saveConfirmedTransaction(expense('latest', amount: 12),
        userId: owner);
    requests.clear();
    await Future.wait(
        [cloud.syncLedger(userId: owner), cloud.syncLedger(userId: owner)]);
    expect(requests.map((r) => r.method).toList(),
        ['DELETE', 'POST', 'DELETE', 'POST']);
    expect((jsonDecode(requests[1].body) as List).single['amount'], 12);
    signedIn = false;
    requests.clear();
    await expectLater(cloud.syncLedger(userId: owner), throwsA(anything));
    expect(requests, isEmpty);
    await client.dispose();
  });
  test(
      'split expense debits full bill, settles without income and undoes atomically',
      () async {
    final bill = SplitBill(4650, 0, [
      const SplitPerson('me', 'Me', 2325),
      const SplitPerson('p', 'Person', 2325)
    ]);
    final value =
        expense('split', amount: 23.25).copyWith(splitData: bill.encode());
    await service.saveConfirmedTransaction(value, userId: owner);
    expect(await balance('bank'), 53.5);
    expect(
        (await service.getAllTransactions(userId: owner)).single.amount, 23.25);
    await service.settleSplit(
        owner: owner,
        billId: 'split',
        personId: 'p',
        accountId: 'bank',
        sen: 1000,
        paymentId: 'payment');
    await service.settleSplit(
        owner: owner,
        billId: 'split',
        personId: 'p',
        accountId: 'bank',
        sen: 1000,
        paymentId: 'payment');
    expect(await balance('bank'), 63.5);
    expect((await service.getAllTransactions(userId: owner)).length, 1);
    await expectLater(
        service.settleSplit(
            owner: owner,
            billId: 'split',
            personId: 'p',
            accountId: 'bank',
            sen: 2000,
            paymentId: 'over'),
        throwsStateError);
    expect(await balance('bank'), 63.5);
    await expectLater(
        service.saveConfirmedTransaction(value, userId: owner, editing: true),
        throwsStateError);
    await service.undoSplitPayment(owner, 'payment');
    expect(await balance('bank'), 53.5);
    await service.settleSplit(
        owner: owner,
        billId: 'split',
        personId: 'p',
        accountId: 'bank',
        sen: 2325,
        paymentId: 'full');
    expect(await balance('bank'), 76.75);
    await service.deleteConfirmedTransaction('split', userId: owner);
    expect(await balance('bank'), 100);
    expect(await service.splitPayments(owner, 'split'), isEmpty);
  });
  test(
      'someone else pays: no original cash debit, own portion is expense and settlement debits once',
      () async {
    final bill = SplitBill(6000, 1, [
      const SplitPerson('me', 'Me', 2000),
      const SplitPerson('p', 'Payer', 4000)
    ]);
    await service.saveConfirmedTransaction(
        expense('owed', amount: 20).copyWith(splitData: bill.encode()),
        userId: owner);
    expect(await balance('bank'), 100);
    await service.settleSplit(
        owner: owner,
        billId: 'owed',
        personId: 'me',
        accountId: 'bank',
        sen: 2000,
        paymentId: 'pay');
    expect(await balance('bank'), 80);
    expect((await service.getAllTransactions(userId: owner)).single.amount, 20);
    await service.deleteConfirmedTransaction('owed', userId: owner);
    expect(await balance('bank'), 100);
  });
  test('split validation, sen remainder and zero own portion remain exact',
      () async {
    expect(SplitBill.evenly(1000, 3), [334, 333, 333]);
    expect(
        () => SplitBill(1000, 0, [
              const SplitPerson('me', 'Me', 500),
              const SplitPerson('x', 'X', 499)
            ]).validate(),
        throwsArgumentError);
    final bill = SplitBill(1000, 0,
        [const SplitPerson('me', 'Me', 0), const SplitPerson('p', 'P', 1000)]);
    await service.saveConfirmedTransaction(
        expense('zero', amount: 0).copyWith(splitData: bill.encode()),
        userId: owner);
    expect(await balance('bank'), 90);
    expect((await service.getAllTransactions(userId: owner)).single.amount, 0);
  });
  test(
      'transfers update both accounts atomically and never become income/expense',
      () async {
    await service.transfer(
        owner: owner,
        id: 'transfer',
        from: 'bank',
        to: 'second',
        sen: 1250,
        date: DateTime(2026));
    await service.transfer(
        owner: owner,
        id: 'transfer',
        from: 'bank',
        to: 'second',
        sen: 1250,
        date: DateTime(2026));
    expect(await balance('bank'), 87.5);
    expect(await balance('second'), 112.5);
    expect(await service.getAllTransactions(userId: owner), isEmpty);
    await expectLater(
        service.transfer(
            owner: owner,
            id: 'bad',
            from: 'bank',
            to: 'missing',
            sen: 100,
            date: DateTime(2026)),
        throwsStateError);
    expect(await balance('bank'), 87.5);
    await expectLater(
        service.transfer(
            owner: 'foreign',
            id: 'foreign',
            from: 'bank',
            to: 'second',
            sen: 100,
            date: DateTime(2026)),
        throwsStateError);
    expect(await balance('second'), 112.5);
  });
  test(
      'undo transfer reverses both balances once and requires the correct owner',
      () async {
    await db.delete('account_transfers');
    await service.transfer(
        owner: owner,
        id: 'undo-t',
        from: 'bank',
        to: 'second',
        sen: 1000,
        date: DateTime(2026));
    await service.undoTransfer('foreign', 'undo-t');
    expect(await balance('bank'), 90);
    await service.undoTransfer(owner, 'undo-t');
    await service.undoTransfer(owner, 'undo-t');
    expect(await balance('bank'), 100);
    expect(await balance('second'), 100);
    expect(await service.transfers(owner), isEmpty);
  });
  test('legacy sign-in migration preserves split participants and repayments',
      () async {
    const old = 'SP-LEGACY';
    await service.insertAccount(
        const AppAccount(
            id: 'legacy-bank',
            name: 'Legacy bank',
            kind: AccountKind.asset,
            subtype: AccountSubtype.bank,
            openingBalance: 100,
            currentBalance: 100,
            icon: 'B',
            colorValue: 0),
        userId: old);
    final bill = SplitBill(2000, 0, [
      const SplitPerson('me', 'Me', 1000),
      const SplitPerson('legacy-person', 'Friend', 1000)
    ]);
    await service.saveConfirmedTransaction(
        expense('legacy-bill', amount: 10, account: 'legacy-bank')
            .copyWith(splitData: bill.encode()),
        userId: old);
    await service.settleSplit(
        owner: old,
        billId: 'legacy-bill',
        personId: 'legacy-person',
        accountId: 'legacy-bank',
        sen: 500,
        paymentId: 'legacy-payment');
    await service.moveLegacyRecords(old, owner);
    expect(await service.splitPayments(old, 'legacy-bill'), isEmpty);
    expect(
        (await service.splitPayments(owner, 'legacy-bill')).single['sen'], 500);
    expect((await service.splitPeople(owner)).map((p) => p['id']),
        contains('legacy-person'));
    expect(
        (await service.getAllTransactions(userId: owner))
            .single
            .split!
            .totalSen,
        2000);
    expect(await balance('legacy-bank'), 85);
  });
  test('new split and transfer flows reject unsupported lending account signs',
      () async {
    await service.insertAccount(
        const AppAccount(
            id: 'borrow',
            name: 'Borrowed',
            kind: AccountKind.lending,
            subtype: AccountSubtype.borrow,
            openingBalance: 100,
            currentBalance: 100,
            icon: 'B',
            colorValue: 0),
        userId: owner);
    await expectLater(
        service.transfer(
            owner: owner,
            id: 'unsupported',
            from: 'bank',
            to: 'borrow',
            sen: 100,
            date: DateTime(2026)),
        throwsStateError);
    expect(await balance('bank'), 100);
    expect(await balance('borrow'), 100);
    const bill = SplitBill(1000, 0,
        [SplitPerson('me', 'Me', 500), SplitPerson('p', 'Person', 500)]);
    await expectLater(
        service.saveConfirmedTransaction(
            expense('borrow-split', amount: 5, account: 'borrow')
                .copyWith(splitData: bill.encode()),
            userId: owner),
        throwsStateError);
    expect(await balance('borrow'), 100);
  });
}

