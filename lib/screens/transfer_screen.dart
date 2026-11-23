import '../widgets/amount_keypad.dart';
import '../models/transaction_model.dart';
import '../utils/operation_message.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../providers/expense_provider.dart';
import '../services/database_service.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key, this.embedded = false, this.header});
  final bool embedded;
  final Widget? header;
  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  String? from, to, error;
  final amount = TextEditingController(), note = TextEditingController();
  DateTime date = DateTime.now();
  bool busy = false;
  String calculation = '';
  final totalController = TextEditingController();
  final amountFocus = FocusNode();
  final noteFocus = FocusNode();
  late final String formOwner;
  @override
  void initState() {
    super.initState();
    formOwner = context.read<ExpenseProvider>().userId;
    noteFocus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    totalController.dispose();
    amountFocus.dispose();
    noteFocus.dispose();
    super.dispose();
  }

  Future<void> _saveTransfer() async {
    if (busy) return;
    final p = context.read<ExpenseProvider>();
    if (p.userId != formOwner) {
      setState(() => error = 'Account changed. Reopen the transfer form.');
      return;
    }

    if (from == null ||
        to == null ||
        !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(amount.text.trim())) {
      setState(() => error = 'Choose both accounts and a valid amount.');
      return;
    }
    setState(() => busy = true);
    try {
      await DatabaseService().transfer(
          owner: p.userId,
          id: const Uuid().v4(),
          from: from!,
          to: to!,
          sen: (double.parse(amount.text) * 100).round(),
          date: date,
          note: note.text);
      await p.loadData();
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(() {
          error = operationMessage(
              e, 'Could not save the record. Please try again.');
          busy = false;
        });
    }
  }

  Future<void> _dateSheet() async {
    var selected = date;
    final result = await showModalBottomSheet<DateTime>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Select date'),
                  SizedBox(
                      height: 300,
                      child: CalendarDatePicker(
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          onDateChanged: (d) => selected = d)),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, selected),
                      child: const Text('Confirm')),
                ]))));
    if (result != null && mounted) setState(() => date = result);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ExpenseProvider>();
    return Scaffold(
        appBar: widget.embedded ? null : AppBar(title: const Text('Transfer')),
        bottomNavigationBar: Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: AmountKeypad(
                noteEditing: noteFocus.hasFocus ||
                    MediaQuery.viewInsetsOf(context).bottom > 0,
                onExpressionChanged: (value) {
                  amountFocus.requestFocus();
                  setState(() => calculation = value);
                },
                onTotalChanged: (value) => totalController.value =
                    TextEditingValue(
                        text: value,
                        selection:
                            TextSelection.collapsed(offset: value.length)),
                controller: amount,
                busy: busy,
                onDone: _saveTransfer,
                onDate: _dateSheet,
                toolbar: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (calculation.contains(' + ') ||
                      calculation.contains(' − ') ||
                      calculation.contains(' = '))
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(calculation,
                            style: const TextStyle(fontSize: 11))),
                  TextField(
                      controller: totalController,
                      focusNode: amountFocus,
                      readOnly: true,
                      showCursor: true,
                      keyboardType: TextInputType.none,
                      onTap: () {
                        noteFocus.unfocus();
                        amountFocus.requestFocus();
                      },
                      style: const TextStyle(
                          fontSize: 27, fontWeight: FontWeight.w600),
                      decoration: const InputDecoration(
                          prefixText: 'RM ',
                          hintText: '0.00',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false)),
                  TextField(
                      controller: note,
                      focusNode: noteFocus,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => noteFocus.unfocus(),
                      decoration: const InputDecoration(
                          hintText: 'Add a note…',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false)),
                ]))),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          if (widget.header != null) ...[
            widget.header!,
            const SizedBox(height: 20)
          ],
          for (final source in [true, false])
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DropdownButtonFormField<String>(
                    borderRadius: BorderRadius.circular(18),
                    isExpanded: true,
                    initialValue: source ? from : to,
                    decoration: InputDecoration(
                        labelText: source ? 'From account' : 'To account'),
                    items: p.accounts
                        .where((a) =>
                            a.kind == AccountKind.asset ||
                            a.kind == AccountKind.liability)
                        .map((a) =>
                            DropdownMenuItem(value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                              if (source)
                                from = v;
                              else
                                to = v;
                            }))),
          const Text(
              'Transfers move money between accounts and do not count as income or expenses.',
              style: TextStyle(fontSize: 12)),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 20),
          const Text('Transfer history',
              style: TextStyle(fontWeight: FontWeight.bold)),
          FutureBuilder<List<Map<String, Object?>>>(
              key: ValueKey(p.userId),
              future: DatabaseService().transfers(p.userId),
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return const Text('Could not load transfer history.');
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return Column(children: [
                  for (final row in snapshot.data!)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${p.accountById(row['fromId'] as String)?.name ?? 'Previous account'} → ${p.accountById(row['toId'] as String)?.name ?? 'Previous account'}'),
                        subtitle: Text(
                            'RM ${((row['sen'] as int) / 100).toStringAsFixed(2)} · ${(row['date'] as String).substring(0, 10)}'),
                        trailing: TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final yes = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                                title: const Text(
                                                    'Undo this transfer?'),
                                                content: const Text(
                                                    'This reverses both account balance changes.'),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, false),
                                                      child:
                                                          const Text('Cancel')),
                                                  FilledButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, true),
                                                      child: const Text(
                                                          'Undo transfer'))
                                                ]));
                                    if (yes != true || !mounted) return;
                                    setState(() => busy = true);
                                    try {
                                      await DatabaseService().undoTransfer(
                                          p.userId, row['id'] as String);
                                      await p.loadData();
                                    } catch (e) {
                                      if (mounted)
                                        setState(() => error = operationMessage(
                                            e,
                                            'Could not save the record. Please try again.'));
                                    } finally {
                                      if (mounted) setState(() => busy = false);
                                    }
                                  },
                            child: const Text('Undo')))
                ]);
              }),
        ]));
  }
}
