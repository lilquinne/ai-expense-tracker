import '../services/ledger_totals.dart';
import 'transaction_model.dart';

/// A live warning derived from one month's saved budget and expenses.
class BudgetAlert {
  final BudgetModel budget;
  final double spent;
  final DateTime? triggeredAt;
  const BudgetAlert(this.budget, this.spent, {this.triggeredAt});

  int get level => spent >= budget.limit ? 2 : 1;
  double get ratio => spent / budget.limit;
  String get key =>
      '${budget.month.year}-${budget.month.month}-${budget.category.name}';
  String get title => spent > budget.limit
      ? '${budget.category.label} is over budget'
      : level == 2
          ? '${budget.category.label} budget reached'
          : '${budget.category.label} is nearing its limit';

  String message(String currency) => spent > budget.limit
      ? '$currency ${(spent - budget.limit).toStringAsFixed(2)} over your '
          '$currency ${budget.limit.toStringAsFixed(2)} budget.'
      : '$currency ${spent.toStringAsFixed(2)} of '
          '$currency ${budget.limit.toStringAsFixed(2)} used '
          '(${(ratio * 100).floor()}%).';

  static List<BudgetAlert> evaluate(
      List<BudgetModel> budgets, List<TransactionModel> transactions) {
    final alerts = <BudgetAlert>[];
    for (final budget in budgets) {
      if (!budget.limit.isFinite || budget.limit <= 0) continue;
      final spent = LedgerTotals.sum(transactions
          .where((t) =>
              t.type == TransactionType.expense &&
              t.category == budget.category &&
              LedgerTotals.inMonth(t.date, budget.month))
          .map((t) => t.amount));
      if (spent >= budget.limit * .8) {
        final records = transactions
            .where((t) =>
                t.type == TransactionType.expense &&
                t.category == budget.category &&
                LedgerTotals.inMonth(t.date, budget.month))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        final threshold =
            spent >= budget.limit ? budget.limit : budget.limit * .8;
        double running = 0;
        DateTime? triggered;
        for (final record in records) {
          running = LedgerTotals.sum([running, record.amount]);
          if (running >= threshold && triggered == null)
            triggered = record.date;
        }
        alerts.add(BudgetAlert(budget, spent, triggeredAt: triggered));
      }
    }
    alerts.sort((a, b) => b.ratio.compareTo(a.ratio));
    return alerts;
  }
}
