import 'package:expense_tracker/services/budget_advice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/models/budget_alert.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final month = DateTime(2026, 10);
  BudgetModel budget({double limit = 100, DateTime? date}) => BudgetModel(
      id: 'b',
      category: TransactionCategory.groceries,
      limit: limit,
      month: date ?? month);
  TransactionModel expense(double amount,
          {DateTime? date, TransactionType type = TransactionType.expense}) =>
      TransactionModel(
          id: 't',
          title: 'Groceries',
          amount: amount,
          type: type,
          category: TransactionCategory.groceries,
          date: date ?? month);
  test('80% warning and 100% limit, excluding other months and income', () {
    expect(BudgetAlert.evaluate([budget()], [expense(79.99)]), isEmpty);
    expect(BudgetAlert.evaluate([budget()], [expense(80)]).single.level, 1);
    expect(BudgetAlert.evaluate([budget()], [expense(100)]).single.title,
        contains('reached'));
    expect(
        BudgetAlert.evaluate([budget()], [expense(110)]).single.message('RM'),
        contains('10.00 over'));
    expect(
        BudgetAlert.evaluate([
          budget()
        ], [
          expense(100, date: DateTime(2026, 9)),
          expense(100, type: TransactionType.income)
        ]),
        isEmpty);
    expect(BudgetAlert.evaluate([budget(limit: 0)], [expense(100)]), isEmpty);
  });
  test('alert date follows the current threshold crossing', () {
    final alert = BudgetAlert.evaluate([
      budget()
    ], [
      expense(30, date: DateTime(2026, 10, 22)),
      expense(80, date: DateTime(2026, 10, 5))
    ]).single;
    expect(alert.triggeredAt, DateTime(2026, 10, 22));
  });
  test(
      'system alerts deduplicate, clear resolved budgets, and retry after permission grant',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    var permission = false;
    final calls = <MethodCall>[];
    const notifications =
        MethodChannel('dexterous.com/flutter/local_notifications');
    const permissions =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(notifications, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails')
        return {'notificationLaunchedApp': false};
      return true;
    });
    messenger.setMockMethodCallHandler(
        permissions, (call) async => permission ? 1 : 0);
    addTearDown(() {
      messenger.setMockMethodCallHandler(notifications, null);
      messenger.setMockMethodCallHandler(permissions, null);
    });
    final warning = BudgetAlert(budget(), 80);
    await NotificationService.syncBudgetAlerts('u', [warning], 'RM');
    expect(calls.where((c) => c.method == 'show'), isEmpty);
    permission = true;
    await NotificationService.syncBudgetAlerts('u', [warning], 'RM');
    await NotificationService.syncBudgetAlerts('u', [warning], 'RM');
    expect(calls.where((c) => c.method == 'show').length, 1);
    await NotificationService.syncBudgetAlerts(
        'u', [BudgetAlert(budget(), 110)], 'RM');
    expect(calls.where((c) => c.method == 'show').length, 2);
    await NotificationService.syncBudgetAlerts('u', [], 'RM');
    expect(calls.where((c) => c.method == 'cancel'), isNotEmpty);
    await NotificationService.syncBudgetAlerts(
        'u', [BudgetAlert(budget(date: DateTime(2026, 11)), 80)], 'RM');
    expect(calls.where((c) => c.method == 'show').length, 3);
    await NotificationService.disableBudgetAlerts('u');
    await NotificationService.syncBudgetAlerts(
        'u', [BudgetAlert(budget(date: DateTime(2026, 11)), 110)], 'RM');
    expect(calls.where((c) => c.method == 'show').length, 3);
  });
  test('forecast advice is quiet and only sends once per state change per day',
      () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <MethodCall>[];
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    const permissionChannel =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails')
        return {'notificationLaunchedApp': false};
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (_) async => 1);
    BudgetAdvice forecast(double daily, DateTime day) =>
        BudgetAdvice.calculate([
          budget()
        ], [
          expense(daily, date: DateTime(2026, 10, 1)),
          expense(daily, date: DateTime(2026, 10, 3)),
          expense(daily, date: DateTime(2026, 10, 8)),
        ], month, day)!;
    final today = DateTime(2026, 10, 10);
    await NotificationService.syncBudgetAdvice(
        'advice-user', forecast(20, today), 'RM', today);
    await NotificationService.syncBudgetAdvice(
        'advice-user', forecast(22, today), 'RM', today);
    expect(calls.where((c) => c.method == 'show').length, 1);
    final recovered = DateTime(2026, 10, 11);
    await NotificationService.syncBudgetAdvice(
        'advice-user', forecast(1, recovered), 'RM', recovered);
    expect(calls.where((c) => c.method == 'show').length, 2);
    final details = (calls.firstWhere((c) => c.method == 'show').arguments
        as Map)['platformSpecifics'] as Map;
    expect(details['playSound'], false);
    await NotificationService.disableBudgetAlerts('advice-user');
    await NotificationService.syncBudgetAdvice(
        'advice-user', forecast(25, recovered), 'RM', DateTime(2026, 10, 12));
    expect(calls.where((c) => c.method == 'show').length, 2);
  });
}
