// lib/screens/transactions_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../providers/expense_provider.dart';
import '../models/transaction_model.dart';
import '../utils/app_theme.dart';
import '../widgets/transaction_tile.dart';
import 'add_transaction_screen.dart';
import 'transaction_detail_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});
  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  TransactionType? _filterType;
  String? _filterCategoryId;
  DateTimeRange? _dateRange;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ExpenseProvider>().loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).bgDark,
      appBar: AppBar(
        title: const Text('All Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, _) {
          var txns = provider.allTransactions;

          // Apply filters
          if (_filterType != null)
            txns = txns.where((t) => t.type == _filterType).toList();
          if (_filterCategoryId != null)
            txns =
                txns.where((t) => t.categoryId == _filterCategoryId).toList();
          if (_dateRange != null) {
            final end = DateTime(_dateRange!.end.year, _dateRange!.end.month,
                _dateRange!.end.day + 1);
            txns = txns
                .where((t) =>
                    !t.date.isBefore(_dateRange!.start) && t.date.isBefore(end))
                .toList();
          }
          if (_searchQuery.isNotEmpty) {
            txns = txns
                .where((t) =>
                    t.title
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase()) ||
                    (t.note
                            ?.toLowerCase()
                            .contains(_searchQuery.toLowerCase()) ??
                        false))
                .toList();
          }

          // Group by date
          final Map<String, List<TransactionModel>> grouped = {};
          for (final t in txns) {
            final key = DateFormat('d MMMM y').format(t.date);
            grouped.putIfAbsent(key, () => []).add(t);
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(color: AppPalette.of(context).textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search transactions...',
                    prefixIcon: Icon(Icons.search_rounded,
                        color: AppPalette.of(context).textMuted),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded,
                                color: AppPalette.of(context).textMuted),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(spacing: 8, children: [
                    ActionChip(
                        avatar: const Icon(Icons.calendar_month, size: 16),
                        label: Text(_dateRange == null
                            ? 'All dates'
                            : '${DateFormat.yMMMd().format(_dateRange!.start)} – ${DateFormat.yMMMd().format(_dateRange!.end)}'),
                        onPressed: _chooseDate),
                    DropdownButton<String>(
                        value: _filterCategoryId,
                        hint: const Text('All categories'),
                        items: [
                          for (final c in provider.categories)
                            DropdownMenuItem(value: c.id, child: Text(c.name))
                        ],
                        onChanged: (id) =>
                            setState(() => _filterCategoryId = id)),
                    if (_dateRange != null ||
                        _filterCategoryId != null ||
                        _filterType != null)
                      TextButton(
                          onPressed: () => setState(() {
                                _dateRange = null;
                                _filterCategoryId = null;
                                _filterType = null;
                              }),
                          child: const Text('Clear filters')),
                    if (_filterType != null)
                      Chip(
                          label: Text(_filterType == TransactionType.income
                              ? 'Income'
                              : 'Expense')),
                  ])),
              Expanded(
                child: txns.isEmpty
                    ? Center(
                        child: Text('No transactions found',
                            style: TextStyle(
                                color: AppPalette.of(context).textMuted)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        itemCount: grouped.length,
                        itemBuilder: (ctx, i) {
                          final dateKey = grouped.keys.elementAt(i);
                          final dayTxns = grouped[dateKey]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(dateKey,
                                    style: TextStyle(
                                        color: AppPalette.of(context).textMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                              ...dayTxns.map((t) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Slidable(
                                      endActionPane: ActionPane(
                                        motion: const DrawerMotion(),
                                        children: [
                                          SlidableAction(
                                            onPressed: (_) => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      AddTransactionScreen(
                                                          editTransaction: t),
                                                )),
                                            backgroundColor: AppTheme.primary,
                                            foregroundColor: Colors.white,
                                            icon: Icons.edit_rounded,
                                            label: 'Edit',
                                            borderRadius:
                                                const BorderRadius.horizontal(
                                                    left: Radius.circular(12)),
                                          ),
                                          SlidableAction(
                                            onPressed: (_) => _confirmDelete(
                                                context, provider, t.id),
                                            backgroundColor:
                                                AppTheme.expenseColor,
                                            foregroundColor: Colors.white,
                                            icon: Icons.delete_rounded,
                                            label: 'Delete',
                                            borderRadius:
                                                const BorderRadius.horizontal(
                                                    right: Radius.circular(12)),
                                          ),
                                        ],
                                      ),
                                      child: Builder(builder: (_) {
                                        final category =
                                            provider.categoryForTransaction(t);
                                        return TransactionTile(
                                          transaction: t,
                                          accountName: provider
                                              .accountForTransaction(t)
                                              .name,
                                          currencySymbol:
                                              provider.currencySymbol,
                                          categoryName: category.name,
                                          categoryIcon: category.icon,
                                          categoryColorValue:
                                              category.colorValue,
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  TransactionDetailScreen(
                                                      transaction: t),
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  )),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _chooseDate() async {
    final mode = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final label in ['Day', 'Month', 'Date range', 'All dates'])
                ListTile(
                    title: Text(label), onTap: () => Navigator.pop(ctx, label)),
            ])));
    if (mode == null || !mounted) return;
    if (mode == 'All dates') {
      setState(() => _dateRange = null);
      return;
    }
    if (mode == 'Date range') {
      final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(1900),
          lastDate: DateTime(2200),
          initialDateRange: _dateRange);
      if (range != null && mounted) setState(() => _dateRange = range);
      return;
    }
    final date = await showDatePicker(
        context: context,
        initialDate: _dateRange?.start ?? DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2200),
        helpText:
            mode == 'Month' ? 'Choose any day in the month' : 'Choose a day');
    if (date != null && mounted)
      setState(() => _dateRange = mode == 'Month'
          ? DateTimeRange(
              start: DateTime(date.year, date.month),
              end: DateTime(date.year, date.month + 1, 0))
          : DateTimeRange(start: date, end: date));
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.of(context).textPrimary)),
            const SizedBox(height: 16),
            Text('Type',
                style: TextStyle(
                    color: AppPalette.of(context).textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                _FilterOption(
                    label: 'All',
                    isActive: _filterType == null,
                    onTap: () {
                      setState(() => _filterType = null);
                      Navigator.pop(ctx);
                    }),
                const SizedBox(width: 8),
                _FilterOption(
                    label: 'Income',
                    isActive: _filterType == TransactionType.income,
                    color: AppTheme.incomeColor,
                    onTap: () {
                      setState(() => _filterType = TransactionType.income);
                      Navigator.pop(ctx);
                    }),
                const SizedBox(width: 8),
                _FilterOption(
                    label: 'Expense',
                    isActive: _filterType == TransactionType.expense,
                    color: AppTheme.expenseColor,
                    onTap: () {
                      setState(() => _filterType = TransactionType.expense);
                      Navigator.pop(ctx);
                    }),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, ExpenseProvider provider, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.of(context).bgCard,
        title: Text('Delete Transaction',
            style: TextStyle(color: AppPalette.of(context).textPrimary)),
        content: Text('Are you sure you want to delete this transaction?',
            style: TextStyle(color: AppPalette.of(context).textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppTheme.expenseColor))),
        ],
      ),
    );
    if (confirmed == true) await provider.deleteTransaction(id);
  }
}

class _FilterOption extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color? color;
  final VoidCallback onTap;
  const _FilterOption(
      {required this.label,
      required this.isActive,
      this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppTheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.15)
              : AppPalette.of(context).bgCardLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isActive ? activeColor : AppPalette.of(context).border),
        ),
        child: Text(label,
            style: TextStyle(
                color: isActive
                    ? activeColor
                    : AppPalette.of(context).textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13)),
      ),
    );
  }
}
