import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/utils/settled_dialog.dart';

void main() {
  for (final dismissWithBack in [false, true]) {
    testWidgets('controller survives dialog exit (back: $dismissWithBack)',
        (tester) async {
      var disposed = false;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return Scaffold(
            body: TextButton(
          onPressed: () async {
            final input = TextEditingController(text: '10.00');
            await showSettledDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                      content: TextField(controller: input),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Cancel'))
                      ],
                    ));
            input.dispose();
            disposed = true;
          },
          child: const Text('Open'),
        ));
      })));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '5.00');
      if (dismissWithBack) {
        Navigator.of(tester.element(find.byType(TextField))).pop();
      } else {
        await tester.tap(find.text('Cancel'));
      }
      await tester.pump();
      expect(disposed, isFalse);
      await tester.pump(const Duration(milliseconds: 75));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(disposed, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
