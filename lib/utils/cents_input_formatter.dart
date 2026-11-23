import 'package:flutter/services.dart';

/// Currency digits enter from the cents end; the caret stays at the end.
class CentsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final cents = int.tryParse(digits);
    if (cents == null || cents > 10000000000) return oldValue;
    final text = (cents / 100).toStringAsFixed(2);
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
