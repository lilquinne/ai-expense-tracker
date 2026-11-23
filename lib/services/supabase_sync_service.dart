import 'database_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/transaction_model.dart';
import '../models/user_model.dart';

class SupabaseSyncService {
  SupabaseSyncService._();

  @visibleForTesting
  SupabaseSyncService.forTesting(
      SupabaseClient client, bool Function(String) sessionCheck)
      : _clientOverride = client,
        _sessionCheck = sessionCheck;
  SupabaseClient? _clientOverride;
  bool Function(String)? _sessionCheck;

  static final SupabaseSyncService instance = SupabaseSyncService._();

  Future<void> _ledgerWork = Future.value();

  /// Serialize uploads and read local records only when this job starts.
  Future<void> syncLedger({required String userId}) {
    final work = _ledgerWork.then((_) async {
      if (!ownsSession(userId)) throw const AuthException('Account changed.');
      final db = await DatabaseService().database;
      final deleted = await db.query('pending_transaction_deletes',
          where: 'userId = ?', whereArgs: [userId]);
      for (final row in deleted) {
        if (!ownsSession(userId)) throw const AuthException('Account changed.');
        await _client
            .from('transactions')
            .delete()
            .eq('id', row['id']!)
            .eq('user_id', userId);
        // Keep tombstones: an interrupted older upload must never revive them.
      }
      final records =
          await DatabaseService().getAllTransactions(userId: userId);
      for (var start = 0; start < records.length; start += 500) {
        if (!ownsSession(userId)) throw const AuthException('Account changed.');
        final end = (start + 500).clamp(0, records.length);
        await _client.from('transactions').upsert(records
            .sublist(start, end)
            .map((t) => _transactionRow(t, userId))
            .toList());
      }
      if (!ownsSession(userId)) throw const AuthException('Account changed.');
    });
    _ledgerWork = work.catchError((Object _) {});
    return work;
  }

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  Future<void> syncUser(AppUser user) {
    if (!ownsSession(user.id)) return Future.value();
    return _run(() async {
      await _client.from('app_users').upsert(_userRow(user));
    });
  }

  Future<void> syncLocalProfile({
    required String userId,
    required String name,
    required String email,
  }) {
    if (!ownsSession(userId)) return Future.value();
    return _run(() async {
      await _client.from('app_users').update({
        'name': name.isEmpty ? 'User' : name,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    });
  }

  Future<void> syncTransactions(
    List<TransactionModel> transactions, {
    required String userId,
  }) {
    if (!ownsSession(userId)) return Future.value();
    return _run(() => syncLedger(userId: userId));
  }

  /// The coach must not silently continue with an upload that failed.
  Future<void> syncForCoach(
      {required String userId,
      required List<TransactionModel> transactions,
      required List<AppCategory> categories}) async {
    if (!ownsSession(userId))
      throw const AuthException('Sign in to use Coach.');
    if (categories.isNotEmpty) {
      await _client
          .from('categories')
          .upsert(categories.map((c) => _categoryRow(c, userId)).toList());
    }
    await syncLedger(userId: userId);
    if (!ownsSession(userId)) throw const AuthException('Account changed.');
  }

  Future<void> syncTransaction(
    TransactionModel transaction, {
    required String userId,
  }) {
    if (!ownsSession(userId)) return Future.value();
    return _run(() => syncLedger(userId: userId));
  }

  Future<void> syncBudgets(
    List<BudgetModel> budgets, {
    required String userId,
  }) {
    if (!ownsSession(userId)) return Future.value();
    return _run(() async {
      if (budgets.isEmpty) return;
      await _client
          .from('budgets')
          .upsert(budgets.map((b) => _budgetRow(b, userId)).toList());
    });
  }

  Future<void> syncBudget(BudgetModel budget, {required String userId}) {
    if (!ownsSession(userId)) return Future.value();
    return _run(() async {
      await _client.from('budgets').upsert(_budgetRow(budget, userId));
    });
  }

  Future<void> deleteBudget(String id) {
    return _run(() async {
      await _client.from('budgets').delete().eq('id', id);
    });
  }

  Future<void> syncCategories(
    List<AppCategory> categories, {
    required String userId,
  }) {
    if (!ownsSession(userId)) return Future.value();
    return _run(() async {
      if (categories.isEmpty) return;
      await _client
          .from('categories')
          .upsert(categories.map((c) => _categoryRow(c, userId)).toList());
    });
  }

  Future<void> syncCategory(AppCategory category, {required String userId}) {
    if (!ownsSession(userId)) return Future.value();
    return _run(() async {
      await _client.from('categories').upsert(_categoryRow(category, userId));
    });
  }

  Future<void> deleteCategory(String id) {
    return _run(() async {
      await _client
          .from('categories')
          .delete()
          .eq('id', cloudCategoryId(_client.auth.currentUser!.id, id));
    });
  }

  Future<void> syncAccounts(
    List<AppAccount> accounts, {
    required String userId,
  }) {
    if (!ownsSession(userId)) return Future.value();
    return _run(() async {
      if (accounts.isEmpty) return;
      await _client
          .from('accounts')
          .upsert(accounts.map((a) => _accountRow(a, userId)).toList());
    });
  }

  Future<void> syncAccount(AppAccount account, {required String userId}) {
    if (!ownsSession(userId)) return Future.value();
    return _run(() async {
      await _client.from('accounts').upsert(_accountRow(account, userId));
    });
  }

  Future<void> deleteAccount(String id) {
    return _run(() async {
      await _client.from('accounts').delete().eq('id', id);
    });
  }

  Future<void> syncCurrentSnapshot({
    required String userId,
    required List<TransactionModel> transactions,
    required List<BudgetModel> budgets,
    required List<AppCategory> categories,
    required List<AppAccount> accounts,
  }) async {
    await syncCategories(categories, userId: userId);
    await syncAccounts(accounts, userId: userId);
    await syncBudgets(budgets, userId: userId);
    await syncTransactions(transactions, userId: userId);
  }

  Map<String, dynamic> _userRow(AppUser user) => {
        'id': user.id,
        'name': user.name,
        'email': user.email.toLowerCase(),
        'created_at': user.createdAt.toIso8601String(),
        'last_login_at': user.lastLoginAt?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

  Map<String, dynamic> _transactionRow(
    TransactionModel transaction,
    String userId,
  ) =>
      {
        'id': transaction.id,
        'user_id': userId,
        'title': transaction.title,
        'amount': transaction.amount,
        'type': transaction.type.index,
        'category': transaction.category.index,
        'category_id': cloudCategoryId(userId, transaction.categoryId),
        'account_id': transaction.accountId,
        'date': transaction.date.toIso8601String(),
        'note': transaction.note,
        'receipt_image_path': transaction.receiptImagePath,
        'is_recurring': transaction.isRecurring,
        'recurring_frequency': transaction.recurringFrequency,
        'updated_at': DateTime.now().toIso8601String(),
      };

  Map<String, dynamic> _budgetRow(BudgetModel budget, String userId) => {
        'id': budget.id,
        'user_id': userId,
        'category': budget.category.index,
        'limit_amount': budget.limit,
        'month': budget.month.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

  Map<String, dynamic> _categoryRow(AppCategory category, String userId) => {
        'id': cloudCategoryId(userId, category.id),
        'user_id': userId,
        'name': category.name,
        'type': category.type.index,
        'parent_category': category.parentCategory.index,
        'icon': category.icon,
        'color_value': category.colorValue,
        'parent_id': category.parentId == null
            ? null
            : cloudCategoryId(userId, category.parentId!),
        'is_default': category.isDefault,
        'updated_at': DateTime.now().toIso8601String(),
      };

  Map<String, dynamic> _accountRow(AppAccount account, String userId) => {
        'id': account.id,
        'user_id': userId,
        'name': account.name,
        'kind': account.kind.index,
        'subtype': account.subtype.index,
        'opening_balance': account.openingBalance,
        'current_balance': account.currentBalance,
        'icon': account.icon,
        'color_value': account.colorValue,
        'is_default': account.isDefault,
        'include_in_net_worth': account.includeInNetWorth,
        'include_in_balance': account.includeInBalance,
        'counterparty_name': account.counterpartyName,
        'linked_account_id': account.linkedAccountId,
        'updated_at': DateTime.now().toIso8601String(),
      };

  static String cloudCategoryId(String userId, String categoryId) =>
      '$userId:$categoryId';

  bool ownsSession(String userId) {
    if (_sessionCheck != null) return _sessionCheck!(userId);
    try {
      return _client.auth.currentSession != null &&
          _client.auth.currentUser?.id == userId;
    } catch (_) {
      return false;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      if (_sessionCheck == null && _client.auth.currentSession == null) return;
      await action();
    } catch (error, stackTrace) {
      debugPrint('Supabase sync skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
