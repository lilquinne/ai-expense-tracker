/// Tracks entry reminders for the lifetime of this app process.
class DailyGuideReminder {
  static final session = DailyGuideReminder();
  final Set<String> _shownFor = {};

  bool claimLaunch(String userId) => _shownFor.add(userId);

  static String preferenceKey(String userId) =>
      'daily_guide_hidden_date:$userId';
  static String localDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
