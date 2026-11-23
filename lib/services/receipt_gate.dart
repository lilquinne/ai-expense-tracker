import 'receipt_parser.dart';
import 'ocr_service.dart';

/// Receipt structure, rather than the presence of paper, separates receipts
/// from product packaging, labels and unrelated photos. Digital receipts work.
class ReceiptGate {
  /// Partial receipts can be edited without asking for the same photo again.
  /// Product labels still need receipt-specific evidence to enter this path.
  static bool canReview(OcrResult result) {
    if (accepts(result)) return true;
    final text = result.rawText.toLowerCase();
    final prices = RegExp(r'\b\d+[.,]\d{2}\b').allMatches(text).length;
    final receiptWords = RegExp(
            r'\b(receipt|invoice|resit|cashier|subtotal|sub total|t[o0]ta[l1]|amount due)\b')
        .hasMatch(text);
    final payment =
        RegExp(r'\b(cash|card|visa|mastercard|tender|change|tunai)\b')
            .hasMatch(text);
    return result.merchant != null &&
        ((receiptWords && (prices > 0 || result.date != null)) ||
            (payment && prices > 0 && result.lineItems.isNotEmpty));
  }

  static bool accepts(OcrResult result) {
    final text = result.rawText.toLowerCase();
    final total =
        RegExp(r'\b(total|amount due|balance due|jumlah|grand total)\b')
                .hasMatch(text) ||
            ReceiptParser.extractAmount(text) != null;
    final payment = RegExp(
            r'\b(cash|card|visa|mastercard|change|paid|payment|tender|tunai|receipt|invoice|resit|tax invoice)\b')
        .hasMatch(text);
    final prices = RegExp(r'\b\d+[.,]\d{2}\b').allMatches(text).length;
    final dated = result.date != null ||
        RegExp(r'\b\d{1,4}[-/]\d{1,2}[-/]\d{1,4}\b').hasMatch(text);
    return (total && prices >= 1 && (payment || dated || prices >= 2)) ||
        (payment && dated && prices >= 2 && result.merchant != null);
  }
}
