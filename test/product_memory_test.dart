import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/services/product_memory_service.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/widgets/transaction_tile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'memory is account scoped, requires confirmed labels, and keeps corrections',
      () async {
    final hash = '01' * 32;
    expect(await ProductMemoryService.hasVisualMemory('one'), false);
    await ProductMemoryService.remember(
        'one', 'Melaleuca essential oil', TransactionCategory.shopping,
        hash: hash, confirmed: false);
    expect(
        await ProductMemoryService.find('one',
            hash: hash, labelText: 'Melaleuca essential oil'),
        isNull);
    await ProductMemoryService.remember(
        'one', 'Melaleuca essential oil', TransactionCategory.health);
    expect(await ProductMemoryService.hasVisualMemory('one'), true);
    expect(await ProductMemoryService.hasVisualMemory('two'), false);
    expect(
        (await ProductMemoryService.find('one',
            name: 'MELALEUCA essential oil'))?['category'],
        'health');
    expect(
        (await ProductMemoryService.find('one',
            hash: hash, labelText: 'Melaleuca essential oil'))?['category'],
        'health');
    expect(
        await ProductMemoryService.find('two', name: 'Melaleuca essential oil'),
        isNull);
    expect(
        await ProductMemoryService.find('one',
            hash: hash, labelText: 'Different bottle'),
        isNull);
  });
  testWidgets('transaction row leads with category, then note and account',
      (tester) async {
    final t = TransactionModel(
        id: 'x',
        title: 'Old merchant title',
        amount: 10,
        type: TransactionType.expense,
        category: TransactionCategory.groceries,
        date: DateTime(2026, 10, 30),
        note: 'Milk and eggs');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TransactionTile(
                transaction: t,
                currencySymbol: 'RM',
                accountName: 'My bank'))));
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Milk and eggs'), findsOneWidget);
    expect(find.text('My bank'), findsOneWidget);
    expect(find.text('Old merchant title'), findsNothing);
    expect(
        tester.widget<Text>(find.text('Groceries')).style!.fontSize!,
        greaterThan(
            tester.widget<Text>(find.text('Milk and eggs')).style!.fontSize!));
  });
}
