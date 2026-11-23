import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/services/budget_advice.dart';
import 'package:expense_tracker/models/transaction_model.dart';

void main() {
  final month = DateTime(2026, 10);
  final budget = BudgetModel(
      id: 'food', category: TransactionCategory.food, limit: 100, month: month);
  TransactionModel expense(int day, double amount,
          {TransactionCategory category = TransactionCategory.food}) =>
      TransactionModel(
          id: '$day-$category',
          title: 'Expense',
          amount: amount,
          type: TransactionType.expense,
          category: category,
          date: DateTime(2026, 10, day));
  test(
      'advice uses budgeted categories, ignores future expenses and does not invent forecasts',
      () {
    expect(
        BudgetAdvice.calculate([], [], month, DateTime(2026, 10, 10)), isNull);
    final advice = BudgetAdvice.calculate([
      budget
    ], [
      expense(1, 10),
      expense(30, 1000),
      expense(2, 500, category: TransactionCategory.shopping)
    ], month, DateTime(2026, 10, 10))!;
    expect(advice.pace.spent, 10);
    expect(advice.state, 'learning');
    expect(advice.pace.projected, isNull);
    expect(advice.message('RM'), contains('forecast needs'));
    expect(advice.pace.remainingPerDay, closeTo(90 / 21, .001));
  });
  test(
      'forecast gives actionable daily allowance and changes state as pace changes',
      () {
    final advice = BudgetAdvice.calculate(
        [budget],
        [expense(1, 20), expense(3, 20), expense(8, 20)],
        month,
        DateTime(2026, 10, 10))!;
    expect(advice.state, 'ahead');
    expect(advice.message('RM'), contains('RM 1.90 per remaining day'));
    expect(advice.message('RM'), contains('RM 186.00'));
    final exceeded = BudgetAdvice.calculate(
        [budget], [expense(1, 110)], month, DateTime(2026, 10, 10))!;
    expect(exceeded.state, 'exceeded');
    expect(exceeded.pace.remainingPerDay, 0);
  });
}
