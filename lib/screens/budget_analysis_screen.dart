import '../services/ledger_totals.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/budget_alert.dart';
import '../models/transaction_model.dart';
import '../providers/expense_provider.dart';

class BudgetAnalysisScreen extends StatelessWidget {
  const BudgetAnalysisScreen({super.key, required this.alert});
  final BudgetAlert alert;
  @override
  Widget build(BuildContext context) {
    final entries = context
        .watch<ExpenseProvider>()
        .transactions
        .where((t) =>
            t.type == TransactionType.expense &&
            t.category == alert.budget.category &&
            t.date.year == alert.budget.month.year &&
            t.date.month == alert.budget.month.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final total = LedgerTotals.sum(entries.map((t) => t.amount));
    final shops = <String, double>{};
    for (final t in entries) {
      shops.update(t.title, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    final ranked = shops.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final heading =
        '${alert.budget.category.label} · ${DateFormat.yMMMM().format(alert.budget.month)}';
    final report =
        '$heading\nBudget: RM ${alert.budget.limit.toStringAsFixed(2)}\nSpent: RM ${total.toStringAsFixed(2)}\n\n' +
            entries
                .map((t) =>
                    '${DateFormat('dd-MM-yyyy').format(t.date)} — ${t.title}: RM ${t.amount.toStringAsFixed(2)}\n${t.note?.trim().isNotEmpty == true ? t.note : 'No item notes saved.'}')
                .join('\n\n');
    return Scaffold(
        appBar: AppBar(title: const Text('Budget analytics'), actions: [
          IconButton(
              tooltip: 'Share report',
              icon: const Icon(Icons.ios_share),
              onPressed: () => Share.share(report, subject: heading)),
        ]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(heading, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Budget: RM ${alert.budget.limit.toStringAsFixed(2)}'),
                        Text('Spent: RM ${total.toStringAsFixed(2)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(total > alert.budget.limit
                            ? 'Over budget: RM ${(total - alert.budget.limit).toStringAsFixed(2)}'
                            : 'Remaining: RM ${(alert.budget.limit - total).toStringAsFixed(2)}'),
                      ]))),
          const SizedBox(height: 20),
          const Text('Where you spent',
              style: TextStyle(fontWeight: FontWeight.bold)),
          for (final shop in ranked)
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(shop.key),
                trailing: Text('RM ${shop.value.toStringAsFixed(2)}')),
          const SizedBox(height: 16),
          const Text('Expenses and item notes',
              style: TextStyle(fontWeight: FontWeight.bold)),
          if (entries.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No expenses saved for this category and month.')),
          for (final t in entries)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${t.title} · RM ${t.amount.toStringAsFixed(2)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(DateFormat('dd-MM-yyyy').format(t.date)),
                          const SizedBox(height: 10),
                          SelectableText(t.note?.trim().isNotEmpty == true
                              ? t.note!
                              : 'No item notes saved.'),
                        ]))),
        ]));
  }
}
