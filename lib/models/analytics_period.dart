enum AnalyticsPeriod { week, month, year }

extension AnalyticsPeriodRange on AnalyticsPeriod {
  String get label => switch (this) {
        AnalyticsPeriod.week => 'Week',
        AnalyticsPeriod.month => 'Month',
        AnalyticsPeriod.year => 'Year',
      };
  DateTime start(DateTime date) => switch (this) {
        AnalyticsPeriod.week =>
          DateTime(date.year, date.month, date.day - date.weekday + 1),
        AnalyticsPeriod.month => DateTime(date.year, date.month),
        AnalyticsPeriod.year => DateTime(date.year),
      };
  DateTime end(DateTime date) {
    final first = start(date);
    return switch (this) {
      AnalyticsPeriod.week => DateTime(first.year, first.month, first.day + 7),
      AnalyticsPeriod.month => DateTime(first.year, first.month + 1),
      AnalyticsPeriod.year => DateTime(first.year + 1),
    };
  }

  DateTime move(DateTime date, int delta) => switch (this) {
        AnalyticsPeriod.week =>
          DateTime(date.year, date.month, date.day + delta * 7),
        AnalyticsPeriod.month => DateTime(date.year, date.month + delta),
        AnalyticsPeriod.year => DateTime(date.year + delta, date.month),
      };
}
