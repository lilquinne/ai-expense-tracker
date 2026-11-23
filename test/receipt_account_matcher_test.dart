import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/services/receipt_account_matcher.dart';

AppAccount account(String id, AccountSubtype subtype,
        {AccountKind kind = AccountKind.asset}) =>
    AppAccount(
        id: id,
        name: id,
        kind: kind,
        subtype: subtype,
        openingBalance: 100,
        currentBalance: 100,
        icon: 'bank',
        colorValue: 0xFF000000);

void main() {
  final cash = account('cash', AccountSubtype.cash);
  final bank = account('bank', AccountSubtype.bank);
  final card =
      account('credit', AccountSubtype.creditCard, kind: AccountKind.liability);
  test('MYDEBIT suggests only a unique bank, never cash or credit', () {
    expect(ReceiptAccountMatcher.suggest('MYDEBIT 4788', [cash, bank, card]),
        'bank');
    expect(ReceiptAccountMatcher.suggest('Debit card / bank', [cash, card]),
        isNull);
    expect(
        ReceiptAccountMatcher.suggest(
            'MYDEBIT', [bank, account('second', AccountSubtype.bank)]),
        isNull);
  });
  test('ambiguous card and missing payment require account selection', () {
    expect(ReceiptAccountMatcher.suggest('VISA', [cash, bank, card]), isNull);
    expect(ReceiptAccountMatcher.suggest(null, [cash]), isNull);
    expect(ReceiptAccountMatcher.suggest('Cash', [cash, bank]), 'cash');
    expect(ReceiptAccountMatcher.suggest('Credit card', [cash, bank, card]),
        'credit');
  });
}
