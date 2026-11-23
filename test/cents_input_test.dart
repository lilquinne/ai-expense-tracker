import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/utils/cents_input_formatter.dart';
import 'package:expense_tracker/widgets/amount_keypad.dart';

void main() {
  test('native money entry shifts cents, deletes, pastes and limits amounts',
      () {
    final formatter = CentsInputFormatter();
    var value = const TextEditingValue();
    for (final expected in ['0.01', '0.10', '1.00', '10.00']) {
      value = formatter.formatEditUpdate(
          value,
          TextEditingValue(
              text: value.text + (value.text.isEmpty ? '1' : '0')));
      expect(value.text, expected);
      expect(value.selection.baseOffset, expected.length);
    }
    value =
        formatter.formatEditUpdate(value, const TextEditingValue(text: '10.0'));
    expect(value.text, '1.00');
    expect(
        formatter
            .formatEditUpdate(value, const TextEditingValue(text: '25.60'))
            .text,
        '25.60');
    expect(
        formatter
            .formatEditUpdate(
                value, const TextEditingValue(text: '999999999999'))
            .text,
        '1.00');
  });
  testWidgets('custom pad shifts cents and deletes the final digit',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AmountKeypad(
                controller: controller,
                onDone: () {},
                onDate: () {},
                toolbar: const SizedBox()))));
    for (final entry in [
      ('1', '0.01'),
      ('0', '0.10'),
      ('0', '1.00'),
      ('0', '10.00')
    ]) {
      await tester.tap(find.text(entry.$1));
      await tester.pump();
      expect(controller.text, entry.$2);
    }
    await tester.tap(find.byTooltip('Delete digit'));
    await tester.pump();
    expect(controller.text, '1.00');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
