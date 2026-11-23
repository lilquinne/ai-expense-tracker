import '../models/transaction_model.dart';
import 'spending_pace_service.dart';

class BudgetAdvice {
  BudgetAdvice(this.pace);
  final SpendingPace pace;
  static BudgetAdvice? calculate(List<BudgetModel> budgets,
      List<TransactionModel> transactions, DateTime month, DateTime now) {
    final active = budgets
        .where((b) =>
            b.limit > 0 &&
            b.month.year == month.year &&
            b.month.month == month.month)
        .toList();
    if (active.isEmpty) return null;
    final categories = active.map((b) => b.category).toSet();
    return BudgetAdvice(SpendingPace.calculate(
        transactions.where((t) => categories.contains(t.category)),
        month: month,
        asOf: now,
        budget: active.fold<double>(0, (sum, b) => sum + b.limit)));
  }

  String get state => pace.spentSen >= pace.budgetSen!
      ? 'exceeded'
      : pace.projectedSen == null
          ? 'learning'
          : pace.projectedSen! > pace.budgetSen! * 1.05
              ? 'ahead'
              : 'on-track';
  String message(String currency) {
    String money(double value) => '$currency ${value.toStringAsFixed(2)}';
    final lines = <String>[];
    if (pace.status == PaceStatus.future)
      return 'Your budget advice starts when this month begins.';
    if (pace.remainingPerDay != null) {
      lines.add(
          'Budget room: ${money(pace.remainingPerDay!)} per remaining day after today.');
    }
    if (pace.dailyAverage != null)
      lines.add('Recorded pace: ${money(pace.dailyAverage!)} per day.');
    if (pace.projected != null) {
      lines.add(
          'At this pace, month-end spending is about ${money(pace.projected!)} against ${money(pace.budgetSen! / 100)} budgeted.');
    } else if (pace.status == PaceStatus.completed) {
      lines.add('This month is complete.');
    } else {
      lines.add(
          'A forecast needs 7 elapsed days and spending on 3 different days.');
    }
    if (state == 'ahead')
      lines.add(
          'A smaller discretionary purchase today could help you stay within your plan.');
    if (state == 'exceeded')
      lines.add(
          'This budget is used up; review planned purchases or adjust the limit.');
    lines.add(
        'Budgeted categories only. Estimates assume your recorded pace continues.');
    return lines.join('\n');
  }
}
