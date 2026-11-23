import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/services/ledger_totals.dart';
import 'package:expense_tracker/models/monthly_analysis.dart';
import 'package:expense_tracker/models/transaction_model.dart';

void main() {
  test('sen sums agree across monthly totals, days and categories', () {
    final records = List.generate(
        3,
        (i) => TransactionModel(
            id: '$i',
            title: 'Small',
            amount: .1,
            type: TransactionType.expense,
            category: TransactionCategory.groceries,
            date: DateTime(2026, 1, i + 1)));
    final analysis = MonthlyAnalysis(records, DateTime(2026, 1));
    expect(LedgerTotals.sum(records.map((t) => t.amount)), .3);
    expect(analysis.expense, .3);
    expect(analysis.days.values.map((d) => d.expense), [.1, .1, .1]);
    expect(analysis.rankedCategories.single.amount, .3);
    expect(LedgerTotals.categories(records)[TransactionCategory.groceries], .3);
  });
  test('zero limits have explicit usage and overspending is uncapped', () {
    expect(LedgerTotals.usage(0, 0), 0);
    expect(LedgerTotals.usage(1, 0), double.infinity);
    expect(LedgerTotals.usage(25, 10), 2.5);
  });
}
