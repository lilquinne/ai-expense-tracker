import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/transaction_model.dart';
import 'ocr_service.dart';
import 'merchant_service.dart';
import 'receipt_item_cleanup.dart';
import 'ai_categorization_service.dart';

typedef ReceiptRequest = Future<dynamic> Function(String text);

class AiReceiptOutcome {
  final OcrResult result;
  final String? message;
  const AiReceiptOutcome(this.result, [this.message]);
}

/// Cloud extraction is optional; failures always preserve the local result.
class AiReceiptService {
  final ReceiptRequest _request;
  final Duration timeout;
  AiReceiptService(
      {ReceiptRequest? request, this.timeout = const Duration(seconds: 40)})
      : _request = request ?? _invoke;

  static Future<dynamic> _invoke(String text) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      throw const AuthException('Sign in to use AI receipt extraction.');
    }
    final response =
        await client.functions.invoke('extract-receipt', body: {'text': text});
    if (response.status != 200) {
      throw const FormatException('Extraction failed');
    }
    return response.data;
  }

  Future<AiReceiptOutcome> enhance(OcrResult local) async {
    try {
      final data = await _request(local.rawText).timeout(timeout);
      final parsed = parse(data, local.rawText);
      return AiReceiptOutcome(parsed.copyWith(
          reviewReasons: {
        ...local.reviewReasons,
        ...parsed.reviewReasons,
      }.toList()));
    } on AuthException {
      return AiReceiptOutcome(local,
          'Sign in or create an online account to use AI. Showing the local scan.');
    } on FunctionException catch (error) {
      return AiReceiptOutcome(
          local,
          error.status == 429
              ? 'AI scan limit reached. Showing the local scan.'
              : 'AI is unavailable. Showing the local scan.');
    } catch (_) {
      return AiReceiptOutcome(
          local, 'AI is unavailable. Showing the local scan.');
    }
  }

  static OcrResult parse(dynamic value, String rawText,
      {bool usedAi = true, bool manualEdit = false}) {
    if (value is! Map) throw const FormatException('Invalid receipt');
    String? string(String key) {
      final v = value[key];
      if (v == null) return null;
      if (v is! String || v.length > 500) {
        throw const FormatException('Invalid text');
      }
      return v.trim().isEmpty ? null : v.trim();
    }

    double? number(dynamic v) {
      if (v == null) return null;
      if (v is! num || !v.isFinite || v < 0 || v > 100000000) {
        throw const FormatException('Invalid amount');
      }
      return v.toDouble();
    }

    final categoryName = string('category');
    TransactionCategory? category;
    for (final candidate in TransactionCategory.values) {
      if (!candidate.isIncomeCategory && candidate.name == categoryName) {
        category = candidate;
      }
    }
    if (categoryName != null && category == null) {
      throw const FormatException('Invalid category');
    }
    final dateText = string('date');
    final time = string('time');
    if (time != null &&
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d:[0-5]\d$').hasMatch(time)) {
      throw const FormatException('Invalid time');
    }
    DateTime? date;
    if (dateText != null) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateText)) {
        throw const FormatException('Invalid date');
      }
      date = DateTime.tryParse('${dateText}T${time ?? '00:00:00'}');
      if (date == null || date.toIso8601String().substring(0, 10) != dateText) {
        throw const FormatException('Invalid date');
      }
    }
    final currency = string('currency');
    if (currency != null && !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const FormatException('Invalid currency');
    }
    final rawItems = value['items'];
    final reasons = value['review_reasons'];
    if (rawItems is! List ||
        rawItems.length > 100 ||
        reasons is! List ||
        reasons.length > 20 ||
        reasons.any((r) => r is! String || r.length > 500)) {
      throw const FormatException('Invalid items');
    }
    final items = rawItems
        .map((item) {
          if (item is! Map ||
              item['name'] is! String ||
              (item['name'] as String).trim().isEmpty ||
              (item['name'] as String).length > 500) {
            throw const FormatException('Invalid item');
          }
          return OcrLineItem(
              name: item['name'] as String,
              amount: number(item['amount']),
              quantity: number(item['quantity']),
              unitPrice: number(item['unit_price']));
        })
        .where(
            (item) => manualEdit || ReceiptItemCleanup.clean(item.name) != null)
        .toList();
    final merchant = manualEdit
        ? string('merchant')
        : MerchantService.canonicalize(string('merchant'));
    final total = number(value['total']);
    final reviewReasons = List<String>.from(reasons).toSet();
    // Recompute these derived checks after edits instead of retaining stale flags.
    reviewReasons.remove(
        'Item totals differ from the receipt total. Check tax, discounts, rounding or missing items.');
    reviewReasons.remove('Check item quantities, discounts and prices.');
    // Recheck at the client boundary, including after manual edits. Never change
    // the receipt total or invent prices to make incomplete items reconcile.
    if (total != null &&
        items.isNotEmpty &&
        items.every((item) => item.amount != null)) {
      final itemSen =
          items.fold<int>(0, (sum, item) => sum + (item.amount! * 100).round());
      if ((itemSen - (total * 100).round()).abs() > 1) {
        reviewReasons.add(
            'Item totals differ from the receipt total. Check tax, discounts, rounding or missing items.');
      }
    }
    for (final item in items) {
      if (item.quantity != null &&
          item.unitPrice != null &&
          item.amount != null &&
          ((item.quantity! * item.unitPrice! * 100).round() -
                      (item.amount! * 100).round())
                  .abs() >
              1) {
        reviewReasons.add('Check item quantities, discounts and prices.');
      }
    }
    var confidence = 0.0;
    if (!manualEdit) {
      final localCategory = AiCategorizationService.categorizeReceipt(
          merchant: merchant,
          items: items.map((item) => item.name).toList(),
          itemAmounts: items.map((item) => item.amount).toList(),
          rawText: rawText);
      // Exact remembered choices and strong item evidence are shared with local
      // OCR. Weak mixed-basket evidence must not silently override AI or a user.
      if (localCategory.confidence >= .6 || category == null) {
        if (localCategory.confidence > 0) {
          category = localCategory.category;
          confidence = localCategory.confidence;
        }
      }
    }
    return OcrResult(
        rawText: rawText,
        merchant: merchant,
        titleItem: items.isEmpty ? null : items.first.name,
        amount: total,
        date: date,
        purchaseTime: time,
        currency: currency,
        receiptNumber: string('receipt_number'),
        paymentMethod: string('payment_method'),
        suggestedCategory: category ?? TransactionCategory.other,
        categoryConfidence: confidence,
        usedAi: usedAi,
        reviewReasons: reviewReasons.toList(),
        lineItems: items,
        items: items.map((i) => i.name).toList());
  }
}
