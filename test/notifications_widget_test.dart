import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/models/budget_alert.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/screens/home_screen.dart';
import 'package:expense_tracker/utils/app_theme.dart';

class _PreviewExpenses extends ExpenseProvider {
  _PreviewExpenses() : super(initialize: false);
  @override
  Future<void> loadData() async {}
  @override
  List<BudgetAlert> get budgetAlerts => [
        BudgetAlert(
            BudgetModel(
                id: 'test',
                category: TransactionCategory.groceries,
                limit: 100,
                month: DateTime(2026, 10)),
            125)
      ];
  @override
  DateTime get selectedMonth => DateTime(2026, 10);
}

void main() {
  testWidgets(
      'bell opens live warnings and budget navigation on a narrow screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final font = FontLoader('Sora')
      ..addFont(rootBundle.load('assets/fonts/Sora-Regular.ttf'));
    await font.load();
    const permissions =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (_) async => 0);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = _PreviewExpenses();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child:
            MaterialApp(theme: AppTheme.darkTheme, home: const HomeScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Budget notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Turn on notifications'), findsOneWidget);
    expect(find.text('Overspending'), findsOneWidget);
    expect(find.text('25% over budget'), findsOneWidget);
    await tester.tap(find.text('Overspending'));
    await tester.pumpAndSettle();
    expect(find.text('Actual'), findsOneWidget);
    expect(find.text('RM 125.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Manage budgets'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
