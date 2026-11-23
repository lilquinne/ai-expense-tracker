import 'receipt_item_cleanup.dart';

/// Pure receipt parsing, separate from the device OCR engine so mistakes can be
/// reproduced and tested with receipt text without uploading receipt images.
class ReceiptLineItem {
  final String name;
  final double? amount;
  final double? quantity;
  final double? unitPrice;
  const ReceiptLineItem(
      {required this.name, this.amount, this.quantity, this.unitPrice});
}

class ReceiptParser {
  static final _money =
      RegExp(r'(?<![\d.,])(?:\d{1,3}(?:[, ]\d{3})+|\d+)[.,]\d{2}(?!\d)');
  static final _summary = RegExp(
      r'^(?:sub\s*total|grand\s*total|total(?:\s+(?:amount|due|payable|rm|myr))?|jumlah(?:\s+besar)?|amount\s+(?:due|payable)|net\s+total|balance\s+due)\b',
      caseSensitive: false);
  static final _metadata = RegExp(
      r'\b(receipt|invoice|resit|cashier|operator|terminal|approval|subtotal|total|tax|sst|gst|change|cash|visa|mastercard|payment|paid|rounding|discount|balance|tel|telephone|fax|www|email|date|time|qty|quantity|description|harga|jumlah|reg|registration|thank|welcome|jalan|lorong|postcode|sdn|bhd)\b',
      caseSensitive: false);

  /// Correct ambiguous zero glyphs only in decimal money tokens, not shop names.
  static String normalize(String text) => text.replaceAllMapped(
      RegExp(
          r'(?<![A-Za-z0-9])[0-9OØøƟɵ∅⊘]+[.,][0-9OØøƟɵ∅⊘]{2}(?![A-Za-z0-9])'),
      (m) => m[0]!.replaceAll(RegExp('[OØøƟɵ∅⊘]'), '0'));

  static double? moneyValue(String value) {
    var cleaned = value.replaceAll(' ', '');
    if (cleaned.contains('.')) {
      cleaned = cleaned.replaceAll(',', '');
    } else {
      cleaned = cleaned.replaceAll(',', '.');
    }
    final amount = double.tryParse(cleaned);
    return amount != null &&
            amount.isFinite &&
            amount >= 0 &&
            amount <= 100000000
        ? amount
        : null;
  }

  static List<String> _lines(String text) => normalize(text)
      .replaceAllMapped(
          RegExp(r'(\d)\s*[.]\s*(\d{2})(?!\d)'), (m) => '${m[1]}.${m[2]}')
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  // Restrict OCR repairs to a leading total label, never arbitrary item text.
  static String _totalLine(String line) => line.replaceFirstMapped(
      RegExp(
          r'^(?:(grand|sub|net)\s*)?t[\s.]*[o0][\s.]*t[\s.]*a[\s.]*[l1i|](?=\s|:|$)',
          caseSensitive: false),
      (m) => '${m[1] ?? ''} total'.trim());

  static double? extractAmount(String text) {
    final lines = _lines(text);
    double? amount;
    var bestRank = -1;
    for (var i = 0; i < lines.length; i++) {
      final line = _totalLine(lines[i]);
      // Refund/credit totals need explicit review; do not drop their sign and
      // turn them into positive expenses.
      if (RegExp(r'[-−(]\s*(?:RM|MYR)?\s*\d+[.,]\d{2}', caseSensitive: false)
          .hasMatch(line)) {
        continue;
      }
      if (!_summary.hasMatch(line) ||
          RegExp(r'\b(sub\s*total|subtotal|saving|savings|discount|qty|quantity|items|item|tax|sst|gst)\b',
                  caseSensitive: false)
              .hasMatch(line)) {
        continue;
      }
      final rank = RegExp(
                  r'grand|payable|amount\s+due|jumlah\s+besar|net\s+total',
                  caseSensitive: false)
              .hasMatch(line)
          ? 3
          : 2;
      var matches = _money.allMatches(line).toList();
      // A total label and its price are frequently emitted on separate lines.
      if (matches.isEmpty &&
          i + 1 < lines.length &&
          RegExp(r'^(?:RM|MYR|USD|SGD|\$)?\s*[\dOØø., ]+$',
                  caseSensitive: false)
              .hasMatch(lines[i + 1])) {
        matches = _money.allMatches(lines[i + 1]).toList();
      }
      if (matches.isNotEmpty && rank >= bestRank) {
        final candidate = moneyValue(matches.last[0]!);
        if (candidate != null) {
          amount = candidate;
          bestRank = rank;
        }
      }
    }
    // Never guess from cash tendered, change, a barcode, or the largest item.
    return amount;
  }

  static String? extractMerchant(String text) {
    // Stop at the receipt body. Department and product names are not shops.
    final header = <String>[];
    for (final line in _lines(text).take(8)) {
      if (header.isEmpty &&
          RegExp(r'^\W*(receipt|invoice|resit)\W*$', caseSensitive: false)
              .hasMatch(line)) continue;
      if (RegExp(
              r'\b(invoice|receipt|resit|qty|quantity|cashier|operator|total|date)\b|\d{1,2}[-/]\d{1,2}[-/]\d{2,4}',
              caseSensitive: false)
          .hasMatch(line)) break;
      header.add(line);
    }
    // The Bataras logo is sometimes recognized as a separate '(ER)' emblem
    // followed by ATARAS. Keep this correction tightly scoped to a header line.
    if (header.any((line) =>
        RegExp(r'^(?:\(ER\)\s*)[BiI8]?ATARAS$', caseSensitive: false)
            .hasMatch(line))) {
      return 'Bataras';
    }
    // A readable repeated brand in the company header can recover a damaged logo.
    if (header.any((line) => RegExp(
            r'^bataras\s+(?:hypermarket|supermarket|sdn)\b',
            caseSensitive: false)
        .hasMatch(line))) {
      return 'Bataras';
    }
    for (final line in header) {
      if (line.length < 3 || !RegExp(r'[A-Za-z]').hasMatch(line)) continue;
      if (RegExp(
              r'\b(chilled|frozen|department|grocery|produce|description|item|unit|roc|jln|park complex)\b',
              caseSensitive: false)
          .hasMatch(line)) continue;
      if (RegExp(r'\b(receipt|invoice|resit|welcome|thank|tel|fax|reg|registration|date|time|jalan|lorong|cashier|www|qty|total)\b',
                  caseSensitive: false)
              .hasMatch(line) ||
          _money.hasMatch(line)) {
        continue;
      }
      if (RegExp(r'^\d+[\s,/-]').hasMatch(line)) continue;
      if (RegExp(r'^ninso\b', caseSensitive: false).hasMatch(line)) {
        return 'Ninso';
      }
      if (RegExp(r'\bbataras\b', caseSensitive: false).hasMatch(line)) {
        return 'Bataras';
      }
      return line
          .replaceAll(
              RegExp(r'\s*\((?:\d|reg)[^)]*\)', caseSensitive: false), '')
          .trim();
    }
    return null;
  }

  static List<ReceiptLineItem> extractItems(String text) {
    final lines = _lines(text);
    final merchant = extractMerchant(text);
    final items = <ReceiptLineItem>[];
    String? pending;
    for (final line in lines) {
      if (_summary.hasMatch(_totalLine(line))) break;
      if (line == merchant ||
          _metadata.hasMatch(line) ||
          RegExp(r'^\s*(?:item\s*#|item\s+\d|qty\b)', caseSensitive: false)
              .hasMatch(line)) {
        pending = null;
        continue;
      }
      if (RegExp(r'^\d{6,}$').hasMatch(line)) continue;
      final matches = _money.allMatches(line).toList();
      if (matches.isNotEmpty) {
        var name = line
            .substring(0, matches.first.start)
            .trim()
            .replaceAll(
                RegExp(r'\b(?:RM|MYR|USD|SGD)\s*$', caseSensitive: false), '')
            .replaceAll(RegExp(r'^\d{6,}\s+'), '')
            .replaceAll(RegExp(r'^\d+\s*[xX]\s*'), '')
            .replaceAll(RegExp(r'\s+\d+(?:[.,]\d+)?\s*[xX@]?\s*$'), '')
            .trim();
        if (!RegExp(r'[A-Za-z]{2}').hasMatch(name)) name = pending ?? '';
        if (ReceiptItemCleanup.clean(name) != null) {
          items.add(ReceiptLineItem(
              name: displayItem(name), amount: moneyValue(matches.last[0]!)));
        }
        pending = null;
      } else if (RegExp(r'[A-Za-z]{2}').hasMatch(line) &&
          !RegExp(r'^[\d\s/:-]+$').hasMatch(line)) {
        pending = line;
      }
    }
    return items;
  }

  static String displayItem(String name) =>
      RegExp(r'^ninso\s+wet\s+(?:kitchen\s+towel|tissues?)\b',
                  caseSensitive: false)
              .hasMatch(name)
          ? 'Ninso Wet Tissue'
          : name;

  static bool isHouseholdSupply(String text) => RegExp(
          r'\b(wet tissues?|wet wipes?|kitchen towels?|rice cooker|kettle|vacuum cleaner)\b',
          caseSensitive: false)
      .hasMatch(text);

  static String? extractInvoiceNumber(String text) => RegExp(
          r'\b(?:invoice|receipt|resit)\s*(?:no\.?|number|#)\s*:?\s*([A-Za-z0-9][A-Za-z0-9/-]{3,})',
          caseSensitive: false)
      .firstMatch(text)
      ?.group(1);

  static String? extractPaymentMethod(String text) {
    if (RegExp(r'\b(my\s*debit|debit)\b', caseSensitive: false)
        .hasMatch(text)) {
      return 'Debit card / bank';
    }
    if (RegExp(r'\b(credit\s*card)\b', caseSensitive: false).hasMatch(text)) {
      return 'Credit card';
    }
    if (RegExp(r'\b(visa|master\s*card|amex|card)\b', caseSensitive: false)
        .hasMatch(text)) {
      return 'Card';
    }
    if (RegExp(r'\b(duitnow|tng|touch.?n.?go|e.?wallet|grabpay|boost)\b',
            caseSensitive: false)
        .hasMatch(text)) {
      return 'E-wallet / QR';
    }
    if (RegExp(r'\b(bank transfer|fpx)\b', caseSensitive: false)
        .hasMatch(text)) {
      return 'Bank transfer';
    }
    if (RegExp(r'^\s*(?:payment\s*:?\s*)?cash\b',
            caseSensitive: false, multiLine: true)
        .hasMatch(text)) {
      return 'Cash';
    }
    return null;
  }

  static DateTime? extractDate(String text) {
    DateTime? valid(int y, int m, int d, [int h = 0, int min = 0]) {
      if (y < 100) y += 2000;
      if (y < 2000 ||
          y > 2100 ||
          m < 1 ||
          m > 12 ||
          d < 1 ||
          d > 31 ||
          h > 23 ||
          min > 59) {
        return null;
      }
      final result = DateTime(y, m, d, h, min);
      return result.year == y && result.month == m && result.day == d
          ? result
          : null;
    }

    final iso = RegExp(
        r'\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})(?:[ T]+(\d{1,2}):(\d{2}))?');
    for (final m in iso.allMatches(text)) {
      final date = valid(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
          int.tryParse(m[4] ?? '') ?? 0, int.tryParse(m[5] ?? '') ?? 0);
      if (date != null) return date;
    }
    final numeric = RegExp(
        r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{4}|\d{2})\b(?:\s+(\d{1,2}):(\d{2}))?');
    for (final m in numeric.allMatches(text)) {
      final date = valid(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!),
          int.tryParse(m[4] ?? '') ?? 0, int.tryParse(m[5] ?? '') ?? 0);
      if (date != null) return date;
    }
    const months = [
      'jan',
      'feb',
      'mar',
      'apr',
      'may',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec'
    ];
    for (final m in RegExp(
            r'\b(\d{1,2})[\s-]+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s-]+(\d{4}|\d{2})\b',
            caseSensitive: false)
        .allMatches(text)) {
      final date = valid(int.parse(m[3]!),
          months.indexOf(m[2]!.toLowerCase()) + 1, int.parse(m[1]!));
      if (date != null) return date;
    }
    return null;
  }
}
