import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/services/ocr_service.dart';
import 'package:expense_tracker/widgets/receipt_review_dialog.dart';

void main() {
  testWidgets(
      'receipt edits survive applying the preview without inventing time',
      (tester) async {
    OcrResult? saved;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      return TextButton(
          onPressed: () async {
            saved = await showDialog<OcrResult>(
                context: context,
                builder: (_) => const ReceiptReviewDialog(
                    receipt: OcrResult(
                        rawText: 'Original scan',
                        merchant: 'Old shop',
                        amount: 12,
                        currency: 'MYR',
                        usedAi: true)));
          },
          child: const Text('Review'));
    }))));
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Shop name'), 'Correct shop');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Total'), '15.50');
    final dateField = find.widgetWithText(TextFormField, 'Date (DD-MM-YYYY)');
    await tester.ensureVisible(dateField);
    await tester.tap(dateField);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Time (HH:mm:ss)'), findsNothing);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(saved?.merchant, 'Correct shop');
    expect(saved?.amount, 15.5);
    expect(saved?.rawText, 'Original scan');
    expect(saved?.purchaseTime, isNull);
    expect(saved?.date, isNotNull);
    expect(saved?.usedAi, isTrue);
    expect(tester.takeException(), isNull);
  });
}
