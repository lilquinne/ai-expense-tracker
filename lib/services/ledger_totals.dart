import '../models/transaction_model.dart';

/// Recorded cash flow includes every saved entry in the selected period.
/// Forecasts must separately restrict evidence to their as-of date.
class LedgerTotals {
  static int sen(double amount) => (amount * 100).round();
  static bool inMonth(DateTime date, DateTime month) =>
      date.year == month.year && date.month == month.month;
  static double sum(Iterable<double> amounts) =>
      amounts.fold<int>(0, (total, amount) => total + sen(amount)) / 100;
  static Map<TransactionCategory, double> categories(
      Iterable<TransactionModel> records) {
    final totals = <TransactionCategory, int>{};
    for (final t in records.where((t) => t.type == TransactionType.expense)) {
      totals[t.category] = (totals[t.category] ?? 0) + sen(t.amount);
    }
    return totals.map((key, value) => MapEntry(key, value / 100));
  }

  static double usage(double spent, double limit) => sen(limit) > 0
      ? sen(spent) / sen(limit)
      : (spent > 0 ? double.infinity : 0);
}
