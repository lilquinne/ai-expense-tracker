import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/services/ocr_service.dart';
import 'package:expense_tracker/widgets/receipt_summary.dart';

void main() {
  testWidgets('phone preview shows five fields and expandable receipt details',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ReceiptSummary(
                    receipt: OcrResult(
                        rawText: '',
                        merchant: 'Ninso',
                        amount: 2.8,
                        date: DateTime(2026, 9, 29),
                        paymentMethod: 'Debit card / bank',
                        suggestedCategory: TransactionCategory.homeAppliances,
                        receiptNumber: 'S2LB98202609290073',
                        lineItems: const [
          ReceiptLineItem(name: 'Ninso Wet Tissue', amount: 2.8)
        ]))))));
    for (final value in [
      'Home appliances',
      'Ninso',
      '2.80',
      '29-09-2026',
      'Debit card / bank'
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('S2LB98202609290073'), findsNothing);
    await tester.tap(find.text('Receipt details'));
    await tester.pumpAndSettle();
    expect(find.text('S2LB98202609290073'), findsOneWidget);
    expect(find.textContaining('Ninso Wet Tissue'), findsOneWidget);
    expect(find.text('Items total'), findsOneWidget);
    expect(find.text('Total − items'), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

