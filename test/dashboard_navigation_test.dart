import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/screens/home_screen.dart';
import 'package:expense_tracker/screens/transactions_screen.dart';
import 'package:expense_tracker/screens/treasure_jar_screen.dart';
import 'package:expense_tracker/widgets/dashboard_spending_chart.dart';
import 'package:expense_tracker/utils/app_theme.dart';

class DashboardExpenses extends ExpenseProvider {
  DashboardExpenses() : super(initialize: false);
  int revision = 0;
  @override
  int get chartRevision => revision;
  void recordEarlierExpense() {
    rows.add(TransactionModel(
        id: 'earlier',
        title: 'Earlier expense',
        amount: 12,
        type: TransactionType.expense,
        category: TransactionCategory.groceries,
        date: DateTime(DateTime.now().year, 1, 1)));
    revision++;
    notifyListeners();
  }

  final rows = [
    TransactionModel(
        id: 'test',
        title: 'Bataras',
        amount: 30,
        type: TransactionType.expense,
        category: TransactionCategory.groceries,
        date: DateTime.now())
  ];
  @override
  List<TransactionModel> get transactions => rows;
  @override
  Future<List<TransactionModel>> loadChartTransactions() async => rows;
  @override
  List<TransactionModel> get allTransactions => rows;
  @override
  Future<void> loadData() async {}
}

void main() {
  testWidgets('expanded spending chart shows both axis names', (tester) async {
    final provider = DashboardExpenses();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: DashboardSpendingChart()))));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byTooltip('Enlarge spending chart')).dy,
        greaterThan(tester.getBottomLeft(find.byType(BarChart)).dy));
    expect(find.textContaining('Tap the chart'), findsNothing);
    await tester.tap(find.byTooltip('Enlarge spending chart'));
    await tester.pumpAndSettle();
    expect(find.text('Spending (RM)'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.byType(BarChart), findsNWidgets(2));
    expect(find.text('39'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });
  test('monthly spending uses each calendar day and sums same-day expenses',
      () {
    TransactionModel row(String id, double amount, DateTime date,
            {TransactionType type = TransactionType.expense}) =>
        TransactionModel(
            id: id,
            title: id,
            amount: amount,
            date: date,
            type: type,
            category: type == TransactionType.expense
                ? TransactionCategory.groceries
                : TransactionCategory.salary);
    final values = spendingSeries([
      row('a', 2.10, DateTime(2026, 10, 7)),
      row('b', 3.20, DateTime(2026, 10, 7)),
      row('last', 9, DateTime(2026, 10, 31)),
      row('other month', 100, DateTime(2026, 9, 7)),
      row('income', 200, DateTime(2026, 10, 7), type: TransactionType.income),
    ], anchor: DateTime(2026, 10), yearly: false, monthly: true);
    expect(values.length, 31);
    expect(values[6], 5.30);
    expect(values[30], 9);
    expect(values[7], 0);
    expect(values.fold<double>(0, (a, b) => a + b), 14.30);
    expect(
        spendingSeries([],
                anchor: DateTime(2024, 2), yearly: false, monthly: true)
            .length,
        29);
  });

  testWidgets('new menu and See all keep records accessible', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final font = FontLoader('Sora')
      ..addFont(rootBundle.load('assets/fonts/Sora-Regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final provider = DashboardExpenses();
    addTearDown(provider.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child:
            MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen())));
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('CAPTURE_PREVIEW')) {
      await tester.runAsync(() async {
        await precacheImage(
            const AssetImage('assets/images/spendly-pocket.png'),
            tester.element(find.byType(HomeScreen)));
      });
      await tester.pumpAndSettle();
      await expectLater(find.byType(HomeScreen),
          matchesGoldenFile('../output/spendly-cream-preview.png'));
    }
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Manage categories'), findsOneWidget);
    expect(find.text('Recurring transactions'), findsOneWidget);
    await tester.tap(find.text('Recurring transactions'));
    await tester.pumpAndSettle();
    expect(find.text('No recurring transactions yet.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.cast<NavigationDestination>().map((d) => d.label),
        ['Home', 'Accounts', '', 'Analytics', 'Treasure Jar']);
    await tester.scrollUntilVisible(find.text('See all'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Treasure Jar').last);
    await tester.pumpAndSettle();
    expect(find.byType(TreasureJarScreen), findsOneWidget);
    expect(find.text('New jar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('weekly chart supports touch amounts and switches to yearly line',
      (tester) async {
    final provider = DashboardExpenses();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: DashboardSpendingChart()))));
    await tester.pumpAndSettle();
    final bar = tester.widget<BarChart>(find.byType(BarChart));
    expect(bar.data.barTouchData.enabled, true);
    final group = bar.data.barGroups.last;
    expect(
        bar.data.barTouchData.touchTooltipData
            .getTooltipItem!(group, 6, group.barRods.first, 0)!.text,
        contains('RM 30.00'));
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year').last);
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('RM 30.00'), findsOneWidget);
    provider.recordEarlierExpense();
    await tester.pumpAndSettle();
    expect(find.text('RM 42.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('monthly chart has calendar day totals and period navigation',
      (tester) async {
    final provider = DashboardExpenses();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child:
            const MaterialApp(home: Scaffold(body: DashboardSpendingChart()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month').last);
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);
    final line = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(line.lineBarsData.single.isCurved, true);
    expect(line.lineBarsData.single.preventCurveOverShooting, true);
    expect(line.lineBarsData.single.dotData.show, false);
    final days = DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;
    final spots = line.lineBarsData.single.spots;
    expect(spots.length, days);
    expect(spots[DateTime.now().day - 1].y, 30);
    expect(spots.first.x, 0);
    expect(spots.last.x, days - 1);
    expect(find.text('Day of month · Tap for daily amounts'), findsNothing);
    expect(find.byTooltip('Enlarge spending chart'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Next month'))
            .onPressed,
        isNull);
    expect(find.byTooltip('Previous month'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Next month'))
            .onPressed,
        isNotNull);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Next month'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
}
