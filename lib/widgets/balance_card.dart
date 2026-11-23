// lib/widgets/balance_card.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/app_theme.dart';

class BalanceCard extends StatelessWidget {
  final double balance;
  final double reserved;
  final double income;
  final double expense;
  final String currencySymbol;
  final DateTime month;

  const BalanceCard({
    super.key,
    required this.balance,
    this.reserved = 0,
    required this.income,
    required this.expense,
    required this.currencySymbol,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE59A), Color(0xFFFFF0C5), Color(0xFFF4D57C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                  child: Text(
                DateFormat('MMMM yyyy').format(month),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF765E4B), fontSize: 13),
              )),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x1F79502F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Total Balance',
                    style: TextStyle(
                        color: const Color(0xFF765E4B), fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$currencySymbol ${balance.toStringAsFixed(2)}',
            style: TextStyle(
              color: balance >= 0
                  ? const Color(0xFF4B2D1C)
                  : AppTheme.expenseColor,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text('Reserved: $currencySymbol ${reserved.toStringAsFixed(2)}',
              style: const TextStyle(color: Color(0xFF765E4B), fontSize: 11)),
          const Text('Total Balance excludes money reserved in jars.',
              style: TextStyle(color: Color(0xFF765E4B), fontSize: 10)),
          const SizedBox(height: 10),
          Container(height: 1, color: const Color(0x2679502F)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatColumn(
                  label: 'Income',
                  value: '$currencySymbol ${income.toStringAsFixed(2)}',
                  icon: Icons.arrow_upward_rounded,
                  color: AppTheme.incomeColor,
                ),
              ),
              Container(width: 1, height: 40, color: const Color(0x2679502F)),
              Expanded(
                child: _StatColumn(
                  label: 'Expenses',
                  value: '$currencySymbol ${expense.toStringAsFixed(2)}',
                  icon: Icons.arrow_downward_rounded,
                  color: AppTheme.expenseColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatColumn(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                color: Color(0xFF765E4B), fontSize: 11)),
                        Text(value,
                            style: const TextStyle(
                                color: Color(0xFF4B2D1C),
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ],
                    ))),
          ],
        ),
      );
}
