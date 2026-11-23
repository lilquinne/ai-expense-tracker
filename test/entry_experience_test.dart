import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/services/daily_guide_reminder.dart';
import 'package:expense_tracker/screens/home_screen.dart';
import 'package:expense_tracker/screens/quick_tutorial_screen.dart';
import 'package:expense_tracker/screens/onboarding_screen.dart';
import 'package:expense_tracker/screens/add_transaction_screen.dart';
import 'package:expense_tracker/screens/transfer_screen.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/utils/app_theme.dart';

class EntryProvider extends ExpenseProvider {
  EntryProvider({this.owner = 'entry-user'}) : super(initialize: false);
  final String owner;
  @override
  String get userId => owner;
  @override
  Future<void> loadData() async {}
  @override
  Future<List<TransactionModel>> loadChartTransactions() async => [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('first-use tutorial saves completion', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const QuickTutorialScreen(
                                userId: 'entry-user'))),
                    child: const Text('Tour'))))));
    await tester.tap(find.text('Tour'));
    await tester.pumpAndSettle();
    expect(find.text('1. Start with a receipt'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(
        (await SharedPreferences.getInstance())
            .getBool('quick_tutorial_v1:entry-user'),
        true);
  });
  testWidgets('budget guide appears on launch but not after switching apps',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'quick_tutorial_v1:entry-user': true});
    final provider = EntryProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: HomeScreen(guideLoader: () async => null))));
    await tester.pumpAndSettle();
    expect(find.text('Your daily budget guide'), findsOneWidget);
    expect(find.text('You can also find this guide in Notifications.'),
        findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Your daily budget guide'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: HomeScreen(guideLoader: () async => null))));
    await tester.pumpAndSettle();
    expect(find.text('Your daily budget guide'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('a fresh process can remind again; calendar dates change at midnight',
      () {
    final firstLaunch = DailyGuideReminder();
    expect(firstLaunch.claimLaunch('user'), isTrue);
    expect(firstLaunch.claimLaunch('user'), isFalse);
    expect(DailyGuideReminder().claimLaunch('user'), isTrue);
    expect(DailyGuideReminder.localDate(DateTime(2026, 11, 3, 23, 59)),
        '2026-11-03');
    expect(DailyGuideReminder.localDate(DateTime(2026, 11, 4)), '2026-11-04');
  });

  testWidgets('do not remind today checkbox saves and clears the preference',
      (tester) async {
    const owner = 'checkbox-user';
    SharedPreferences.setMockInitialValues({'quick_tutorial_v1:$owner': true});
    final provider = EntryProvider(owner: owner);
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: HomeScreen(guideLoader: () async => null))));
    await tester.pumpAndSettle();
    final checkbox = find.byType(CheckboxListTile);
    expect(find.text('Do not remind me today'), findsOneWidget);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final key = DailyGuideReminder.preferenceKey(owner);
    expect(prefs.getString(key), DailyGuideReminder.localDate(DateTime.now()));
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(prefs.getString(key), isNull);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(prefs.getString(key), DailyGuideReminder.localDate(DateTime.now()));
    expect(tester.takeException(), isNull);
  });

  for (final hiddenToday in [true, false]) {
    testWidgets(
        'launch respects saved reminder date: hidden today = $hiddenToday',
        (tester) async {
      final owner = 'saved-date-$hiddenToday';
      final date = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'quick_tutorial_v1:$owner': true,
        DailyGuideReminder.preferenceKey(owner): DailyGuideReminder.localDate(
            hiddenToday ? date : DateTime(date.year, date.month, date.day - 1)),
      });
      final provider = EntryProvider(owner: owner);
      addTearDown(provider.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
          value: provider,
          child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: HomeScreen(guideLoader: () async => null))));
      await tester.pumpAndSettle();
      expect(find.text('Your daily budget guide'),
          hiddenToday ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'transfer changes mode without navigation and old document tab is absent',
      (tester) async {
    final provider = EntryProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme, home: const AddTransactionScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Insert Doc'), findsNothing);
    final route =
        ModalRoute.of(tester.element(find.byType(AddTransactionScreen)));
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    expect(ModalRoute.of(tester.element(find.byType(TransferScreen))),
        same(route));
    expect(find.text('From account'), findsOneWidget);
    expect(find.text('To account'), findsOneWidget);
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    expect(find.byType(TransferScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('onboarding leads with camera capture and OCR review',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme, home: const OnboardingScreen()));
    expect(find.text('A receipt becomes a record'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Clear text, better results'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Review before you save'), findsOneWidget);
  });
}
