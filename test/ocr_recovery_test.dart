import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:expense_tracker/services/ocr_service.dart';
import 'package:expense_tracker/services/receipt_gate.dart';

const readable =
    'CORNER SHOP\nMILK 5.00\nEGGS 7.00\nTOTAL 12.00\nCASH 20.00\nCHANGE 8.00';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('complete item reads skip recovery but header-only reads do not', () {
    final complete = OcrService.parseText(readable);
    expect(receiptNeedsRecovery(complete), false);
    expect(
        receiptNeedsRecovery(OcrService.parseText('CORNER SHOP\nTOTAL 12.00')),
        true);
  });
  test('a richer read is preferred and conflicting totals remain flagged', () {
    final header = OcrService.parseText('CORNER SHOP\nTOTAL 12.00');
    final detailed = OcrService.parseText(readable);
    expect(selectReceiptRead(header, detailed).lineItems.length, 2);
    final different =
        OcrService.parseText(readable.replaceAll('TOTAL 12.00', 'TOTAL 72.00'));
    final selected = selectReceiptRead(header, different);
    expect(selected.amount, 12);
    expect(selected.lineItems.length, 2);
    expect(selected.reviewReasons.single, contains('disagree'));
    expect(selectReceiptRead(detailed, header).lineItems.length, 2);
  });
  test('repaired printed total labels still pass the receipt gate', () {
    final receipt = OcrService.parseText(
        'CORNER SHOP\nMILK 12.00\nT0TA1 12.00\nCASH 20.00');
    expect(receipt.amount, 12);
    expect(ReceiptGate.accepts(receipt), true);
    expect(
        ReceiptGate.accepts(
            OcrService.parseText('Shampoo 12.00 Ingredients Vitamin E')),
        false);
  });
  for (final initial in ['', 'CORNER SHOP\nTOTAL 12.00']) {
    test(
        'recovery runs after ${initial.isEmpty ? 'blank' : 'header-only'} OCR without changing original photo',
        () async {
      final folder =
          await Directory.systemTemp.createTemp('receipt-recovery-test-');
      final original = await File('${folder.path}/original.jpg')
          .writeAsBytes(img.encodeJpg(img.Image(width: 240, height: 360)));
      final originalBytes = await original.readAsBytes();
      var calls = 0;
      const textChannel = MethodChannel('google_mlkit_text_recognizer');
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(textChannel, (call) async {
        if (call.method == 'vision#startTextRecognizer') {
          calls++;
          return {'text': calls == 1 ? initial : readable, 'blocks': []};
        }
        return null;
      });
      messenger.setMockMethodCallHandler(pathChannel, (_) async => folder.path);
      final ocr = OcrService();
      try {
        final result = await ocr.scanReceipt(original);
        expect(calls, 2);
        expect(result.amount, 12);
        expect(result.lineItems.length, 2);
        expect(await original.readAsBytes(), originalBytes);
      } finally {
        ocr.dispose();
        await Future<void>.delayed(Duration.zero);
        messenger.setMockMethodCallHandler(textChannel, null);
        messenger.setMockMethodCallHandler(pathChannel, null);
        if (folder.absolute.path.startsWith(
            '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}')) {
          await folder.delete(recursive: true);
        }
      }
    });
  }
}
