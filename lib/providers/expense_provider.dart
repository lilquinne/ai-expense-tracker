import '../services/recurring_service.dart';
import '../services/budget_advice.dart';
import '../services/ledger_totals.dart';
// lib/providers/expense_provider.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../models/budget_alert.dart';
import '../models/treasure_jar.dart';
import '../services/category_learning_service.dart';
import '../services/merchant_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/device_sync_service.dart';
import '../services/sync_merge.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExpenseProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final DeviceSyncService _deviceSync = DeviceSyncService();
  Future<void>? _activeSync;
  String? _activeSyncOwner;
  bool _syncAgain = false;
  bool _disposed = false;
  String syncStatus = 'Not synced yet';
  bool syncNeedsReview = false;
  DateTime? lastSyncAt;
  bool get isSyncing => _activeSync != null;
  bool get canSync => _deviceSync.ownsSession(_userId);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> syncNow({bool? useDeviceCopy}) {
    final owner = _userId;
    if (!_deviceSync.ownsSession(owner) || _disposed) return Future.value();
    if (_activeSync != null) {
      _syncAgain = true;
      if (_activeSyncOwner != owner)
        return _activeSync!.then((_) => syncNow(useDeviceCopy: useDeviceCopy));
      return _activeSync!;
    }
    _activeSyncOwner = owner;
    // Deferring work ensures the future is assigned before notifying listeners.
    final work = Future<void>.delayed(Duration.zero, () async {
      do {
        _syncAgain = false;
        if (_disposed || owner != _userId) return;
        syncStatus = 'Syncing…';
        syncNeedsReview = false;
        notifyListeners();
        try {
          await _deviceSync.sync(owner, preferLocalConflicts: useDeviceCopy);
          useDeviceCopy = null;
          if (_disposed || owner != _userId || !_deviceSync.ownsSession(owner))
            return;
          lastSyncAt = await _db.lastSyncedAt(owner);
          syncStatus = 'Up to date';
          _chartRevision++;
          await _loadLocalData(syncCloud: false);
        } on SyncConflict catch (error) {
          if (_disposed || owner != _userId) return;
          syncNeedsReview = true;
          syncStatus = error.toString();
          _syncAgain = false;
        } catch (error) {
          if (_disposed || owner != _userId) return;
          syncStatus =
              'Could not sync. Your records are saved on this device. Tap to retry.';
          debugPrint('Device sync failed: $error');
          _syncAgain = false;
        }
      } while (_syncAgain && _deviceSync.ownsSession(owner));
    }).whenComplete(() {
      _activeSync = null;
      _activeSyncOwner = null;
      if (!_disposed) notifyListeners();
    });
    _activeSync = work;
    return work;
  }

  final _uuid = const Uuid();

  List<TransactionModel> _transactions = [];
  List<TransactionModel> _allTransactions = [];
  List<BudgetModel> _budgets = [];
  List<AppCategory> _categories = AppCategory.defaults;
  List<AppAccount> _accounts = AppAccount.defaults;
  int _chartRevision = 0;
  int _loadRevision = 0;
  int get chartRevision => _chartRevision;
  List<TreasureJar> _jars = [];
  List<TreasureJar> get jars => _jars;
  double reservedFor(String accountId) =>
      _jars
          .where((j) => j.accountId == accountId)
          .fold<int>(0, (sum, j) => sum + j.savedCents) /
      100;
  double get totalReserved =>
      _jars.fold<int>(0, (s, j) => s + j.savedCents) / 100;
  List<TransactionModel> get currentMonthTransactions => _allTransactions
      .where((t) => LedgerTotals.inMonth(t.date, DateTime.now()))
      .toList();
  double get currentMonthIncome => LedgerTotals.sum(currentMonthTransactions
      .where((t) => t.type == TransactionType.income)
      .map((t) => t.amount));
  double get currentMonthExpense => LedgerTotals.sum(currentMonthTransactions
      .where((t) => t.type == TransactionType.expense)
      .map((t) => t.amount));

  double availableFor(AppAccount account) =>
      account.currentBalance - reservedFor(account.id);
  Future<void> saveJar(TreasureJar jar) async {
    await _db.saveJar(jar, _userId);
    await loadData();
  }

  Future<void> adjustJar(String id, int cents) async {
    await _db.adjustJar(id, _userId, cents);
    await loadData();
  }

  Future<void> deleteJar(String id) async {
    await _db.deleteJar(id, _userId);
    await loadData();
  }

  Future<List<Map<String, Object?>>> jarHistory(String id) =>
      _db.jarHistory(id, _userId);
  Future<List<TransactionModel>> loadChartTransactions() => _userId.isEmpty
      ? Future.value(transactions)
      : _db.getAllTransactions(userId: _userId);
  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = false;
  String _userId = '';
  String _userName = 'User';
  String _userEmail = '';
  String _currencySymbol = 'RM';
  String _colorTheme = 'Light';
  bool _isLoggedIn = false;
  Future<void> _alertWork = Future.value();
  List<BudgetAlert> get budgetAlerts =>
      BudgetAlert.evaluate(_budgets, _transactions);
  List<Map<String, Object?>> _jarNotifications = [];
  List<Map<String, Object?>> get jarNotifications =>
      List.unmodifiable(_jarNotifications);
  Future<void> readJarNotification(String id) async {
    await _db.readJarNotification(id, _userId);
    await loadData();
  }

  Set<String> _readAlerts = {};
  String _alertReadKey(BudgetAlert alert) => '${alert.key}:${alert.level}';
  bool isAlertRead(BudgetAlert alert) =>
      _readAlerts.contains(_alertReadKey(alert));
  int get unreadAlertCount =>
      budgetAlerts.where((a) => !isAlertRead(a)).length +
      recurringNotices.length +
      _jarNotifications.where((n) => n['isRead'] == 0).length;
  Future<void> markAlertRead(BudgetAlert alert) async {
    final owner = _userId;
    _readAlerts.add(_alertReadKey(alert));
    final values = _readAlerts.toList();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('read_budget_alerts:$owner', values);
  }

  Future<void> refreshBudgetNotifications() {
    final user = _userId;
    final currency = _currencySymbol;
    _alertWork = _alertWork.then((_) async {
      try {
        if (user != _userId) return;
        final month = DateTime.now();
        final budgets = await _db.getBudgetsByMonth(month, userId: user);
        final transactions =
            await _db.getTransactionsByMonth(month, userId: user);
        if (user != _userId) return;
        final advice =
            BudgetAdvice.calculate(budgets, transactions, month, month);
        final alerts = BudgetAlert.evaluate(budgets, transactions);
        await NotificationService.syncBudgetAlerts(user, alerts, currency,
            advice: advice?.message(currency));
        if (user != _userId) return;
        await NotificationService.syncBudgetAdvice(
            user, alerts.isEmpty ? advice : null, currency, month);
      } catch (error) {
        debugPrint('Budget notifications unavailable: $error');
      }
    });
    return _alertWork;
  }

  Future<void> _syncRecurringReminders(
      String owner, List<TransactionModel> records, Set<String> muted) async {
    try {
      if (owner != _userId) return;
      await NotificationService.syncRecurringReminders(
          owner,
          RecurringService.due(owner, records, DateTime.now(), futureCount: 24)
              .where((o) => !muted.contains(o.template.id))
              .toList(),
          _currencySymbol);
    } catch (error) {
      debugPrint('Recurring reminders unavailable: $error');
    }
  }

  List<RecurringOccurrence> _recurringDue = [];
  Set<String> _mutedRecurring = {};
  List<RecurringOccurrence> get recurringDue => _recurringDue;
  List<RecurringOccurrence> get recurringNotices => _recurringDue
      .where((o) => !_mutedRecurring.contains(o.template.id))
      .toList();
  bool recurringMuted(String id) => _mutedRecurring.contains(id);

  Future<void> muteRecurring(String id, bool muted) async {
    final owner = _userId;
    final prefs = await SharedPreferences.getInstance();
    if (owner != _userId) return;
    if (muted) {
      _mutedRecurring.add(id);
    } else {
      _mutedRecurring.remove(id);
    }
    await prefs.setStringList(
        'recurring_muted:$owner', _mutedRecurring.toList());
    notifyListeners();
    await loadData();
  }

  Future<void> confirmRecurring(RecurringOccurrence occurrence) async {
    final owner = _userId;
    final records = await _db.getAllTransactions(userId: owner);
    if (owner != _userId)
      throw StateError('Account changed. Reopen recurring transactions.');
    final pending = RecurringService.due(owner, records, DateTime.now())
        .where((o) => o.id == occurrence.id)
        .firstOrNull;
    if (pending == null) {
      await loadData();
      return;
    }
    final saved = await _db.saveConfirmedTransaction(pending.transaction(),
        userId: owner);
    await _afterLedgerCommit(owner, saved: saved);
  }

  // Getters
  List<TransactionModel> get transactions => _transactions;
  List<TransactionModel> get allTransactions =>
      List.unmodifiable(_allTransactions);
  List<BudgetModel> get budgets => _budgets;
  List<AppCategory> get categories => _categories;
  List<AppAccount> get accounts => _accounts;
  DateTime get selectedMonth => _selectedMonth;
  bool get isLoading => _isLoading;
  String get userId => _userId;
  String get userName => _userName;
  String get userEmail => _userEmail;
  String get currencySymbol => _currencySymbol;
  String get colorTheme => _colorTheme;

  List<TransactionModel> get incomeTransactions =>
      _transactions.where((t) => t.type == TransactionType.income).toList();

  List<TransactionModel> get expenseTransactions =>
      _transactions.where((t) => t.type == TransactionType.expense).toList();

  double get totalIncome =>
      LedgerTotals.sum(incomeTransactions.map((t) => t.amount));

  double get totalExpense =>
      LedgerTotals.sum(expenseTransactions.map((t) => t.amount));

  double get balance =>
      (LedgerTotals.sen(totalIncome) - LedgerTotals.sen(totalExpense)) / 100;
  double get totalBudget => LedgerTotals.sum(_budgets.map((b) => b.limit));
  double get budgetedSpending {
    final categories = _budgets.map((b) => b.category).toSet();
    return LedgerTotals.sum(expenseTransactions
        .where((t) => categories.contains(t.category))
        .map((t) => t.amount));
  }

  double get unbudgetedSpending =>
      (LedgerTotals.sen(totalExpense) - LedgerTotals.sen(budgetedSpending)) /
      100;

  double get totalAssets => _accounts
      .where((a) => a.kind == AccountKind.asset && a.includeInBalance)
      .fold(0.0, (sum, a) => sum + a.currentBalance);

  double get totalMyBalance => accounts
          .where((a) => a.includeInBalance && a.kind != AccountKind.liability)
          .fold(0.0, (sum, a) {
        if (a.kind == AccountKind.lending &&
            a.subtype == AccountSubtype.borrow) {
          return sum - a.currentBalance.abs();
        }
        if (a.kind == AccountKind.other) return sum;
        return sum +
            (LedgerTotals.sen(a.currentBalance) -
                    LedgerTotals.sen(reservedFor(a.id))) /
                100;
      });

  double get totalLiabilities => _accounts
      .where((a) => a.kind == AccountKind.liability && a.includeInNetWorth)
      .fold(0.0, (sum, a) => sum + a.currentBalance.abs());

  double get lendingBalance => _accounts
          .where((a) => a.kind == AccountKind.lending && a.includeInNetWorth)
          .fold(0.0, (sum, a) {
        if (a.subtype == AccountSubtype.borrow)
          return sum - a.currentBalance.abs();
        return sum + a.currentBalance;
      });

  double get netWorth {
    final netWorthAssets = _accounts
        .where((a) => a.kind == AccountKind.asset && a.includeInNetWorth)
        .fold(0.0, (sum, a) => sum + a.currentBalance);
    return netWorthAssets + lendingBalance - totalLiabilities;
  }

  double get savingsRate =>
      totalIncome > 0 ? ((balance / totalIncome) * 100) : 0;

  Map<TransactionCategory, double> get categoryBreakdown {
    final breakdown = LedgerTotals.categories(expenseTransactions);
    return Map.fromEntries(
      breakdown.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  // Recent transactions (last 5)
  List<TransactionModel> get recentTransactions =>
      allTransactions.take(5).toList();

  ExpenseProvider({bool initialize = true}) {
    if (initialize) _init();
  }

  Future<void> _init() async {
    await _loadPreferences();
    await loadData();
  }

  Future<void> reloadSession() async {
    await _loadPreferences();
    await loadData();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    _userId = prefs.getString('currentUserId') ??
        prefs.getString('userId') ??
        'SP-${_uuid.v4().substring(0, 8).toUpperCase()}';
    await prefs.setString('userId', _userId);
    await prefs.setString('currentUserId', _userId);
    await prefs.remove('recurring_paused:$_userId');
    _favouriteCategories =
        prefs.getStringList('favourite_categories:$_userId')?.toSet();
    syncStatus = 'Not synced yet';
    syncNeedsReview = false;
    lastSyncAt = await _db.lastSyncedAt(_userId);
    _userName = prefs.getString('userName') ?? 'User';
    _jars = [];
    _jarNotifications = [];
    _recurringDue = [];
    _mutedRecurring = {};
    _userEmail = prefs.getString('userEmail') ?? '';
    _currencySymbol = 'RM';
    _colorTheme = prefs.getString('colorTheme') ?? 'Light';
    _readAlerts =
        (prefs.getStringList('read_budget_alerts:$_userId') ?? []).toSet();
    await CategoryLearningService.load(_userId);
    await MerchantService.load(_userId);
    notifyListeners();
  }

  Future<void> savePreferences({
    String? userName,
    String? userEmail,
    String? currencySymbol,
    String? colorTheme,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (userName != null) {
      _userName = userName;
      await prefs.setString('userName', userName);
    }
    if (userEmail != null) {
      _userEmail = userEmail;
      await prefs.setString('userEmail', userEmail);
    }
    if (currencySymbol != null) {
      _currencySymbol = 'RM';
      await prefs.setString('currencySymbol', 'RM');
    }
    if (colorTheme != null) {
      _colorTheme = colorTheme;
      await prefs.setString('colorTheme', colorTheme);
    }
    notifyListeners();
  }

  Future<void> loadData() => _loadLocalData();

  Future<void> _loadLocalData({bool syncCloud = true}) async {
    final revision = ++_loadRevision;
    final owner = _userId;
    final month = _selectedMonth;
    _isLoading = true;
    notifyListeners();

    try {
      await _db.ensureUserDefaults(owner);
      final savedReceipts = await _db.getAllTransactions(userId: owner);
      final prefs = await SharedPreferences.getInstance();
      final mutedRecurring =
          (prefs.getStringList('recurring_muted:$owner') ?? []).toSet();
      final transactions =
          await _db.getTransactionsByMonth(month, userId: owner);
      final budgets = await _db.getBudgetsByMonth(month, userId: owner);
      final categories = await _db.getCategories(userId: owner);
      final accounts = await _db.getAccounts(userId: owner);
      final jars = await _db.getJars(owner);
      final jarNotices = await _db.jarNotifications(owner);
      if (revision != _loadRevision ||
          owner != _userId ||
          month != _selectedMonth) {
        return;
      }
      MerchantService.includeSavedShops(savedReceipts
          .where((t) =>
              t.type == TransactionType.expense && t.receiptImagePath != null)
          .map((t) => t.title));
      _recurringDue =
          RecurringService.due(owner, savedReceipts, DateTime.now());
      _mutedRecurring = mutedRecurring;
      _transactions = transactions;
      _allTransactions = savedReceipts;
      _budgets = budgets;
      _categories = categories;
      _accounts = accounts;
      _jars = jars;
      _jarNotifications = jarNotices;
      unawaited(refreshBudgetNotifications());
      unawaited(_syncRecurringReminders(owner, savedReceipts, mutedRecurring));
      if (_isLoggedIn && syncCloud) {
        unawaited(syncNow());
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to load expense data: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (revision == _loadRevision) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void setSelectedMonth(DateTime month) {
    _selectedMonth = month;
    loadData();
  }

  Future<void> addTransaction({
    required String title,
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
    String? splitData,
  }) async {
    final transaction = TransactionModel(
      id: _uuid.v4(),
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
      splitData: splitData,
    );

    final owner = _userId;
    final saved =
        await _db.saveConfirmedTransaction(transaction, userId: owner);
    await _afterLedgerCommit(owner, saved: saved);
  }

  Future<void> updateTransaction(TransactionModel transaction) async {
    final owner = _userId;
    final saved = await _db.saveConfirmedTransaction(transaction,
        userId: owner, editing: true);
    await _afterLedgerCommit(owner, saved: saved);
  }

  Future<void> deleteTransaction(String id) async {
    final owner = _userId;
    await _db.deleteConfirmedTransaction(id, userId: owner);
    await _afterLedgerCommit(owner, deletedId: id);
  }

  Future<void> _afterLedgerCommit(String owner,
      {TransactionModel? saved, String? deletedId}) async {
    // The save has succeeded. A refresh/upload failure must never invite a
    // second submission or pretend the committed local transaction rolled back.
    if (owner != _userId) return;
    _chartRevision++;
    try {
      await loadData();
      if (owner == _userId) await syncNow();
    } catch (error) {
      debugPrint(
          'Transaction saved locally; refresh or sync unavailable: $error');
    }
  }

  Future<void> upsertBudget({
    required TransactionCategory category,
    required double limit,
  }) async {
    final existing = _budgets.where((b) => b.category == category).firstOrNull;
    final budget = BudgetModel(
      id: existing?.id ?? _uuid.v4(),
      category: category,
      limit: limit,
      month: _selectedMonth,
    );
    await _db.upsertBudget(budget, userId: _userId);
    unawaited(refreshBudgetNotifications());
    unawaited(syncNow());
    await loadData();
  }

  Future<void> deleteBudget(String id) async {
    await _db.deleteBudget(id, userId: _userId);
    unawaited(syncNow());
    _budgets = _budgets.where((b) => b.id != id).toList();
    unawaited(refreshBudgetNotifications());
    notifyListeners();
  }

  Future<void> deleteBudgetForCategory(TransactionCategory category) async {
    final existing = _budgets.where((b) => b.category == category).firstOrNull;
    if (existing != null) await deleteBudget(existing.id);
  }

  double getBudgetUsage(TransactionCategory category) {
    final budget = _budgets.where((b) => b.category == category).firstOrNull;
    if (budget == null) return 0;
    final spent = categoryBreakdown[category] ?? 0;
    return LedgerTotals.usage(spent, budget.limit);
  }

  double? getBudgetLimit(TransactionCategory category) {
    return _budgets.where((b) => b.category == category).firstOrNull?.limit;
  }

  Set<String>? _favouriteCategories;

  bool isFavouriteCategory(AppCategory category) =>
      _favouriteCategories?.contains(category.id) ??
      category.id == category.parentCategory.name;

  Future<void> toggleFavouriteCategory(AppCategory category) async {
    final owner = _userId;
    final next = Set<String>.from(_favouriteCategories ??
        _categories
            .where((c) => c.id == c.parentCategory.name)
            .map((c) => c.id));
    if (!next.remove(category.id)) next.add(category.id);
    _favouriteCategories = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favourite_categories:$owner', next.toList());
  }

  List<AppCategory> categoriesForType(TransactionType type) {
    final result = _categories.where((c) => c.type == type).toList();
    int rank(AppCategory c) {
      final root = c.parentCategory;
      if (root == TransactionCategory.food) return 0;
      if (root == TransactionCategory.groceries) return 1;
      if (root == TransactionCategory.other ||
          root == TransactionCategory.incomeOther) return 999;
      return root.index + 2;
    }

    result.sort((a, b) {
      if (a.id == b.id) return 0;
      final order = rank(a).compareTo(rank(b));
      if (order != 0) return order;
      if (a.id == a.parentCategory.name) return -1;
      if (b.id == b.parentCategory.name) return 1;
      return a.name.compareTo(b.name);
    });
    return result;
  }

  AppCategory? categoryById(String id) {
    for (final category in _categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  AppCategory categoryForTransaction(TransactionModel transaction) {
    return categoryById(transaction.categoryId) ??
        categoryById(transaction.category.name) ??
        AppCategory(
          id: transaction.category.name,
          name: transaction.category.label,
          type: transaction.type,
          parentCategory: transaction.category,
          icon: transaction.category.emoji,
          colorValue: transaction.category.colorValue,
          isDefault: true,
        );
  }

  AppAccount? accountById(String id) {
    for (final account in _accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  AppAccount accountForTransaction(TransactionModel transaction) {
    return accountById(transaction.accountId) ??
        accountById(defaultAccountId) ??
        accountById(AppAccount.defaultId) ??
        AppAccount.defaults.first;
  }

  String get defaultAccountId => _accounts.isNotEmpty
      ? _accounts.first.id
      : DatabaseService.defaultAccountIdForUser(_userId);

  Future<AppCategory> addCategory({
    required String name,
    required TransactionType type,
    required TransactionCategory parentCategory,
    required String icon,
    required int colorValue,
    String? parentId,
  }) async {
    final id = '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4()}';
    final category = AppCategory(
      id: id,
      name: name,
      type: type,
      parentCategory: parentCategory,
      icon: icon,
      colorValue: colorValue,
      parentId: parentId,
    );
    await _db.insertCategory(category, userId: _userId);
    unawaited(syncNow());
    _categories = [..._categories, category]
      ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return category;
  }

  Future<void> updateCategory(AppCategory category) async {
    if (category.isDefault) return;
    await _db.updateCategory(category, userId: _userId);
    unawaited(syncNow());
    _categories = _categories
        .map((c) => c.id == category.id ? category : c)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  Future<void> deleteCategory(AppCategory category) async {
    if (category.isDefault) return;
    await _db.deleteCategory(category, userId: _userId);
    unawaited(syncNow());
    _categories = _categories.where((c) => c.id != category.id).toList();
    _allTransactions = _allTransactions
        .map((t) => t.categoryId == category.id
            ? t.copyWith(categoryId: category.parentCategory.name)
            : t)
        .toList();
    _transactions = _transactions
        .map((t) => t.categoryId == category.id
            ? t.copyWith(categoryId: category.parentCategory.name)
            : t)
        .toList();
    notifyListeners();
  }

  Future<AppAccount> addAccount({
    required String name,
    required AccountKind kind,
    required AccountSubtype subtype,
    required double openingBalance,
    String? icon,
    int colorValue = 0xFF06D6A0,
    bool includeInNetWorth = true,
    bool includeInBalance = true,
    String? counterpartyName,
    String? linkedAccountId,
  }) async {
    final id = '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4()}';
    final account = AppAccount(
      id: id,
      name: name,
      kind: kind,
      subtype: subtype,
      openingBalance: openingBalance,
      currentBalance: openingBalance,
      icon: icon ?? subtype.icon,
      colorValue: colorValue,
      includeInNetWorth: includeInNetWorth,
      includeInBalance: includeInBalance,
      counterpartyName: counterpartyName,
      linkedAccountId: linkedAccountId,
    );
    await _db.insertAccount(account, userId: _userId);
    unawaited(syncNow());
    _accounts = [..._accounts, account]
      ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return account;
  }

  Future<void> adjustAccountBalance(String accountId, double balance) async {
    final account = accountById(accountId);
    if (account == null) return;
    final updated = account.copyWith(currentBalance: balance);
    await _db.updateAccount(updated, userId: _userId);
    unawaited(syncNow());
    _accounts = _accounts.map((a) => a.id == accountId ? updated : a).toList();
    notifyListeners();
  }

  Future<void> deleteAccount(AppAccount account) async {
    if (account.isDefault) {
      throw Exception('Default account cannot be deleted');
    }
    final previousAccounts = _accounts;
    _accounts = _accounts.where((a) => a.id != account.id).toList();
    notifyListeners();

    try {
      await _db.deleteAccount(account.id, userId: _userId);
      unawaited(syncNow());
    } catch (_) {
      _accounts = previousAccounts;
      notifyListeners();
      rethrow;
    }
  }

  Future<List<TransactionModel>> transactionsForAccount(String accountId) {
    return _db.getTransactionsByAccount(accountId, userId: _userId);
  }

  /// Get spending for last 7 days (for mini chart)
  List<DailySpending> getLast7DaysSpending() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      final dayTransactions = _transactions.where((t) =>
          t.type == TransactionType.expense &&
          t.date.year == day.year &&
          t.date.month == day.month &&
          t.date.day == day.day);
      final total = LedgerTotals.sum(dayTransactions.map((t) => t.amount));
      return DailySpending(date: day, amount: total);
    });
  }
}

class DailySpending {
  final DateTime date;
  final double amount;
  DailySpending({required this.date, required this.amount});
}
