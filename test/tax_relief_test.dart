import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/services/tax_relief_service.dart';
import 'package:expense_tracker/screens/tax_relief_screen.dart';
import 'package:expense_tracker/utils/app_theme.dart';

TransactionModel expense(String title,
        {String? note,
        int year = 2025,
        TransactionType type = TransactionType.expense,
        String? receipt,
        TransactionCategory category = TransactionCategory.shopping}) =>
    TransactionModel(
        id: title,
        title: title,
        amount: 50,
        type: type,
        category: category,
        date: DateTime(year, 1, 5),
        note: note,
        receiptImagePath: receipt);

class TaxProvider extends ExpenseProvider {
  TaxProvider() : super(initialize: false);
  @override
  Future<List<TransactionModel>> loadChartTransactions() async =>
      [expense('Gym membership', year: DateTime.now().year)];
}

void main() {
  test('possible matches use year and item wording, never whole categories',
      () {
    final rows = [
      expense('Badminton racket'),
      expense('Running shoes'),
      expense('Groceries'),
      expense('Tablet medicine', category: TransactionCategory.health),
      expense('Laptop repair'),
      expense('Laptop'),
      expense('Gym membership', type: TransactionType.income),
      expense('Gym membership', year: 2024)
    ];
    final matches = TaxReliefService.find(rows, 2025, asOf: DateTime(2026));
    expect(matches.map((m) => m.transaction.title).toSet(),
        {'Badminton racket', 'Laptop'});
  });
  test(
      'mixed receipts can appear in two groups without calculating a claim total',
      () {
    final row = expense('Department store',
        note: 'Books and badminton equipment', receipt: '/saved/receipt.jpg');
    final matches = TaxReliefService.find([row], 2025, asOf: DateTime(2026));
    expect(
        matches.map((m) => m.group).toSet(), {'Sports', 'Reading materials'});
    expect(matches.every((m) => m.transaction.id == row.id), true);
    expect(matches.first.transaction.receiptImagePath, '/saved/receipt.jpg');
    expect(
        TaxReliefService.find([expense('Gym membership', year: 2027)], 2027,
            asOf: DateTime(2026)),
        isEmpty);
  });
  testWidgets('list marks items for review and identifies missing receipts',
      (tester) async {
    final provider = TaxProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme, home: const TaxReliefScreen())));
    await tester.pumpAndSettle();
    expect(find.text('1. Sports'), findsOneWidget);
    expect(find.text('Needs checking'), findsOneWidget);
    expect(find.text('No receipt · View'), findsOneWidget);
    expect(find.textContaining('not claim amounts'), findsOneWidget);
    await tester.tap(find.byTooltip('About tax relief hints'));
    await tester.pumpAndSettle();
    expect(find.text(TaxReliefService.referenceUrl), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
