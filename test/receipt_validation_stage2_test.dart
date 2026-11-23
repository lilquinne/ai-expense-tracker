import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/services/ai_receipt_service.dart';
import 'package:expense_tracker/services/ai_categorization_service.dart';
import 'package:expense_tracker/services/category_learning_service.dart';
import 'package:expense_tracker/services/ocr_service.dart';
import 'package:expense_tracker/services/receipt_parser.dart';

Map<String, dynamic> payload() => {
      'merchant': 'Bataras',
      'total': 15.0,
      'category': 'shopping',
      'items': [
        {'name': 'Eggs', 'amount': 15.0, 'quantity': 1, 'unit_price': 15.0}
      ],
      'review_reasons': <String>[],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CategoryLearningService.load('stage2');
  });
  test('AI and local OCR share strong product evidence', () {
    final ai =
        AiReceiptService.parse(payload(), 'Bataras\nEggs 15.00\nTOTAL 15.00');
    final local = OcrService.parseText('Bataras\nEggs 15.00\nTOTAL 15.00');
    expect(ai.suggestedCategory, local.suggestedCategory);
    expect(ai.suggestedCategory, TransactionCategory.groceries);
  });
  test('remembered basket wins over AI but manual confirmation wins over both',
      () async {
    await CategoryLearningService.remember(
        CategoryLearningService.receiptKey('Bataras', ['Eggs']),
        TransactionCategory.other);
    expect(AiReceiptService.parse(payload(), '').suggestedCategory,
        TransactionCategory.other);
    expect(
        AiReceiptService.parse(payload(), '', manualEdit: true)
            .suggestedCategory,
        TransactionCategory.shopping);
    await CategoryLearningService.load('different-user');
    expect(AiReceiptService.parse(payload(), '').suggestedCategory,
        TransactionCategory.groceries);
  });
  test('reconciliation records a mismatch without changing totals or prices',
      () {
    final data = payload()..['total'] = 20.0;
    final result = AiReceiptService.parse(data, '');
    expect(result.amount, 20);
    expect(result.lineItems.single.amount, 15);
    expect(result.reviewReasons, contains(contains('Item totals differ')));
    data['review_reasons'] = result.reviewReasons;
    data['total'] = 15.0;
    expect(AiReceiptService.parse(data, '', manualEdit: true).reviewReasons,
        isNot(contains(contains('Item totals differ'))));
  });
  test('partial items keep confirmed total without inventing missing prices',
      () {
    final data = payload()
      ..['items'] = [
        {'name': 'Eggs', 'amount': null}
      ];
    final result = AiReceiptService.parse(data, '');
    expect(result.amount, 15);
    expect(result.lineItems.single.amount, isNull);
    expect(result.reviewReasons, isEmpty);
    data['items'] = [];
    expect(AiReceiptService.parse(data, '').amount, 15);
  });
  test(
      'sen arithmetic tolerates one sen rounding and detects quantity mismatch',
      () {
    final data = payload()
      ..['total'] = .3
      ..['items'] = [
        {'name': 'Eggs', 'amount': .1},
        {'name': 'Milk', 'amount': .2}
      ];
    expect(AiReceiptService.parse(data, '').reviewReasons, isEmpty);
    data['total'] = .31;
    expect(AiReceiptService.parse(data, '').reviewReasons, isEmpty);
    final quantity = payload();
    (quantity['items'] as List).first['quantity'] = 2;
    expect(AiReceiptService.parse(quantity, '').reviewReasons,
        contains(contains('quantities')));
  });
  test('nonfinite oversized and malformed AI input preserves local scan',
      () async {
    const local = OcrResult(rawText: 'TOTAL 15.00', amount: 15);
    for (final bad in [double.nan, double.infinity, -1, 100000001, '15']) {
      final service =
          AiReceiptService(request: (_) async => payload()..['total'] = bad);
      expect((await service.enhance(local)).result, same(local));
    }
    final data = payload()
      ..['items'] = List.generate(101, (_) => {'name': 'Eggs'});
    expect(() => AiReceiptService.parse(data, ''), throwsFormatException);
  });
  test('negative and oversized local totals are not positive expenses', () {
    for (final text in [
      'TOTAL -15.00',
      'TOTAL RM -15.00',
      'TOTAL (15.00)',
      'TOTAL\n-15.00',
      'TOTAL 100000001.00'
    ]) {
      expect(ReceiptParser.extractAmount(text), isNull, reason: text);
    }
    expect(ReceiptParser.moneyValue('Infinity'), isNull);
    expect(ReceiptParser.moneyValue('NaN'), isNull);
  });
  test('invalid price weights fall back safely and duplicate items remain', () {
    final result = AiCategorizationService.categorizeReceipt(
        items: ['Eggs', 'Eggs', 'Lipstick'],
        itemAmounts: [5, double.nan, 100],
        rawText: '');
    expect(result.category, TransactionCategory.groceries);
    expect(result.confidence.isFinite, isTrue);
    final data = payload()
      ..['items'] = [
        {'name': 'Eggs', 'amount': 5},
        {'name': 'Eggs', 'amount': 5},
        {'name': 'TOTAL', 'amount': 10}
      ];
    expect(AiReceiptService.parse(data, '').lineItems.length, 2);
  });
}
