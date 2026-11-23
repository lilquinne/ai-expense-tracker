import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../providers/expense_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/transaction_notes.dart';
import 'add_transaction_screen.dart';

class TransactionDetailScreen extends StatelessWidget {
  final TransactionModel transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpenseProvider>(
      builder: (context, provider, _) {
        final current = provider.transactions
                .where((t) => t.id == transaction.id)
                .firstOrNull ??
            transaction;
        final category = provider.categoryForTransaction(current);
        final account = provider.accountForTransaction(current);
        final isIncome = current.type == TransactionType.income;
        final amountColor =
            isIncome ? AppTheme.incomeColor : AppTheme.expenseColor;

        return Scaffold(
          backgroundColor: AppPalette.of(context).bgDark,
          appBar: AppBar(
            title: const Text('Transaction Details'),
            actions: [
              IconButton(
                tooltip: 'Edit',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AddTransactionScreen(editTransaction: current),
                  ),
                ),
                icon: const Icon(Icons.edit_rounded),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, provider, current.id),
                icon: const Icon(Icons.delete_rounded,
                    color: AppTheme.expenseColor),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppPalette.of(context).bgCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppPalette.of(context).border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Color(category.colorValue)
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(category.icon,
                                style: const TextStyle(fontSize: 22)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                current.title,
                                style: TextStyle(
                                  color: AppPalette.of(context).textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${category.name} / ${account.name}',
                                style: TextStyle(
                                    color: AppPalette.of(context).textMuted,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '${isIncome ? '+' : '-'}${provider.currencySymbol} ${current.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: amountColor,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _DetailCard(
                children: [
                  _DetailRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Date',
                    value: DateFormat('EEEE, d MMMM y, HH:mm')
                        .format(current.date),
                  ),
                  const Divider(color: Color(0xFF2D2D55)),
                  _DetailRow(
                    icon: Icons.swap_vert_rounded,
                    label: 'Type',
                    value: isIncome ? 'Income' : 'Expense',
                  ),
                  const Divider(color: Color(0xFF2D2D55)),
                  _DetailRow(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Account',
                    value: account.name,
                  ),
                  if (current.isRecurring) ...[
                    const Divider(color: Color(0xFF2D2D55)),
                    _DetailRow(
                      icon: Icons.repeat_rounded,
                      label: 'Recurring',
                      value: current.recurringFrequency ?? 'Enabled',
                    ),
                  ],
                ],
              ),
              if (current.note?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 18),
                _DetailCard(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TransactionNotes(
                        key: ValueKey(current.id), note: current.note!),
                  ],
                ),
              ],
              if (current.receiptImagePath != null) ...[
                const SizedBox(height: 18),
                _ReceiptAttachment(path: current.receiptImagePath!),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ExpenseProvider provider,
    String id,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.of(context).bgCard,
        title: Text('Delete Transaction',
            style: TextStyle(color: AppPalette.of(context).textPrimary)),
        content: Text(
          'This transaction will be removed from your records.',
          style: TextStyle(color: AppPalette.of(context).textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.expenseColor)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.deleteTransaction(id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _DetailCard extends StatelessWidget {
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  const _DetailCard({
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.of(context).bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: children,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppPalette.of(context).textMuted, size: 18),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: AppPalette.of(context).textSecondary, fontSize: 13)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppPalette.of(context).textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptAttachment extends StatelessWidget {
  final String path;

  const _ReceiptAttachment({required this.path});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return _DetailCard(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photo Attachment',
          style:
              TextStyle(color: AppPalette.of(context).textMuted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (file.existsSync())
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(file, width: double.infinity, fit: BoxFit.cover),
          )
        else
          const Text(
            'Photo is no longer available on this device.',
            style: TextStyle(color: AppTheme.warningColor, fontSize: 13),
          ),
      ],
    );
  }
}
