// Recording-only entry point. Never selected by the normal app build.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/providers/expense_provider.dart';
import '../../lib/models/transaction_model.dart';
import '../../lib/models/treasure_jar.dart';
import '../../lib/services/database_service.dart';
import '../../lib/screens/home_screen.dart';
import '../../lib/utils/app_theme.dart';

class ManualDemoProvider extends ExpenseProvider {
  ManualDemoProvider() : super(initialize: false);
  @override
  Future<void> refreshBudgetNotifications() async {}
  @override
  Future<void> syncNow({bool? useDeviceCopy}) async {}
  @override
  bool get canSync => false;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final info =
      await const MethodChannel('dev.fluttercommunity.plus/package_info')
          .invokeMapMethod<String, dynamic>('getAll');
  if (!const bool.fromEnvironment('SPENDLY_MANUAL_DEMO') ||
      info?['packageName'] != 'com.example.expense_tracker.manualdemo') {
    runApp(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Text(
                    'Demo entry point requires the isolated demo package.')))));
    return;
  }
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  const owner = 'SP-MANUAL-DEMO';
  await prefs.setString('currentUserId', owner);
  await prefs.setString('userId', owner);
  await prefs.setString('userName', 'Alex Demo');
  await prefs.setString('userEmail', 'demo@spendly.example');
  await prefs.setBool('is_logged_in', false);
  await prefs.setBool('onboarding_done', true);
  await prefs.setBool('quick_tutorial_v1:$owner', true);
  await prefs.setBool('budget_notifications_$owner', false);
  await prefs.setString('currencySymbol', 'RM');
  await prefs.setString('colorTheme', 'Dark');
  if (prefs.getBool('manual_seed_v1') != true) {
    final db = DatabaseService();
    await db.ensureUserDefaults(owner);
    for (final a in [
      AppAccount(
          id: DatabaseService.defaultAccountIdForUser(owner),
          name: 'Cash',
          kind: AccountKind.asset,
          subtype: AccountSubtype.cash,
          openingBalance: 200,
          currentBalance: 200,
          icon: '💵',
          colorValue: 0xFF47B8A1,
          isDefault: true),
      const AppAccount(
          id: 'demo-bank',
          name: 'Everyday Bank',
          kind: AccountKind.asset,
          subtype: AccountSubtype.bank,
          openingBalance: 2500,
          currentBalance: 2500,
          icon: '🏦',
          colorValue: 0xFF745CFF),
      const AppAccount(
          id: 'demo-wallet',
          name: 'E-wallet',
          kind: AccountKind.asset,
          subtype: AccountSubtype.eWallet,
          openingBalance: 150,
          currentBalance: 150,
          icon: '📱',
          colorValue: 0xFF43A9E0),
    ]) {
      await db.insertAccount(a, userId: owner);
    }
    final now = DateTime.now();
    Future<void> entry(String id, String title, double amount, int day,
        TransactionCategory category,
        {bool income = false,
        bool recurring = false,
        DateTime? date,
        String? note}) async {
      await db.saveConfirmedTransaction(
          TransactionModel(
              id: id,
              title: title,
              amount: amount,
              type: income ? TransactionType.income : TransactionType.expense,
              category: category,
              accountId: 'demo-bank',
              date: date ?? DateTime(now.year, now.month, day),
              note: note,
              isRecurring: recurring,
              recurringFrequency: recurring ? 'monthly' : null),
          userId: owner);
    }

    await entry(
        'demo-salary', 'Monthly salary', 4200, 1, TransactionCategory.salary,
        income: true, note: 'Sample salary');
    await entry('demo-lunch', 'Lunch', 18.50, 3, TransactionCategory.food,
        note: 'Lunch with friends');
    await entry(
        'demo-groceries', 'Groceries', 82.40, 6, TransactionCategory.groceries,
        note: 'Weekly essentials');
    await entry('demo-transport', 'Train', 12, 9, TransactionCategory.transport,
        note: 'Train tickets');
    await entry(
        'demo-shopping', 'Shopping', 65.90, 14, TransactionCategory.shopping,
        note: 'A small gift');
    await entry('demo-dinner', 'Dinner', 38, 20, TransactionCategory.food,
        note: 'Dinner');
    await entry(
        'demo-market', 'Market', 47.20, 25, TransactionCategory.groceries,
        note: 'Fruit and vegetables');
    await entry('demo-streaming', 'Music subscription', 19.90, 12,
        TransactionCategory.subscriptions,
        recurring: true,
        date: DateTime(now.year, now.month - 1, 12),
        note: 'Monthly music plan');
    for (final b in [
      BudgetModel(
          id: 'demo-food-budget',
          category: TransactionCategory.food,
          limit: 500,
          month: DateTime(now.year, now.month)),
      BudgetModel(
          id: 'demo-grocery-budget',
          category: TransactionCategory.groceries,
          limit: 600,
          month: DateTime(now.year, now.month)),
      BudgetModel(
          id: 'demo-transport-budget',
          category: TransactionCategory.transport,
          limit: 200,
          month: DateTime(now.year, now.month)),
    ]) {
      await db.upsertBudget(b, userId: owner);
    }
    for (final jar in [
      const TreasureJar(
          id: 'demo-holiday',
          name: 'Holiday fund',
          accountId: 'demo-bank',
          targetCents: 200000,
          savedCents: 45000),
      const TreasureJar(
          id: 'demo-emergency',
          name: 'Emergency fund',
          accountId: 'demo-bank',
          targetCents: 300000,
          savedCents: 80000),
    ]) {
      await db.saveJar(jar, owner);
      await db.adjustJar(jar.id, owner, jar.savedCents);
    }
    await prefs.setBool('manual_seed_v1', true);
  }
  final provider = ManualDemoProvider();
  await provider.reloadSession();
  runApp(ChangeNotifierProvider<ExpenseProvider>.value(
      value: provider,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: const HomeScreen())));
}
