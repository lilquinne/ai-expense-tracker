import '../utils/cents_input_formatter.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/split_bill.dart';
import '../services/database_service.dart';

class SplitBillEditor extends StatefulWidget {
  const SplitBillEditor(
      {super.key, required this.totalSen, required this.owner, this.initial});
  final int totalSen;
  final String owner;
  final SplitBill? initial;
  @override
  State<SplitBillEditor> createState() => _SplitBillEditorState();
}

class _SplitBillEditorState extends State<SplitBillEditor> {
  final people = <SplitPerson>[];
  final amounts = <TextEditingController>[];
  bool custom = false;
  int payer = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    people.addAll(widget.initial?.people ?? [const SplitPerson('me', 'Me', 0)]);
    payer = widget.initial?.payer ?? 0;
    custom = widget.initial != null;
    for (final p in people) {
      amounts
          .add(TextEditingController(text: (p.sen / 100).toStringAsFixed(2)));
    }
  }

  @override
  void dispose() {
    for (final c in amounts) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> add() async {
    final saved = await DatabaseService().splitPeople(widget.owner);
    if (!mounted) return;
    final input = TextEditingController();
    final selected = await showModalBottomSheet<SplitPerson>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 20, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
                child: SizedBox(
                    height: 360,
                    child: Column(children: [
                      TextField(
                          controller: input,
                          decoration: const InputDecoration(
                              labelText: 'Search or type a new name'),
                          onChanged: (_) => update(() {})),
                      Expanded(
                          child: ListView(children: [
                        for (final row in saved.where((r) =>
                            !people.any((p) => p.id == r['id']) &&
                            (r['name'] as String)
                                .toLowerCase()
                                .contains(input.text.toLowerCase())))
                          ListTile(
                              title: Text(row['name'] as String),
                              onTap: () => Navigator.pop(
                                  ctx,
                                  SplitPerson(row['id'] as String,
                                      row['name'] as String, 0))),
                        if (input.text.trim().isNotEmpty)
                          ListTile(
                              leading: const Icon(Icons.person_add_alt),
                              title: Text('Add ${input.text.trim()}'),
                              onTap: () => Navigator.pop(
                                  ctx,
                                  SplitPerson(const Uuid().v4(),
                                      input.text.trim(), 0))),
                        ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: const Text('Add an open slot'),
                            subtitle: const Text('Name this person later'),
                            onTap: () => Navigator.pop(
                                ctx,
                                SplitPerson('open-${const Uuid().v4()}',
                                    'Someone ${people.length}', 0))),
                      ])),
                    ])))));
    input.dispose();
    if (selected != null && mounted)
      setState(() {
        people.add(selected);
        amounts.add(TextEditingController(text: '0.00'));
      });
  }

  @override
  Widget build(BuildContext context) {
    final even = people.length < 2
        ? <int>[widget.totalSen]
        : SplitBill.evenly(widget.totalSen, people.length);
    return AlertDialog(
        title: const Text('Split bill'),
        content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  'Bill total: RM ${(widget.totalSen / 100).toStringAsFixed(2)}'),
              SegmentedButton<bool>(segments: const [
                ButtonSegment(value: false, label: Text('Evenly')),
                ButtonSegment(value: true, label: Text('Custom'))
              ], selected: {
                custom
              }, onSelectionChanged: (v) => setState(() => custom = v.single)),
              for (var i = 0; i < people.length; i++)
                Row(children: [
                  Expanded(child: Text(people[i].name)),
                  if (custom)
                    SizedBox(
                        width: 100,
                        child: TextField(
                            controller: amounts[i],
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [CentsInputFormatter()],
                            decoration:
                                const InputDecoration(prefixText: 'RM ')))
                  else
                    Text('RM ${(even[i] / 100).toStringAsFixed(2)}'),
                  if (i > 0)
                    IconButton(
                        tooltip: 'Remove person',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                              amounts.removeAt(i).dispose();
                              people.removeAt(i);
                              if (payer == i)
                                payer = 0;
                              else if (payer > i) payer--;
                            })),
                ]),
              TextButton.icon(
                  onPressed: add,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add person / open slot')),
              DropdownButtonFormField<int>(
                  initialValue: payer,
                  key: ValueKey('${people.length}-$payer'),
                  decoration:
                      const InputDecoration(labelText: 'Who paid the bill?'),
                  items: [
                    for (var i = 0; i < people.length; i++)
                      DropdownMenuItem(value: i, child: Text(people[i].name))
                  ],
                  onChanged: (v) => setState(() => payer = v ?? 0)),
              const SizedBox(height: 8),
              const Text(
                  'Your portion is your expense. Repayments settle money owed; they are not income.',
                  style: TextStyle(fontSize: 12)),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                try {
                  final shares = custom
                      ? amounts.map((c) {
                          if (!RegExp(r'^\d+(\.\d{1,2})?$')
                              .hasMatch(c.text.trim()))
                            throw ArgumentError(
                                'Use valid amounts with up to two decimals.');
                          return (double.parse(c.text) * 100).round();
                        }).toList()
                      : even;
                  final bill = SplitBill(widget.totalSen, payer, [
                    for (var i = 0; i < people.length; i++)
                      SplitPerson(people[i].id, people[i].name, shares[i])
                  ]);
                  bill.validate();
                  Navigator.pop(context, bill);
                } catch (e) {
                  setState(() => error = e is ArgumentError
                      ? e.message.toString()
                      : 'Check participant amounts.');
                }
              },
              child: const Text('Confirm split'))
        ]);
  }
}
