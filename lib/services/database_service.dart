import 'ledger_totals.dart';
// lib/services/database_service.dart

import 'dart:io';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'sync_merge.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import '../models/treasure_jar.dart';

class DatabaseService {
  static Database? _database;
  static const String _dbName = 'expense_tracker.db';
  static const int _dbVersion = 11;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _ensureSchema,
    );
  }

  Future<SyncData> exportSyncData(String owner) async {
    final db = await database;
    return db.transaction((txn) => _exportSyncData(txn, owner));
  }

  Future<SyncData> _exportSyncData(DatabaseExecutor txn, String owner) async {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final table in syncTables) {
      final rows =
          await txn.query(table, where: 'userId = ?', whereArgs: [owner]);
      result[table] = rows.map((r) {
        final row = Map<String, dynamic>.from(r)..remove('userId');
        if (table == 'transactions') row.remove('receiptImagePath');
        if (table == 'jar_activity') {
          row['id'] = row.remove('syncId');
        }
        return row;
      }).toList();
    }
    return result;
  }

  Future<Set<String>> pendingDeletedIds(String owner) async {
    final rows = await (await database).query('pending_transaction_deletes',
        where: 'userId = ?', whereArgs: [owner]);
    return rows.map((r) => r['id'] as String).toSet();
  }

  Future<SyncData?> syncBaseline(String owner) async {
    final rows = await (await database)
        .query('device_sync_state', where: 'userId = ?', whereArgs: [owner]);
    return rows.isEmpty
        ? null
        : decodeSyncData(jsonDecode(rows.single['payload'] as String));
  }

  Future<DateTime?> lastSyncedAt(String owner) async {
    final rows = await (await database)
        .query('device_sync_state', where: 'userId = ?', whereArgs: [owner]);
    return rows.isEmpty
        ? null
        : DateTime.parse(rows.single['syncedAt'] as String);
  }

  /// The backup and import commit together; local writes during the request are
  /// rebased instead of being replaced by the network response.
  Future<bool> applySyncData(String owner, SyncData captured, SyncData accepted,
      {required bool Function() ownsSession}) async {
    final db = await database;
    return db.transaction((txn) async {
      if (!ownsSession()) throw StateError('Account changed during sync.');
      final current = await _exportSyncData(txn, owner);
      final rebased = mergeSyncData(captured, current, accepted);
      final changedDuringSync = !sameSyncValue(current, captured);
      validateSyncData(rebased);
      if (!sameSyncValue(current, rebased)) {
        final paths = await txn.query('transactions',
            columns: ['id', 'receiptImagePath'],
            where: 'userId = ?',
            whereArgs: [owner]);
        final receipts = {
          for (final r in paths) r['id']: r['receiptImagePath']
        };
        await txn.insert('device_sync_backups', {
          'userId': owner,
          'payload': jsonEncode(current),
          'createdAt': DateTime.now().toUtc().toIso8601String()
        });
        for (final table in syncTables.reversed) {
          await txn.delete(table, where: 'userId = ?', whereArgs: [owner]);
        }
        for (final table in syncTables) {
          final columns = (await txn.rawQuery('PRAGMA table_info($table)'))
              .map((r) => r['name'])
              .toSet();
          for (final value in rebased[table] ?? <Map<String, dynamic>>[]) {
            final row = Map<String, dynamic>.from(value);
            if (table == 'jar_activity') row['syncId'] = row.remove('id');
            if (table == 'transactions')
              row['receiptImagePath'] = receipts[row['id']];
            row['userId'] = owner;
            if (row.keys.any((key) => !columns.contains(key)))
              throw StateError('Update Spendly to sync this record.');
            if (table != 'jar_activity') {
              final collision = await txn.query(table,
                  columns: ['userId'], where: 'id = ?', whereArgs: [row['id']]);
              if (collision.any((r) => r['userId'] != owner))
                throw StateError('Record belongs to another local account.');
            }
            await txn.insert(table, row,
                conflictAlgorithm: ConflictAlgorithm.abort);
          }
        }
      }
      await txn.insert(
          'device_sync_state',
          {
            'userId': owner,
            'payload': jsonEncode(accepted),
            'syncedAt': DateTime.now().toUtc().toIso8601String()
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      // Retain tombstones for the legacy analytics mirror as well. They must
      // never be discarded while an old upload could revive a deleted expense.
      final kept = (rebased['transactions'] ?? <Map<String, dynamic>>[])
          .map((r) => r['id'])
          .toSet();
      for (final row in current['transactions'] ?? <Map<String, dynamic>>[]) {
        if (!kept.contains(row['id']))
          await txn.insert(
              'pending_transaction_deletes', {'id': row['id'], 'userId': owner},
              conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.rawDelete(
          'DELETE FROM device_sync_backups WHERE userId = ? AND id NOT IN (SELECT id FROM device_sync_backups WHERE userId = ? ORDER BY id DESC LIMIT 5)',
          [owner, owner]);
      return changedDuringSync;
    });
  }

  Future<String> get databasePath async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, _dbName);
  }

  Future<int> getDatabaseSizeBytes() async {
    final path = await databasePath;
    final file = File(path);
    if (!await file.exists()) return 0;
    return file.length();
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _ensureSchema(db);
  }

  Future<void> _createTables(Database db) async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS split_payments (id TEXT PRIMARY KEY, userId TEXT NOT NULL, billId TEXT NOT NULL, personId TEXT NOT NULL, accountId TEXT NOT NULL, sen INTEGER NOT NULL, date TEXT NOT NULL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS split_people (id TEXT NOT NULL, userId TEXT NOT NULL, name TEXT NOT NULL, PRIMARY KEY(id,userId))');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS account_transfers (id TEXT PRIMARY KEY, userId TEXT NOT NULL, fromId TEXT NOT NULL, toId TEXT NOT NULL, sen INTEGER NOT NULL, date TEXT NOT NULL, note TEXT)');
    await db.execute('''CREATE TABLE IF NOT EXISTS pending_transaction_deletes (
      id TEXT NOT NULL, userId TEXT NOT NULL, PRIMARY KEY (id, userId)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS treasure_jars (
      id TEXT PRIMARY KEY, userId TEXT NOT NULL, name TEXT NOT NULL,
      accountId TEXT NOT NULL, targetCents INTEGER NOT NULL CHECK(targetCents > 0),
      savedCents INTEGER NOT NULL DEFAULT 0 CHECK(savedCents >= 0), deadline TEXT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS jar_activity (
      id INTEGER PRIMARY KEY AUTOINCREMENT, userId TEXT NOT NULL,
      jarId TEXT NOT NULL, amountCents INTEGER NOT NULL, date TEXT NOT NULL
    )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        pin TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        lastLoginAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY,
        userId TEXT,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        type INTEGER NOT NULL,
        category INTEGER NOT NULL,
        categoryId TEXT,
        accountId TEXT,
        date TEXT NOT NULL,
        note TEXT,
        receiptImagePath TEXT,
        isRecurring INTEGER DEFAULT 0,
        recurringFrequency TEXT,
        splitData TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS budgets (
        id TEXT PRIMARY KEY,
        userId TEXT,
        category INTEGER NOT NULL,
        "limit" REAL NOT NULL,
        month TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        userId TEXT,
        name TEXT NOT NULL,
        type INTEGER NOT NULL,
        parentCategory INTEGER NOT NULL,
        icon TEXT NOT NULL,
        colorValue INTEGER NOT NULL,
        parentId TEXT,
        isDefault INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        userId TEXT,
        name TEXT NOT NULL,
        kind INTEGER NOT NULL,
        subtype INTEGER NOT NULL,
        openingBalance REAL NOT NULL,
        currentBalance REAL NOT NULL,
        icon TEXT NOT NULL,
        colorValue INTEGER NOT NULL,
        isDefault INTEGER DEFAULT 0,
        includeInNetWorth INTEGER DEFAULT 1,
        includeInBalance INTEGER DEFAULT 1,
        counterpartyName TEXT,
        linkedAccountId TEXT
      )
    ''');
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS jar_notifications (id TEXT PRIMARY KEY, userId TEXT NOT NULL, message TEXT NOT NULL, date TEXT NOT NULL, isRead INTEGER NOT NULL DEFAULT 0)');
    await _createTables(db);
    await _addMissingColumn(db,
        table: 'transactions', column: 'splitData', definition: 'TEXT');
    await _addMissingColumn(
      db,
      table: 'transactions',
      column: 'userId',
      definition: 'TEXT',
    );
    await _addMissingColumn(
      db,
      table: 'transactions',
      column: 'categoryId',
      definition: 'TEXT',
    );
    await _addMissingColumn(
      db,
      table: 'transactions',
      column: 'accountId',
      definition: 'TEXT',
    );
    await _addMissingColumn(
      db,
      table: 'transactions',
      column: 'receiptImagePath',
      definition: 'TEXT',
    );
    await _addMissingColumn(
      db,
      table: 'transactions',
      column: 'isRecurring',
      definition: 'INTEGER DEFAULT 0',
    );
    await _addMissingColumn(
      db,
      table: 'transactions',
      column: 'recurringFrequency',
      definition: 'TEXT',
    );
    await _addMissingColumn(
      db,
      table: 'budgets',
      column: 'userId',
      definition: 'TEXT',
    );
    await _addMissingColumn(
      db,
      table: 'categories',
      column: 'userId',
      definition: 'TEXT',
    );
    await _addMissingColumn(
      db,
      table: 'accounts',
      column: 'userId',
      definition: 'TEXT',
    );
    await _addMissingColumn(
      db,
      table: 'accounts',
      column: 'includeInNetWorth',
      definition: 'INTEGER DEFAULT 1',
    );
    await _addMissingColumn(
      db,
      table: 'accounts',
      column: 'includeInBalance',
      definition: 'INTEGER DEFAULT 1',
    );
    await _addMissingColumn(
      db,
      table: 'accounts',
      column: 'counterpartyName',
      definition: 'TEXT',
    );
    await _addMissingColumn(
      db,
      table: 'accounts',
      column: 'linkedAccountId',
      definition: 'TEXT',
    );
    await _addMissingColumn(
      db,
      table: 'users',
      column: 'lastLoginAt',
      definition: 'TEXT',
    );
    await _addMissingColumn(db,
        table: 'jar_activity', column: 'syncId', definition: 'TEXT');
    await db.execute(
        "UPDATE jar_activity SET syncId = lower(hex(randomblob(16))) WHERE syncId IS NULL");
    await db.execute(
        'CREATE TABLE IF NOT EXISTS device_sync_state (userId TEXT PRIMARY KEY, payload TEXT NOT NULL, syncedAt TEXT NOT NULL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS device_sync_backups (id INTEGER PRIMARY KEY AUTOINCREMENT, userId TEXT NOT NULL, payload TEXT NOT NULL, createdAt TEXT NOT NULL)');
    await _seedDefaultCategories(db);
  }

  Future<void> _addMissingColumn(
    Database db, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _seedDefaultCategories(Database db) async {
    for (final category in AppCategory.defaults) {
      await db.insert(
        'categories',
        category.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    for (final category in TransactionCategory.values) {
      await db.update(
        'transactions',
        {'categoryId': category.name},
        where: 'category = ? AND (categoryId IS NULL OR categoryId = ?)',
        whereArgs: [category.index, ''],
      );
    }
  }

  Future<void> ensureUserDefaults(String userId) async {
    final db = await database;
    await _seedDefaultAccounts(db, userId);
    await db.update(
      'transactions',
      {'userId': userId},
      where: 'userId IS NULL OR userId = ?',
      whereArgs: [''],
    );
  }

  /// Called only after the user verifies the old offline account PIN.
  Future<void> moveLegacyRecords(String oldId, String newId) async {
    if (!oldId.startsWith('SP-') || oldId == newId) {
      throw ArgumentError('Invalid legacy account');
    }
    final db = await database;
    await db.transaction((txn) async {
      for (final table in [
        'transactions',
        'budgets',
        'categories',
        'accounts',
        'treasure_jars',
        'jar_activity',
        'split_payments',
        'split_people',
        'account_transfers'
      ]) {
        await txn.update(table, {'userId': newId},
            where: 'userId = ?', whereArgs: [oldId]);
      }
    });
  }

  Future<void> _seedDefaultAccounts(Database db, String userId) async {
    final defaultAccount = AppAccount.defaults.first.copyWith(
      id: defaultAccountIdForUser(userId),
      isDefault: true,
    );
    await db.insert(
      'accounts',
      {
        ...defaultAccount.toMap(),
        'userId': userId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.update(
      'transactions',
      {'accountId': defaultAccount.id},
      where:
          '(userId = ? OR userId IS NULL OR userId = ?) AND (accountId IS NULL OR accountId = ? OR accountId = ?)',
      whereArgs: [userId, '', '', AppAccount.defaultId],
    );
  }

  static String defaultAccountIdForUser(String userId) =>
      '${AppAccount.defaultId}_$userId';

  Future<AppUser?> getUserByEmail(String email) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return AppUser.fromMap(maps.first);
  }

  Future<void> insertUser(AppUser user) async {
    final db = await database;
    await db.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateUser(AppUser user) async {
    final db = await database;
    await db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  // Transactions CRUD
  Future<List<BudgetModel>> getAllBudgets({required String userId}) async {
    final db = await database;
    final rows =
        await db.query('budgets', where: 'userId = ?', whereArgs: [userId]);
    return rows.map(BudgetModel.fromMap).toList();
  }

  Future<List<TreasureJar>> getJars(String owner) async {
    final db = await database;
    final rows = await db.query('treasure_jars',
        where: 'userId = ?', whereArgs: [owner], orderBy: 'rowid DESC');
    return rows.map(TreasureJar.fromMap).toList();
  }

  Future<void> saveJar(TreasureJar jar, String owner) async {
    if (owner.isEmpty || jar.name.trim().isEmpty || jar.targetCents <= 0)
      throw StateError('Enter a name and a positive target.');
    final db = await database;
    await db.transaction((txn) async {
      final accounts = await txn.query('accounts',
          where: 'id = ? AND userId = ? AND kind = ?',
          whereArgs: [jar.accountId, owner, AccountKind.asset.index]);
      if (accounts.isEmpty)
        throw StateError('Choose one of your asset accounts.');
      final old = await txn.query('treasure_jars',
          where: 'id = ? AND userId = ?', whereArgs: [jar.id, owner]);
      if (old.isNotEmpty &&
          (old.first['savedCents'] as int) > 0 &&
          old.first['accountId'] != jar.accountId)
        throw StateError(
            'Release the reserved money before changing accounts.');
      final values = {
        'name': jar.name.trim(),
        'accountId': jar.accountId,
        'targetCents': jar.targetCents,
        'deadline': jar.deadline?.toIso8601String()
      };
      if (old.isEmpty) {
        await txn.insert('treasure_jars',
            {'id': jar.id, 'userId': owner, ...values, 'savedCents': 0});
      } else {
        await txn.update('treasure_jars', values,
            where: 'id = ? AND userId = ?', whereArgs: [jar.id, owner]);
      }
    });
  }

  Future<void> adjustJar(String id, String owner, int deltaCents) async {
    if (deltaCents == 0) throw StateError('Enter a positive amount.');
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('treasure_jars',
          where: 'id = ? AND userId = ?', whereArgs: [id, owner]);
      if (rows.isEmpty) throw StateError('This jar is no longer available.');
      final jar = TreasureJar.fromMap(rows.single);
      if (jar.savedCents + deltaCents < 0)
        throw StateError('You cannot release more than this jar holds.');
      if (deltaCents > 0) {
        final accounts = await txn.query('accounts',
            where: 'id = ? AND userId = ?', whereArgs: [jar.accountId, owner]);
        if (accounts.isEmpty)
          throw StateError('The source account is unavailable.');
        if (accounts.single['kind'] != AccountKind.asset.index) {
          throw StateError('Only asset accounts can fund a jar.');
        }
        final reserved = await txn.rawQuery(
            'SELECT COALESCE(SUM(savedCents),0) AS amount FROM treasure_jars WHERE userId = ? AND accountId = ?',
            [owner, jar.accountId]);
        final balance =
            ((accounts.single['currentBalance'] as num) * 100).round();
        if (deltaCents > balance - (reserved.single['amount'] as num).toInt())
          throw StateError('Not enough unreserved money in this account.');
      }
      await txn.update(
          'treasure_jars', {'savedCents': jar.savedCents + deltaCents},
          where: 'id = ? AND userId = ?', whereArgs: [id, owner]);
      await txn.insert('jar_activity', {
        'userId': owner,
        'jarId': id,
        'syncId': const Uuid().v4(),
        'amountCents': deltaCents,
        'date': DateTime.now().toIso8601String()
      });
    });
  }

  Future<List<Map<String, Object?>>> jarHistory(
          String id, String owner) async =>
      (await database).query('jar_activity',
          where: 'jarId = ? AND userId = ?',
          whereArgs: [id, owner],
          orderBy: 'id DESC');

  Future<void> deleteJar(String id, String owner) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('treasure_jars',
          where: 'id = ? AND userId = ?', whereArgs: [id, owner]);
      if (rows.isEmpty) return;
      final jar = rows.single;
      final accounts = await txn.query('accounts',
          where: 'id = ? AND userId = ?', whereArgs: [jar['accountId'], owner]);
      final accountName =
          accounts.isEmpty ? 'the linked account' : accounts.single['name'];
      final amount = (jar['savedCents'] as int) / 100;
      await txn.insert('jar_notifications', {
        'id': const Uuid().v4(),
        'userId': owner,
        'message':
            '${jar['name']} deleted. RM ${amount.toStringAsFixed(2)} released to $accountName and available to spend. Released money returns to Total Balance if this account is included.',
        'date': DateTime.now().toIso8601String(),
        'isRead': 0,
      });
      await txn.delete('jar_activity',
          where: 'jarId = ? AND userId = ?', whereArgs: [id, owner]);
      await txn.delete('treasure_jars',
          where: 'id = ? AND userId = ?', whereArgs: [id, owner]);
    });
  }

  Future<List<Map<String, Object?>>> jarNotifications(String owner) async =>
      (await database).query('jar_notifications',
          where: 'userId = ?', whereArgs: [owner], orderBy: 'date DESC');
  Future<void> readJarNotification(String id, String owner) async {
    await (await database).update('jar_notifications', {'isRead': 1},
        where: 'id = ? AND userId = ?', whereArgs: [id, owner]);
  }

  /// User-confirmed ledger changes and account balances commit as one unit.
  /// Raw insertTransaction remains available for legacy imports/test fixtures.
  Future<TransactionModel> saveConfirmedTransaction(TransactionModel value,
      {required String userId, bool editing = false}) async {
    final split = value.split;
    split?.validate();
    if (split != null &&
        (value.type != TransactionType.expense ||
            (value.amount * 100).round() != split.ownSen))
      throw ArgumentError('Invalid split expense.');
    if (userId.isEmpty ||
        value.id.isEmpty ||
        value.title.trim().isEmpty ||
        !value.amount.isFinite ||
        (value.amount <= 0 && split == null) ||
        value.amount > 100000000 ||
        ((value.amount * 100).round() <= 0 && split == null) ||
        value.category.isIncomeCategory !=
            (value.type == TransactionType.income)) {
      throw ArgumentError('Check the amount, title and category.');
    }
    final saved = value.copyWith(amount: (value.amount * 100).round() / 100);
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn
          .query('transactions', where: 'id = ?', whereArgs: [saved.id]);
      if (rows.isNotEmpty && rows.single['userId'] != userId) {
        throw StateError('Transaction belongs to a different account.');
      }
      final old = rows.isEmpty ? null : TransactionModel.fromMap(rows.single);
      if (editing && old == null) {
        throw StateError('Transaction no longer exists.');
      }
      if (!editing && old != null) {
        final previous = old.toMap();
        if (saved.toMap().entries.every((e) => previous[e.key] == e.value)) {
          return old;
        }
        throw StateError('Transaction already exists. Refresh before editing.');
      }
      if (old?.splitData != null) {
        final payments = await txn.query('split_payments',
            where: 'billId = ? AND userId = ?', whereArgs: [saved.id, userId]);
        if (payments.isNotEmpty)
          throw StateError(
              'Undo recorded repayments before editing this bill.');
      }
      // Check the new account before reversing anything. Deleted legacy source
      // accounts may be absent; never recreate them or touch another user's row.
      final accounts = await txn.query('accounts',
          where: 'id = ? AND userId = ?', whereArgs: [saved.accountId, userId]);
      if (accounts.isEmpty ||
          (split != null &&
              ![AccountKind.asset.index, AccountKind.liability.index]
                  .contains(accounts.single['kind'])))
        throw StateError('Choose an existing financial account.');
      if (old != null) {
        await _changeLedgerBalance(txn, old, userId, reverse: true);
      }
      await _changeLedgerBalance(txn, saved, userId);
      await txn.delete('pending_transaction_deletes',
          where: 'id = ? AND userId = ?', whereArgs: [saved.id, userId]);
      final row = {...saved.toMap(), 'userId': userId};
      if (editing) {
        await txn.update('transactions', row,
            where: 'id = ? AND userId = ?', whereArgs: [saved.id, userId]);
      } else {
        await txn.insert('transactions', row);
      }
      if (split != null) {
        for (final person in split.people.skip(1)) {
          if (!person.id.startsWith('open-'))
            await txn.insert('split_people',
                {'id': person.id, 'userId': userId, 'name': person.name},
                conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      return saved;
    });
  }

  Future<void> deleteConfirmedTransaction(String id,
      {required String userId}) async {
    if (userId.isEmpty) throw ArgumentError('Missing owner.');
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('transactions',
          where: 'id = ? AND userId = ?', whereArgs: [id, userId]);
      if (rows.isEmpty) return;
      await _changeLedgerBalance(
          txn, TransactionModel.fromMap(rows.single), userId,
          reverse: true);
      final payments = await txn.query('split_payments',
          where: 'billId = ? AND userId = ?', whereArgs: [id, userId]);
      final bill = TransactionModel.fromMap(rows.single).split;
      for (final payment in payments) {
        await _changeLedgerBalance(
            txn,
            TransactionModel(
                id: 'settlement',
                title: 'Settlement',
                amount: (payment['sen'] as int) / 100,
                type: bill!.payer == 0
                    ? TransactionType.income
                    : TransactionType.expense,
                category: bill.payer == 0
                    ? TransactionCategory.incomeOther
                    : TransactionCategory.other,
                accountId: payment['accountId'] as String,
                date: DateTime.now()),
            userId,
            reverse: true);
      }
      await txn.delete('split_payments',
          where: 'billId = ? AND userId = ?', whereArgs: [id, userId]);
      await txn.insert(
          'pending_transaction_deletes', {'id': id, 'userId': userId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.delete('transactions',
          where: 'id = ? AND userId = ?', whereArgs: [id, userId]);
    });
  }

  Future<void> _changeLedgerBalance(
      Transaction txn, TransactionModel value, String owner,
      {bool reverse = false}) async {
    final rows = await txn.query('accounts',
        where: 'id = ? AND userId = ?', whereArgs: [value.accountId, owner]);
    if (rows.isEmpty) return;
    final account = AppAccount.fromMap(rows.single);
    if (account.kind == AccountKind.other) return;
    if (!account.currentBalance.isFinite || !value.amount.isFinite) {
      throw StateError('Invalid stored balance or amount.');
    }
    var delta = value.split?.cashSen ?? (value.amount * 100).round();
    final increases = account.kind == AccountKind.liability
        ? value.type == TransactionType.expense
        : value.type == TransactionType.income;
    if (!increases) delta = -delta;
    if (reverse) delta = -delta;
    await txn.update(
        'accounts',
        {
          'currentBalance':
              ((account.currentBalance * 100).round() + delta) / 100
        },
        where: 'id = ? AND userId = ?',
        whereArgs: [value.accountId, owner]);
  }

  Future<List<Map<String, Object?>>> splitPeople(String owner) async =>
      (await database).query('split_people',
          where: 'userId = ?', whereArgs: [owner], orderBy: 'name');
  Future<List<Map<String, Object?>>> splitPayments(
          String owner, String bill) async =>
      (await database).query('split_payments',
          where: 'userId = ? AND billId = ?',
          whereArgs: [owner, bill],
          orderBy: 'date');
  Future<void> settleSplit(
      {required String owner,
      required String billId,
      required String personId,
      required String accountId,
      required int sen,
      required String paymentId}) async {
    if (sen <= 0) throw ArgumentError('Enter a positive repayment.');
    final db = await database;
    await db.transaction((txn) async {
      final duplicate = await txn
          .query('split_payments', where: 'id = ?', whereArgs: [paymentId]);
      if (duplicate.isNotEmpty) {
        final old = duplicate.single;
        if (old['userId'] == owner &&
            old['billId'] == billId &&
            old['personId'] == personId &&
            old['accountId'] == accountId &&
            old['sen'] == sen) return;
        throw StateError('Payment ID already used.');
      }
      final rows = await txn.query('transactions',
          where: 'id = ? AND userId = ?', whereArgs: [billId, owner]);
      if (rows.isEmpty) throw StateError('Bill unavailable.');
      final bill = TransactionModel.fromMap(rows.single).split;
      if (bill == null) throw StateError('This is not a split bill.');
      final index = bill.people.indexWhere((p) => p.id == personId);
      if (index < 0 || (bill.payer == 0 ? index == 0 : index != 0))
        throw StateError('No settlement is owed for this participant.');
      final payments = await txn.query('split_payments',
          where: 'billId = ? AND personId = ? AND userId = ?',
          whereArgs: [billId, personId, owner]);
      final paid = payments.fold<int>(0, (s, p) => s + (p['sen'] as int));
      if (sen > bill.people[index].sen - paid)
        throw StateError('Repayment exceeds the outstanding amount.');
      final accounts = await txn.query('accounts',
          where: 'id = ? AND userId = ?', whereArgs: [accountId, owner]);
      if (accounts.isEmpty ||
          ![AccountKind.asset.index, AccountKind.liability.index]
              .contains(accounts.single['kind']))
        throw StateError('Choose an existing financial account.');
      await _changeLedgerBalance(
          txn,
          TransactionModel(
              id: paymentId,
              title: 'Split settlement',
              amount: sen / 100,
              type: bill.payer == 0
                  ? TransactionType.income
                  : TransactionType.expense,
              category: bill.payer == 0
                  ? TransactionCategory.incomeOther
                  : TransactionCategory.other,
              accountId: accountId,
              date: DateTime.now()),
          owner);
      await txn.insert('split_payments', {
        'id': paymentId,
        'userId': owner,
        'billId': billId,
        'personId': personId,
        'accountId': accountId,
        'sen': sen,
        'date': DateTime.now().toIso8601String()
      });
    });
  }

  Future<void> undoSplitPayment(String owner, String paymentId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('split_payments',
          where: 'id = ? AND userId = ?', whereArgs: [paymentId, owner]);
      if (rows.isEmpty) return;
      final row = rows.single;
      final bills = await txn.query('transactions',
          where: 'id = ? AND userId = ?', whereArgs: [row['billId'], owner]);
      if (bills.isEmpty) throw StateError('Bill unavailable.');
      final bill = TransactionModel.fromMap(bills.single).split!;
      await _changeLedgerBalance(
          txn,
          TransactionModel(
              id: paymentId,
              title: 'Undo settlement',
              amount: (row['sen'] as int) / 100,
              type: bill.payer == 0
                  ? TransactionType.income
                  : TransactionType.expense,
              category: bill.payer == 0
                  ? TransactionCategory.incomeOther
                  : TransactionCategory.other,
              accountId: row['accountId'] as String,
              date: DateTime.now()),
          owner,
          reverse: true);
      await txn.delete('split_payments',
          where: 'id = ? AND userId = ?', whereArgs: [paymentId, owner]);
    });
  }

  Future<void> transfer(
      {required String owner,
      required String id,
      required String from,
      required String to,
      required int sen,
      required DateTime date,
      String? note}) async {
    if (owner.isEmpty || from == to || sen <= 0 || sen > 10000000000)
      throw ArgumentError('Choose different accounts and a valid amount.');
    final db = await database;
    await db.transaction((txn) async {
      final old = await txn
          .query('account_transfers', where: 'id = ?', whereArgs: [id]);
      if (old.isNotEmpty) {
        if (old.single['userId'] == owner &&
            old.single['fromId'] == from &&
            old.single['toId'] == to &&
            old.single['sen'] == sen &&
            old.single['date'] == date.toIso8601String()) return;
        throw StateError('Transfer ID already exists.');
      }
      for (final accountId in [from, to]) {
        final rows = await txn.query('accounts',
            where: 'id = ? AND userId = ?', whereArgs: [accountId, owner]);
        if (rows.isEmpty ||
            ![AccountKind.asset.index, AccountKind.liability.index]
                .contains(rows.single['kind']))
          throw StateError('Choose available financial accounts.');
        await _changeLedgerBalance(
            txn,
            TransactionModel(
                id: id,
                title: 'Transfer',
                amount: sen / 100,
                type: accountId == from
                    ? TransactionType.expense
                    : TransactionType.income,
                category: accountId == from
                    ? TransactionCategory.other
                    : TransactionCategory.incomeOther,
                accountId: accountId,
                date: date),
            owner);
      }
      await txn.insert('account_transfers', {
        'id': id,
        'userId': owner,
        'fromId': from,
        'toId': to,
        'sen': sen,
        'date': date.toIso8601String(),
        'note': note
      });
    });
  }

  Future<List<Map<String, Object?>>> transfers(String owner) async =>
      (await database).query('account_transfers',
          where: 'userId = ?', whereArgs: [owner], orderBy: 'date DESC');
  Future<void> undoTransfer(String owner, String id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('account_transfers',
          where: 'id = ? AND userId = ?', whereArgs: [id, owner]);
      if (rows.isEmpty) return;
      final row = rows.single;
      for (final accountId in [row['fromId'], row['toId']]) {
        final accounts = await txn.query('accounts',
            where: 'id = ? AND userId = ?', whereArgs: [accountId, owner]);
        if (accounts.isEmpty)
          throw StateError(
              'Restore both accounts before undoing this transfer.');
        await _changeLedgerBalance(
            txn,
            TransactionModel(
                id: id,
                title: 'Undo transfer',
                amount: (row['sen'] as int) / 100,
                type: accountId == row['fromId']
                    ? TransactionType.expense
                    : TransactionType.income,
                category: accountId == row['fromId']
                    ? TransactionCategory.other
                    : TransactionCategory.incomeOther,
                accountId: accountId as String,
                date: DateTime.now()),
            owner,
            reverse: true);
      }
      await txn.delete('account_transfers',
          where: 'id = ? AND userId = ?', whereArgs: [id, owner]);
    });
  }

  Future<void> insertTransaction(TransactionModel transaction,
      {String? userId}) async {
    final db = await database;
    final values = {
      ...transaction.toMap(),
      if (userId != null) 'userId': userId,
    };
    try {
      await db.insert(
        'transactions',
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException {
      await _ensureSchema(db);
      await db.insert(
        'transactions',
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<List<TransactionModel>> getAllTransactions({String? userId}) async {
    final db = await database;
    final maps = await db.query(
      'transactions',
      where: userId == null ? null : 'userId = ?',
      whereArgs: userId == null ? null : [userId],
      orderBy: 'date DESC',
    );
    return maps.map((m) => TransactionModel.fromMap(m)).toList();
  }

  Future<List<TransactionModel>> getTransactionsByMonth(DateTime month,
      {String? userId}) async {
    final db = await database;
    final start = DateTime(month.year, month.month, 1).toIso8601String();
    final end = DateTime(month.year, month.month + 1, 1).toIso8601String();

    final maps = await db.query(
      'transactions',
      where: userId == null
          ? 'date >= ? AND date < ?'
          : 'userId = ? AND date >= ? AND date < ?',
      whereArgs: userId == null ? [start, end] : [userId, start, end],
      orderBy: 'date DESC',
    );
    return maps.map((m) => TransactionModel.fromMap(m)).toList();
  }

  Future<void> updateTransaction(TransactionModel transaction,
      {String? userId}) async {
    final db = await database;
    final values = {
      ...transaction.toMap(),
      if (userId != null) 'userId': userId,
    };
    try {
      await db.update(
        'transactions',
        values,
        where: userId == null ? 'id = ?' : 'id = ? AND userId = ?',
        whereArgs: userId == null ? [transaction.id] : [transaction.id, userId],
      );
    } on DatabaseException {
      await _ensureSchema(db);
      await db.update(
        'transactions',
        values,
        where: userId == null ? 'id = ?' : 'id = ? AND userId = ?',
        whereArgs: userId == null ? [transaction.id] : [transaction.id, userId],
      );
    }
  }

  Future<void> deleteTransaction(String id, {String? userId}) async {
    final db = await database;
    await db.delete(
      'transactions',
      where: userId == null ? 'id = ?' : 'id = ? AND userId = ?',
      whereArgs: userId == null ? [id] : [id, userId],
    );
  }

  Future<List<AppCategory>> getCategories({String? userId}) async {
    final db = await database;
    final maps = await db.query(
      'categories',
      where: userId == null ? null : 'isDefault = 1 OR userId = ?',
      whereArgs: userId == null ? null : [userId],
      orderBy: 'isDefault DESC, name ASC',
    );
    return maps.map((m) => AppCategory.fromMap(m)).toList();
  }

  Future<void> insertCategory(AppCategory category, {String? userId}) async {
    final db = await database;
    await db.insert(
      'categories',
      {
        ...category.toMap(),
        if (userId != null) 'userId': userId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateCategory(AppCategory category, {String? userId}) async {
    final db = await database;
    await db.update(
      'categories',
      {
        ...category.toMap(),
        if (userId != null) 'userId': userId,
      },
      where: userId == null ? 'id = ?' : 'id = ? AND userId = ?',
      whereArgs: userId == null ? [category.id] : [category.id, userId],
    );
  }

  Future<void> deleteCategory(AppCategory category, {String? userId}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'transactions',
        {'categoryId': category.parentCategory.name},
        where:
            userId == null ? 'categoryId = ?' : 'categoryId = ? AND userId = ?',
        whereArgs: userId == null ? [category.id] : [category.id, userId],
      );
      await txn.delete(
        'categories',
        where: userId == null ? 'id = ?' : 'id = ? AND userId = ?',
        whereArgs: userId == null ? [category.id] : [category.id, userId],
      );
    });
  }

  Future<List<AppAccount>> getAccounts({String? userId}) async {
    final db = await database;
    if (userId != null) await _seedDefaultAccounts(db, userId);
    final maps = await db.query(
      'accounts',
      where: userId == null ? null : 'userId = ?',
      whereArgs: userId == null ? null : [userId],
      orderBy: 'isDefault DESC, name ASC',
    );
    return maps.map((m) => AppAccount.fromMap(m)).toList();
  }

  Future<void> insertAccount(AppAccount account, {String? userId}) async {
    final db = await database;
    await db.insert(
      'accounts',
      {
        ...account.toMap(),
        if (userId != null) 'userId': userId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateAccount(AppAccount account, {String? userId}) async {
    final db = await database;
    if (account.kind != AccountKind.asset) {
      final jars = await db.query('treasure_jars',
          where: 'accountId = ?', whereArgs: [account.id], limit: 1);
      if (jars.isNotEmpty)
        throw StateError(
            'Move or remove this account’s jars before changing its type.');
    }
    await db.update(
      'accounts',
      {
        ...account.toMap(),
        if (userId != null) 'userId': userId,
      },
      where: userId == null ? 'id = ?' : 'id = ? AND userId = ?',
      whereArgs: userId == null ? [account.id] : [account.id, userId],
    );
  }

  Future<void> deleteAccount(String id, {String? userId}) async {
    final db = await database;
    final jars = await db.query('treasure_jars',
        where: 'accountId = ?', whereArgs: [id], limit: 1);
    if (jars.isNotEmpty)
      throw StateError('Remove or move this account’s treasure jars first.');
    await db.delete(
      'accounts',
      where: userId == null ? 'id = ?' : 'id = ? AND userId = ?',
      whereArgs: userId == null ? [id] : [id, userId],
    );
  }

  Future<List<TransactionModel>> getTransactionsByAccount(String accountId,
      {String? userId}) async {
    final db = await database;
    final maps = await db.query(
      'transactions',
      where: userId == null ? 'accountId = ?' : 'accountId = ? AND userId = ?',
      whereArgs: userId == null ? [accountId] : [accountId, userId],
      orderBy: 'date DESC',
    );
    return maps.map((m) => TransactionModel.fromMap(m)).toList();
  }

  // Budget CRUD
  Future<void> upsertBudget(BudgetModel budget, {String? userId}) async {
    final db = await database;
    await db.insert(
        'budgets',
        {
          ...budget.toMap(),
          if (userId != null) 'userId': userId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<BudgetModel>> getBudgetsByMonth(DateTime month,
      {String? userId}) async {
    final db = await database;
    final start = DateTime(month.year, month.month, 1).toIso8601String();
    final end = DateTime(month.year, month.month + 1, 1).toIso8601String();
    final maps = await db.query(
      'budgets',
      where: userId == null
          ? 'month >= ? AND month < ?'
          : 'userId = ? AND month >= ? AND month < ?',
      whereArgs: userId == null ? [start, end] : [userId, start, end],
    );
    return maps.map((m) => BudgetModel.fromMap(m)).toList();
  }

  Future<void> deleteBudget(String id, {String? userId}) async {
    final db = await database;
    await db.delete(
      'budgets',
      where: userId == null ? 'id = ?' : 'id = ? AND userId = ?',
      whereArgs: userId == null ? [id] : [id, userId],
    );
  }

  // Stats
  Future<Map<String, double>> getMonthlyStats(DateTime month) async {
    final transactions = await getTransactionsByMonth(month);
    final income = LedgerTotals.sum(transactions
        .where((t) => t.type == TransactionType.income)
        .map((t) => t.amount));
    final expense = LedgerTotals.sum(transactions
        .where((t) => t.type == TransactionType.expense)
        .map((t) => t.amount));
    return {
      'income': income,
      'expense': expense,
      'balance': (LedgerTotals.sen(income) - LedgerTotals.sen(expense)) / 100
    };
  }

  Future<Map<TransactionCategory, double>> getCategoryBreakdown(
      DateTime month) async {
    final transactions = await getTransactionsByMonth(month);
    return LedgerTotals.categories(transactions);
  }
}
