import '../models/transaction_model.dart';
import 'receipt_parser.dart';

/// A payment network identifies a payment type, never a specific bank account.
class ReceiptAccountMatcher {
  static List<AppAccount> candidates(
      String? payment, List<AppAccount> accounts) {
    final method = ReceiptParser.extractPaymentMethod(payment ?? '');
    return accounts.where((a) {
      switch (method) {
        case 'Debit card / bank':
        case 'Bank transfer':
          return a.kind == AccountKind.asset &&
              a.subtype == AccountSubtype.bank;
        case 'Credit card':
          return a.kind == AccountKind.liability &&
              a.subtype == AccountSubtype.creditCard;
        case 'Card':
          return (a.kind == AccountKind.asset &&
                  a.subtype == AccountSubtype.bank) ||
              (a.kind == AccountKind.liability &&
                  a.subtype == AccountSubtype.creditCard);
        case 'Cash':
          return a.kind == AccountKind.asset &&
              a.subtype == AccountSubtype.cash;
        case 'E-wallet / QR':
          return a.kind == AccountKind.asset &&
              (a.subtype == AccountSubtype.eWallet ||
                  a.subtype == AccountSubtype.bank);
        default:
          return false;
      }
    }).toList();
  }

  static String? suggest(String? payment, List<AppAccount> accounts) {
    final matches = candidates(payment, accounts);
    return matches.length == 1 ? matches.single.id : null;
  }
}
