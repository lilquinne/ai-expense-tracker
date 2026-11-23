import '../utils/cents_input_formatter.dart';
import '../utils/settled_dialog.dart';
import '../utils/operation_message.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../providers/expense_provider.dart';
import '../models/transaction_model.dart';
import '../models/split_bill.dart';
import '../services/database_service.dart';

class SplitBillsScreen extends StatefulWidget {
  const SplitBillsScreen({super.key});
  @override
  State<SplitBillsScreen> createState() => _SplitBillsScreenState();
}

class _SplitBillsScreenState extends State<SplitBillsScreen> {
  Future<List<(TransactionModel, List<Map<String, Object?>>)>>? future;
  String? owner;
  void load() {
    final p = context.read<ExpenseProvider>();
    owner = p.userId;
    future = fetch(owner!);
  }

  Future<List<(TransactionModel, List<Map<String, Object?>>)>> fetch(
      String user) async {
    final db = DatabaseService();
    final rows = await db.getAllTransactions(userId: user);
    return [
      for (final t in rows.where((t) => t.splitData != null))
        (t, await db.splitPayments(user, t.id))
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (owner != context.watch<ExpenseProvider>().userId || future == null)
      load();
  }

  String money(int value) => 'RM ${(value / 100).toStringAsFixed(2)}';
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Split bills')),
      body: FutureBuilder(
          key: ValueKey(owner),
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return Center(
                  child: TextButton(
                      onPressed: () => setState(load),
                      child: const Text('Could not load bills. Retry')));
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final rows = snapshot.data!;
            int due = 0, owed = 0;
            for (final row in rows) {
              final bill = row.$1.split!;
              final totalPaid =
                  row.$2.fold<int>(0, (s, p) => s + (p['sen'] as int));
              if (bill.payer == 0)
                due += bill.totalSen - bill.ownSen - totalPaid;
              else
                owed += bill.ownSen - totalPaid;
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(spacing: 24, runSpacing: 12, children: [
                        Text('People owe you\n${money(due)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text('You owe people\n${money(owed)}',
                            style: const TextStyle(fontWeight: FontWeight.bold))
                      ]))),
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                      'Mark paid only after money has actually changed hands.')),
              if (rows.isEmpty)
                const ListTile(
                    title: Text('No split bills yet'),
                    subtitle: Text('Use Split bill when adding an expense.')),
              for (final row in rows)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.$1.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              Text(
                                  'Bill ${money(row.$1.split!.totalSen)} · Your expense ${money(row.$1.split!.ownSen)}'),
                              for (var i = 0;
                                  i < row.$1.split!.people.length;
                                  i++)
                                person(row.$1, row.$1.split!, i, row.$2),
                              for (final payment in row.$2)
                                ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                        'Recorded ${money(payment['sen'] as int)}'),
                                    trailing: TextButton(
                                        onPressed: () async {
                                          try {
                                            await DatabaseService()
                                                .undoSplitPayment(owner!,
                                                    payment['id'] as String);
                                            if (!mounted) return;
                                            await context
                                                .read<ExpenseProvider>()
                                                .loadData();
                                            if (mounted) setState(load);
                                          } catch (e) {
                                            if (mounted)
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(SnackBar(
                                                      content: Text(
                                                          operationMessage(e,
                                                              'Could not update the record. Please try again.'))));
                                          }
                                        },
                                        child: const Text('Undo'))),
                            ]))),
            ]);
          }));
  Widget person(TransactionModel t, SplitBill bill, int index,
      List<Map<String, Object?>> payments) {
    final p = bill.people[index];
    final paid = payments
        .where((r) => r['personId'] == p.id)
        .fold<int>(0, (s, r) => s + (r['sen'] as int));
    final left = p.sen - paid;
    final eligible = bill.payer == 0 ? index > 0 : index == 0;
    return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Row(children: [
          Expanded(
              child: Text(bill.payer == 0 || !eligible
                  ? p.name
                  : 'You owe ${bill.people[bill.payer].name}')),
          if (p.id.startsWith('open-'))
            IconButton(
                tooltip: 'Name this person',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => rename(t, bill, index))
        ]),
        subtitle: Text(eligible
            ? 'Paid ${money(paid)} · Outstanding ${money(left)}'
            : 'Allocated ${money(p.sen)}${index == bill.payer ? ' · Paid the bill' : ''}'),
        onLongPress:
            p.id.startsWith('open-') ? () => rename(t, bill, index) : null,
        trailing: !eligible
            ? null
            : left == 0
                ? const Icon(Icons.check_circle_outline)
                : IconButton(
                    tooltip: 'Record repayment',
                    icon: const Icon(Icons.payments_outlined),
                    onPressed: () => settle(t, p, left)));
  }

  Future<void> rename(TransactionModel t, SplitBill bill, int index) async {
    final user = owner!;
    final input = TextEditingController(text: bill.people[index].name);
    final value = await showSettledDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Name this person'),
                content: TextField(controller: input, maxLength: 60),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, input.text.trim()),
                      child: const Text('Save'))
                ]));
    input.dispose();
    if (value == null || value.isEmpty || !mounted || owner != user) return;
    final people = [...bill.people];
    people[index] = SplitPerson(people[index].id, value, people[index].sen);
    final db = await DatabaseService().database;
    await db.insert(
        'split_people', {'id': people[index].id, 'userId': user, 'name': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.update('transactions',
        {'splitData': SplitBill(bill.totalSen, bill.payer, people).encode()},
        where: 'id = ? AND userId = ?', whereArgs: [t.id, user]);
    if (mounted) {
      await context.read<ExpenseProvider>().loadData();
      if (mounted) setState(load);
    }
  }

  Future<void> settle(TransactionModel t, SplitPerson person, int left) async {
    final provider = context.read<ExpenseProvider>();
    final user = owner!;
    final input = TextEditingController(text: (left / 100).toStringAsFixed(2));
    String account = provider.defaultAccountId;
    bool busy = false;
    String? error;
    final id = const Uuid().v4();
    await showSettledDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                    title: const Text('Record full or partial payment'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('Outstanding ${money(left)}'),
                      const SizedBox(height: 20),
                      TextField(
                          controller: input,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [CentsInputFormatter()],
                          decoration: const InputDecoration(
                              labelText: 'Amount received / paid (RM)')),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                          borderRadius: BorderRadius.circular(18),
                          initialValue: account,
                          isExpanded: true,
                          items: provider.accounts
                              .where((a) =>
                                  a.kind == AccountKind.asset ||
                                  a.kind == AccountKind.liability)
                              .map((a) => DropdownMenuItem(
                                  value: a.id, child: Text(a.name)))
                              .toList(),
                          onChanged: busy ? null : (v) => account = v!,
                          decoration: const InputDecoration(
                              labelText: 'Account receiving / paying')),
                      if (error != null)
                        Text(error!, style: const TextStyle(color: Colors.red)),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: busy ? null : () => Navigator.pop(ctx),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  if (!RegExp(r'^\d+(\.\d{1,2})?$')
                                      .hasMatch(input.text.trim())) {
                                    update(
                                        () => error = 'Enter a valid amount.');
                                    return;
                                  }
                                  update(() => busy = true);
                                  try {
                                    await DatabaseService().settleSplit(
                                        owner: user,
                                        billId: t.id,
                                        personId: person.id,
                                        accountId: account,
                                        sen: (double.parse(input.text) * 100)
                                            .round(),
                                        paymentId: id);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  } catch (e) {
                                    if (ctx.mounted)
                                      update(() {
                                        error = operationMessage(e,
                                            'Could not save the record. Please try again.');
                                        busy = false;
                                      });
                                  }
                                },
                          child: Text(busy ? 'Saving…' : 'Record payment'))
                    ])));
    input.dispose();
    if (!mounted || owner != user) return;
    await provider.loadData();
    if (mounted) setState(load);
  }
}
