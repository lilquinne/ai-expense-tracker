import 'ocr_service.dart';
import 'receipt_gate.dart';
import 'receipt_parser.dart';
import 'merchant_service.dart';

/// Skip a network round-trip only for complete, reconciled local reads.
bool receiptReadyLocally(OcrResult result) {
  if (!ReceiptGate.accepts(result) ||
      result.amount == null ||
      result.amount! <= 0 ||
      result.merchant == null ||
      result.date == null ||
      result.lineItems.isEmpty ||
      result.reviewReasons.isNotEmpty ||
      result.lineItems.any((i) => i.amount == null)) return false;
  final sum = result.lineItems
      .fold<int>(0, (sum, i) => sum + (i.amount! * 100).round());
  return (sum - (result.amount! * 100).round()).abs() <= 1;
}

OcrResult prepareReceiptDraft(OcrResult local, OcrResult enhanced) {
  final warnings = {...local.reviewReasons, ...enhanced.reviewReasons};
  if (local.amount == null)
    warnings.add(
        'The printed total was not read clearly. Check it against the receipt.');
  if (local.amount != null &&
      enhanced.amount != null &&
      (local.amount! * 100).round() != (enhanced.amount! * 100).round()) {
    warnings.add(
        'AI and the printed-total text disagree. Check the receipt total.');
  }
  if (enhanced.lineItems.isEmpty)
    warnings.add(
        'Some item details could not be read. The receipt photo is attached.');
  // A recognised labelled total outranks an AI guess from an item price.
  // An absent labelled total is left blank in the editor rather than invented.
  return OcrResult(
      rawText: local.rawText,
      merchant: MerchantService.canonicalize(
          ReceiptParser.extractMerchant(local.rawText)),
      titleItem: enhanced.titleItem ?? local.titleItem,
      amount: local.amount,
      suggestedCategory: enhanced.suggestedCategory ?? local.suggestedCategory,
      categoryConfidence: enhanced.categoryConfidence,
      date: enhanced.date ?? local.date,
      items: enhanced.items.isEmpty ? local.items : enhanced.items,
      lineItems:
          enhanced.lineItems.isEmpty ? local.lineItems : enhanced.lineItems,
      currency: enhanced.currency ?? local.currency,
      receiptNumber: enhanced.receiptNumber ?? local.receiptNumber,
      paymentMethod: enhanced.paymentMethod ?? local.paymentMethod,
      purchaseTime: enhanced.purchaseTime ?? local.purchaseTime,
      usedAi: enhanced.usedAi,
      reviewReasons: warnings.toList());
}
