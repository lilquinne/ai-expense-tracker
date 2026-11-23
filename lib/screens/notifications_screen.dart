import 'recurring_screen.dart';
import '../services/budget_advice.dart';
import '../utils/category_icons.dart';
import '../models/transaction_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../services/notification_service.dart';
import '../utils/app_theme.dart';
import 'budget_screen.dart';
import 'budget_analysis_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  bool? _enabled;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      await context.read<ExpenseProvider>().loadData();
      if (!mounted) return;
      final enabled = await NotificationService.budgetAlertsEnabled(
          context.read<ExpenseProvider>().userId);
      if (mounted) setState(() => _enabled = enabled);
    } catch (_) {
      if (mounted) setState(() => _enabled = false);
    }
  }

  Future<void> _toggle(bool enabled) async {
    final provider = context.read<ExpenseProvider>();
    setState(() => _busy = true);
    try {
      if (enabled) {
        final granted =
            await NotificationService.enableBudgetAlerts(provider.userId);
        if (granted) {
          await provider.refreshBudgetNotifications();
          await provider.loadData();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
                'Allow Spendly notifications in phone settings. Alerts remain visible here.'),
            action:
                SnackBarAction(label: 'Settings', onPressed: openAppSettings),
          ));
        }
      } else {
        await NotificationService.disableBudgetAlerts(provider.userId);
      }
      await _refresh();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not change phone notifications. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final alerts = provider.budgetAlerts;
    final advice = BudgetAdvice.calculate(provider.budgets,
        provider.transactions, provider.selectedMonth, DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Turn on notifications',
              style: TextStyle(fontSize: 14)),
          dense: true,
          value: _enabled ?? false,
          onChanged: _busy || _enabled == null ? null : _toggle,
        ),
        const SizedBox(height: 16),
        for (final notice in provider.jarNotifications)
          Card(
              child: ListTile(
            leading: Icon(Icons.savings_outlined,
                color: notice['isRead'] == 0 ? AppTheme.primary : null),
            title: const Text('Jar funds released',
                style: TextStyle(fontSize: 14)),
            subtitle: Text(
                '${notice['message']}\n${DateFormat.yMMMd().add_jm().format(DateTime.parse(notice['date'] as String))}'),
            onTap: () => provider.readJarNotification(notice['id'] as String),
          )),
        if (provider.recurringDue.isNotEmpty)
          Card(
              child: ListTile(
            leading: const Icon(Icons.repeat_rounded),
            title: Text(
                'Recurring transactions · ${provider.recurringDue.length} due'),
            subtitle: const Text('Confirm before recording'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RecurringScreen())),
          )),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.insights_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Your daily budget guide',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500))
                      ]),
                      const SizedBox(height: 10),
                      Text(
                          advice?.message(provider.currencySymbol) ??
                              'Add a category budget in More → Budget Tracker to see your daily budget room and spending forecast.',
                          style: const TextStyle(fontSize: 12, height: 1.6)),
                    ]))),
        const SizedBox(height: 20),
        Text(
            'Budget alerts · ${DateFormat.yMMMM().format(provider.selectedMonth)}',
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        const SizedBox(height: 12),
        if (alerts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              Icon(Icons.notifications_none_rounded,
                  size: 44, color: AppPalette.of(context).textMuted),
              const SizedBox(height: 12),
              Text(provider.budgets.isEmpty
                  ? 'Set a budget to start receiving alerts.'
                  : 'Your budgets are below 80% usage.'),
            ]),
          ),
        for (final alert in alerts)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: PageStorageKey(alert.key),
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              leading: CircleAvatar(
                backgroundColor: AppTheme.primary.withValues(alpha: .12),
                child: Icon(categoryIcon(alert.budget.category),
                    color: AppTheme.primary, size: 23),
              ),
              title: Text(
                  alert.spent > alert.budget.limit
                      ? 'Overspending'
                      : alert.level == 2
                          ? 'Budget reached'
                          : 'Near the limit',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.budget.category.label,
                        style: const TextStyle(fontSize: 13)),
                    if (alert.triggeredAt != null)
                      Text(
                          'Since ${DateFormat.MMMd().format(alert.triggeredAt!)}',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppPalette.of(context).textMuted)),
                    Text(
                        alert.spent > alert.budget.limit
                            ? '${((alert.ratio - 1) * 100).toStringAsFixed(0)}% over budget'
                            : '${(alert.ratio * 100).toStringAsFixed(0)}% used',
                        style: TextStyle(
                            fontSize: 12,
                            color: alert.level == 2
                                ? AppTheme.expenseColor
                                : AppTheme.warningColor)),
                  ]),
              onExpansionChanged: (expanded) {
                if (expanded) provider.markAlertRead(alert);
              },
              children: [
                for (final entry in {
                  'Budget': alert.budget.limit,
                  'Actual': alert.spent,
                  alert.spent > alert.budget.limit
                      ? 'Over budget'
                      : 'Remaining': (alert.spent - alert.budget.limit).abs(),
                }.entries)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(
                            child: Text(entry.key,
                                style: const TextStyle(fontSize: 12))),
                        Text(
                            '${provider.currencySymbol} ${entry.value.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12)),
                      ])),
                Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.analytics_outlined, size: 17),
                      label: const Text('View analysis'),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  BudgetAnalysisScreen(alert: alert))),
                    )),
              ],
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BudgetScreen())),
            icon: const Icon(Icons.savings_outlined),
            label: const Text('Manage budgets')),
        const SizedBox(height: 12),
      ]),
    );
  }
}
