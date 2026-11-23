import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'ai_categorization_service.dart';
import 'receipt_parser.dart';
import 'merchant_service.dart';
import '../models/transaction_model.dart';

export 'receipt_parser.dart' show ReceiptLineItem;

typedef OcrLineItem = ReceiptLineItem;

class OcrResult {
  final String rawText;
  final String? merchant;
  final String? titleItem;
  final double? amount;
  final TransactionCategory? suggestedCategory;
  final double categoryConfidence;
  final DateTime? date;
  final List<String> items;
  final List<OcrLineItem> lineItems;
  final String? currency;
  final String? receiptNumber;
  final String? paymentMethod;
  final String? purchaseTime;
  final bool usedAi;
  final List<String> reviewReasons;
  const OcrResult(
      {required this.rawText,
      this.merchant,
      this.titleItem,
      this.amount,
      this.suggestedCategory,
      this.categoryConfidence = 0,
      this.date,
      this.items = const [],
      this.lineItems = const [],
      this.currency,
      this.receiptNumber,
      this.paymentMethod,
      this.purchaseTime,
      this.usedAi = false,
      this.reviewReasons = const []});
  OcrResult copyWith({double? amount, List<String>? reviewReasons}) =>
      OcrResult(
          rawText: rawText,
          merchant: merchant,
          titleItem: titleItem,
          amount: amount ?? this.amount,
          suggestedCategory: suggestedCategory,
          categoryConfidence: categoryConfidence,
          date: date,
          items: items,
          lineItems: lineItems,
          currency: currency,
          receiptNumber: receiptNumber,
          paymentMethod: paymentMethod,
          purchaseTime: purchaseTime,
          usedAi: usedAi,
          reviewReasons: reviewReasons ?? this.reviewReasons);
}

class OcrService {
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Product labels need one text pass, not receipt parsing or a contrast retry.
  Future<String> readLabel(File imageFile) async {
    final recognized =
        await _textRecognizer.processImage(InputImage.fromFile(imageFile));
    return recognized.text;
  }

  Future<OcrResult> scanReceipt(File imageFile) async {
    OcrResult? first;
    try {
      first = await _scanOnce(imageFile);
    } on FormatException {
      // Even an empty first read deserves the local contrast recovery pass.
    }
    if (first != null && !receiptNeedsRecovery(first)) return first;
    Directory? temp;
    OcrResult? retry;
    try {
      final bytes =
          await compute(enhanceReceiptForOcr, await imageFile.readAsBytes());
      if (bytes != null) {
        temp = await (await getTemporaryDirectory()).createTemp('receipt-ocr-');
        final enhanced =
            await File('${temp.path}/enhanced.jpg').writeAsBytes(bytes);
        retry = await _scanOnce(enhanced);
      }
    } catch (_) {
      // Preserve a usable first read if recovery is unavailable.
    } finally {
      if (temp != null) {
        try {
          await temp.delete(recursive: true);
        } catch (_) {}
      }
    }
    if (first == null && retry == null) {
      throw const FormatException(
          'No readable text found. Retake a sharp photo with the whole receipt visible.');
    }
    if (first == null) return retry!;
    return retry == null ? first : selectReceiptRead(first, retry);
  }

  Future<OcrResult> _scanOnce(File imageFile) async {
    final recognized =
        await _textRecognizer.processImage(InputImage.fromFile(imageFile));
    if (recognized.text.trim().isEmpty) {
      throw const FormatException(
          'No readable text found. Retake the receipt in bright light, keeping it flat and fully in frame.');
    }
    // ML Kit may group the item names and the price column into separate blocks.
    // Reassemble lines by their image coordinates before extracting item prices.
    final lines = recognized.blocks.expand((b) => b.lines).toList()
      ..sort(
          (a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
    final rows = <List<TextLine>>[];
    for (final line in lines) {
      if (rows.isEmpty) {
        rows.add([line]);
        continue;
      }
      final row = rows.last;
      final anchor = row.first.boundingBox;
      final box = line.boundingBox;
      final minHeight = box.height < anchor.height ? box.height : anchor.height;
      final sameRow =
          (box.center.dy - anchor.center.dy).abs() < minHeight * .45;
      final overlaps = row.any((other) =>
          box.left < other.boundingBox.right &&
          box.right > other.boundingBox.left);
      if (sameRow && !overlaps) {
        row.add(line);
      } else {
        rows.add([line]);
      }
    }
    final text = rows.map((row) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      return row.map((line) => line.text).join('  ');
    }).join('\n');
    final ordered = parseText(text);
    final original = parseText(recognized.text);
    // Preserve a total that ML Kit placed correctly before geometric row sorting.
    return selectReceiptRead(original, ordered);
  }

  static OcrResult parseText(String text) {
    final rawText = ReceiptParser.normalize(text);
    final merchant =
        MerchantService.canonicalize(ReceiptParser.extractMerchant(rawText));
    final lineItems = ReceiptParser.extractItems(rawText);
    final items = lineItems.map((item) => item.name).toList();
    final category = AiCategorizationService.categorizeReceipt(
        merchant: merchant,
        items: items,
        rawText: rawText,
        itemAmounts: lineItems.map((item) => item.amount).toList());
    return OcrResult(
        rawText: rawText,
        merchant: merchant,
        titleItem: items.isNotEmpty ? items.first : null,
        amount: ReceiptParser.extractAmount(rawText),
        date: ReceiptParser.extractDate(rawText),
        receiptNumber: ReceiptParser.extractInvoiceNumber(rawText),
        paymentMethod: ReceiptParser.extractPaymentMethod(rawText),
        items: items,
        lineItems: lineItems,
        suggestedCategory: category.confidence > 0
            ? category.category
            : TransactionCategory.other,
        categoryConfidence: category.confidence);
  }

  void dispose() {
    _textRecognizer.close();
  }
}

Uint8List? enhanceReceiptForOcr(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final scale = math.min(2.0, 4000 / math.max(image.width, image.height));
  image =
      img.copyResize(image, width: math.max(1, (image.width * scale).round()));
  image = img.grayscale(image);
  image = img.adjustColor(image, contrast: 1.25);
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// A header and total alone do not mean that all receipt items were read.
bool receiptNeedsRecovery(OcrResult result) {
  if (result.merchant == null ||
      result.amount == null ||
      result.lineItems.isEmpty) return true;
  final priced = result.lineItems.where((i) => i.amount != null).toList();
  if (priced.length != result.lineItems.length) return true;
  final subtotal = priced.fold<double>(0, (sum, i) => sum + i.amount!);
  return result.amount! > 0 && subtotal < result.amount! * .65;
}

OcrResult selectReceiptRead(OcrResult first, OcrResult candidate) {
  num score(OcrResult r) =>
      (r.amount == null ? 0 : 1000) +
      (r.merchant == null ? 0 : 100) +
      (r.date == null ? 0 : 5) +
      math.min(r.lineItems.length, 30) +
      math.min(r.lineItems.where((i) => i.amount != null).length, 30) * 2;
  final selected = score(candidate) > score(first) ? candidate : first;
  if (first.amount == null ||
      candidate.amount == null ||
      (first.amount! * 100).round() == (candidate.amount! * 100).round())
    return selected;
  // Conflicting reads are evidence to review, never a reason to invent a total.
  return selected.copyWith(
      amount: first.amount,
      reviewReasons: {
        ...selected.reviewReasons,
        'Two text reads disagree on the total. Check the printed total.'
      }.toList());
}
