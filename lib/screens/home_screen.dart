import '../widgets/spendly_logo.dart';
import '../widgets/recurring_confirmation.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/budget_advice.dart';
import '../services/daily_guide_reminder.dart';
import '../services/database_service.dart';
import 'quick_tutorial_screen.dart';
import 'budget_screen.dart';
import 'category_management_screen.dart';
import 'recurring_screen.dart';
import 'split_bills_screen.dart';
// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../models/transaction_model.dart';
import '../utils/app_theme.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/balance_card.dart';
import '../widgets/stat_pill.dart';
import 'add_transaction_screen.dart';
import 'transactions_screen.dart';
import 'analytics_screen.dart';
import 'scan_receipt_screen.dart';
import 'treasure_jar_screen.dart';
import '../widgets/dashboard_spending_chart.dart';
import 'settings_screen.dart';
import 'accounts_screen.dart';
import 'transaction_detail_screen.dart';
import 'notifications_screen.dart';
import 'spending_coach_screen.dart';
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.guideLoader});
  final Future<BudgetAdvice?> Function()? guideLoader;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _entryOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.budgetTap.addListener(_openBudgetNotification);
    NotificationService.recurringTap.addListener(_openRecurringNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openBudgetNotification();
      _openRecurringNotification();
      _entryExperience();
    });
  }

  Future<void> _entryExperience() async {
    final provider = context.read<ExpenseProvider>();
    final user = provider.userId;
    if (_entryOpen || user.isEmpty || ModalRoute.of(context)?.isCurrent != true)
      return;
    _entryOpen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || provider.userId != user) return;
      if (prefs.getBool('quick_tutorial_v1:$user') != true) {
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => QuickTutorialScreen(userId: user)));
      }
      if (!mounted ||
          provider.userId != user ||
          ModalRoute.of(context)?.isCurrent != true) return;
      final now = DateTime.now();
      if (!DailyGuideReminder.session.claimLaunch(user)) return;
      final reminderKey = DailyGuideReminder.preferenceKey(user);
      final today = DailyGuideReminder.localDate(now);
      if (prefs.getString(reminderKey) == today) return;
      var hideToday = false;
      BudgetAdvice? advice;
      if (widget.guideLoader != null) {
        advice = await widget.guideLoader!();
      } else {
        final budgets =
            await DatabaseService().getBudgetsByMonth(now, userId: user);
        final transactions = await provider.loadChartTransactions();
        advice = BudgetAdvice.calculate(budgets, transactions, now, now);
      }
      if (!mounted ||
          provider.userId != user ||
          ModalRoute.of(context)?.isCurrent != true) return;
      final notifications = await showDialog<bool>(
          context: context,
          barrierColor: Colors.black45,
          builder: (ctx) => StatefulBuilder(
              builder: (ctx, updateDialog) => BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: AlertDialog(
                    backgroundColor:
                        AppPalette.of(context).bgCard.withValues(alpha: .96),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26)),
                    title: const Text('Your daily budget guide',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w500)),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              advice?.message(provider.currencySymbol) ??
                                  'Add a category budget in More → Budget Tracker to see your daily budget room and spending forecast.',
                              style:
                                  const TextStyle(fontSize: 13, height: 1.6)),
                          const SizedBox(height: 16),
                          const Text(
                              'You can also find this guide in Notifications.',
                              style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Do not remind me today',
                                style: TextStyle(fontSize: 13)),
                            value: hideToday,
                            onChanged: (value) async {
                              updateDialog(() => hideToday = value ?? false);
                              if (hideToday) {
                                await prefs.setString(reminderKey, today);
                              } else {
                                await prefs.remove(reminderKey);
                              }
                            },
                          ),
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Notifications')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Got it'))
                    ],
                  ))));
      if (notifications == true && mounted)
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    } catch (_) {
      // Guidance must never prevent access to saved data.
    } finally {
      try {
        if (mounted &&
            provider.userId == user &&
            ModalRoute.of(context)?.isCurrent == true) {
          await provider.loadData();
          final due = mounted && provider.userId == user
              ? provider.recurringNotices
              : [];
          if (due.isNotEmpty) {
            await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => RecurringConfirmation(occurrence: due.first));
          }
        }
      } catch (_) {
        // Due items remain available on the recurring transactions screen.
      }
      _entryOpen = false;
    }
  }

  void _openRecurringNotification() {
    if (!mounted) return;
    final pending = NotificationService.pendingRecurring;
    if (pending == null) return;
    final owner = context.read<ExpenseProvider>().userId;
    if (owner.isEmpty) return;
    NotificationService.pendingRecurring = null;
    if (pending['owner'] != owner) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RecurringScreen(
                initialOccurrenceId: pending['id'] as String?,
                initialAction: pending['action'] as String?)));
  }

  void _openBudgetNotification() {
    if (!mounted || !NotificationService.pendingBudgetTap) return;
    NotificationService.pendingBudgetTap = false;
    context.read<ExpenseProvider>().setSelectedMonth(DateTime.now());
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.budgetTap.removeListener(_openBudgetNotification);
    NotificationService.recurringTap.removeListener(_openRecurringNotification);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<ExpenseProvider>().loadData();
    }
  }

  final List<Widget> _screens = [
    const _DashboardTab(),
    const AccountsScreen(),
    const SizedBox.shrink(),
    const AnalyticsScreen(),
    const TreasureJarScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).bgDark,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      floatingActionButton: _currentIndex == 0 ? _buildFAB() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: GestureDetector(
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -100) _showMore();
        },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          InkWell(
              onTap: _showMore,
              child: const SizedBox(
                  height: 24,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.keyboard_arrow_up, size: 16),
                        SizedBox(width: 4),
                        Text('More', style: TextStyle(fontSize: 10))
                      ]))),
          _buildBottomNav(),
        ]),
      ),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton(
      heroTag: 'add_transaction',
      onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AddTransactionScreen())),
      backgroundColor: AppPalette.of(context).primary,
      foregroundColor: Colors.white,
      elevation: 8,
      child: const Icon(Icons.add_rounded, size: 30),
    );
  }

  void _showMore() {
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheet) => SafeArea(
                child: SingleChildScrollView(
                    child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('More tools',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                        builder: (ctx, box) =>
                            Wrap(spacing: 10, runSpacing: 10, children: [
                              for (final item in <(IconData, String, Widget?)>[
                                (
                                  Icons.pie_chart_outline,
                                  'Budget Tracker',
                                  const BudgetScreen()
                                ),
                                (
                                  Icons.group_outlined,
                                  'Split bills',
                                  const SplitBillsScreen()
                                ),
                                (
                                  Icons.category_outlined,
                                  'Manage categories',
                                  const CategoryManagementScreen()
                                ),
                                (
                                  Icons.repeat_rounded,
                                  'Recurring transactions',
                                  const RecurringScreen()
                                ),
                                (
                                  Icons.auto_awesome_outlined,
                                  'Spending coach AI',
                                  const SpendingCoachScreen()
                                ),
                                (
                                  Icons.help_outline_rounded,
                                  'Quick tutorial',
                                  QuickTutorialScreen(
                                      userId: context
                                          .read<ExpenseProvider>()
                                          .userId)
                                ),
                                (Icons.people_outline, 'Friends', null),
                              ])
                                SizedBox(
                                    width: (box.maxWidth - 20) / 3,
                                    child: Material(
                                        color: AppPalette.of(context)
                                            .primary
                                            .withValues(
                                                alpha: item.$3 == null
                                                    ? .04
                                                    : .09),
                                        borderRadius: BorderRadius.circular(18),
                                        child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            onTap: item.$3 == null
                                                ? null
                                                : () {
                                                    Navigator.pop(sheet);
                                                    Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                            builder: (_) =>
                                                                item.$3!));
                                                  },
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 14),
                                                child: Column(children: [
                                                  Icon(item.$1,
                                                      color: item.$3 == null
                                                          ? AppPalette.of(
                                                                  context)
                                                              .textMuted
                                                          : AppPalette.of(
                                                                  context)
                                                              .primary,
                                                      size: 25),
                                                  const SizedBox(height: 8),
                                                  Text(item.$2,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                          fontSize: 11)),
                                                  if (item.$3 == null)
                                                    const Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                top: 4),
                                                        child: Text(
                                                            'Coming later',
                                                            style: TextStyle(
                                                                fontSize: 9))),
                                                ]))))),
                            ])),
                  ]),
            ))));
  }

  Widget _buildBottomNav() {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: AppPalette.of(context).bgCard,
        indicatorColor: AppPalette.of(context).primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppPalette.of(context).primary
                : AppPalette.of(context).textMuted,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppPalette.of(context).primary
                : AppPalette.of(context).textMuted,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: _currentIndex,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          if (index == 2) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ScanReceiptScreen(openCamera: true)));
            return;
          }
          setState(() => _currentIndex = index);
        },
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Accounts'),
          NavigationDestination(
              icon: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(colors: [
                        Color(0xFFAA784C),
                        Color(0xFF79502F),
                        Color(0xFF56341F)
                      ]),
                      border: Border.all(
                          color: const Color(0xFFFFF0C5), width: 1.4),
                      boxShadow: [
                        BoxShadow(
                            color:
                                const Color(0xFFFFE59A).withValues(alpha: .55),
                            blurRadius: 14,
                            spreadRadius: 1),
                        const BoxShadow(color: Color(0xFFEBC85E), blurRadius: 6)
                      ]),
                  child: const Icon(Icons.center_focus_strong_rounded,
                      color: Colors.white, size: 32)),
              label: ''),
          NavigationDestination(
              icon: Icon(Icons.bar_chart_rounded), label: 'Analytics'),
          NavigationDestination(
              icon: Icon(Icons.savings_rounded), label: 'Treasure Jar'),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpenseProvider>(
      builder: (context, provider, _) {
        return CustomScrollView(
          slivers: [
            _buildHeader(context, provider),
            SliverToBoxAdapter(child: _buildBalanceCard(context, provider)),
            SliverToBoxAdapter(child: _buildStatsRow(context, provider)),
            SliverToBoxAdapter(child: _buildDashboardPanels(context, provider)),
            SliverToBoxAdapter(
                child: _buildRecentTransactions(context, provider)),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      },
    );
  }

  Widget _buildDashboardPanels(BuildContext context, ExpenseProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: LayoutBuilder(builder: (context, constraints) {
        final chart = const DashboardSpendingChart(compact: true);
        final jars = _buildJarPreview(context, provider);
        if (constraints.maxWidth < 300) {
          return Column(children: [chart, const SizedBox(height: 12), jars]);
        }
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 6, child: chart),
            const SizedBox(width: 12),
            Expanded(flex: 5, child: jars),
          ]),
        );
      }),
    );
  }

  Widget _buildJarPreview(BuildContext context, ExpenseProvider provider) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TreasureJarScreen())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                  child: Text('My Jar',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600))),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: palette.textMuted),
            ]),
            const SizedBox(height: 16),
            if (provider.jars.isEmpty) ...[
              Icon(Icons.savings_outlined,
                  color: AppPalette.of(context).primary, size: 32),
              const SizedBox(height: 12),
              const Text('Save for something special',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Create your first jar',
                  style: TextStyle(fontSize: 11, color: palette.textSecondary)),
              const SizedBox(height: 16),
            ] else
              for (final jar in provider.jars.take(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(jar.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(
                            '${provider.currencySymbol} ${(jar.savedCents / 100).toStringAsFixed(2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: palette.textSecondary)),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: jar.targetCents > 0 ? jar.progress : 0,
                            minHeight: 7,
                            backgroundColor: palette.bgCardLight,
                            color: AppPalette.of(context).primary,
                          ),
                        ),
                      ]),
                ),
            Text('View jars',
                style: TextStyle(
                    fontSize: 11, color: AppPalette.of(context).primary)),
          ]),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ExpenseProvider provider) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  SpendlyLogo(size: 32),
                  SizedBox(width: 6),
                  Text('spendly',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text(greeting,
                    style: TextStyle(
                        color: AppPalette.of(context).textSecondary,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(provider.userName,
                    style: TextStyle(
                        color: AppPalette.of(context).textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
                GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen())),
                  child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            provider.syncNeedsReview
                                ? Icons.sync_problem
                                : Icons.cloud_outlined,
                            size: 12,
                            color: AppPalette.of(context).textSecondary),
                        const SizedBox(width: 4),
                        Text(
                            provider.isSyncing
                                ? 'Syncing…'
                                : provider.syncNeedsReview
                                    ? 'Sync needs attention'
                                    : provider.lastSyncAt != null
                                        ? 'Synced'
                                        : 'Device sync',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppPalette.of(context).textSecondary)),
                      ])),
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppPalette.of(context).border),
                  ),
                  child: Badge(
                    isLabelVisible: provider.unreadAlertCount > 0,
                    label: Text('${provider.unreadAlertCount}'),
                    child: IconButton(
                      tooltip: 'Budget notifications',
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      constraints:
                          const BoxConstraints.tightFor(width: 22, height: 22),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const NotificationsScreen())),
                      icon: Icon(Icons.notifications_outlined,
                          color: AppPalette.of(context).textSecondary,
                          size: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen())),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppPalette.of(context).border),
                    ),
                    child: Icon(Icons.settings_outlined,
                        color: AppPalette.of(context).textSecondary, size: 22),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, ExpenseProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: BalanceCard(
        balance: provider.totalMyBalance,
        income: provider.currentMonthIncome,
        expense: provider.currentMonthExpense,
        currencySymbol: provider.currencySymbol,
        month: DateTime.now(),
        reserved: provider.totalReserved,
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, ExpenseProvider provider) {
    final savings = provider.currentMonthIncome > 0
        ? (provider.currentMonthIncome - provider.currentMonthExpense) /
            provider.currentMonthIncome *
            100
        : 0.0;
    final txCount = provider.currentMonthTransactions.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: StatPill(
              label: 'Savings Rate',
              value: '${savings.toStringAsFixed(1)}%',
              icon: Icons.savings_rounded,
              color:
                  savings >= 20 ? AppTheme.incomeColor : AppTheme.warningColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatPill(
              label: 'Transactions',
              value: '$txCount',
              icon: Icons.receipt_rounded,
              color: AppTheme.primaryLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions(
      BuildContext context, ExpenseProvider provider) {
    final recents = provider.recentTransactions;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                  child: Text('Recent Transactions',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.of(context).textPrimary))),
              TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TransactionsScreen())),
                child: Text('See all',
                    style: TextStyle(
                        color: AppPalette.of(context).primary, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recents.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppPalette.of(context).bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppPalette.of(context).border),
              ),
              child: Center(
                child: Column(
                  children: [
                    Text('💸', style: TextStyle(fontSize: 40)),
                    SizedBox(height: 12),
                    Text('No transactions yet',
                        style: TextStyle(
                            color: AppPalette.of(context).textSecondary,
                            fontSize: 14)),
                    Text('Tap + to add your first one',
                        style: TextStyle(
                            color: AppPalette.of(context).textMuted,
                            fontSize: 12)),
                  ],
                ),
              ),
            )
          else
            ...recents.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Builder(builder: (_) {
                    final category = provider.categoryForTransaction(t);
                    return TransactionTile(
                      transaction: t,
                      accountName: provider.accountById(t.accountId)?.name ??
                          'Account unavailable',
                      currencySymbol: provider.currencySymbol,
                      categoryName: category.name,
                      categoryIcon: category.icon,
                      categoryColorValue: category.colorValue,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              TransactionDetailScreen(transaction: t),
                        ),
                      ),
                    );
                  }),
                )),
        ],
      ),
    );
  }
}
