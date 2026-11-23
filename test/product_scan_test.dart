import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/services/product_scan_service.dart';
import 'package:expense_tracker/services/receipt_gate.dart';
import 'package:expense_tracker/services/ocr_service.dart';
import 'package:expense_tracker/models/transaction_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('single product preparation preserves fingerprint and upload detail',
      () {
    final source = img.Image(width: 1600, height: 900);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(source));
    final prepared = prepareProductScan(bytes);
    expect(prepared['hash'], productFingerprint(bytes));
    expect(prepared['image'], prepareProductPhoto(bytes));
    final upload = img.decodeJpg(base64Decode(prepared['image']!))!;
    expect(upload.width, 1280);
    expect(upload.height, 720);
    expect(() => prepareProductScan(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });
  test('product labels use one text pass without receipt retry', () async {
    const channel = MethodChannel('google_mlkit_text_recognizer');
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'vision#startTextRecognizer') {
        reads++;
        return {'text': 'Milk 250 ml', 'blocks': []};
      }
      return null;
    });
    final ocr = OcrService();
    try {
      expect(await ocr.readLabel(File('product.jpg')), 'Milk 250 ml');
      expect(reads, 1);
    } finally {
      ocr.dispose();
      await Future<void>.delayed(Duration.zero);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  test('product suggestions only accept a clear product and expense category',
      () {
    final item = ProductSuggestion.parse({
      'is_product': true,
      'name': ' Milk ',
      'category': 'groceries',
      'price': 100
    });
    expect(item.name, 'Milk');
    expect(item.category, TransactionCategory.groceries);
    expect(
        () => ProductSuggestion.parse(
            {'is_product': false, 'name': '', 'category': 'other'}),
        throwsFormatException);
    expect(
        ProductSuggestion.parse({
          'is_product': true,
          'name': 'Mystery object',
          'category': 'salary'
        }).category,
        TransactionCategory.other);
    expect(
        ProductSuggestion.parse(
            {'is_product': true, 'name': 'Milk', 'category': null}).category,
        TransactionCategory.groceries);
    expect(
        ProductSuggestion.parse({
          'is_product': true,
          'name': 'Unknown object',
          'category': 'other'
        }).category,
        TransactionCategory.other);
  });
  test('receipt gate rejects products, random images and unrelated text', () {
    expect(
        ReceiptGate.accepts(const OcrResult(
            rawText: 'Shampoo 250ml RM 12.50 ingredients vitamin E')),
        false);
    expect(ReceiptGate.accepts(const OcrResult(rawText: '')), false);
    expect(
        ReceiptGate.accepts(
            const OcrResult(rawText: 'Happy birthday 30/10/2026')),
        false);
    expect(ReceiptGate.accepts(const OcrResult(rawText: '''SHOP
Milk 5.00
TOTAL 5.00
CASH 10.00
CHANGE 5.00''', merchant: 'Shop', amount: 5)), true);
    expect(ReceiptGate.accepts(OcrResult(rawText: '''Online store
Invoice 991
Item 20.00
Paid 20.00''', merchant: 'Online store', date: DateTime(2026, 10, 30))), true);
  });
}
