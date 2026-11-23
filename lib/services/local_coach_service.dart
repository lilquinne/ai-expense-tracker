import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../models/treasure_jar.dart';
import 'database_service.dart';
import 'ledger_totals.dart';
import 'spending_pace_service.dart';

enum LocalCoachIntent { budget, comparison, pace, jars, categories }

class LocalCoachService {
  static LocalCoachIntent? intent(String message) {
    final q = message.toLowerCase().trim();
    if (RegExp(
            r'\b(next|yesterday|tomorrow|year|week|january|february|march|april|may|june|july|august|september|october|november|december)\b|\d{4}')
        .hasMatch(q)) return null;
    if (q.contains('last month') &&
        !RegExp(r'compare|changed|comparison|increased|decreased').hasMatch(q))
      return null;
    final subjects = [
      RegExp(r'\b(jar|jars|saved goal|goal progress)\b').hasMatch(q),
      RegExp(r'\b(budget|budgets)\b').hasMatch(q),
      RegExp(r'\b(changed|compare|comparison|increased|decreased)\b')
          .hasMatch(q),
      RegExp(r'\b(pace|forecast|projection|projected)\b').hasMatch(q),
    ].where((matched) => matched).length;
    if (subjects > 1) return null;
    // Plans and ambiguous follow-ups need the existing contextual Coach path.
    if (RegExp(r'\b(plan|should|recommend|could i|can i|why)\b').hasMatch(q))
      return null;
    if (RegExp(r'\b(jar|jars|saved goal|goal progress)\b').hasMatch(q))
      return LocalCoachIntent.jars;
    if (RegExp(r'\b(budget|budgets)\b').hasMatch(q))
      return LocalCoachIntent.budget;
    if (RegExp(r'\b(changed|compare|comparison|increased|decreased)\b')
        .hasMatch(q)) return LocalCoachIntent.comparison;
    if (RegExp(r'\b(pace|forecast|projection|projected)\b').hasMatch(q))
      return LocalCoachIntent.pace;
    if (q == 'where does most of my money go?' ||
        RegExp(r'\b(top categories|largest expenses|biggest expenses)\b')
            .hasMatch(q)) return LocalCoachIntent.categories;
    return null;
  }

  static Future<Map<String, dynamic>?> answer(
      String owner, String message, DateTime month, String currency,
      {DateTime? asOf}) async {
    final kind = intent(message);
    if (kind == null || owner.isEmpty) return null;
    final db = DatabaseService();
    // Retrieve only evidence used by the selected calculation, always scoped to owner.
    if (kind == LocalCoachIntent.jars) {
      return calculate(kind,
          message: message,
          month: month,
          currency: currency,
          asOf: asOf ?? DateTime.now(),
          jars: await db.getJars(owner));
    }
    final records = await db.getTransactionsByMonth(month, userId: owner);
    if (kind == LocalCoachIntent.comparison) {
      records.addAll(await db.getTransactionsByMonth(
          DateTime(month.year, month.month - 1),
          userId: owner));
    }
    final budgets = kind == LocalCoachIntent.budget
        ? await db.getBudgetsByMonth(month, userId: owner)
        : <BudgetModel>[];
    return calculate(kind,
        message: message,
        month: month,
        currency: currency,
        asOf: asOf ?? DateTime.now(),
        records: records,
        budgets: budgets);
  }

  static Map<String, dynamic> calculate(LocalCoachIntent kind,
      {required String message,
      required DateTime month,
      required DateTime asOf,
      required String currency,
      List<TransactionModel> records = const [],
      List<BudgetModel> budgets = const [],
      List<TreasureJar> jars = const []}) {
    String money(int sen) => '$currency ${(sen / 100).toStringAsFixed(2)}';
    final metrics = <String, dynamic>{};
    final lines = <String>[
      kind == LocalCoachIntent.jars
          ? 'Your saved jars'
          : '${DateFormat.yMMMM().format(month)} · saved records'
    ];
    final q = message.toLowerCase();
    final matches = TransactionCategory.values
        .where((c) => q.contains(c.name) || q.contains(c.label.toLowerCase()))
        .toList();
    final category = matches.length == 1 ? matches.single : null;
    final selected = records
        .where((t) => matches.isEmpty || matches.contains(t.category))
        .toList();
    if (kind != LocalCoachIntent.jars)
      lines.add(matches.isEmpty
          ? 'All expenses'
          : matches.map((c) => c.label).join(', '));
    final pace = SpendingPace.calculate(selected, month: month, asOf: asOf);
    if (kind == LocalCoachIntent.jars) {
      final matches =
          jars.where((j) => q.contains(j.name.toLowerCase())).toList();
      final selectedJars = matches.isEmpty ? jars : matches;
      if (selectedJars.isEmpty) lines.add('No saved Treasure Jars were found.');
      for (final jar in selectedJars) {
        final remaining =
            (jar.targetCents - jar.savedCents).clamp(0, jar.targetCents);
        lines.add(
            '${jar.name}: ${money(jar.savedCents)} reserved toward ${money(jar.targetCents)}; ${money(remaining)} remaining.');
      }
      lines.add('Jars set money aside; they do not add money to your bank.');
      metrics['jar_saved'] =
          money(selectedJars.fold<int>(0, (s, j) => s + j.savedCents));
    } else if (pace.status == PaceStatus.future) {
      lines.add('This month has not started yet.');
    } else if (kind == LocalCoachIntent.budget) {
      final selectedBudgets = budgets
          .where((b) => matches.isEmpty || matches.contains(b.category))
          .toList();
      if (selectedBudgets.isEmpty)
        lines.add('No budget is set for this selection.');
      for (final budget in selectedBudgets) {
        final spent = pace.categorySen[budget.category] ?? 0;
        final limit = LedgerTotals.sen(budget.limit);
        final remaining = limit - spent;
        lines.add(
            '${budget.category.label}: ${money(spent)} spent of ${money(limit)}; ${money(remaining.abs())} ${remaining < 0 ? 'over budget' : 'remaining'}.');
        metrics['budget_${budget.category.name}'] = money(remaining);
      }
      lines.add('Based on expenses saved so far.');
    } else if (kind == LocalCoachIntent.comparison) {
      if (pace.previousSen == null) {
        lines.add(
            'I need expenses from three different days last month to compare.');
      } else {
        lines.add(
            'Across the first ${pace.comparisonDays} matched days: ${money(pace.comparisonCurrentSen)} this month versus ${money(pace.previousSen!)} last month.');
        lines.add(
            'Your spending ${pace.changeSen! < 0 ? 'decreased' : 'increased'} by ${money(pace.changeSen!.abs())}.');
        final deltas = pace.categoryDeltaSen.entries
            .where((e) => e.value != 0)
            .toList()
          ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
        for (final e in deltas.take(3)) {
          lines.add(
              '${e.key.label}: ${e.value > 0 ? '+' : '-'}${money(e.value.abs())}.');
        }
        metrics['comparison_previous'] = money(pace.previousSen!);
        metrics['comparison_current'] = money(pace.comparisonCurrentSen);
      }
    } else if (kind == LocalCoachIntent.pace) {
      if (pace.projectedSen != null) {
        lines.add(
            'At the recorded daily rate, estimated month-end spending is ${money(pace.projectedSen!)}. This assumes the same rate continues.');
        metrics['projected_expenses'] = money(pace.projectedSen!);
      } else {
        lines.add(pace.status == PaceStatus.completed
            ? 'This month is complete; no forecast is needed.'
            : 'I need seven days of history and spending on three days to estimate.');
      }
    } else {
      final categories = pace.categorySen.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (categories.isEmpty) lines.add('No expenses saved here yet.');
      for (final e in categories.take(3)) {
        lines.add('${e.key.label}: ${money(e.value)}.');
      }
      for (final t in pace.records.take(3)) {
        lines.add(
            '${t.title} (${DateFormat.MMMd().format(t.date)}): ${money(LedgerTotals.sen(t.amount))}.');
      }
    }
    if (kind != LocalCoachIntent.jars)
      metrics['expenses_0'] = money(pace.spentSen);
    return {
      'answer': lines.join('\n'),
      'fallback': false,
      'suggestPlan': false,
      'evidence': {
        'source': 'local',
        'selectedMonth': DateFormat('yyyy-MM').format(month),
        'asOf': asOf.toIso8601String(),
        'metrics': metrics,
        'summary': {
          'expenses': pace.spent,
          'scope': category?.label ?? 'All expenses'
        }
      }
    };
  }
}
