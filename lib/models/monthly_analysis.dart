import '../services/ledger_totals.dart';
import 'transaction_model.dart';

/// One month of recorded cash flow, shared by the calendar and reports.
class MonthlyAnalysis {
  MonthlyAnalysis(Iterable<TransactionModel> source, this.month,
      {List<AppCategory> categories = const [],
      DateTime? periodStart,
      DateTime? periodEnd}) {
    transactions = source
        .where((t) =>
            !t.date
                .isBefore(periodStart ?? DateTime(month.year, month.month)) &&
            t.date.isBefore(periodEnd ?? DateTime(month.year, month.month + 1)))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final t in transactions) {
      final day = days.putIfAbsent(t.date.day, () => DayCashFlow());
      day.transactions.add(t);
      if (t.type == TransactionType.income) {
        income = (LedgerTotals.sen(income) + LedgerTotals.sen(t.amount)) / 100;
        day.income =
            (LedgerTotals.sen(day.income) + LedgerTotals.sen(t.amount)) / 100;
      } else {
        expense =
            (LedgerTotals.sen(expense) + LedgerTotals.sen(t.amount)) / 100;
        day.expense =
            (LedgerTotals.sen(day.expense) + LedgerTotals.sen(t.amount)) / 100;
        var custom = categories.where((c) => c.id == t.categoryId).firstOrNull;
        final visited = <String>{};
        while (custom?.parentId != null && visited.add(custom!.id)) {
          final parent =
              categories.where((c) => c.id == custom!.parentId).firstOrNull;
          if (parent == null) break;
          custom = parent;
        }
        final key = custom?.id ?? t.category.name;
        final category = categoryTotals.putIfAbsent(
            key,
            () => CategoryTotal(custom?.name ?? t.category.label,
                custom?.colorValue ?? t.category.colorValue));
        category.amount =
            (LedgerTotals.sen(category.amount) + LedgerTotals.sen(t.amount)) /
                100;
      }
    }
  }

  final DateTime month;
  late final List<TransactionModel> transactions;
  final Map<int, DayCashFlow> days = {};
  final Map<String, CategoryTotal> categoryTotals = {};
  double income = 0;
  double expense = 0;
  double get net =>
      (LedgerTotals.sen(income) - LedgerTotals.sen(expense)) / 100;
  List<CategoryTotal> get rankedCategories => categoryTotals.values.toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
}

class DayCashFlow {
  double income = 0;
  double expense = 0;
  final List<TransactionModel> transactions = [];
}

class CategoryTotal {
  CategoryTotal(this.name, this.color);
  final String name;
  final int color;
  double amount = 0;
}
