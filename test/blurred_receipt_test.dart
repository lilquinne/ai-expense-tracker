import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/services/ocr_service.dart';
import 'package:expense_tracker/services/receipt_notes.dart';
import 'package:expense_tracker/widgets/transaction_notes.dart';

void main() {
  test('recognizes the observed damaged Bataras logo without a repeated header',
      () {
    final result =
        OcrService.parseText('(ER) ATARAS\nDRIED MUSHROOM\nTOTAL 46 . 50');
    expect(result.merchant, 'Bataras');
    expect(result.amount, 46.50);
    expect(result.suggestedCategory, TransactionCategory.groceries);
    expect(OcrService.parseText('(ER) ATARAS\nTOTAL 18 . 20').amount, 18.20);
  });
  test('partial grocery receipt retains essentials without priced items', () {
    final result = OcrService.parseText('''(ER iATARAS
BATARAS HYPERMARKET SDN BHD
ITEM # 203119000000 1 1.74
DRIED MUSHROOM (S)
EGG TRAY (B)
SUB TOTAL 46.48
ROUNDING ADJ 0.02
T0TA1
46.50
CASH 100.00
CHANGE 53.50''');
    expect(result.merchant, 'Bataras');
    expect(result.amount, 46.50);
    expect(result.suggestedCategory, TransactionCategory.groceries);
    expect(result.lineItems, isEmpty);
  });

  test('product words categorize an unknown shop without item prices', () {
    final result =
        OcrService.parseText('CORNER MART\nMUSHROOM\nEGGS 30S\nTOTAL 27.00');
    expect(result.suggestedCategory, TransactionCategory.groceries);
    expect(result.amount, 27);
  });

  test('damaged subtotal and cash never replace a missing final total', () {
    final result =
        OcrService.parseText('SHOP\nEGGS\nSUB T0TAL 20.00\nCASH 50.00');
    expect(result.amount, isNull);
  });

  test('receipt notes contain the shop only',
      () {
    const receipt = OcrResult(
        rawText: 'private OCR',
        merchant: 'Shop',
        currency: 'MYR',
        lineItems: [
          OcrLineItem(name: 'apple', amount: 7),
          OcrLineItem(name: 'eggs 30s', amount: 20),
          OcrLineItem(name: 'mushroom'),
        ]);
    expect(buildReceiptNote(receipt, defaultCurrency: 'USD'),
        'Shop');
    expect(
        buildReceiptNote(const OcrResult(rawText: 'blur'),
            defaultCurrency: 'RM'),
        isNull);
  });

  testWidgets('notes expand and collapse', (tester) async {
    const note = '1. apple (RM7.00)\n2. eggs (RM20.00)\n3. milk\n4. mushroom';
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
      body: TransactionNotes(note: note),
    )));
    expect(tester.widget<Text>(find.text(note)).maxLines, 3);
    await tester.tap(find.text('Show more'));
    await tester.pump();
    expect(tester.widget<Text>(find.text(note)).maxLines, isNull);
    await tester.tap(find.text('Show less'));
    await tester.pump();
    expect(tester.widget<Text>(find.text(note)).maxLines, 3);
  });
}
