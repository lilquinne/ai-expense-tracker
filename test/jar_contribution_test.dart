import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/treasure_jar.dart';
import 'package:expense_tracker/services/jar_contribution_service.dart';

void main() {
  TreasureJar jar({DateTime? deadline, int saved = 0}) => TreasureJar(
      id: 'j',
      name: 'Goal',
      accountId: 'bank',
      targetCents: 10000,
      savedCents: saved,
      deadline: deadline);
  test('weekly starts today and includes an aligned deadline, rounding upward',
      () {
    final plan = JarContributionPlan.calculate(
        jar(deadline: DateTime(2026, 1, 15)),
        asOf: DateTime(2026, 1, 1));
    expect(plan.weeklyPayments, 3);
    expect(plan.weeklySen, 3334);
    expect(plan.monthlyPayments, 1);
    expect(plan.monthlySen, 10000);
  });
  test('monthly anniversaries clamp shorter months without drifting', () {
    final plan = JarContributionPlan.calculate(
        jar(deadline: DateTime(2026, 3, 30)),
        asOf: DateTime(2026, 1, 31));
    expect(plan.monthlyPayments, 2);
    expect(plan.monthlySen, 5000);
    final aligned = JarContributionPlan.calculate(
        jar(deadline: DateTime(2026, 3, 31)),
        asOf: DateTime(2026, 1, 31));
    expect(aligned.monthlyPayments, 3);
  });
  test('same-day deadline uses one payment and ignores time of day', () {
    final plan = JarContributionPlan.calculate(
        jar(deadline: DateTime(2026, 1, 1)),
        asOf: DateTime(2026, 1, 1, 23, 59));
    expect(plan.weeklySen, 10000);
    expect(plan.monthlySen, 10000);
  });
  test('missing, overdue and reached states never invent a schedule', () {
    expect(JarContributionPlan.calculate(jar(), asOf: DateTime(2026)).status,
        JarPlanStatus.noDeadline);
    final overdue = JarContributionPlan.calculate(jar(deadline: DateTime(2025)),
        asOf: DateTime(2026));
    expect(overdue.status, JarPlanStatus.overdue);
    expect(overdue.weeklySen, isNull);
    final reached =
        JarContributionPlan.calculate(jar(saved: 10000), asOf: DateTime(2026));
    expect(reached.status, JarPlanStatus.reached);
    expect(reached.remainingSen, 0);
  });
  test('leap years and partial savings change only the plan', () {
    final goal = jar(deadline: DateTime(2024, 2, 29), saved: 2500);
    final plan =
        JarContributionPlan.calculate(goal, asOf: DateTime(2024, 1, 31));
    expect(plan.monthlyPayments, 2);
    expect(plan.monthlySen, 3750);
    expect(goal.savedCents, 2500);
    expect(plan.weeklyPayments, 5);
  });
}
