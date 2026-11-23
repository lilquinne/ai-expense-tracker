import 'package:provider/provider.dart';
import 'package:expense_tracker/widgets/recurring_confirmation.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/services/recurring_service.dart';
import 'package:expense_tracker/services/notification_service.dart';
import 'package:expense_tracker/services/database_service.dart';

TransactionModel template({DateTime? date, String frequency = 'monthly'}) =>
    TransactionModel(
        id: 'rent',
        title: 'Rent',
        amount: 100,
        accountId: 'bank',
        type: TransactionType.expense,
        category: TransactionCategory.rent,
        date: date ?? DateTime(2026, 1, 31),
        isRecurring: true,
        recurringFrequency: frequency,
        receiptImagePath: 'old-receipt.jpg');

class RecurringPreview extends ExpenseProvider {
  RecurringPreview() : super(initialize: false);
  int confirmed = 0;
  bool muted = false;
  @override
  String get userId => 'one';
  @override
  Future<void> confirmRecurring(RecurringOccurrence occurrence) async {
    confirmed++;
  }

  @override
  Future<void> muteRecurring(String id, bool value) async {
    muted = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('monthly dates clamp without drifting and leap-year dates recover', () {
    final t = template();
    expect(RecurringService.dateAt(t, 1), DateTime(2026, 2, 28));
    expect(RecurringService.dateAt(t, 2), DateTime(2026, 3, 31));
    final leap = template(date: DateTime(2024, 2, 29), frequency: 'yearly');
    expect(RecurringService.dateAt(leap, 1), DateTime(2025, 2, 28));
    expect(RecurringService.dateAt(leap, 4), DateTime(2028, 2, 29));
  });
  test(
      'due dates exclude initial entry and confirmed repeats, and remain owner scoped',
      () {
    final t = template();
    expect(RecurringService.due('one', [t], DateTime(2026, 2, 27)), isEmpty);
    final first =
        RecurringService.due('one', [t], DateTime(2026, 2, 28)).single;
    expect(first.date, DateTime(2026, 2, 28));
    expect(first.transaction().isRecurring, false);
    expect(first.transaction().receiptImagePath, isNull);
    expect(
        RecurringService.due(
            'one', [t, first.transaction()], DateTime(2026, 2, 28)),
        isEmpty);
    expect(RecurringService.due('two', [t], DateTime(2026, 2, 28)).single.id,
        isNot(first.id));
    expect(RecurringService.due('', [t], DateTime(2026, 3, 31)), isEmpty);
    expect(RecurringService.dateAt(template(frequency: 'weekly'), 1),
        DateTime(2026, 2, 7));
    expect(RecurringService.dateAt(template(frequency: 'daily'), 1),
        DateTime(2026, 2, 1));
  });
  test('phone reminders schedule actions, deduplicate and cancel when muted',
      () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    const permissions =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails')
        return {'notificationLaunchedApp': false};
      return true;
    });
    messenger.setMockMethodCallHandler(permissions, (_) async => 1);
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(permissions, null);
    });
    final now = DateTime.now();
    final t = template(
        date: DateTime(now.year, now.month, now.day - 2), frequency: 'daily');
    final dates = RecurringService.due('one', [t], now, futureCount: 2);
    await NotificationService.syncRecurringReminders('one', dates, 'RM');
    final shown = calls.where((c) => c.method == 'show').length;
    expect(shown, greaterThan(0));
    expect(calls.where((c) => c.method == 'zonedSchedule'), isNotEmpty);
    final details = (calls.firstWhere((c) => c.method == 'show').arguments
        as Map)['platformSpecifics'] as Map;
    expect((details['actions'] as List).length, 2);
    await NotificationService.syncRecurringReminders('one', dates, 'RM');
    expect(calls.where((c) => c.method == 'show').length, shown);
    await NotificationService.syncRecurringReminders('one', [], 'RM');
    expect(calls.where((c) => c.method == 'cancel'), isNotEmpty);
  });
  testWidgets(
      'confirmation records only on Confirm and mute only silences the item',
      (tester) async {
    final p = RecurringPreview();
    final occurrence =
        RecurringOccurrence(template(), DateTime(2026, 2, 28), 'one');
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: p,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showDialog(
                            context: context,
                            builder: (_) =>
                                RecurringConfirmation(occurrence: occurrence)),
                        child: const Text('Open')))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Recurring for Rent'), findsOneWidget);
    expect(p.confirmed, 0);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(p.confirmed, 1);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Do not show this again'));
    await tester.pumpAndSettle();
    expect(p.muted, true);
    expect(p.confirmed, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    p.dispose();
  });
  test('confirming the same occurrence twice only updates the ledger once',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final folder = await Directory.systemTemp.createTemp('recurring-test-');
    await databaseFactory.setDatabasesPath(folder.path);
    final service = DatabaseService();
    final db = await service.database;
    await service.insertAccount(
        AppAccount(
            id: 'bank',
            name: 'Bank',
            openingBalance: 1000,
            currentBalance: 1000,
            kind: AccountKind.asset,
            subtype: AccountSubtype.bank,
            icon: 'B',
            colorValue: 0),
        userId: 'one');
    final t = template();
    await service.saveConfirmedTransaction(t, userId: 'one');
    final occurrence =
        RecurringService.due('one', [t], DateTime(2026, 2, 28)).single;
    await service.saveConfirmedTransaction(occurrence.transaction(),
        userId: 'one');
    await service.saveConfirmedTransaction(occurrence.transaction(),
        userId: 'one');
    expect((await service.getAllTransactions(userId: 'one')).length, 2);
    expect(
        (await db.query('accounts', where: 'id = ?', whereArgs: ['bank']))
            .single['currentBalance'],
        800);
    SharedPreferences.setMockInitialValues(
        {'currentUserId': 'one', 'budget_notifications_one': false});
    final provider = ExpenseProvider(initialize: false);
    await provider.reloadSession();
    await provider.muteRecurring(t.id, true);
    expect(provider.recurringNotices, isEmpty);
    expect(provider.recurringDue, isNotEmpty);
    await provider.reloadSession();
    expect(provider.recurringMuted(t.id), true);
    await provider.muteRecurring(t.id, false);
    final next = provider.recurringDue.first;
    await provider.confirmRecurring(next);
    await provider.confirmRecurring(next);
    expect((await service.getAllTransactions(userId: 'one')).length, 3);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentUserId', 'two');
    await provider.reloadSession();
    expect(provider.recurringDue, isEmpty);
    expect(provider.recurringMuted(t.id), false);
    provider.dispose();
    // Wait for best-effort notification refreshes before closing the database.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await db.close();
    if (folder.absolute.path.startsWith(
        '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}')) {
      await folder.delete(recursive: true);
    }
  });
}
