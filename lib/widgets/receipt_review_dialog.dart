import '../utils/cents_input_formatter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/ai_receipt_service.dart';
import '../services/ocr_service.dart';

class ReceiptReviewDialog extends StatefulWidget {
  final OcrResult receipt;
  const ReceiptReviewDialog({super.key, required this.receipt});
  @override
  State<ReceiptReviewDialog> createState() => _ReceiptReviewDialogState();
}

class _ReceiptReviewDialogState extends State<ReceiptReviewDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  final _items = <Map<String, TextEditingController>>[];
  final _removed = <TextEditingController>[];
  String? _category;
  String? _error;
  static const _labels = {
    'merchant': 'Shop name',
    'total': 'Total',
    'currency': 'Currency code (MYR, USD, etc.)',
    'date': 'Date (DD-MM-YYYY)',
    'receipt_number': 'Receipt number',
    'payment_method': 'Payment method'
  };

  @override
  void initState() {
    super.initState();
    final r = widget.receipt;
    final initial = {
      'merchant': r.merchant,
      'total': r.amount?.toStringAsFixed(2),
      'currency': r.currency,
      'date': r.date == null ? null : DateFormat('dd-MM-yyyy').format(r.date!),
      'receipt_number': r.receiptNumber,
      'payment_method': r.paymentMethod
    };
    _fields = initial
        .map((k, v) => MapEntry(k, TextEditingController(text: v ?? '')));
    _category = r.suggestedCategory?.name;
    for (final item in r.lineItems) {
      _items.add(_itemFields(item));
    }
  }

  Map<String, TextEditingController> _itemFields([OcrLineItem? item]) => {
        'name': TextEditingController(text: item?.name ?? ''),
        'quantity':
            TextEditingController(text: item?.quantity?.toString() ?? ''),
        'unit_price': TextEditingController(
            text: item?.unitPrice?.toStringAsFixed(2) ?? ''),
        'amount':
            TextEditingController(text: item?.amount?.toStringAsFixed(2) ?? ''),
      };

  @override
  void dispose() {
    for (final c in [
      ..._fields.values,
      ..._items.expand((i) => i.values),
      ..._removed
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  dynamic _value(String key, TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    if (key == 'date')
      return DateFormat('yyyy-MM-dd')
          .format(DateFormat('dd-MM-yyyy').parseStrict(text));
    if (['total', 'quantity', 'unit_price', 'amount'].contains(key)) {
      return double.parse(text);
    }
    return key == 'currency' ? text.toUpperCase() : text;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    try {
      final value = <String, dynamic>{
        for (final entry in _fields.entries)
          entry.key: _value(entry.key, entry.value),
        'category': _category,
        'time': null,
        'items': _items
            .map((item) => <String, dynamic>{
                  for (final entry in item.entries)
                    entry.key: _value(entry.key, entry.value),
                })
            .toList(),
        'review_reasons': widget.receipt.reviewReasons,
      };
      final result = AiReceiptService.parse(value, widget.receipt.rawText,
          usedAi: widget.receipt.usedAi, manualEdit: true);
      Navigator.pop(context, result);
    } catch (_) {
      setState(() => _error = 'Check the date, currency and amounts.');
    }
  }

  Widget _field(String key, String label, TextEditingController controller) {
    final numeric = ['total', 'quantity', 'unit_price', 'amount'].contains(key);
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          readOnly: key == 'date',
          onTap: key != 'date'
              ? null
              : () async {
                  final selected = controller.text.isEmpty
                      ? null
                      : DateFormat('dd-MM-yyyy').parseStrict(controller.text);
                  final picked = await showDatePicker(
                      context: context,
                      initialDate: selected ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100, 12, 31));
                  if (picked != null && mounted)
                    setState(() => controller.text =
                        DateFormat('dd-MM-yyyy').format(picked));
                },
          decoration: InputDecoration(
              labelText: label,
              suffixIcon: key != 'date'
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (controller.text.isNotEmpty)
                        IconButton(
                            tooltip: 'Clear date',
                            onPressed: () => setState(controller.clear),
                            icon: const Icon(Icons.clear)),
                      const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Icon(Icons.calendar_today_outlined)),
                    ])),
          inputFormatters:
              numeric && key != 'quantity' ? [CentsInputFormatter()] : null,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (key == 'name' && text.isEmpty) return 'Enter an item name';
            if (text.length > 500) return 'Keep this under 500 characters';
            if (numeric && text.isNotEmpty) {
              final number = double.tryParse(text);
              if (number == null ||
                  !number.isFinite ||
                  number < 0 ||
                  number > 100000000) {
                return 'Enter a valid positive number';
              }
            }
            return null;
          },
        ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit receipt details'),
        content: SizedBox(
            width: double.maxFinite,
            child: Form(
                key: _form,
                child: ListView(shrinkWrap: true, children: [
                  for (final entry in _fields.entries)
                    _field(entry.key, _labels[entry.key]!, entry.value),
                  DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        const DropdownMenuItem<String>(
                            value: null, child: Text('Choose later')),
                        for (final c in TransactionCategory.values
                            .where((c) => !c.isIncomeCategory))
                          DropdownMenuItem(value: c.name, child: Text(c.label))
                      ],
                      onChanged: (v) => _category = v),
                  for (var i = 0; i < _items.length; i++) ...[
                    Row(children: [
                      Expanded(child: Text('Item ${i + 1}')),
                      IconButton(
                          tooltip: 'Remove item',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            setState(() {
                              _removed.addAll(_items.removeAt(i).values);
                            });
                          })
                    ]),
                    _field('name', 'Item name', _items[i]['name']!),
                    _field('quantity', 'Quantity', _items[i]['quantity']!),
                    _field(
                        'unit_price', 'Unit price', _items[i]['unit_price']!),
                    _field('amount', 'Line total', _items[i]['amount']!),
                  ],
                  TextButton.icon(
                      onPressed: _items.length >= 100
                          ? null
                          : () => setState(() => _items.add(_itemFields())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add item')),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Apply'))
        ],
      );
}
