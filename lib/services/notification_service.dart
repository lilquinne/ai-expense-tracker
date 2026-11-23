import 'dart:convert';
import 'package:timezone/timezone.dart' as tz;
import 'recurring_service.dart';
import 'budget_advice.dart';
// lib/services/notification_service.dart

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/budget_alert.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final recurringTap = ValueNotifier<int>(0);
  static Map<String, dynamic>? pendingRecurring;
  static void _handleResponse(NotificationResponse response) {
    if (response.payload?.startsWith('recurring:') == true) {
      try {
        pendingRecurring = Map<String, dynamic>.from(
            jsonDecode(response.payload!.substring(10)) as Map)
          ..['action'] = response.actionId;
        recurringTap.value++;
      } catch (_) {}
    }
    if (response.payload == 'budgets') {
      pendingBudgetTap = true;
      budgetTap.value++;
    }
  }

  static final budgetTap = ValueNotifier<int>(0);
  static bool pendingBudgetTap = false;
  static bool _initialized = false;
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void>? _initWork;
  static Future<void> init() {
    if (_initialized) return Future.value();
    return _initWork ??= _initialize().whenComplete(() => _initWork = null);
  }

  static Future<void> _initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_launcher');
    final iosSettings = DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory('recurring', actions: [
          DarwinNotificationAction.plain('confirm', 'Confirm',
              options: {DarwinNotificationActionOption.foreground}),
          DarwinNotificationAction.plain('mute', 'Do not show this again',
              options: {DarwinNotificationActionOption.foreground}),
        ])
      ],
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    final settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _plugin.initialize(settings,
        onDidReceiveNotificationResponse: _handleResponse);
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      _handleResponse(launch!.notificationResponse!);
    }
    _initialized = true;
  }

  static Future<bool> enableBudgetAlerts(String userId) async {
    await init();
    final status = await Permission.notification.request();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('budget_notifications_$userId', true);
    return status.isGranted;
  }

  static Future<bool> budgetAlertsEnabled(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool('budget_notifications_$userId') ?? true) &&
        await Permission.notification.isGranted;
  }

  static Future<void> disableBudgetAlerts(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('budget_notifications_$userId', false);
    await _plugin.cancel(_id('$userId:budget-advice'));
    await cancelRecurringReminders(userId);
    final active = prefs.getStringList('budget_active_$userId') ?? [];
    for (final key in active) {
      await _plugin.cancel(_id('$userId:$key'));
    }
  }

  static int _id(String value) {
    var hash = 0;
    for (final code in value.codeUnits) {
      hash = (hash * 31 + code) & 0x3fffffff;
    }
    return hash;
  }

  /// One notification per threshold per category/month, persisted across restarts.
  /// Resolved/deleted budgets also remove their stale system notification.
  static Future<void> syncBudgetAlerts(
      String userId, List<BudgetAlert> alerts, String currency,
      {String? advice}) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    final activeKey = 'budget_active_$userId';
    final previous = prefs.getStringList(activeKey) ?? [];
    final keys = alerts.map((a) => a.key).toList();
    for (final key in previous.where((key) => !keys.contains(key))) {
      await _plugin.cancel(_id('$userId:$key'));
    }
    await prefs.setStringList(activeKey, keys);
    if (!await budgetAlertsEnabled(userId)) return;
    for (final alert in alerts) {
      final key = 'budget_sent_$userId:${alert.key}';
      // A correction can bring an over-budget category back below its limit.
      // Remove the obsolete warning without re-alerting at a lower threshold.
      final activeLevelKey = 'budget_level_$userId:${alert.key}';
      if ((prefs.getInt(activeLevelKey) ?? 0) > alert.level) {
        await _plugin.cancel(_id('$userId:${alert.key}'));
      }
      await prefs.setInt(activeLevelKey, alert.level);
      if ((prefs.getInt(key) ?? 0) >= alert.level) continue;
      await _plugin.show(
          _id('$userId:${alert.key}'),
          alert.title,
          '${alert.message(currency)}${advice == null ? '' : '\n$advice'}',
          const NotificationDetails(
              android: AndroidNotificationDetails(
                  'budget_guidance', 'Budget guidance',
                  channelDescription:
                      'Warnings at 80% and 100% of your monthly budgets',
                  importance: Importance.low,
                  priority: Priority.low,
                  playSound: false),
              iOS: DarwinNotificationDetails(presentSound: false)),
          payload: 'budgets');
      await prefs.setInt(key, alert.level);
    }
  }

  /// Quiet advice only when the forecast changes status, at most once a day.
  static Future<void> syncBudgetAdvice(
      String user, BudgetAdvice? advice, String currency, DateTime now) async {
    final id = _id('$user:budget-advice');
    if (advice == null ||
        advice.pace.month.year != now.year ||
        advice.pace.month.month != now.month) {
      await _plugin.cancel(id);
      return;
    }
    if (!await budgetAlertsEnabled(user)) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'budget_advice:$user:${now.year}-${now.month}';
    final previous = prefs.getString(key);
    final state = advice.state;
    if (state == previous || state == 'learning') return;
    // The first healthy forecast is available in-app without sending a push.
    if (previous == null && state == 'on-track') {
      await prefs.setString(key, state);
      return;
    }
    final day = '${now.year}-${now.month}-${now.day}';
    if (prefs.getString('$key:day') == day) return;
    await init();
    await _plugin.show(
        id,
        state == 'on-track'
            ? 'Your budget pace is back on track'
            : 'A small budget check-in',
        advice.message(currency),
        const NotificationDetails(
            android: AndroidNotificationDetails(
                'budget_advice', 'Budget advice',
                channelDescription:
                    'Quiet advice when your recorded spending pace changes',
                importance: Importance.low,
                priority: Priority.low,
                playSound: false),
            iOS: DarwinNotificationDetails(presentSound: false)),
        payload: 'budgets');
    await prefs.setString(key, state);
    await prefs.setString('$key:day', day);
  }

  static Future<void> cancelRecurringReminders(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    for (final id
        in prefs.getStringList('recurring_active:$owner') ?? <String>[]) {
      await _plugin.cancel(int.parse(id));
    }
    await prefs.remove('recurring_active:$owner');
  }

  static Future<void> _recurringWork = Future.value();
  static Future<void> syncRecurringReminders(
      String owner, List<RecurringOccurrence> occurrences, String currency) {
    _recurringWork = _recurringWork
        .catchError((Object _) {})
        .then((_) => _syncRecurringReminders(owner, occurrences, currency));
    return _recurringWork;
  }

  static Future<void> _syncRecurringReminders(String owner,
      List<RecurringOccurrence> occurrences, String currency) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    final currentOwner = prefs.getString('currentUserId');
    if ((currentOwner != null && currentOwner != owner) ||
        prefs.getBool('recurring_paused:$owner') == true) {
      await cancelRecurringReminders(owner);
      return;
    }
    final previousOwner = prefs.getString('recurring_notification_owner');
    if (previousOwner != null && previousOwner != owner) {
      await cancelRecurringReminders(previousOwner);
    }
    await prefs.setString('recurring_notification_owner', owner);
    if (!await budgetAlertsEnabled(owner)) {
      await cancelRecurringReminders(owner);
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // One overdue alert per series; also reserve the nearest future dates.
    final overdue = <String>{};
    final selected = occurrences
        .where((o) => !o.date.isBefore(today) || overdue.add(o.template.id))
        .take(60)
        .toList();
    final ids = selected
        .map((o) => _id('recurring:$owner:${o.id}').toString())
        .toList();
    for (final old
        in prefs.getStringList('recurring_active:$owner') ?? <String>[]) {
      if (!ids.contains(old)) await _plugin.cancel(int.parse(old));
    }
    // Track before scheduling so partial failures can be cleaned up on retry.
    await prefs.setStringList('recurring_active:$owner', ids);
    for (final o in selected) {
      final id = _id('recurring:$owner:${o.id}');
      final payload = 'recurring:${jsonEncode({'owner': owner, 'id': o.id})}';
      const details = NotificationDetails(
          android: AndroidNotificationDetails(
              'recurring_due', 'Recurring transactions',
              channelDescription:
                  'Confirm transactions when their recurring date is due',
              actions: [
                AndroidNotificationAction('confirm', 'Confirm',
                    showsUserInterface: true),
                AndroidNotificationAction('mute', 'Do not show this again',
                    showsUserInterface: true),
              ]),
          iOS: DarwinNotificationDetails(categoryIdentifier: 'recurring'));
      final title = 'Recurring for ${o.template.title}';
      final body =
          '$currency ${o.template.amount.toStringAsFixed(2)} · Confirm before recording.';
      final scheduled = DateTime(o.date.year, o.date.month, o.date.day, 9);
      if (!scheduled.isAfter(now)) {
        final sent = 'recurring_sent:$owner:${o.id}';
        if (prefs.getBool(sent) == true) continue;
        await _plugin.show(id, title, body, details, payload: payload);
        await prefs.setBool(sent, true);
      } else {
        await _plugin.zonedSchedule(
            id, title, body, tz.TZDateTime.from(scheduled, tz.UTC), details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: payload);
        await prefs.setBool('recurring_sent:$owner:${o.id}', true);
      }
    }
  }

  static Future<void> showTransactionAdded({
    required String title,
    required double amount,
    required bool isIncome,
    required String currencySymbol,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'transaction_added',
      'Transaction Added',
      channelDescription: 'Confirmation when a transaction is added',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      isIncome ? '💰 Income Added' : '💸 Expense Recorded',
      '$title — $currencySymbol ${amount.toStringAsFixed(2)}',
      details,
    );
  }

  static Future<void> showDownloadComplete({
    required String fileName,
    required String filePath,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'report_downloads',
      'Report Downloads',
      channelDescription: 'Confirmation when reports are exported',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Report downloaded',
      '$fileName saved to $filePath',
      details,
    );
  }
}
