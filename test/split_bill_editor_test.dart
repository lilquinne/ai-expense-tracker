import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/widgets/transaction_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/split_bill.dart';
import 'package:expense_tracker/widgets/split_bill_editor.dart';

void main() {
  testWidgets('removing another person preserves the selected payer identity',
      (tester) async {
    const bill = SplitBill(1000, 2, [
      SplitPerson('me', 'Me', 400),
      SplitPerson('one', 'First friend', 300),
      SplitPerson('two', 'Payer friend', 300)
    ]);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SplitBillEditor(
                totalSen: 1000, owner: 'owner', initial: bill))));
    await tester.tap(find.byTooltip('Remove person').first);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButtonFormField<int>>(
                find.byType(DropdownButtonFormField<int>))
            .initialValue,
        1);
    expect(find.text('Payer friend'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'home split row displays own expense and original bill total without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const bill = SplitBill(4650, 0,
        [SplitPerson('me', 'Me', 2325), SplitPerson('p', 'Person', 2325)]);
    final entry = TransactionModel(
        id: 'b',
        title: 'Bataras',
        amount: 23.25,
        type: TransactionType.expense,
        category: TransactionCategory.groceries,
        date: DateTime(2026, 10, 24),
        splitData: bill.encode());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TransactionTile(transaction: entry, currencySymbol: 'RM'))));
    await tester.pumpAndSettle();
    expect(find.text('-RM 23.25'), findsOneWidget);
    expect(find.text('Bill total RM 46.50'), findsOneWidget);
    expect(find.textContaining('Split'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
