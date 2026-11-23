// lib/widgets/transaction_tile.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../utils/app_theme.dart';
import '../utils/category_icons.dart' as category_icons;

class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final String currencySymbol;
  final String? accountName;
  final String? categoryName;
  final String? categoryIcon;
  final int? categoryColorValue;
  final VoidCallback? onTap;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.currencySymbol,
    this.accountName,
    this.categoryName,
    this.categoryIcon,
    this.categoryColorValue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.type == TransactionType.income;
    final amountColor = isIncome ? AppTheme.incomeColor : AppTheme.expenseColor;
    final displayCategoryName = categoryName ?? transaction.category.label;
    final displayCategoryColor =
        categoryColorValue ?? transaction.category.colorValue;

    final note = transaction.note?.trim().isNotEmpty == true
        ? transaction.note!.trim()
        : transaction.title.toLowerCase().endsWith(' expense') ||
                transaction.title.toLowerCase().endsWith(' income')
            ? ''
            : transaction.title;
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppPalette.of(context).bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.of(context).border)),
          child: Row(children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: Color(displayCategoryColor).withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(category_icons.categoryIcon(transaction.category),
                    color: Color(displayCategoryColor), size: 23)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                        child: Text(displayCategoryName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppPalette.of(context).textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 8),
                    Text(
                        '${isIncome ? '+' : '-'}$currencySymbol ${transaction.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                            color: amountColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w700))
                  ]),
                  if (note.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: AppPalette.of(context).textMuted))),
                  const SizedBox(height: 5),
                  Row(children: [
                    Expanded(
                        child: Text(accountName ?? transaction.accountId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10,
                                color: AppPalette.of(context).textSecondary))),
                    if (transaction.isRecurring)
                      const Icon(Icons.repeat_rounded, size: 12),
                    if (transaction.receiptImagePath != null)
                      const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.attach_file, size: 12)),
                    if (transaction.split != null)
                      const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text('Split',
                              style: TextStyle(
                                  fontSize: 9, color: AppTheme.primary))),
                    const SizedBox(width: 8),
                    Text(DateFormat('d MMM, HH:mm').format(transaction.date),
                        style: TextStyle(
                            fontSize: 10,
                            color: AppPalette.of(context).textMuted))
                  ]),
                  if (transaction.split != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                            'Bill total $currencySymbol ${(transaction.split!.totalSen / 100).toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppPalette.of(context).textMuted))),
                ])),
          ]),
        ));
  }
}
