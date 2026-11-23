import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../providers/expense_provider.dart';
import '../services/spending_pace_service.dart';

class SpendingPaceCard extends StatefulWidget {
  const SpendingPaceCard({super.key});
  @override
  State<SpendingPaceCard> createState() => _SpendingPaceCardState();
}

class _SpendingPaceCardState extends State<SpendingPaceCard> {
  Future<List<TransactionModel>>? _future;
  String? _owner;
  int? _revision;
  List<TransactionModel>? _records;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.watch<ExpenseProvider>();
    if (_owner != provider.userId ||
        _revision != provider.chartRevision ||
        !identical(_records, provider.transactions)) {
      _owner = provider.userId;
      _revision = provider.chartRevision;
      _records = provider.transactions;
      _future = provider.loadChartTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final month = provider.selectedMonth;
    final owner = provider.userId;
    final budgetCategories = provider.budgets.map((b) => b.category).toSet();
    String money(num amount) =>
        '${provider.currencySymbol} ${amount.toStringAsFixed(2)}';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: FutureBuilder<List<TransactionModel>>(
                key: ValueKey('$owner:$_revision'),
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Spending pace unavailable.'),
                          TextButton(
                              onPressed: () => setState(() {
                                    _future = provider.loadChartTransactions();
                                  }),
                              child: const Text('Retry'))
                        ]);
                  }
                  if (provider.isLoading ||
                      snapshot.connectionState != ConnectionState.done) {
                    return const Text('Loading spending pace…');
                  }
                  // Pace and budget refer to the same category set. No budgets means all expenses.
                  final rows = (snapshot.data ?? []).where((t) =>
                      budgetCategories.isEmpty ||
                      budgetCategories.contains(t.category));
                  final pace = SpendingPace.calculate(rows,
                      month: month,
                      asOf: DateTime.now(),
                      budget: budgetCategories.isEmpty
                          ? null
                          : provider.totalBudget);
                  final increases = pace.categoryDeltaSen.entries
                      .where((e) => e.value > 0)
                      .toList()
                    ..sort((a, b) => b.value.compareTo(a.value));
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Spending pace · ${DateFormat.yMMMM().format(month)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(budgetCategories.isEmpty
                            ? 'All expense categories'
                            : 'Budgeted categories only'),
                        const SizedBox(height: 8),
                        if (pace.status == PaceStatus.future)
                          const Text(
                              'Forecasts are available once this month starts.')
                        else ...[
                          Text(
                              'Spent through ${DateFormat.yMMMd().format(pace.asOf)}: ${money(pace.spent)}'),
                          if (pace.dailyAverage != null)
                            Text(
                                'Average per elapsed day: ${money(pace.dailyAverage!)}'),
                          if (pace.projected != null) ...[
                            Text(
                                'Estimated month-end spending: ${money(pace.projected!)}'),
                            const Text(
                                'Estimate assumes spending continues at the same daily rate.'),
                          ] else if (pace.status == PaceStatus.completed)
                            const Text('Completed month · no forecast needed.')
                          else
                            const Text(
                                'Not enough history for a forecast. Needs 7 elapsed days and expenses on 3 different days.'),
                          if (pace.remainingPerDay != null)
                            Text(
                                'Budget available per remaining day: ${money(pace.remainingPerDay!)}'),
                          const SizedBox(height: 8),
                          if (pace.previousSen == null)
                            const Text(
                                'Not enough previous-month records for a comparison.')
                          else ...[
                            Text(
                                'First ${pace.comparisonDays} days vs previous month: ${money(pace.comparisonCurrentSen / 100)} vs ${money(pace.previousSen! / 100)}'),
                            Text(
                                'Change: ${pace.changeSen! >= 0 ? '+' : '-'}${money(pace.changeSen!.abs() / 100)}${pace.changePercent == null ? '' : ' (${pace.changePercent!.toStringAsFixed(1)}%)'}'),
                            for (final entry in increases.take(3))
                              Text(
                                  '${entry.key.label}: +${money(entry.value / 100)}'),
                            const Text(
                                'Comparison uses saved records; missing entries can affect it.'),
                          ],
                          if (pace.records.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text('Largest recorded expenses',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            for (final t in pace.records.take(3))
                              Text(
                                  '${t.title} · ${DateFormat.MMMd().format(t.date)} · ${money(t.amount)}'),
                          ],
                        ],
                      ]);
                })));
  }
}
