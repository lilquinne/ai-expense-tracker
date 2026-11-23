import 'package:flutter/services.dart';
import 'package:expense_tracker/utils/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/screens/add_transaction_screen.dart';
import 'package:expense_tracker/screens/accounts_screen.dart';

class ReceiptExpenses extends ExpenseProvider {
  ReceiptExpenses() : super(initialize: false);
  String? savedAccount;
  String? savedTitle;
  @override
  List<AppAccount> get accounts => [
        ...AppAccount.defaults,
        for (final id in ['Bank A', 'Bank B'])
          AppAccount(
              id: id,
              name: id,
              kind: AccountKind.asset,
              subtype: AccountSubtype.bank,
              openingBalance: 100,
              currentBalance: 100,
              icon: 'B',
              colorValue: 0xFF000000),
      ];
  @override
  AppAccount? accountById(String id) =>
      accounts.where((a) => a.id == id).firstOrNull;
  @override
  Future<void> addTransaction(
      {required String title,
      required double amount,
      required TransactionType type,
      required TransactionCategory category,
      String? categoryId,
      String? accountId,
      DateTime? date,
      String? note,
      String? receiptImagePath,
      bool isRecurring = false,
      String? recurringFrequency,
      String? splitData}) async {
    savedAccount = accountId;
    savedTitle = title;
  }
}

void main() {
  testWidgets(
      'account Add opens the existing account page and back preserves shop',
      (tester) async {
    final provider = ReceiptExpenses();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: const MaterialApp(
            home: AddTransactionScreen(
                prefilledTitle: 'Bataras',
                prefilledAmount: 10,
                prefilledCategory: TransactionCategory.groceries))));
    await tester.tap(find.byKey(const ValueKey('transaction-account-picker')));
    await tester.pumpAndSettle();
    final add = find.text('Add Account');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.byType(AddAccountScreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save Transaction'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bank A'));
    await tester.tap(find.text('Bank A'));
    await tester.pumpAndSettle();
    expect(provider.savedTitle, 'Bataras');
  });
  testWidgets(
      'receipt cannot silently save to cash when bank choice is ambiguous',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = ReceiptExpenses();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: const MaterialApp(
            home: AddTransactionScreen(
                prefilledTitle: 'Ninso',
                prefilledAmount: 2.8,
                prefilledCategory: TransactionCategory.homeAppliances,
                prefilledPaymentMethod: 'Debit card / bank',
                requireAccountSelection: true))));
    await tester.ensureVisible(find.byTooltip('Save Transaction'));
    await tester.tap(find.byTooltip('Save Transaction'));
    await tester.pumpAndSettle();
    expect(provider.savedAccount, isNull);
    expect(find.text('Choose account'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bank B'));
    await tester.tap(find.text('Bank B'));
    await tester.pumpAndSettle();
    expect(provider.savedAccount, 'Bank B');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'manual entry has no Shop field and parent category is optional to expand',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = ReceiptExpenses();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: const MaterialApp(home: AddTransactionScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Shop'), findsNothing);
    expect(find.text('Transfer'), findsOneWidget);
    expect(find.text('Insert Doc'), findsNothing);
    await tester.ensureVisible(find.text('Food'));
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    expect(find.text('Food & Dining'), findsWidgets);
    await tester.ensureVisible(find.byTooltip('All categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('All categories'));
    await tester.pumpAndSettle();
    expect(find.text('All categories'), findsOneWidget);
    final layoutError = tester.takeException();
    expect(layoutError, isNull);
  });
  testWidgets('entry preview uses compact readable typography', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_PREVIEW')) return;
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final loader = FontLoader('Sora')
      ..addFont(rootBundle.load('assets/fonts/Sora-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Sora-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Sora-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Sora-Bold.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final provider = ReceiptExpenses();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme, home: const AddTransactionScreen())));
    await tester.pumpAndSettle();
    await expectLater(find.byType(AddTransactionScreen),
        matchesGoldenFile('../output/manual-entry-preview.png'));
  });
}
