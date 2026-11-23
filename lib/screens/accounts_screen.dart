import '../utils/cents_input_formatter.dart';
import '../utils/settled_dialog.dart';
// lib/screens/accounts_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../providers/expense_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/transaction_tile.dart';
import 'transaction_detail_screen.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).bgDark,
      appBar: AppBar(title: const Text('Accounts'), actions: [
        IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About accounts',
            onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                        title: const Text('How accounts work'),
                        content: const SingleChildScrollView(
                            child: Text(
                                'Assets: money you own, such as bank, cash and e-wallet balances.\n\n'
                                'Liabilities: money you owe, including credit cards and loans.\n\n'
                                'Lend to: money someone owes you. Borrow from: money you owe someone.\n\n'
                                'Others: accounts tracked separately from your main balance.\n\n'
                                'Credit cards: record purchases as expenses on the card. Repay principal using a transfer from your bank to the card, so spending is counted once. Record interest and fees separately as expenses. Visa is a card network: choose Bank for debit cards or Credit Card for credit cards.\n\n'
                                'Jars reserve existing money; they do not create an expense.')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Got it'))
                        ])))
      ]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_account',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddAccountScreen()),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Account'),
      ),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              _NetWorthCard(provider: provider),
              const SizedBox(height: 20),
              for (final kind in AccountKind.values) ...[
                _AccountSection(kind: kind, provider: provider),
                const SizedBox(height: 16),
              ],
            ],
          );
        },
      ),
    );
  }

  static List<AccountSubtype> _subtypesForKind(AccountKind kind) {
    switch (kind) {
      case AccountKind.asset:
        return const [
          AccountSubtype.bank,
          AccountSubtype.eWallet,
          AccountSubtype.cash,
          AccountSubtype.investment
        ];
      case AccountKind.liability:
        return const [
          AccountSubtype.creditCard,
          AccountSubtype.carLoan,
          AccountSubtype.mortgage,
          AccountSubtype.personalLoan
        ];
      case AccountKind.lending:
        return const [AccountSubtype.lend, AccountSubtype.borrow];
      case AccountKind.other:
        return const [AccountSubtype.other];
    }
  }
}

class _NetWorthCard extends StatelessWidget {
  final ExpenseProvider provider;
  const _NetWorthCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppGradients.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Net Worth',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
              '${provider.currencySymbol} ${provider.netWorth.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _MoneyStat(
                      label: 'Assets',
                      value: provider.totalAssets,
                      color: const Color(0xFFB9F6CA),
                      provider: provider)),
              const SizedBox(width: 12),
              Expanded(
                  child: _MoneyStat(
                      label: 'Liabilities',
                      value: provider.totalLiabilities,
                      color: AppTheme.expenseColor,
                      provider: provider)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoneyStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final ExpenseProvider provider;

  const _MoneyStat(
      {required this.label,
      required this.value,
      required this.color,
      required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        Text('${provider.currencySymbol} ${value.toStringAsFixed(2)}',
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _AccountSection extends StatelessWidget {
  final AccountKind kind;
  final ExpenseProvider provider;

  const _AccountSection({required this.kind, required this.provider});

  @override
  Widget build(BuildContext context) {
    final accounts = provider.accounts.where((a) => a.kind == kind).toList();
    if (accounts.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kind.label.toUpperCase(),
            style: TextStyle(
                color: AppPalette.of(context).textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ...accounts.map(
            (account) => _AccountTile(account: account, provider: provider)),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  final AppAccount account;
  final ExpenseProvider provider;

  const _AccountTile({required this.account, required this.provider});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AccountDetailScreen(account: account))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.of(context).bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.of(context).border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Color(account.colorValue).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                  child:
                      Text(account.icon, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.name,
                      style: TextStyle(
                          color: AppPalette.of(context).textPrimary,
                          fontWeight: FontWeight.w700)),
                  Text(account.subtype.label,
                      style: TextStyle(
                          color: AppPalette.of(context).textMuted,
                          fontSize: 12)),
                  if (provider.reservedFor(account.id) > 0) ...[
                    Text(
                        'Reserved: RM ${provider.reservedFor(account.id).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11)),
                    Text(
                        'Available: RM ${provider.availableFor(account).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11)),
                  ],
                  if (!account.includeInNetWorth || !account.includeInBalance)
                    Text(
                      [
                        if (!account.includeInNetWorth) 'Not in net worth',
                        if (!account.includeInBalance &&
                            account.kind != AccountKind.liability)
                          'Not in balance',
                      ].join(' / '),
                      style: const TextStyle(
                          color: AppTheme.warningColor, fontSize: 11),
                    ),
                ],
              ),
            ),
            Text(
                '${provider.currencySymbol} ${account.currentBalance.toStringAsFixed(2)}',
                style: TextStyle(
                    color: AppPalette.of(context).textPrimary,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController(text: '0.00');
  final _counterpartyController = TextEditingController();

  AccountKind _kind = AccountKind.asset;
  AccountSubtype _subtype = AccountSubtype.bank;
  int _colorValue = AppTheme.primary.value;
  bool _includeInNetWorth = true;
  bool _includeInBalance = true;
  String? _linkedAccountId;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _counterpartyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final subtypes = AccountsScreen._subtypesForKind(_kind);
    if (!subtypes.contains(_subtype)) _subtype = subtypes.first;

    return Scaffold(
      backgroundColor: AppPalette.of(context).bgDark,
      appBar: AppBar(
        title: const Text('Add Account'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _isSaving ? null : () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildCard(
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                style: TextStyle(color: AppPalette.of(context).textPrimary),
                decoration: const InputDecoration(labelText: 'Account name'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<AccountKind>(
                borderRadius: BorderRadius.circular(18),
                value: _kind,
                dropdownColor: AppPalette.of(context).bgCard,
                decoration: const InputDecoration(labelText: 'Account group'),
                items: AccountKind.values
                    .map(
                      (kind) => DropdownMenuItem(
                        value: kind,
                        child: Text(
                          kind.label,
                          style: TextStyle(
                              color: AppPalette.of(context).textPrimary),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _kind = value;
                          _includeInBalance = value == AccountKind.asset ||
                              value == AccountKind.lending;
                          _includeInNetWorth = value != AccountKind.other;
                          _linkedAccountId = null;
                        });
                      },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<AccountSubtype>(
                borderRadius: BorderRadius.circular(18),
                value: _subtype,
                dropdownColor: AppPalette.of(context).bgCard,
                decoration: const InputDecoration(labelText: 'Type'),
                items: subtypes
                    .map(
                      (subtype) => DropdownMenuItem(
                        value: subtype,
                        child: Text(
                          '${subtype.icon} ${subtype.label}',
                          style: TextStyle(
                              color: AppPalette.of(context).textPrimary),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _subtype = value);
                      },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _balanceController,
                enabled: !_isSaving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [CentsInputFormatter()],
                style: TextStyle(color: AppPalette.of(context).textPrimary),
                decoration: const InputDecoration(labelText: 'Balance'),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Include in Net Worth',
                  style: TextStyle(color: AppPalette.of(context).textPrimary),
                ),
                value: _includeInNetWorth,
                onChanged: _isSaving || _kind == AccountKind.other
                    ? null
                    : (value) => setState(() => _includeInNetWorth = value),
              ),
              if (_kind == AccountKind.asset || _kind == AccountKind.lending)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Include in My Balance',
                    style: TextStyle(color: AppPalette.of(context).textPrimary),
                  ),
                  value: _includeInBalance,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _includeInBalance = value),
                ),
              if (_kind == AccountKind.lending) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _counterpartyController,
                  enabled: !_isSaving,
                  style: TextStyle(color: AppPalette.of(context).textPrimary),
                  decoration: InputDecoration(
                    labelText: _subtype == AccountSubtype.borrow
                        ? 'Lender name'
                        : 'Borrower name',
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  borderRadius: BorderRadius.circular(18),
                  value: _linkedAccountId,
                  dropdownColor: AppPalette.of(context).bgCard,
                  decoration: InputDecoration(
                    labelText: _subtype == AccountSubtype.borrow
                        ? 'Deposited to'
                        : 'Paid from',
                  ),
                  items: provider.accounts
                      .where((account) => account.kind == AccountKind.asset)
                      .map(
                        (account) => DropdownMenuItem(
                          value: account.id,
                          child: Text(
                            account.name,
                            style: TextStyle(
                                color: AppPalette.of(context).textPrimary),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _linkedAccountId = value),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : () => _save(provider),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.of(context).bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.of(context).border),
      ),
      child: Material(
          color: Colors.transparent, child: Column(children: children)),
    );
  }

  Future<void> _save(ExpenseProvider provider) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an account name'),
          backgroundColor: AppTheme.expenseColor,
        ),
      );
      return;
    }

    final balance = double.tryParse(_balanceController.text.trim()) ?? 0;
    setState(() => _isSaving = true);
    try {
      await provider.addAccount(
        name: name,
        kind: _kind,
        subtype: _subtype,
        openingBalance: balance,
        icon: _subtype.icon,
        colorValue: _colorValue,
        includeInNetWorth: _includeInNetWorth,
        includeInBalance: _includeInBalance,
        counterpartyName: _counterpartyController.text.trim().isEmpty
            ? null
            : _counterpartyController.text.trim(),
        linkedAccountId: _linkedAccountId,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not add account: $error'),
          backgroundColor: AppTheme.expenseColor,
        ),
      );
    }
  }
}

class AccountDetailScreen extends StatelessWidget {
  final AppAccount account;
  const AccountDetailScreen({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpenseProvider>(
      builder: (context, provider, _) {
        final current = provider.accountById(account.id) ?? account;
        return Scaffold(
          backgroundColor: AppPalette.of(context).bgDark,
          appBar: AppBar(
            title: Text(current.name),
            actions: [
              IconButton(
                onPressed: () => _showAdjustDialog(context, provider, current),
                icon: const Icon(Icons.tune_rounded),
              ),
              if (!current.isDefault)
                IconButton(
                  tooltip: 'Delete Account',
                  onPressed: () =>
                      _confirmDeleteAccount(context, provider, current),
                  icon: const Icon(
                    Icons.delete_rounded,
                    color: AppTheme.expenseColor,
                  ),
                ),
            ],
          ),
          body: FutureBuilder<List<TransactionModel>>(
            future: provider.transactionsForAccount(current.id),
            builder: (context, snapshot) {
              final txns = snapshot.data ?? const <TransactionModel>[];
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).bgCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppPalette.of(context).border),
                    ),
                    child: Row(
                      children: [
                        Text(current.icon,
                            style: const TextStyle(fontSize: 34)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(current.subtype.label,
                                  style: TextStyle(
                                      color: AppPalette.of(context).textMuted,
                                      fontSize: 12)),
                              Text(
                                  '${provider.currencySymbol} ${current.currentBalance.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      color: AppPalette.of(context).textPrimary,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 8),
                              if (provider.reservedFor(current.id) > 0) ...[
                                Text(
                                    'Reserved in jars: RM ${provider.reservedFor(current.id).toStringAsFixed(2)}'),
                                Text(
                                    'Available: RM ${provider.availableFor(current).toStringAsFixed(2)}'),
                                const SizedBox(height: 8),
                              ],
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _AccountFlag(
                                    label: current.includeInNetWorth
                                        ? 'In Net Worth'
                                        : 'Hidden from Net Worth',
                                  ),
                                  if (current.kind != AccountKind.liability)
                                    _AccountFlag(
                                      label: current.includeInBalance
                                          ? 'In My Balance'
                                          : 'Hidden from Balance',
                                    ),
                                  if (current.counterpartyName != null)
                                    _AccountFlag(
                                        label: current.counterpartyName!),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!current.isDefault) ...[
                    OutlinedButton.icon(
                      onPressed: () =>
                          _confirmDeleteAccount(context, provider, current),
                      icon: const Icon(
                        Icons.delete_rounded,
                        color: AppTheme.expenseColor,
                      ),
                      label: const Text(
                        'Delete Account',
                        style: TextStyle(color: AppTheme.expenseColor),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.expenseColor),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text('Transactions',
                      style: TextStyle(
                          color: AppPalette.of(context).textPrimary,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator())
                  else if (txns.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                          child: Text('No transactions yet',
                              style: TextStyle(
                                  color: AppPalette.of(context).textMuted))),
                    )
                  else
                    ...txns.map((t) {
                      final category = provider.categoryForTransaction(t);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TransactionTile(
                          transaction: t,
                          accountName:
                              provider.accountById(t.accountId)?.name ??
                                  'Account unavailable',
                          currencySymbol: provider.currencySymbol,
                          categoryName: category.name,
                          categoryIcon: category.icon,
                          categoryColorValue: category.colorValue,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  TransactionDetailScreen(transaction: t),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showAdjustDialog(BuildContext context, ExpenseProvider provider,
      AppAccount account) async {
    final controller =
        TextEditingController(text: account.currentBalance.toStringAsFixed(2));
    final balance = await showSettledDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.of(context).bgCard,
        title: Text('Adjust Balance',
            style: TextStyle(color: AppPalette.of(context).textPrimary)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [CentsInputFormatter()],
          style: TextStyle(color: AppPalette.of(context).textPrimary),
          decoration: const InputDecoration(labelText: 'Current balance'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final balance = double.tryParse(controller.text.trim());
              if (balance == null) return;
              Navigator.of(ctx, rootNavigator: true).pop(balance);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (balance != null) {
      await provider.adjustAccountBalance(account.id, balance);
    }
  }

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    ExpenseProvider provider,
    AppAccount account,
  ) async {
    final txns = await provider.transactionsForAccount(account.id);
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.of(context).bgCard,
        title: Text(
          'Delete Account?',
          style: TextStyle(color: AppPalette.of(context).textPrimary),
        ),
        content: Text(
          txns.isEmpty
              ? 'This account will be removed from your account list.'
              : 'This account has ${txns.length} transaction(s). The transactions will stay in your records, but this account will be removed from your account list.',
          style: TextStyle(color: AppPalette.of(context).textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.expenseColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await provider.deleteAccount(account);
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete account: $error'),
          backgroundColor: AppTheme.expenseColor,
        ),
      );
    }
  }
}

class _AccountFlag extends StatelessWidget {
  final String label;
  const _AccountFlag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppPalette.of(context).bgCardLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.of(context).border),
      ),
      child: Text(label,
          style: TextStyle(
              color: AppPalette.of(context).textSecondary, fontSize: 11)),
    );
  }
}
