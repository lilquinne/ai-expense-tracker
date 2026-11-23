import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:expense_tracker/services/ai_receipt_service.dart';
import 'package:expense_tracker/services/ocr_service.dart';
import 'package:expense_tracker/models/transaction_model.dart';

Map<String, dynamic> receipt() => {
      'merchant': 'Mini Market',
      'receipt_number': 'R-12',
      'currency': 'MYR',
      'date': '2026-10-09',
      'time': '14:35:00',
      'total': 15.0,
      'payment_method': 'cash',
      'category': 'groceries',
      'review_reasons': <String>[],
      'items': [
        {'name': 'Milk', 'quantity': 2, 'unit_price': 7.5, 'amount': 15}
      ],
    };

void main() {
  const local =
      OcrResult(rawText: 'Mini Market\nMilk 15.00\nTOTAL 15.00', amount: 15);
  test('Groq quota response keeps the local result and explains the limit',
      () async {
    var requests = 0;
    final service = AiReceiptService(request: (_) async {
      requests++;
      throw const FunctionException(
          status: 429, details: {'error': 'provider_limit_reached'});
    });
    final outcome = await service.enhance(local);
    expect(outcome.result, same(local));
    expect(outcome.message, contains('limit reached'));
    expect(requests, 1);
  });
  test('maps AI fields and retains the original OCR', () async {
    final outcome =
        await AiReceiptService(request: (_) async => receipt()).enhance(local);
    expect(outcome.result.usedAi, isTrue);
    expect(outcome.result.rawText, local.rawText);
    expect(outcome.result.date, DateTime(2026, 10, 9, 14, 35));
    expect(outcome.result.lineItems.single.quantity, 2);
    expect(outcome.result.lineItems.single.unitPrice, 7.5);
    expect(outcome.result.suggestedCategory, TransactionCategory.groceries);
  });
  test('AI retains local conflicting-read warnings', () async {
    final warned = local.copyWith(reviewReasons: [
      'Two text reads disagree on the total. Check the printed total.'
    ]);
    final outcome =
        await AiReceiptService(request: (_) async => receipt()).enhance(warned);
    expect(outcome.result.reviewReasons, contains(warned.reviewReasons.single));
  });
  test('missing values stay missing rather than borrowing local guesses', () {
    final data = receipt()
      ..['total'] = null
      ..['time'] = null
      ..['merchant'] = null;
    final result = AiReceiptService.parse(data, local.rawText);
    expect(result.amount, isNull);
    expect(result.purchaseTime, isNull);
    expect(result.merchant, isNull);
    expect(result.date, DateTime(2026, 10, 9));
  });
  test('network and malformed responses preserve the local result', () async {
    for (final request in <ReceiptRequest>[
      (_) async => throw Exception('offline'),
      (_) async => {'items': 'invalid'},
      (_) async => receipt()..['date'] = '2026-02-31',
      (_) async => receipt()..['category'] = 'salary',
      (_) async => receipt()..['total'] = -5,
    ]) {
      final outcome = await AiReceiptService(request: request).enhance(local);
      expect(identical(outcome.result, local), isTrue);
      expect(outcome.message, isNotNull);
    }
  });
  test('timeout returns local data', () async {
    final service = AiReceiptService(
        timeout: const Duration(milliseconds: 1),
        request: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return receipt();
        });
    expect((await service.enhance(local)).result, same(local));
  });
  test('invalid times and currencies are rejected', () {
    expect(() => AiReceiptService.parse(receipt()..['time'] = '25:10:00', ''),
        throwsFormatException);
    expect(() => AiReceiptService.parse(receipt()..['currency'] = 'RM', ''),
        throwsFormatException);
  });
}
