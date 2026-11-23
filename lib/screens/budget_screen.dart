import '../utils/cents_input_formatter.dart';
import '../utils/category_icons.dart';
import '../widgets/spending_pace_card.dart';
// lib/screens/budget_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../models/transaction_model.dart';
import '../utils/app_theme.dart';

class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).bgDark,
      appBar: AppBar(
        title: const Text('Budget Tracker'),
        actions: [
          IconButton(
            tooltip: 'Add budget',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BudgetFormScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<ExpenseProvider>(
        builder: (ctx, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildHeader(context, provider),
              const SizedBox(height: 12),
              const ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title:
                      Text('Spending advice', style: TextStyle(fontSize: 12)),
                  children: [SpendingPaceCard()]),
              const SizedBox(height: 20),
              ...provider.budgets.map((b) => b.category).toSet().map((cat) =>
                  _BudgetCategoryCard(
                    category: cat,
                    provider: provider,
                    onSetBudget: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BudgetFormScreen(initialCategory: cat),
                      ),
                    ),
                    onDeleteBudget: () => provider.deleteBudgetForCategory(cat),
                  )),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ExpenseProvider provider) {
    final budgeted = provider.totalBudget;
    final spent = provider.budgetedSpending;
    final remaining = budgeted - spent;

    if (budgeted == 0) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(children: [
                Icon(Icons.savings_outlined, color: AppTheme.primary, size: 28),
                SizedBox(height: 8),
                Text('No budgets yet'),
                SizedBox(height: 4),
                Text('Use + in the top bar to add a category budget.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12)),
              ])));
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          gradient: AppGradients.primaryGradient,
          borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Total Budget',
            style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        Text('${provider.currencySymbol} ${budgeted.toStringAsFixed(2)}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        LinearProgressIndicator(
            value: (spent / budgeted).clamp(0.0, 1.0),
            minHeight: 5,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: Colors.white24,
            color: remaining >= 0 ? Colors.white : AppTheme.expenseColor),
        const SizedBox(height: 8),
        Wrap(spacing: 18, runSpacing: 4, children: [
          Text('Used ${provider.currencySymbol} ${spent.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(
              '${remaining >= 0 ? 'Remaining' : 'Over'} ${provider.currencySymbol} ${remaining.abs().toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ]),
      ]),
    );
  }
}

class BudgetFormScreen extends StatefulWidget {
  final TransactionCategory? initialCategory;

  const BudgetFormScreen({super.key, this.initialCategory});

  @override
  State<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends State<BudgetFormScreen> {
  final _limitController = TextEditingController();
  AppCategory? _selectedCategory;
  bool _isSaving = false;

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final categories = provider
        .categoriesForType(TransactionType.expense)
        .where((category) => category.id == category.parentCategory.name)
        .toList();

    _syncInitialValues(provider, categories);
    final selected = _selectedCategory;
    final hasBudget = selected != null &&
        provider.getBudgetLimit(selected.parentCategory) != null;

    return Scaffold(
      backgroundColor: AppPalette.of(context).bgDark,
      appBar: AppBar(
        title:
            Text(widget.initialCategory == null ? 'Add Budget' : 'Edit Budget'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _isSaving ? null : () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppPalette.of(context).bgCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppPalette.of(context).border),
            ),
            child: Column(
              children: [
                DropdownButtonFormField<AppCategory>(
                  borderRadius: BorderRadius.circular(18),
                  value: selected,
                  dropdownColor: AppPalette.of(context).bgCard,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(
                            category.name,
                            style: TextStyle(
                                color: AppPalette.of(context).textPrimary),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving || widget.initialCategory != null
                      ? null
                      : (value) => setState(() {
                            _selectedCategory = value;
                            final limit = value == null
                                ? null
                                : provider.getBudgetLimit(value.parentCategory);
                            _limitController.text =
                                limit?.toStringAsFixed(2) ?? '';
                          }),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _limitController,
                  enabled: !_isSaving,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CentsInputFormatter()],
                  style: TextStyle(color: AppPalette.of(context).textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Monthly limit (${provider.currencySymbol})',
                  ),
                  autofocus: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (hasBudget) ...[
            OutlinedButton.icon(
              onPressed: _isSaving || selected == null
                  ? null
                  : () => _delete(provider, selected.parentCategory),
              icon: const Icon(Icons.delete_rounded,
                  color: AppTheme.expenseColor),
              label: const Text(
                'Delete Budget',
                style: TextStyle(color: AppTheme.expenseColor),
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                  onPressed: _isSaving || selected == null
                      ? null
                      : () => _save(provider, selected.parentCategory),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _syncInitialValues(
    ExpenseProvider provider,
    List<AppCategory> categories,
  ) {
    if (_selectedCategory != null || categories.isEmpty) return;
    final initialParent = widget.initialCategory;
    _selectedCategory = initialParent == null
        ? categories.first
        : categories.firstWhere(
            (category) => category.parentCategory == initialParent,
            orElse: () => categories.first,
          );
    final limit = provider.getBudgetLimit(_selectedCategory!.parentCategory);
    _limitController.text = limit?.toStringAsFixed(2) ?? '';
  }

  Future<void> _save(
    ExpenseProvider provider,
    TransactionCategory category,
  ) async {
    final limit = double.tryParse(_limitController.text.trim());
    if (limit == null || limit <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid budget limit'),
          backgroundColor: AppTheme.expenseColor,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await provider.upsertBudget(category: category, limit: limit);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save budget: $error'),
          backgroundColor: AppTheme.expenseColor,
        ),
      );
    }
  }

  Future<void> _delete(
    ExpenseProvider provider,
    TransactionCategory category,
  ) async {
    setState(() => _isSaving = true);
    try {
      await provider.deleteBudgetForCategory(category);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete budget: $error'),
          backgroundColor: AppTheme.expenseColor,
        ),
      );
    }
  }
}

class _BudgetCategoryCard extends StatelessWidget {
  final TransactionCategory category;
  final ExpenseProvider provider;
  final VoidCallback onSetBudget;
  final Future<void> Function() onDeleteBudget;

  const _BudgetCategoryCard({
    required this.category,
    required this.provider,
    required this.onSetBudget,
    required this.onDeleteBudget,
  });

  @override
  Widget build(BuildContext context) {
    final limit = provider.getBudgetLimit(category) ?? 0;
    final spent = provider.categoryBreakdown[category] ?? 0;
    final left = limit - spent;
    final color = left < 0 ? AppTheme.expenseColor : Color(category.colorValue);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
          endActionPane: ActionPane(motion: const DrawerMotion(), children: [
            SlidableAction(
                onPressed: (_) => onSetBudget(),
                backgroundColor: AppTheme.primary,
                icon: Icons.edit_outlined,
                label: 'Edit'),
            SlidableAction(
                onPressed: (_) => onDeleteBudget(),
                backgroundColor: AppTheme.expenseColor,
                icon: Icons.delete_outline,
                label: 'Delete'),
          ]),
          child: Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                  onTap: onSetBudget,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                color: color.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(12)),
                            child: Icon(categoryIcon(category),
                                size: 23, color: color)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Expanded(
                                    child: Text(category.label,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600))),
                                Text(
                                    '${provider.currencySymbol} ${limit.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 12))
                              ]),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                  value: limit > 0
                                      ? (spent / limit).clamp(0.0, 1.0)
                                      : 0,
                                  minHeight: 4,
                                  color: color,
                                  backgroundColor:
                                      AppPalette.of(context).bgCardLight,
                                  borderRadius: BorderRadius.circular(6)),
                              const SizedBox(height: 6),
                              Wrap(spacing: 12, runSpacing: 4, children: [
                                Text(
                                    'Used ${provider.currencySymbol} ${spent.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color:
                                            AppPalette.of(context).textMuted)),
                                Text(
                                    '${left >= 0 ? 'Left' : 'Over'} ${provider.currencySymbol} ${left.abs().toStringAsFixed(2)}',
                                    style:
                                        TextStyle(fontSize: 10, color: color))
                              ]),
                            ])),
                      ]))))),
    );
  }
}
