import '../utils/settled_dialog.dart';
// lib/screens/category_management_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../providers/expense_provider.dart';
import '../utils/app_theme.dart';
import '../utils/category_icons.dart';

class CategoryManagementScreen extends StatelessWidget {
  const CategoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).bgDark,
      appBar: AppBar(title: const Text('Category Library')),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, _) {
          final expense = provider.categoriesForType(TransactionType.expense);
          final income = provider.categoriesForType(TransactionType.income);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              const Text(
                  'Star your favourites to show them when adding a transaction. Long press a custom category to edit it.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 20),
              _CategorySection(title: 'Expense', categories: expense),
              const SizedBox(height: 20),
              _CategorySection(title: 'Income', categories: income),
            ],
          );
        },
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String title;
  final List<AppCategory> categories;

  const _CategorySection({required this.title, required this.categories});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: TextStyle(
                color: AppPalette.of(context).textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        LayoutBuilder(
            builder: (context, box) => Wrap(
                  spacing: 8,
                  runSpacing: 12,
                  children: [
                    for (final category in categories)
                      SizedBox(
                        width: (box.maxWidth - 24) / 4,
                        child: Column(children: [
                          Stack(children: [
                            Material(
                              color: Color(category.colorValue)
                                  .withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: category.parentId != null
                                    ? null
                                    : () => context
                                        .read<ExpenseProvider>()
                                        .toggleFavouriteCategory(category),
                                onLongPress: category.isDefault
                                    ? null
                                    : () => showModalBottomSheet<void>(
                                          context: context,
                                          builder: (sheet) => SafeArea(
                                              child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                ListTile(
                                                    title: const Text(
                                                        'Edit category'),
                                                    leading: const Icon(
                                                        Icons.edit_outlined),
                                                    onTap: () {
                                                      Navigator.pop(sheet);
                                                      _showEditCategoryDialog(
                                                          context, category);
                                                    }),
                                                ListTile(
                                                    title: const Text(
                                                        'Delete category'),
                                                    leading: const Icon(
                                                        Icons.delete_outline),
                                                    onTap: () {
                                                      Navigator.pop(sheet);
                                                      _confirmDeleteCategory(
                                                          context, category);
                                                    }),
                                              ])),
                                        ),
                                child: SizedBox(
                                    width: 64,
                                    height: 64,
                                    child: Icon(appCategoryIcon(category),
                                        size: 28,
                                        color: Color(category.colorValue))),
                              ),
                            ),
                            if (category.parentId == null)
                              Positioned(
                                  right: 0,
                                  top: 0,
                                  child: IgnorePointer(
                                      child: Icon(
                                    context
                                            .watch<ExpenseProvider>()
                                            .isFavouriteCategory(category)
                                        ? Icons.star_rounded
                                        : Icons.star_border_rounded,
                                    size: 18,
                                    color: context
                                            .watch<ExpenseProvider>()
                                            .isFavouriteCategory(category)
                                        ? AppTheme.primary
                                        : AppPalette.of(context).textMuted,
                                  ))),
                          ]),
                          const SizedBox(height: 6),
                          Text(category.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10)),
                        ]),
                      ),
                  ],
                )),
      ],
    );
  }

  Future<void> _showEditCategoryDialog(
      BuildContext context, AppCategory category) async {
    final provider = context.read<ExpenseProvider>();
    final nameController = TextEditingController(text: category.name);
    var parentCategory = category.parentCategory;
    var icon = category.icon;
    var colorValue = category.colorValue;
    final icons = <String>{
      ...TransactionCategory.values.map((category) => category.emoji),
      '🍳',
      '☕',
      '🍿',
      '🍜',
      '🥗',
      '🐾',
      '🎮',
      '🏋️',
      '🎵',
      '📱',
      '💻',
      '🔧',
      '🎨',
      '🚲',
      '🏦',
      '💳',
      '💰',
    }.toList();
    const colors = [
      0xFFFF6B6B,
      0xFF4ECDC4,
      0xFFFFBE0B,
      0xFF9B5DE5,
      0xFF00BBF9,
      0xFFFF9F1C,
      0xFF2EC4B6,
      0xFF1982C4
    ];

    final updated = await showSettledDialog<AppCategory>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final parentOptions = TransactionCategory.values
              .where((c) =>
                  c.isIncomeCategory ==
                  (category.type == TransactionType.income))
              .toList();
          return AlertDialog(
            backgroundColor: AppPalette.of(context).bgCard,
            title: Text('Edit Category',
                style: TextStyle(color: AppPalette.of(context).textPrimary)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: AppPalette.of(context).textPrimary),
                    decoration:
                        const InputDecoration(labelText: 'Category name'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TransactionCategory>(
                    borderRadius: BorderRadius.circular(18),
                    value: parentCategory,
                    dropdownColor: AppPalette.of(context).bgCard,
                    decoration:
                        const InputDecoration(labelText: 'Parent category'),
                    items: parentOptions
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text('${c.emoji} ${c.label}',
                                  style: TextStyle(
                                      color:
                                          AppPalette.of(context).textPrimary)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          parentCategory = value;
                          icon = value.emoji;
                          colorValue = value.colorValue;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Icon library',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: icons.map((item) {
                      final selected = icon == item;
                      return GestureDetector(
                        onTap: () => setDialogState(() => icon = item),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.primary.withValues(alpha: 0.2)
                                : Color(colorValue).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: selected
                                    ? AppTheme.primary
                                    : AppPalette.of(context).border),
                          ),
                          child: Center(
                              child: Text(item,
                                  style: const TextStyle(fontSize: 18))),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: colors.map((item) {
                      final selected = colorValue == item;
                      return GestureDetector(
                        onTap: () => setDialogState(() => colorValue = item),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Color(item),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: selected
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.of(ctx, rootNavigator: true).pop(AppCategory(
                    id: category.id,
                    name: name,
                    type: category.type,
                    parentCategory: parentCategory,
                    icon: icon,
                    colorValue: colorValue,
                    parentId: category.parentId,
                    isDefault: false,
                  ));
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    if (updated != null) {
      await provider.updateCategory(updated);
    }
  }

  Future<void> _confirmDeleteCategory(
      BuildContext context, AppCategory category) async {
    final provider = context.read<ExpenseProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.of(context).bgCard,
        title: Text('Delete category?',
            style: TextStyle(color: AppPalette.of(context).textPrimary)),
        content: Text(
          'Transactions using "${category.name}" will move back to "${category.parentCategory.label}".',
          style: TextStyle(color: AppPalette.of(context).textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.expenseColor)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.deleteCategory(category);
    }
  }
}
