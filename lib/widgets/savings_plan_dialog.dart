import '../utils/cents_input_formatter.dart';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class SavingsPlanDialog extends StatefulWidget {
  const SavingsPlanDialog(
      {super.key, required this.currency, this.hint, this.baseline});
  final String currency;
  final Map<String, dynamic>? hint;
  final Map<String, dynamic>? baseline;
  @override
  State<SavingsPlanDialog> createState() => _SavingsPlanDialogState();
}

class _SavingsPlanDialogState extends State<SavingsPlanDialog> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    final values = <String, dynamic>{
      'target': widget.hint?['target'],
      'months': widget.hint?['months'] ?? 2,
      'saved': 0,
      'income': widget.baseline?['salary'],
      'expenses': widget.baseline?['expenses'],
      'essentials': null,
      'buffer': null
    };
    for (final entry in values.entries) {
      _fields[entry.key] =
          TextEditingController(text: entry.value?.toString() ?? '');
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String? _validate(String name, String? text) {
    final value = double.tryParse(text ?? '');
    if (value == null || !value.isFinite || value < 0 || value > 100000000)
      return 'Enter a valid amount';
    if (name == 'target' && value == 0) return 'Enter a target above zero';
    if (name == 'months' &&
        (value < 1 || value > 24 || value != value.roundToDouble()))
      return 'Choose 1–24 whole months';
    if (name != 'months' && !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text!))
      return 'Use up to two decimal places';
    if (name == 'essentials' &&
        value > (double.tryParse(_fields['expenses']!.text) ?? 0))
      return 'Cannot exceed total monthly expenses';
    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppPalette.of(context).bgCard,
        title: const Text('Savings plan'),
        content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Confirm your monthly estimates, including upcoming bills. This checks a plan; it does not move money.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppPalette.of(context).textSecondary)),
                          if ((widget.baseline?['months'] as num? ?? 0) > 0)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                    'Income and expenses are suggested from ${widget.baseline!['months']} past months with records. Please check them.',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppPalette.of(context)
                                            .textSecondary))),
                          const SizedBox(height: 18),
                          for (final entry in {
                            'target': 'Savings target',
                            'months': 'Months from now',
                            'saved': 'Already saved for this goal',
                            'income': 'Expected monthly take-home income',
                            'expenses': 'Expected total monthly expenses',
                            'essentials':
                                'Essential bills within those expenses',
                            'buffer': 'Extra monthly safety buffer'
                          }.entries)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: TextFormField(
                                    key: ValueKey('plan-${entry.key}'),
                                    controller: _fields[entry.key],
                                    inputFormatters: entry.key == 'months'
                                        ? null
                                        : [CentsInputFormatter()],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: InputDecoration(
                                        labelText: entry.value,
                                        prefixText: entry.key == 'months'
                                            ? null
                                            : '${widget.currency} ',
                                        helperText: entry.key == 'essentials'
                                            ? 'Include minimum debt payments, rent and necessities'
                                            : entry.key == 'buffer'
                                                ? 'Enter 0 if no extra buffer is needed'
                                                : null,
                                        helperMaxLines: 2),
                                    validator: (value) =>
                                        _validate(entry.key, value))),
                        ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                Navigator.pop(context, <String, dynamic>{
                  for (final entry in _fields.entries)
                    entry.key: entry.key == 'months'
                        ? double.parse(entry.value.text).toInt()
                        : double.parse(entry.value.text)
                });
              },
              child: const Text('Check plan'))
        ],
      );
}
