import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/models/transaction_model.dart';

class ReservedBalanceProvider extends ExpenseProvider {
  ReservedBalanceProvider() : super(initialize: false);
  final reservations = <String, double>{};
  @override
  double reservedFor(String accountId) => reservations[accountId] ?? 0;
  @override
  List<AppAccount> get accounts => [
        const AppAccount(
            id: 'bank',
            name: 'Bank',
            kind: AccountKind.asset,
            subtype: AccountSubtype.bank,
            openingBalance: 100,
            currentBalance: 100,
            icon: 'B',
            colorValue: 0),
        const AppAccount(
            id: 'hidden',
            name: 'Hidden',
            kind: AccountKind.asset,
            subtype: AccountSubtype.bank,
            openingBalance: 80,
            currentBalance: 80,
            icon: 'B',
            colorValue: 0,
            includeInBalance: false),
      ];
}

void main() {
  test('total balance deducts reservations and restores released funds', () {
    final provider = ReservedBalanceProvider();
    addTearDown(provider.dispose);
    expect(provider.totalMyBalance, 100);
    provider.reservations['bank'] = 30.25;
    expect(provider.totalMyBalance, 69.75);
    provider.reservations['hidden'] = 40;
    expect(provider.totalMyBalance, 69.75);
    provider.reservations['bank'] = 20.25;
    expect(provider.totalMyBalance, 79.75);
    provider.reservations.remove('bank');
    expect(provider.totalMyBalance, 100);
  });
}
