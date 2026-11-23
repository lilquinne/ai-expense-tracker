import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/services/merchant_service.dart';
import 'package:expense_tracker/services/receipt_notes.dart';
import 'package:expense_tracker/services/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MerchantService.load('user-a');
  });
  test('Bataras OCR variants have one canonical name', () {
    for (final name in [
      'ERBATARAS BATANAS HYIERAARKET O LABUAM',
      'BATANAS HYPERARKET',
      '(ER) ATARAS',
      'Bataras'
    ]) {
      expect(MerchantService.canonicalize(name), 'Bataras');
    }
    expect(MerchantService.canonicalize('Unknown Store'), 'Unknown Store');
    expect(
        MerchantService.canonicalize('Bataras Guardian'), 'Bataras Guardian');
  });
  test('Borneo Mart is read from the top header, not a department', () {
    final receipt = OcrService.parseText(
        'BORNEO MART PLT\nUNIT A030 - A034 & B016 - B018,\nFINANCIAL PARK COMPLEX, JLN MERDEKA,\n87000 WP LABUAN\n(ROC: 202504002941)\n**INVOICE**\nCHILLED & FR\nFUMAKILLA VAPE AERIST WHITE 270ML\n1.0 X 7.00 7.00\nTOTAL RM 7.00\nDEBIT CARD 7.00');
    expect(buildReceiptNote(receipt, defaultCurrency: 'RM'), 'Borneo Mart');
    expect(
        buildReceiptNote(
            OcrService.parseText('INVOICE\nCHILLED & FR\nTOTAL RM 7.00'),
            defaultCurrency: 'RM'),
        isNull);
  });
  test('saved corrections survive reload and remain scoped to a user',
      () async {
    await MerchantService.remember('HAPY MART', 'Happy Mart');
    await MerchantService.load('user-a');
    expect(MerchantService.canonicalize('HAPY MART'), 'Happy Mart');
    expect(MerchantService.canonicalize('HAPY MART SDN BHD'), 'Happy Mart');
    await MerchantService.load('user-b');
    expect(MerchantService.canonicalize('HAPY MART'), 'HAPY MART');
  });
  test('receipt note contains only the shop, never item names or prices', () {
    const receipt = OcrResult(rawText: '', merchant: 'Bataras', lineItems: [
      OcrLineItem(name: 'DADA 4YAM TTULAN', amount: 9.90),
      OcrLineItem(name: 'EGGS 30S', amount: 20),
      OcrLineItem(name: 'EGGS 30S', amount: 20),
      OcrLineItem(name: 'oTAL', amount: 48.50),
      OcrLineItem(name: 'SUBTOTAL', amount: 46.48),
      OcrLineItem(name: 'ITEM # 1234567', amount: 2),
      OcrLineItem(name: '123456789', amount: 2),
    ]);
    expect(buildReceiptNote(receipt, defaultCurrency: 'RM'), 'Bataras');
    expect(
        buildReceiptNote(
            const OcrResult(rawText: '', titleItem: 'Milk', items: ['Milk']),
            defaultCurrency: 'RM'),
        isNull);
  });
}
