import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/ocr_service.dart';
import '../utils/app_theme.dart';

/// The primary receipt preview stays focused on the five expense fields.
class ReceiptSummary extends StatelessWidget {
  final OcrResult receipt;
  const ReceiptSummary({super.key, required this.receipt});

  Widget _row(
          BuildContext context, IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, size: 20, color: AppPalette.of(context).textMuted),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(color: AppPalette.of(context).textSecondary)),
          const SizedBox(width: 16),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: AppPalette.of(context).textPrimary,
                      fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppPalette.of(context).bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.of(context).border)),
        child: Column(children: [
          _row(context, Icons.category_outlined, 'Category',
              receipt.suggestedCategory?.label ?? 'Choose category'),
          _row(context, Icons.storefront, 'Shop',
              receipt.merchant ?? 'Enter shop name'),
          _row(
              context,
              Icons.payments_outlined,
              'Total',
              receipt.amount == null
                  ? 'Enter total'
                  : '${receipt.currency ?? ''} ${receipt.amount!.toStringAsFixed(2)}'
                      .trim()),
          _row(
              context,
              Icons.calendar_today_outlined,
              'Date',
              receipt.date == null
                  ? 'Enter date'
                  : DateFormat('dd-MM-yyyy').format(receipt.date!)),
          _row(context, Icons.credit_card, 'Payment method',
              receipt.paymentMethod ?? 'Choose payment method'),
          Material(
              color: Colors.transparent,
              child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Receipt details'),
                  children: [
                    if (receipt.receiptNumber != null)
                      _row(context, Icons.receipt_long, 'Invoice No.',
                          receipt.receiptNumber!),
                    if (receipt.purchaseTime != null)
                      _row(context, Icons.schedule, 'Time',
                          receipt.purchaseTime!),
                    for (final item in receipt.lineItems)
                      _row(context, Icons.shopping_bag_outlined, 'Item',
                          '${item.name}${item.amount == null ? '' : ' · ${item.amount!.toStringAsFixed(2)}'}'),
                    if (receipt.lineItems.isNotEmpty)
                      _row(
                          context,
                          Icons.calculate_outlined,
                          receipt.lineItems.every((i) => i.amount != null)
                              ? 'Items total'
                              : 'Known items total',
                          (_itemSen / 100).toStringAsFixed(2)),
                    if (receipt.amount != null &&
                        receipt.lineItems.isNotEmpty &&
                        receipt.lineItems.every((i) => i.amount != null))
                      _row(
                          context,
                          Icons.compare_arrows,
                          'Total − items',
                          (((receipt.amount! * 100).round() - _itemSen) / 100)
                              .toStringAsFixed(2)),
                  ])),
        ]),
      );

  int get _itemSen => receipt.lineItems
      .fold<int>(0, (sum, item) => sum + ((item.amount ?? 0) * 100).round());
}
