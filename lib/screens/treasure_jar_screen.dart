import '../utils/cents_input_formatter.dart';
import '../services/jar_contribution_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/treasure_jar.dart';
import '../models/transaction_model.dart';
import '../providers/expense_provider.dart';
import '../utils/app_theme.dart';

class TreasureJarScreen extends StatelessWidget {
  const TreasureJarScreen({super.key});
  static String money(int cents) => 'RM ${(cents / 100).toStringAsFixed(2)}';
  static Future<bool> confirmDelete(
      BuildContext context, TreasureJar jar) async {
    final provider = context.read<ExpenseProvider>();
    final account =
        provider.accountById(jar.accountId)?.name ?? 'the linked account';
    return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                  title: const Text('Delete jar?'),
                  content: Text(
                      'Delete "${jar.name}"? ${money(jar.savedCents)} will be released to $account and available to spend. Released money will return to Total Balance if this account is included.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'))
                  ],
                )) ??
        false;
  }

  Future<void> _delete(BuildContext context, TreasureJar jar) async {
    final provider = context.read<ExpenseProvider>();
    if (!await confirmDelete(context, jar) || !context.mounted) return;
    try {
      await provider.deleteJar(jar.id);
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Jar deleted. Reserved funds released. See Notifications.')));
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not delete jar. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Treasure Jar'), actions: [
        IconButton(
            tooltip: 'How jars work',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                      title: const Text('How jars work'),
                      content: const Text(
                          'Jars reserve money in your account for a goal. Reserved money is deducted from Total Balance for included accounts, while Reserved shows how much is set aside. Available account balances exclude reservations. They do not create expenses or transfers. Sign in to sync jar details across your devices.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Got it'))
                      ],
                    ))),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          heroTag: 'new_jar',
          onPressed: () =>
              showDialog(context: context, builder: (_) => const _JarEditor()),
          icon: const Icon(Icons.add),
          label: const Text('New jar')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    gradient: AppGradients.primaryGradient,
                    borderRadius: BorderRadius.circular(22)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your savings, with purpose.',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      const SizedBox(height: 8),
                      Text(
                          money(provider.jars
                              .fold<int>(0, (sum, j) => sum + j.savedCents)),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24)),
                      const Text('Reserved across your jars',
                          style: TextStyle(color: Colors.white70)),
                    ])),
            if (provider.jars.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(children: [
                    Icon(Icons.savings_outlined,
                        size: 64, color: AppTheme.primary),
                    SizedBox(height: 16),
                    Text('A holiday, a new laptop, a rainy day…',
                        textAlign: TextAlign.center),
                    SizedBox(height: 8),
                    Text(
                        'Create your first jar and give your savings a purpose.',
                        textAlign: TextAlign.center),
                  ])),
            for (final jar in provider.jars)
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Slidable(
                      key: ValueKey('jar-${jar.id}'),
                      endActionPane:
                          ActionPane(motion: const DrawerMotion(), children: [
                        SlidableAction(
                            onPressed: (_) => _delete(context, jar),
                            backgroundColor: AppTheme.expenseColor,
                            foregroundColor: Colors.white,
                            icon: Icons.delete_outline,
                            label: 'Delete',
                            borderRadius: BorderRadius.circular(16)),
                      ]),
                      child: Card(
                          child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      const Icon(Icons.savings_rounded,
                                          color: AppTheme.primary),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Text(jar.name,
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      IconButton(
                                          tooltip: 'Edit jar',
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () => showDialog(
                                              context: context,
                                              builder: (_) =>
                                                  _JarEditor(jar: jar))),
                                    ]),
                                    Text(
                                        provider
                                                .accountById(jar.accountId)
                                                ?.name ??
                                            'Account unavailable',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppPalette.of(context)
                                                .textSecondary)),
                                    const SizedBox(height: 10),
                                    Text(
                                        '${money(jar.savedCents)} / ${money(jar.targetCents)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 10),
                                    LinearProgressIndicator(
                                        value: jar.progress,
                                        minHeight: 5,
                                        borderRadius: BorderRadius.circular(8)),
                                    const SizedBox(height: 10),
                                    Text(jar.savedCents >= jar.targetCents
                                        ? 'Goal reached!'
                                        : '${money(jar.targetCents - jar.savedCents)} to go'),
                                    ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      title: const Text('Details & history',
                                          style: TextStyle(fontSize: 12)),
                                      children: [
                                        const SizedBox(height: 12),
                                        Wrap(spacing: 8, children: [
                                          FilledButton.icon(
                                              onPressed: () =>
                                                  _adjust(context, jar, true),
                                              icon: const Icon(Icons.add),
                                              label: const Text('Add money')),
                                          OutlinedButton(
                                              onPressed: jar.savedCents == 0
                                                  ? null
                                                  : () => _adjust(
                                                      context, jar, false),
                                              child: const Text('Release')),
                                        ]),
                                        if (jar.deadline != null)
                                          Text(
                                              'Target date: ${DateFormat('dd-MM-yyyy').format(jar.deadline!)}'),
                                        _contributions(jar),
                                        if (provider.accountById(jar.accountId)
                                            case final account?) ...[
                                          Text(
                                              'Available in account: RM ${provider.availableFor(account).toStringAsFixed(2)}'),
                                          if (provider.availableFor(account) <
                                              0)
                                            const Text(
                                                'Your account balance is below its total reservations. Release some reserved money or update the balance.',
                                                style: TextStyle(
                                                    color:
                                                        AppTheme.expenseColor)),
                                        ],
                                        TextButton(
                                            onPressed: () =>
                                                _history(context, jar),
                                            child: const Text('History')),
                                      ],
                                    ),
                                  ]))))),
          ]),
    );
  }

  Widget _contributions(TreasureJar jar) {
    final plan = JarContributionPlan.calculate(jar, asOf: DateTime.now());
    final text = switch (plan.status) {
      JarPlanStatus.reached => 'No further contribution needed.',
      JarPlanStatus.noDeadline =>
        'Add a target date to see weekly and monthly contributions.',
      JarPlanStatus.overdue =>
        'Target date has passed. Choose a new date to update your contribution plan.',
      JarPlanStatus.active => 'Starting today: ${money(plan.weeklySen!)} weekly '
          '(up to ${plan.weeklyPayments} payments), or ${money(plan.monthlySen!)} monthly '
          '(up to ${plan.monthlyPayments} payments). Stop when the target is reached; the final payment may be smaller.',
    };
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text),
          if (plan.status == JarPlanStatus.active)
            const Text(
                'Choose one schedule. Monthly dates follow today’s day of month, shortened for smaller months. These estimates do not reserve money automatically.',
                style: TextStyle(fontSize: 12)),
        ]));
  }

  Future<void> _adjust(BuildContext context, TreasureJar jar, bool add) async {
    await showDialog(
        context: context, builder: (_) => _JarAmountDialog(jar: jar, add: add));
  }

  void _history(BuildContext context, TreasureJar jar) {
    final future = context.read<ExpenseProvider>().jarHistory(jar.id);
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text('${jar.name} history'),
                content: SizedBox(
                    width: 360,
                    child: FutureBuilder<List<Map<String, Object?>>>(
                        future: future,
                        builder: (_, snapshot) {
                          if (snapshot.hasError)
                            return const Text(
                                'Could not load history. Please try again.');
                          if (!snapshot.hasData)
                            return const SizedBox(
                                height: 80,
                                child:
                                    Center(child: CircularProgressIndicator()));
                          if (snapshot.data!.isEmpty)
                            return const Text('No money reserved yet.');
                          return ListView(
                              shrinkWrap: true,
                              children: snapshot.data!.map((row) {
                                final amount = row['amountCents'] as int;
                                return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                        '${amount > 0 ? 'Reserved' : 'Released'} ${money(amount.abs())}'),
                                    subtitle: Text(
                                        DateFormat('dd-MM-yyyy HH:mm').format(
                                            DateTime.parse(
                                                row['date'] as String))));
                              }).toList());
                        })),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'))
                ]));
  }
}

class _JarEditor extends StatefulWidget {
  const _JarEditor({this.jar});
  final TreasureJar? jar;
  @override
  State<_JarEditor> createState() => _JarEditorState();
}

class _JarEditorState extends State<_JarEditor> {
  late final name = TextEditingController(text: widget.jar?.name);
  late final target = TextEditingController(
      text: widget.jar == null
          ? ''
          : (widget.jar!.targetCents / 100).toStringAsFixed(2));
  late String? accountId = widget.jar?.accountId;
  late DateTime? deadline = widget.jar?.deadline;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context
        .watch<ExpenseProvider>()
        .accounts
        .where((a) => a.kind == AccountKind.asset)
        .toList();
    return AlertDialog(
        title: Text(widget.jar == null ? 'New treasure jar' : 'Edit jar'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              maxLength: 60,
              decoration: const InputDecoration(
                  labelText: 'Goal name', hintText: 'My next adventure')),
          const SizedBox(height: 12),
          TextField(
              controller: target,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [CentsInputFormatter()],
              decoration: const InputDecoration(labelText: 'Target (RM)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
              borderRadius: BorderRadius.circular(18),
              value: accountId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Reserve from'),
              items: accounts
                  .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: busy || (widget.jar?.savedCents ?? 0) > 0
                  ? null
                  : (value) => setState(() => accountId = value)),
          if (accounts.isEmpty)
            const Text('Add an asset account in Accounts first.'),
          TextButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: Text(deadline == null
                  ? 'Target date (optional)'
                  : DateFormat('dd-MM-yyyy').format(deadline!)),
              onPressed: busy
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final date = await showDatePicker(
                          context: context,
                          initialDate: deadline ?? now,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(now.year + 50));
                      if (date != null && mounted)
                        setState(() => deadline = date);
                    }),
          if (deadline != null)
            TextButton(
                onPressed: busy ? null : () => setState(() => deadline = null),
                child: const Text('Remove date')),
          if (error != null)
            Text(error!, style: const TextStyle(color: AppTheme.expenseColor)),
        ])),
        actions: [
          if (widget.jar != null)
            TextButton(
                onPressed: busy ? null : () => _save(delete: true),
                child: const Text('Delete jar')),
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: busy ? null : () => _save(),
              child: Text(busy ? 'Saving…' : 'Save')),
        ]);
  }

  Future<void> _save({bool delete = false}) async {
    final provider = context.read<ExpenseProvider>();
    final amount = double.tryParse(target.text);
    if (!delete &&
        (name.text.trim().isEmpty ||
            amount == null ||
            !amount.isFinite ||
            amount <= 0 ||
            amount > 100000000 ||
            accountId == null)) {
      setState(
          () => error = 'Enter a name, positive target and source account.');
      return;
    }
    if (delete && !await TreasureJarScreen.confirmDelete(context, widget.jar!))
      return;
    if (!mounted) return;
    setState(() => busy = true);
    try {
      if (delete) {
        await provider.deleteJar(widget.jar!.id);
      } else {
        await provider.saveJar(TreasureJar(
            id: widget.jar?.id ?? const Uuid().v4(),
            name: name.text,
            accountId: accountId!,
            targetCents: (amount! * 100).round(),
            savedCents: widget.jar?.savedCents ?? 0,
            deadline: deadline));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(() => error = e is StateError
            ? e.message.toString()
            : 'Could not save the jar. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _JarAmountDialog extends StatefulWidget {
  const _JarAmountDialog({required this.jar, required this.add});
  final TreasureJar jar;
  final bool add;
  @override
  State<_JarAmountDialog> createState() => _JarAmountDialogState();
}

class _JarAmountDialogState extends State<_JarAmountDialog> {
  final amount = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title:
              Text(widget.add ? 'Add money to jar' : 'Release reserved money'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [CentsInputFormatter()],
                decoration: const InputDecoration(labelText: 'Amount (RM)')),
            if (error != null)
              Text(error!,
                  style: const TextStyle(color: AppTheme.expenseColor)),
          ]),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: busy ? null : _save,
                child: Text(busy ? 'Saving…' : 'Confirm'))
          ]);
  Future<void> _save() async {
    final value = double.tryParse(amount.text);
    if (value == null ||
        !value.isFinite ||
        value <= 0 ||
        value > 100000000 ||
        (value * 100).round() == 0) {
      setState(() => error = 'Enter a positive amount.');
      return;
    }
    setState(() => busy = true);
    try {
      await context.read<ExpenseProvider>().adjustJar(
          widget.jar.id, (value * 100).round() * (widget.add ? 1 : -1));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(() => error = e is StateError
            ? e.message.toString()
            : 'Could not update the jar. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
