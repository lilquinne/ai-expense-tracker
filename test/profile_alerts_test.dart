import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/models/budget_alert.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/screens/budget_analysis_screen.dart';
import 'package:expense_tracker/screens/settings_screen.dart';
import 'package:expense_tracker/screens/login_screen.dart';
import 'package:expense_tracker/widgets/loading_screen.dart';
import 'package:expense_tracker/utils/app_theme.dart';

class AlertExpenses extends ExpenseProvider {
  AlertExpenses() : super(initialize: false);
  final budget = BudgetModel(
      id: 'test',
      category: TransactionCategory.groceries,
      limit: 100,
      month: DateTime(2026, 10));
  double spent = 90;
  @override
  List<BudgetAlert> get budgetAlerts => [BudgetAlert(budget, spent)];
  @override
  List<TransactionModel> get transactions => [
        TransactionModel(
            id: 'a',
            title: 'Bataras',
            amount: 123.5,
            type: TransactionType.expense,
            category: TransactionCategory.groceries,
            date: DateTime(2026, 10, 18),
            note: '1. Eggs (RM20)\n2. Mushrooms (RM7)'),
        TransactionModel(
            id: 'b',
            title: 'Previous month shop',
            amount: 90,
            type: TransactionType.expense,
            category: TransactionCategory.groceries,
            date: DateTime(2026, 9, 18)),
      ];
}

void main() {
  testWidgets('startup hides login while restoring a session', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme, home: const LoginScreen()));
    expect(find.byType(LoadingScreen), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(LoadingScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile hides removed fields and persists light theme',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = AlertExpenses();
    await provider.savePreferences(colorTheme: 'Dark');
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: Consumer<ExpenseProvider>(
            builder: (context, preferences, child) => MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: preferences.colorTheme == 'Light'
                    ? ThemeMode.light
                    : ThemeMode.dark,
                home: const SettingsScreen()))));
    await tester.pumpAndSettle();
    expect(find.text('Currency'), findsNothing);
    expect(find.text('IP location'), findsNothing);
    expect(find.text('Category Management'), findsNothing);
    await tester.scrollUntilVisible(find.text('Light theme'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Light theme'));
    await tester.pumpAndSettle();
    expect(provider.colorTheme, 'Light');
    expect((await SharedPreferences.getInstance()).getString('colorTheme'),
        'Light');
    expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
        Brightness.light);
    expect(tester.takeException(), isNull);
  });

  test('read state is saved and a new budget threshold becomes unread',
      () async {
    SharedPreferences.setMockInitialValues({});
    final provider = AlertExpenses();
    addTearDown(provider.dispose);
    expect(provider.unreadAlertCount, 1);
    await provider.markAlertRead(provider.budgetAlerts.single);
    expect(provider.unreadAlertCount, 0);
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('read_budget_alerts:'),
        isNotEmpty);
    provider.spent = 120;
    expect(provider.unreadAlertCount, 1);
  });

  testWidgets(
      'light budget breakdown includes shop and notes only for the alert month',
      (tester) async {
    final provider = AlertExpenses();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: BudgetAnalysisScreen(alert: provider.budgetAlerts.single))));
    expect(find.text('Bataras'), findsOneWidget);
    expect(find.textContaining('Eggs (RM20)'), findsOneWidget);
    expect(find.textContaining('Previous month shop'), findsNothing);
    final context = tester.element(find.byType(BudgetAnalysisScreen));
    expect(AppPalette.of(context).bgCard, const Color(0xFFFFFDF6));
    expect(AppPalette.of(context).textPrimary, isNot(AppTheme.textPrimary));
    expect(tester.takeException(), isNull);
  });
}
