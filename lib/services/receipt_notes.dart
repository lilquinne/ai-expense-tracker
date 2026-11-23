import 'ocr_service.dart';
import 'merchant_service.dart';

/// Receipt notes contain only the shop. Item details stay in receipt review.
String? buildReceiptNote(OcrResult receipt, {required String defaultCurrency}) {
  final merchant = receipt.merchant?.trim();
  if (merchant == null || merchant.isEmpty) return null;
  return MerchantService.canonicalize(merchant);
}
