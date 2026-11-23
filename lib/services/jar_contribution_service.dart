import '../models/treasure_jar.dart';

enum JarPlanStatus { reached, noDeadline, overdue, active }

/// Contributions are opportunities starting today, never posted money.
class JarContributionPlan {
  const JarContributionPlan(this.status, this.remainingSen,
      {this.weeklyPayments = 0, this.monthlyPayments = 0});
  final JarPlanStatus status;
  final int remainingSen, weeklyPayments, monthlyPayments;
  int? get weeklySen => weeklyPayments == 0
      ? null
      : (remainingSen + weeklyPayments - 1) ~/ weeklyPayments;
  int? get monthlySen => monthlyPayments == 0
      ? null
      : (remainingSen + monthlyPayments - 1) ~/ monthlyPayments;

  static JarContributionPlan calculate(TreasureJar jar,
      {required DateTime asOf}) {
    final remaining =
        (jar.targetCents - jar.savedCents).clamp(0, jar.targetCents);
    if (remaining == 0)
      return const JarContributionPlan(JarPlanStatus.reached, 0);
    if (jar.deadline == null)
      return JarContributionPlan(JarPlanStatus.noDeadline, remaining);
    // UTC date-only arithmetic avoids daylight-saving changes in day counts.
    final today = DateTime.utc(asOf.year, asOf.month, asOf.day);
    final deadline = DateTime.utc(
        jar.deadline!.year, jar.deadline!.month, jar.deadline!.day);
    if (deadline.isBefore(today))
      return JarContributionPlan(JarPlanStatus.overdue, remaining);
    final weekly = 1 + deadline.difference(today).inDays ~/ 7;
    var monthly = 1;
    for (var offset = 1;; offset++) {
      final lastDay = DateTime.utc(today.year, today.month + offset + 1, 0).day;
      final next = DateTime.utc(
          today.year, today.month + offset, today.day.clamp(1, lastDay));
      if (next.isAfter(deadline)) break;
      monthly++;
    }
    return JarContributionPlan(JarPlanStatus.active, remaining,
        weeklyPayments: weekly, monthlyPayments: monthly);
  }
}
