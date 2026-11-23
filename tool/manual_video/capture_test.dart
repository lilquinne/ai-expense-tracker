// Generates the user-guide visuals from Spendly's real widgets and sample data.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/models/treasure_jar.dart';
import 'package:expense_tracker/services/ocr_service.dart';
import 'package:expense_tracker/services/receipt_notes.dart';
import 'package:expense_tracker/services/recurring_service.dart';
import 'package:expense_tracker/screens/home_screen.dart';
import 'package:expense_tracker/screens/add_transaction_screen.dart';
import 'package:expense_tracker/screens/budget_screen.dart';
import 'package:expense_tracker/screens/recurring_screen.dart';
import 'package:expense_tracker/screens/category_management_screen.dart';
import 'package:expense_tracker/utils/app_theme.dart';

class VideoDemo extends ExpenseProvider {
  VideoDemo() : super(initialize: false) {
    final now = DateTime.now();
    TransactionModel row(String id, String name, double amount, int day,
            TransactionCategory category, {bool income = false}) =>
        TransactionModel(
            id: id,
            title: name,
            amount: amount,
            date: DateTime(now.year, now.month, day),
            type: income ? TransactionType.income : TransactionType.expense,
            category: category,
            accountId: 'bank',
            note: name);
    rows.addAll([
      row('salary', 'Monthly salary', 4200, 1, TransactionCategory.salary,
          income: true),
      row('lunch', 'Lunch with friends', 18.50, 3, TransactionCategory.food),
      row('grocery', 'Weekly essentials', 82.40, 6,
          TransactionCategory.groceries),
      row('train', 'Train tickets', 12, 9, TransactionCategory.transport),
      row('gift', 'A small gift', 65.90, 14, TransactionCategory.shopping),
      row('dinner', 'Dinner', 38, 20, TransactionCategory.food),
      row('market', 'Fruit and vegetables', 47.20, 25,
          TransactionCategory.groceries),
      TransactionModel(
          id: 'streaming',
          title: 'Music subscription',
          amount: 19.90,
          date: DateTime(now.year, now.month - 1, 12),
          type: TransactionType.expense,
          category: TransactionCategory.subscriptions,
          accountId: 'bank',
          isRecurring: true,
          recurringFrequency: 'monthly',
          note: 'Monthly music plan'),
    ]);
  }
  final rows = <TransactionModel>[];
  final budgetRows = [
    for (final c in [
      TransactionCategory.food,
      TransactionCategory.groceries,
      TransactionCategory.transport
    ])
      BudgetModel(
          id: c.name,
          category: c,
          limit: c == TransactionCategory.food
              ? 500
              : c == TransactionCategory.groceries
                  ? 600
                  : 200,
          month: DateTime(DateTime.now().year, DateTime.now().month))
  ];
  final accountRows = <AppAccount>[
    const AppAccount(
        id: 'cash',
        name: 'Cash',
        kind: AccountKind.asset,
        subtype: AccountSubtype.cash,
        openingBalance: 200,
        currentBalance: 200,
        icon: '💵',
        colorValue: 0xFF47B8A1,
        isDefault: true),
    const AppAccount(
        id: 'bank',
        name: 'Everyday Bank',
        kind: AccountKind.asset,
        subtype: AccountSubtype.bank,
        openingBalance: 2500,
        currentBalance: 6416.10,
        icon: '🏦',
        colorValue: 0xFF745CFF),
    const AppAccount(
        id: 'wallet',
        name: 'E-wallet',
        kind: AccountKind.asset,
        subtype: AccountSubtype.eWallet,
        openingBalance: 150,
        currentBalance: 150,
        icon: '📱',
        colorValue: 0xFF43A9E0),
  ];
  final jarRows = <TreasureJar>[
    const TreasureJar(
        id: 'holiday',
        name: 'Holiday fund',
        accountId: 'bank',
        targetCents: 200000,
        savedCents: 45000),
    const TreasureJar(
        id: 'emergency',
        name: 'Emergency fund',
        accountId: 'bank',
        targetCents: 300000,
        savedCents: 80000),
  ];
  @override
  String get userId => 'MANUAL-DEMO';
  @override
  String get userName => 'Alex Demo';
  @override
  String get userEmail => 'demo@spendly.example';
  @override
  String get defaultAccountId => 'cash';
  @override
  bool get canSync => false;
  @override
  Future<void> loadData() async {}
  @override
  Future<List<TransactionModel>> loadChartTransactions() async => rows;
  @override
  List<TransactionModel> get transactions => rows
      .where((r) =>
          r.date.year == selectedMonth.year &&
          r.date.month == selectedMonth.month)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  @override
  List<TransactionModel> get recentTransactions =>
      transactions.take(5).toList();
  @override
  List<TransactionModel> get expenseTransactions =>
      transactions.where((r) => r.type == TransactionType.expense).toList();
  @override
  List<TransactionModel> get incomeTransactions =>
      transactions.where((r) => r.type == TransactionType.income).toList();
  @override
  List<BudgetModel> get budgets => budgetRows;
  @override
  List<AppAccount> get accounts => accountRows;
  @override
  List<TreasureJar> get jars => jarRows;
  @override
  double reservedFor(String id) =>
      jarRows
          .where((j) => j.accountId == id)
          .fold<int>(0, (s, j) => s + j.savedCents) /
      100;
  @override
  AppAccount? accountById(String id) =>
      accountRows.where((a) => a.id == id).firstOrNull;
  @override
  double get totalAssets => accountRows.fold(0, (s, a) => s + a.currentBalance);
  @override
  double get totalMyBalance => totalAssets;
  @override
  double get totalLiabilities => 0;
  @override
  double get netWorth => totalAssets;
  @override
  double get totalBudget => budgetRows.fold(0, (s, b) => s + b.limit);
  @override
  double get budgetedSpending => expenseTransactions
      .where((t) => budgetRows.any((b) => b.category == t.category))
      .fold(0, (s, t) => s + t.amount);
  @override
  double? getBudgetLimit(TransactionCategory category) =>
      budgetRows.where((b) => b.category == category).firstOrNull?.limit;
  @override
  double getBudgetUsage(TransactionCategory category) =>
      ((categoryBreakdown[category] ?? 0) / (getBudgetLimit(category) ?? 1))
          .clamp(0, 1);
  @override
  List<RecurringOccurrence> get recurringDue =>
      RecurringService.due(userId, rows, DateTime.now());
  @override
  List<RecurringOccurrence> get recurringNotices => [];
  @override
  Future<void> confirmRecurring(RecurringOccurrence o) async {
    if (!rows.any((r) => r.id == o.id)) rows.add(o.transaction());
    notifyListeners();
  }

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
    rows.add(TransactionModel(
        id: 'demo-${rows.length}',
        title: title,
        amount: amount,
        type: type,
        category: category,
        categoryId: categoryId,
        accountId: accountId,
        date: date ?? DateTime.now(),
        note: note,
        receiptImagePath: receiptImagePath,
        isRecurring: isRecurring,
        recurringFrequency: recurringFrequency,
        splitData: splitData));
    for (var i = 0; i < accountRows.length; i++) {
      final a = accountRows[i];
      if (a.id == accountId)
        accountRows[i] = a.copyWith(
            currentBalance: a.currentBalance +
                (type == TransactionType.income ? amount : -amount));
    }
    notifyListeners();
  }

  @override
  Future<void> upsertBudget(
      {required TransactionCategory category, required double limit}) async {
    budgetRows.removeWhere((b) => b.category == category);
    budgetRows.add(BudgetModel(
        id: category.name,
        category: category,
        limit: limit,
        month: selectedMonth));
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture clean demo walkthrough', (tester) async {
    SharedPreferences.setMockInitialValues(
        {'quick_tutorial_v1:MANUAL-DEMO': true});
    final font = FontLoader('Sora')
      ..addFont(rootBundle.load('assets/fonts/Sora-Regular.ttf'));
    await font.load();
    // Use the app font for platform fallback labels in headless captures.
    for (final family in ['Roboto', 'sans-serif', 'Ahem']) {
      final fallback = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/Sora-Regular.ttf'));
      await fallback.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    const ratio = 2.975;
    tester.view.physicalSize = const Size(1264, 2460);
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final demo = VideoDemo();
    final capture = GlobalKey();
    final nav = GlobalKey<NavigatorState>();
    final guide = <Map<String, dynamic>>[];
    await tester.runAsync(
        () => Directory('tmp/manual-video/stills').create(recursive: true));
    Future<void> shot(String name, String title, String caption,
        {Finder? target, double duration = 5}) async {
      await tester.pumpAndSettle();
      final entry = <String, dynamic>{
        'name': name,
        'title': title,
        'text': caption,
        'duration': duration,
        'image': 'tmp/manual-video/stills/$name.png'
      };
      if (target != null && target.evaluate().isNotEmpty) {
        final r = tester.getRect(target.first);
        entry['box'] = [
          r.left * ratio - 10,
          r.top * ratio + 128,
          r.right * ratio + 10,
          r.bottom * ratio + 148
        ];
      }
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: ratio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(entry['image'] as String)
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      guide.add(entry);
      print('CAPTURED $name');
    }

    Future<void> tap(Finder f) async {
      await tester.ensureVisible(f.first);
      await tester.tap(f.first);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: demo,
        child: MaterialApp(
            navigatorKey: nav,
            theme: AppTheme.darkTheme,
            debugShowCheckedModeBanner: false,
            builder: (_, child) => RepaintBoundary(key: capture, child: child!),
            home: HomeScreen(guideLoader: () async => null))));
    await tester.pumpAndSettle();
    if (find.text('Got it').evaluate().isNotEmpty)
      await tap(find.text('Got it'));
    await shot('01-home', 'Home at a glance',
        'See your balance, income and expenses.');
    await tap(find.text('Week'));
    await tap(find.text('Month').last);
    await shot('02-monthly-chart', 'Read your spending chart',
        'Days run along the bottom. The line shows daily spending.');
    await shot('03-scan-button', 'Start with a receipt',
        'Tap the glowing scan button at the centre of the bottom bar.',
        target: find.byIcon(Icons.center_focus_strong_rounded));
    guide.add({
      'name': '04-camera',
      'title': 'Scan a receipt',
      'text':
          'Choose Receipt. Keep the whole bill in frame; tap the text to focus.',
      'duration': 6,
      'image': 'tmp/manual-video/camera-demo.png',
      'nativeChrome': true,
      'box': [95, 450, 1170, 1890]
    });
    guide.add({
      'name': '05-gallery',
      'title': 'Capture or import',
      'text': 'Use the shutter, or choose a saved receipt from your gallery.',
      'duration': 5,
      'image': 'tmp/manual-video/camera-demo.png',
      'nativeChrome': true,
      'targets': [
        [631, 2420, 120],
        [980, 2420, 85]
      ]
    });
    final receipt = OcrService.parseText(
        'SPENDLY MART\nDEMO RECEIPT\nDATE 31/10/2026\nMILK 5.00\nBREAD 3.50\nEGGS 7.00\nTOTAL 15.50\nCASH 20.00\nCHANGE 4.50');
    nav.currentState!.push(MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
            prefilledTitle: receipt.merchant,
            prefilledAmount: 15.50,
            prefilledCategory: TransactionCategory.groceries,
            prefilledDate: receipt.date,
            prefilledPaymentMethod: 'Cash',
            requireAccountSelection: true,
            prefilledReceiptImagePath:
                File('tmp/manual-video/Spendly-Demo-Receipt.jpg').absolute.path,
            prefilledNote: buildReceiptNote(receipt, defaultCurrency: 'RM'),
            receiptReview: receipt)));
    await tester.pumpAndSettle();
    await shot('06-scan-editor', 'Check the scanned details',
        'Scanning opens the editor. Check the amount, category and account.');
    await shot('07-attached-receipt', 'Keep the receipt attached',
        'Expand Scanned receipt to review the extracted information.',
        target: find.text('Scanned receipt'));
    await tap(find.text('Cash'));
    await shot('08-choose-account', 'Choose how you paid',
        'Select the account that paid for this transaction.',
        target: find.text('Choose account'));
    await tap(find.text('Cash').last);
    await shot('09-save-receipt', 'Save the transaction',
        'Tap Done after checking the amount and payment account.',
        target: find.text('Done'));
    await tap(find.text('Done'));
    await shot('10-new-transaction', 'Add a transaction manually',
        'Tap + on Home to add an expense, income or transfer.',
        target: find.byType(FloatingActionButton));
    await tap(find.byType(FloatingActionButton));
    await tap(find.text('Food'));
    for (final digit in ['1', '0', '0', '0']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await shot('11-cents-keypad', 'Enter amounts from the right',
        'Type 1000 to enter RM10.00. Backspace removes the last digit.',
        target: find.byWidgetPredicate((w) => w is TextField && w.readOnly));
    final note = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Add a note…');
    await tester.tap(note);
    await tester.enterText(note, 'Coffee');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await shot('12-entry-tools', 'Add the details you need',
        'Add a note. Use Account, Split, Recurring and Date when needed.');
    await tap(find.text('Account'));
    await tap(find.text('Cash').last);
    await tap(find.text('Done'));
    await tap(find.text('Accounts').last);
    await shot('13-accounts', 'Manage your accounts',
        'Track cash, bank and e-wallet balances in one place.',
        target: find.text('Add Account'));
    await tap(find.text('Home').last);
    await tap(find.text('More'));
    await shot('14-more', 'Find more tools',
        'Open More for budgets, recurring transactions and category favourites.',
        target: find.text('Budget Tracker'));
    await tap(find.text('Budget Tracker'));
    await shot('15-budget', 'Track a category budget',
        'Only budgets you add appear here. Review used and remaining amounts.');
    await tap(find.byTooltip('Add budget'));
    await shot('16-budget-form', 'Set a spending limit',
        'Choose a category and monthly limit, then save the budget.');
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    await tap(find.text('More'));
    await tap(find.text('Recurring transactions'));
    await shot('17-recurring', 'Review recurring transactions',
        'Open a due transaction to review its amount and account.');
    await tap(find.text('Recurring for Music subscription'));
    await shot('18-recurring-confirm', 'Confirm recurring expenses',
        'Confirm records this occurrence once. Later leaves it pending.',
        target: find.text('Confirm'));
    await shot('19-recurring-mute', 'Control recurring reminders',
        'Do not show this again silences reminders for this recurring item.',
        target: find.text('Do not show this again'));
    await tap(find.text('Confirm'));
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    await tap(find.text('Analytics').last);
    await shot('20-analytics', 'Understand your spending',
        'Choose the month and compare income, expenses and category totals.');
    await tester.scrollUntilVisible(find.text('Show more'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await shot('21-category-chart', 'Explore the category chart',
        'Tap a coloured segment for its amount. Show more opens category rankings.',
        target: find.text('Show more'));
    await tap(find.text('Show more'));
    await shot('22-category-rankings', 'See category rankings',
        'Compare categories inside the same Spending by category card.');
    await tap(find.byTooltip('Reports'));
    await shot('23-reports', 'Create a monthly report',
        'Preview the text report, or choose Share PDF to…');
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    await tap(find.text('Treasure Jar').last);
    await shot('24-jars', 'Save towards a goal',
        'Jars show your target, reserved amount and progress.',
        target: find.text('New jar'));
    await tap(find.text('Details & history').first);
    await shot('25-jar-tools', 'Manage reserved savings',
        'Add money to reserve funds. Release returns them to the available balance.',
        target: find.text('Add money').first);
    await tap(find.text('Add money').first);
    await shot('26-jar-confirm', 'Reserve money for a jar',
        'Enter the amount and confirm. A reservation is not a new expense.');
    await tap(find.text('Cancel'));
    await tap(find.text('Home').last);
    await tap(find.text('More'));
    await tap(find.text('Manage categories'));
    await shot('27-favourites', 'Choose favourite categories',
        'Star the categories you use most. They become your quick transaction choices.');
    await tester.runAsync(() => File('tmp/manual-video/still-guide.json')
        .writeAsString(jsonEncode(guide)));
    await tester.pumpWidget(const SizedBox());
    demo.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
