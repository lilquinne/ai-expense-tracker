import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/widgets/spending_pace_card.dart';

class PaceProvider extends ExpenseProvider {
  PaceProvider() : super(initialize: false);
  @override
  String get userId => 'pace-test';
  @override
  DateTime get selectedMonth =>
      DateTime(DateTime.now().year, DateTime.now().month + 1);
  @override
  Future<List<TransactionModel>> loadChartTransactions() async => [];
}

void main() {
  testWidgets('future month shows no estimate on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = PaceProvider();
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(child: SpendingPaceCard())))));
    await tester.pumpAndSettle();
    expect(find.text('Forecasts are available once this month starts.'),
        findsOneWidget);
    expect(find.textContaining('Estimated month-end'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
}
