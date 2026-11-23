import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/screens/category_management_screen.dart';
import 'package:expense_tracker/screens/add_transaction_screen.dart';
import 'package:expense_tracker/utils/category_icons.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('favourites persist and categories follow food/groceries/other priority',
      () async {
    final provider = ExpenseProvider(initialize: false);
    addTearDown(provider.dispose);
    final categories = provider.categoriesForType(TransactionType.expense);
    final roots =
        categories.where((c) => c.id == c.parentCategory.name).toList();
    expect(roots.first.id, 'food');
    expect(roots[1].id, 'groceries');
    expect(roots.last.id, 'other');
    final fuel = categories.firstWhere((c) => c.name == 'Fuel');
    expect(provider.isFavouriteCategory(fuel), false);
    await provider.toggleFavouriteCategory(fuel);
    expect(provider.isFavouriteCategory(fuel), true);
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('favourite_categories:'),
        contains(fuel.id));
    await provider.toggleFavouriteCategory(fuel);
    expect(provider.isFavouriteCategory(fuel), false);
    expect(
        categories
            .where((c) => c.parentCategory == TransactionCategory.food)
            .length,
        5);
    expect(categories.length, greaterThan(60));
  });

  testWidgets('library stars control transaction shortcuts on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = ExpenseProvider(initialize: false);
    addTearDown(provider.dispose);
    Widget app(Widget home) => ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider, child: MaterialApp(home: home));
    await tester.pumpWidget(app(const CategoryManagementScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(Wrap), findsWidgets);
    await tester.tap(
        find.byIcon(appCategoryIcon(provider.categoryById('food')!)).first);
    await tester.pumpAndSettle();
    expect(provider.isFavouriteCategory(provider.categoryById('food')!), false);
    await tester.pumpWidget(app(const AddTransactionScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsNothing);
    expect(find.text('Groceries'), findsWidgets);
    await tester.tap(find.byTooltip('All categories'));
    await tester.pumpAndSettle();
    expect(find.text('All categories'), findsOneWidget);
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
