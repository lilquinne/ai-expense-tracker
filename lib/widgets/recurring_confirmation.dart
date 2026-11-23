import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../services/recurring_service.dart';

class RecurringConfirmation extends StatefulWidget {
  const RecurringConfirmation(
      {super.key, required this.occurrence, this.initialAction});
  final RecurringOccurrence occurrence;
  final String? initialAction;
  @override
  State<RecurringConfirmation> createState() => _RecurringConfirmationState();
}

class _RecurringConfirmationState extends State<RecurringConfirmation> {
  bool busy = false;
  String? error;
  late final String owner;
  @override
  void initState() {
    super.initState();
    owner = context.read<ExpenseProvider>().userId;
    if (widget.initialAction == 'confirm' || widget.initialAction == 'mute') {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => act(widget.initialAction!));
    }
  }

  Future<void> act(String action) async {
    if (busy || !mounted) return;
    final provider = context.read<ExpenseProvider>();
    if (provider.userId != owner) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (action == 'mute') {
        await provider.muteRecurring(widget.occurrence.template.id, true);
      } else {
        await provider.confirmRecurring(widget.occurrence);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error =
              'Could not confirm. Check the account in the original transaction, then try again.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ExpenseProvider>();
    final o = widget.occurrence;
    return PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: Text('Recurring for ${o.template.title}'),
          content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    '${p.currencySymbol} ${o.template.amount.toStringAsFixed(2)} · ${DateFormat.yMMMd().format(o.date)}'),
                const SizedBox(height: 10),
                Text(
                    'Account: ${p.accountById(o.template.accountId)?.name ?? 'Account unavailable'}'),
                const SizedBox(height: 10),
                const Text(
                    'Confirm to record this transaction. Nothing is added until you confirm.'),
                const SizedBox(height: 8),
                const Text(
                    'Do not show this again silences reminders for this item. You can still confirm it in Recurring transactions.',
                    style: TextStyle(fontSize: 12)),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error!)),
              ])),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Later')),
            TextButton(
                onPressed: busy ? null : () => act('mute'),
                child: const Text('Do not show this again')),
            FilledButton(
                onPressed: busy ? null : () => act('confirm'),
                child: Text(busy ? 'Saving…' : 'Confirm')),
          ],
        ));
  }
}
