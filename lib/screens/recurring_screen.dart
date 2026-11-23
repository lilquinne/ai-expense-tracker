import '../widgets/recurring_confirmation.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../models/transaction_model.dart';
import '../widgets/transaction_tile.dart';
import 'transaction_detail_screen.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen(
      {super.key, this.initialOccurrenceId, this.initialAction});
  final String? initialOccurrenceId, initialAction;
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  Future<List<TransactionModel>>? records;
  bool handledAction = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    records ??= context.read<ExpenseProvider>().loadChartTransactions();
    if (!handledAction) {
      handledAction = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final p = context.read<ExpenseProvider>();
        await p.loadData();
        if (!mounted) return;
        setState(() {
          records = p.loadChartTransactions();
        });
        final occurrence = p.recurringDue
            .where((o) => o.id == widget.initialOccurrenceId)
            .firstOrNull;
        if (occurrence != null) {
          await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => RecurringConfirmation(
                  occurrence: occurrence, initialAction: widget.initialAction));
          if (mounted)
            setState(() {
              records = p.loadChartTransactions();
            });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    return Scaffold(
        appBar: AppBar(title: const Text('Recurring transactions')),
        body: FutureBuilder<List<TransactionModel>>(
            future: records,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(
                    child: TextButton(
                        onPressed: () => setState(() {
                              records = provider.loadChartTransactions();
                            }),
                        child:
                            const Text('Could not load transactions. Retry')));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final recurring = snapshot.data!
                  .where((t) => t.isRecurring)
                  .toList()
                ..sort((a, b) => b.date.compareTo(a.date));
              if (recurring.isEmpty)
                return const Center(
                    child: Text('No recurring transactions yet.'));
              return ListView(padding: const EdgeInsets.all(16), children: [
                if (provider.recurringDue.isNotEmpty) ...[
                  const Text('Waiting for confirmation',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  for (final o in provider.recurringDue)
                    Card(
                        child: ListTile(
                      title: Text('Recurring for ${o.template.title}'),
                      subtitle: Text(
                          '${provider.currencySymbol} ${o.template.amount.toStringAsFixed(2)} · ${DateFormat.yMMMd().format(o.date)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) =>
                                RecurringConfirmation(occurrence: o));
                        if (mounted)
                          setState(() {
                            records = provider.loadChartTransactions();
                          });
                      },
                    )),
                  const SizedBox(height: 20),
                ],
                const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Transactions marked as recurring',
                        style: TextStyle(fontSize: 12))),
                for (final t in recurring) ...[
                  SwitchListTile.adaptive(
                      title: Text('Reminders for ${t.title}',
                          style: const TextStyle(fontSize: 12)),
                      value: !provider.recurringMuted(t.id),
                      onChanged: (value) =>
                          provider.muteRecurring(t.id, !value)),
                  TransactionTile(
                      transaction: t,
                      accountName: provider.accountById(t.accountId)?.name ??
                          'Account unavailable',
                      currencySymbol: provider.currencySymbol,
                      categoryName: provider.categoryForTransaction(t).name,
                      categoryIcon: provider.categoryForTransaction(t).icon,
                      categoryColorValue:
                          provider.categoryForTransaction(t).colorValue,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  TransactionDetailScreen(transaction: t)))),
                ],
              ]);
            }));
  }
}
