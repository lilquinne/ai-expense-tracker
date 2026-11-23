import 'monthly_analysis.dart';
import 'transaction_model.dart';

class ReportSelection {
  const ReportSelection(this.date, {this.annual = false});
  final DateTime date;
  final bool annual;
  static List<int> recordedYears(Iterable<TransactionModel> records) =>
      records.map((t) => t.date.year).toSet().toList()
        ..sort((a, b) => b.compareTo(a));
  MonthlyAnalysis analyze(
          Iterable<TransactionModel> records, List<AppCategory> categories) =>
      MonthlyAnalysis(records, date,
          categories: categories,
          periodStart:
              annual ? DateTime(date.year) : DateTime(date.year, date.month),
          periodEnd: annual
              ? DateTime(date.year + 1)
              : DateTime(date.year, date.month + 1));
}
