import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/services/ocr_service.dart';
import 'package:expense_tracker/services/ai_receipt_service.dart';
import 'package:expense_tracker/services/receipt_gate.dart';
import 'package:expense_tracker/services/receipt_scan_draft.dart';
import 'package:expense_tracker/screens/scan_receipt_screen.dart';
import 'package:expense_tracker/screens/receipt_camera_screen.dart';
import 'package:expense_tracker/screens/add_transaction_screen.dart';

class ScanPreviewProvider extends ExpenseProvider {
  ScanPreviewProvider() : super(initialize: false);
  @override
  String get userId => 'scan-owner';
  @override
  Future<void> loadData() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const partialText = 'CORNER SHOP\nINVOICE R123\nMILK 1.74\nCASHIER 9';
  test('printed header outranks an incorrect AI department name', () {
    final local =
        OcrService.parseText('BORNEO MART PLT\nINVOICE\nTOTAL RM 7.00');
    final draft = prepareReceiptDraft(
        local, const OcrResult(rawText: '', merchant: 'Chilled & Fr'));
    expect(draft.merchant, 'Borneo Mart');
    final blank = prepareReceiptDraft(
        OcrService.parseText('INVOICE\nCHILLED & FR\nTOTAL RM 7.00'),
        const OcrResult(rawText: '', merchant: 'Chilled & Fr'));
    expect(blank.merchant, isNull);
  });
  test('partial receipts can be reviewed but product labels cannot', () {
    expect(ReceiptGate.canReview(OcrService.parseText(partialText)), true);
    expect(
        ReceiptGate.canReview(
            OcrService.parseText('Shampoo 250ml 12.50 Vitamin E')),
        false);
  });
  test('labelled total wins over a mistaken AI item-price total', () {
    final local = OcrService.parseText(
        'BATARAS\nEGGS 30.00\nMILK 16.50\nTOTAL 46.50\nCASH 50.00');
    final draft = prepareReceiptDraft(local, local.copyWith(amount: 1.74));
    expect(draft.amount, 46.50);
    expect(draft.reviewReasons.join(' '), contains('disagree'));
    final partial = OcrService.parseText(partialText);
    final uncertain =
        prepareReceiptDraft(partial, partial.copyWith(amount: 1.74));
    expect(uncertain.amount, isNull);
    expect(uncertain.reviewReasons.join(' '),
        contains('total was not read clearly'));
  });
  test('cloud fast path requires reconciled priced items and a date', () {
    final complete = OcrService.parseText(
        'CORNER SHOP\nDATE 31/10/2026\nMILK 5.00\nEGGS 7.00\nTOTAL 12.00\nCASH 20.00\nCHANGE 8.00');
    expect(receiptReadyLocally(complete), true);
    expect(receiptReadyLocally(complete.copyWith(amount: 15)), false);
    expect(receiptReadyLocally(OcrService.parseText(partialText)), false);
  });
  for (final complete in [true, false]) {
    testWidgets(
        'capture opens editor directly for ${complete ? 'complete' : 'partial'} receipts',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      const cameraChannel = MethodChannel('plugins.flutter.io/camera');
      const textChannel = MethodChannel('google_mlkit_text_recognizer');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(cameraChannel, (_) async => []);
      messenger.setMockMethodCallHandler(textChannel, (_) async => null);
      final folder = (await tester
          .runAsync(() => Directory.systemTemp.createTemp('scan-flow-test-')))!;
      final photo = File('${folder.path}/photo.jpg');
      await tester.runAsync(() => photo
          .writeAsBytes(img.encodeJpg(img.Image(width: 200, height: 300))));
      final provider = ScanPreviewProvider();
      var aiCalls = 0;
      final local = OcrService.parseText(complete
          ? 'CORNER SHOP\nDATE 31/10/2026\nMILK 5.00\nEGGS 7.00\nTOTAL 12.00\nCASH 20.00\nCHANGE 8.00'
          : partialText);
      await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
          value: provider,
          child: MaterialApp(
              home: Builder(
                  builder: (context) => Scaffold(
                      body: TextButton(
                          child: const Text('Scan'),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ScanReceiptScreen(
                                        receiptReader: (_) async => local,
                                        receiptEnhancer: (r) async {
                                          aiCalls++;
                                          return AiReceiptOutcome(
                                              r.copyWith(amount: 1.74));
                                        },
                                        directoryProvider: () async => folder,
                                      )))))))));
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptCameraScreen), findsOneWidget);
      await tester.runAsync(() async {
        Navigator.of(tester.element(find.byType(ReceiptCameraScreen)))
            .pop(ReceiptCapture(photo.path, false));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      for (var i = 0;
          i < 30 && find.byType(AddTransactionScreen).evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionScreen), findsOneWidget);
      expect(find.byType(ReceiptCameraScreen), findsNothing);
      expect(find.text('Continue to Add Transaction'), findsNothing);
      expect(find.widgetWithText(TextField, 'Merchant'), findsNothing);
      final entry = tester
          .widget<AddTransactionScreen>(find.byType(AddTransactionScreen));
      expect(entry.prefilledAmount, complete ? 12 : null);
      expect(entry.prefilledNote, entry.receiptReview!.merchant);
      expect(entry.prefilledTitle, entry.receiptReview!.merchant);
      expect(entry.prefilledNote ?? '', isNot(contains('MILK')));
      expect(aiCalls, complete ? 0 : 1);
      expect(File(entry.prefilledReceiptImagePath!).existsSync(), true);
      if (!complete) expect(entry.receiptReview!.reviewReasons, isNotEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      provider.dispose();
      messenger.setMockMethodCallHandler(cameraChannel, null);
      messenger.setMockMethodCallHandler(textChannel, null);
      if (folder.absolute.path.startsWith(
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}')) {
        await tester.runAsync(() async {
          try {
            await folder.delete(recursive: true);
          } on FileSystemException {
            // Windows can hold a decoded image until the test process exits.
          }
        });
      }
    });
  }
}
