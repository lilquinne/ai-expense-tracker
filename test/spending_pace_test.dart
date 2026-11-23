import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/services/spending_pace_service.dart';

TransactionModel expense(String id, DateTime date, double amount,
        {TransactionCategory category = TransactionCategory.groceries,
        TransactionType type = TransactionType.expense}) =>
    TransactionModel(
        id: id,
        title: id,
        date: date,
        amount: amount,
        type: type,
        category: category);
void main() {
  final month = DateTime(2026, 10);
  final now = DateTime(2026, 10, 10, 12);
  List<TransactionModel> threeDays(int month) => [
        for (var day = 1; day <= 3; day++)
          expense('$month-$day', DateTime(2026, month, day), 10),
      ];
  test('pace projects in sen and excludes later records and income', () {
    final pace = SpendingPace.calculate([
      ...threeDays(10),
      expense('later', DateTime(2026, 10, 10, 13), 100),
      expense('future', DateTime(2026, 10, 20), 100),
      expense('income', DateTime(2026, 10, 1), 500,
          type: TransactionType.income),
    ], month: month, asOf: now, budget: 100);
    expect(pace.status, PaceStatus.current);
    expect(pace.spentSen, 3000);
    expect(pace.projectedSen, 9300);
    expect(pace.dailyAverage, 3);
    expect(pace.remainingPerDay, closeTo(70 / 21, .00001));
    expect(pace.records.length, 3);
  });
  test('sparse, new, future and completed months have no forecast', () {
    expect(
        SpendingPace.calculate(threeDays(10),
                month: month, asOf: DateTime(2026, 10, 3))
            .status,
        PaceStatus.insufficientHistory);
    expect(
        SpendingPace.calculate([expense('one', month, 100)],
                month: month, asOf: now)
            .projected,
        isNull);
    final future =
        SpendingPace.calculate([], month: DateTime(2026, 11), asOf: now);
    expect(future.status, PaceStatus.future);
    expect(future.dailyAverage, isNull);
    expect(future.projected, isNull);
    final past = SpendingPace.calculate(threeDays(9),
        month: DateTime(2026, 9), asOf: now);
    expect(past.status, PaceStatus.completed);
    expect(past.elapsedDays, 30);
    expect(past.projected, isNull);
    expect(past.remainingPerDay, isNull);
  });
  test(
      'comparison matches days, excludes later previous-month purchases and explains deltas',
      () {
    final pace = SpendingPace.calculate([
      ...threeDays(10),
      ...threeDays(9),
      expense('increase', DateTime(2026, 10, 4), 15,
          category: TransactionCategory.transport),
      expense('old-late', DateTime(2026, 9, 11), 100),
    ], month: month, asOf: now);
    expect(pace.previousSen, 3000);
    expect(pace.changeSen, 1500);
    expect(pace.changePercent, 50);
    expect(pace.categoryDeltaSen[TransactionCategory.transport], 1500);
    expect(pace.categoryDeltaSen.values.fold<int>(0, (a, b) => a + b),
        pace.changeSen);
    expect(pace.records.first.id, 'increase');
  });
  test('short February and leap year compare equally long prefixes', () {
    for (final year in [2024, 2025]) {
      final days = DateTime(year, 3, 0).day;
      final rows = [
        for (final m in [2, 3])
          for (final day in [1, 2, 3])
            expense('$m-$day', DateTime(year, m, day), .1),
        expense('last-march', DateTime(year, 3, 31), 100)
      ];
      final pace = SpendingPace.calculate(rows,
          month: DateTime(year, 3), asOf: DateTime(year, 3, 31, 12));
      expect(pace.comparisonDays, days);
      expect(pace.comparisonCurrentSen, 30);
      expect(pace.previousSen, 30);
      expect(pace.changeSen, 0);
      expect(pace.spentSen, 10030);
    }
  });
  test(
      'missing history is not silently treated as zero and budget overspend stays finite',
      () {
    final pace = SpendingPace.calculate(threeDays(10),
        month: month, asOf: now, budget: 10);
    expect(pace.previousSen, isNull);
    expect(pace.changePercent, isNull);
    expect(pace.categoryDeltaSen, isEmpty);
    expect(pace.remainingPerDay, 0);
  });
  test(
      'December to January comparison and future-record rejection use supplied clock',
      () {
    final rows = [
      for (final date in [DateTime(2025, 12), DateTime(2026, 1)])
        for (final day in [1, 2, 3])
          expense('${date.month}-$day', DateTime(date.year, date.month, day), 1)
    ];
    final pace = SpendingPace.calculate(rows,
        month: DateTime(2026, 1), asOf: DateTime(2026, 1, 10));
    expect(pace.previousSen, 300);
    expect(pace.changeSen, 0);
  });
}
