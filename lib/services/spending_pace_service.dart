import '../models/transaction_model.dart';
import 'ledger_totals.dart';

enum PaceStatus { future, insufficientHistory, current, completed }

/// Estimates use saved expense records only; no AI, network or balance writes.
class SpendingPace {
  SpendingPace._(
      {required this.status,
      required this.month,
      required this.asOf,
      required this.elapsedDays,
      required this.daysInMonth,
      required this.spentSen,
      required this.records,
      required this.categorySen,
      required this.comparisonDays,
      required this.comparisonCurrentSen,
      required this.previousSen,
      required this.categoryDeltaSen,
      required this.projectedSen,
      required this.budgetSen});
  final PaceStatus status;
  final DateTime month, asOf;
  final int elapsedDays,
      daysInMonth,
      spentSen,
      comparisonDays,
      comparisonCurrentSen;
  final int? previousSen, projectedSen, budgetSen;
  final List<TransactionModel> records;
  final Map<TransactionCategory, int> categorySen, categoryDeltaSen;
  double get spent => spentSen / 100;
  double? get dailyAverage =>
      elapsedDays == 0 ? null : spentSen / elapsedDays / 100;
  double? get projected => projectedSen == null ? null : projectedSen! / 100;
  int? get changeSen =>
      previousSen == null ? null : comparisonCurrentSen - previousSen!;
  double? get changePercent => previousSen == null || previousSen == 0
      ? null
      : changeSen! / previousSen! * 100;
  double? get remainingPerDay => budgetSen == null ||
          status == PaceStatus.future ||
          elapsedDays >= daysInMonth
      ? null
      : (budgetSen! - spentSen).clamp(0, budgetSen!) /
          (daysInMonth - elapsedDays) /
          100;

  static const minimumDays = 7;
  static const minimumSpendingDays = 3;

  static SpendingPace calculate(Iterable<TransactionModel> source,
      {required DateTime month, required DateTime asOf, double? budget}) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final today = DateTime(asOf.year, asOf.month, asOf.day);
    final future = start.isAfter(today);
    final completed = !end.isAfter(today);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final elapsed = future
        ? 0
        : completed
            ? days
            : asOf.day;
    final expenses = source
        .where((t) =>
            t.type == TransactionType.expense &&
            t.amount.isFinite &&
            t.amount > 0 &&
            !t.date.isAfter(asOf))
        .toList();
    final records = expenses
        .where((t) => !t.date.isBefore(start) && t.date.isBefore(end))
        .toList()
      ..sort((a, b) {
        final amount = b.amount.compareTo(a.amount);
        return amount == 0 ? a.id.compareTo(b.id) : amount;
      });
    int sum(Iterable<TransactionModel> rows) =>
        rows.fold<int>(0, (v, t) => v + LedgerTotals.sen(t.amount));
    Map<TransactionCategory, int> categories(Iterable<TransactionModel> rows) {
      final totals = <TransactionCategory, int>{};
      for (final t in rows) {
        totals[t.category] =
            (totals[t.category] ?? 0) + LedgerTotals.sen(t.amount);
      }
      return totals;
    }

    final spent = sum(records);
    final distinctDays = records.map((t) => t.date.day).toSet().length;
    final enough =
        elapsed >= minimumDays && distinctDays >= minimumSpendingDays;
    final status = future
        ? PaceStatus.future
        : completed
            ? PaceStatus.completed
            : enough
                ? PaceStatus.current
                : PaceStatus.insufficientHistory;
    final previousStart = DateTime(month.year, month.month - 1);
    final previousDays = DateTime(month.year, month.month, 0).day;
    final matchedDays = elapsed < previousDays ? elapsed : previousDays;
    // For current periods compare the same number of days and time of day.
    // Completed periods compare equally long prefixes of both months.
    final currentCutoff = completed || elapsed > matchedDays
        ? DateTime(month.year, month.month, matchedDays + 1)
        : asOf;
    final previousCutoff = completed || elapsed > matchedDays
        ? DateTime(previousStart.year, previousStart.month, matchedDays + 1)
        : DateTime(
            previousStart.year,
            previousStart.month,
            matchedDays,
            asOf.hour,
            asOf.minute,
            asOf.second,
            asOf.millisecond,
            asOf.microsecond);
    final currentComparison = records
        .where((t) => completed || elapsed > matchedDays
            ? t.date.isBefore(currentCutoff)
            : !t.date.isAfter(currentCutoff))
        .toList();
    final previous = expenses
        .where((t) =>
            !t.date.isBefore(previousStart) &&
            t.date.isBefore(start) &&
            (completed || elapsed > matchedDays
                ? t.date.isBefore(previousCutoff)
                : !t.date.isAfter(previousCutoff)))
        .toList();
    final hasComparison = !future &&
        previous.map((t) => t.date.day).toSet().length >= minimumSpendingDays;
    final deltas = <TransactionCategory, int>{};
    if (hasComparison) {
      final currentCategories = categories(currentComparison),
          previousCategories = categories(previous);
      for (final c in {...currentCategories.keys, ...previousCategories.keys}) {
        deltas[c] = (currentCategories[c] ?? 0) - (previousCategories[c] ?? 0);
      }
    }
    return SpendingPace._(
        status: status,
        month: start,
        asOf: asOf,
        elapsedDays: elapsed,
        daysInMonth: days,
        spentSen: spent,
        records: List.unmodifiable(records),
        categorySen: Map.unmodifiable(categories(records)),
        comparisonDays: matchedDays,
        comparisonCurrentSen: sum(currentComparison),
        previousSen: hasComparison ? sum(previous) : null,
        categoryDeltaSen: Map.unmodifiable(deltas),
        projectedSen: status == PaceStatus.current
            ? (spent * days / elapsed).round()
            : null,
        budgetSen: budget != null && budget.isFinite && budget > 0
            ? LedgerTotals.sen(budget)
            : null);
  }
}
