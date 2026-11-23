import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_service.dart';
import '../models/transaction_model.dart';
import 'sync_merge.dart';

abstract class DeviceSyncRemote {
  bool ownsSession(String owner);
  Future<Map<String, dynamic>?> read(String owner);
  Future<SyncData> readLegacy(String owner);
  Future<Map<String, dynamic>> commit(int expectedRevision, SyncData payload);
}

class SupabaseDeviceSyncRemote implements DeviceSyncRemote {
  SupabaseClient get client => Supabase.instance.client;
  @override
  bool ownsSession(String owner) {
    try {
      return client.auth.currentSession != null &&
          client.auth.currentUser?.id == owner;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> read(String owner) async => await client
      .from('device_snapshots')
      .select('revision,payload')
      .eq('user_id', owner)
      .maybeSingle();
  @override
  Future<Map<String, dynamic>> commit(
          int expectedRevision, SyncData payload) async =>
      Map<String, dynamic>.from(await client.rpc('commit_device_snapshot',
          params: {
            'expected_revision': expectedRevision,
            'new_payload': payload
          }));

  @override
  Future<SyncData> readLegacy(String owner) async {
    final result = <String, List<Map<String, dynamic>>>{
      for (final t in syncTables) t: []
    };
    const names = {
      'user_id': 'userId',
      'category_id': 'categoryId',
      'account_id': 'accountId',
      'is_recurring': 'isRecurring',
      'recurring_frequency': 'recurringFrequency',
      'limit_amount': 'limit',
      'parent_category': 'parentCategory',
      'color_value': 'colorValue',
      'parent_id': 'parentId',
      'is_default': 'isDefault',
      'opening_balance': 'openingBalance',
      'current_balance': 'currentBalance',
      'include_in_net_worth': 'includeInNetWorth',
      'include_in_balance': 'includeInBalance',
      'counterparty_name': 'counterpartyName',
      'linked_account_id': 'linkedAccountId'
    };
    for (final table in ['accounts', 'categories', 'budgets', 'transactions']) {
      for (int offset = 0;; offset += 500) {
        if (!ownsSession(owner)) throw const AuthException('Account changed.');
        final page = await client
            .from(table)
            .select()
            .eq('user_id', owner)
            .order('id')
            .range(offset, offset + 499);
        for (final source in page) {
          final row = <String, dynamic>{};
          for (final entry in source.entries) {
            if (['user_id', 'updated_at', 'receipt_image_path']
                .contains(entry.key)) continue;
            var value = entry.value;
            if (value is bool) value = value ? 1 : 0;
            final key = names[entry.key] ?? entry.key;
            if ((table == 'categories' && key == 'id') ||
                key == 'categoryId' ||
                key == 'parentId') {
              if (value is String && value.startsWith('$owner:'))
                value = value.substring(owner.length + 1);
            }
            if ((key == 'date' || key == 'month') && value is String) {
              value = DateTime.parse(value).toLocal().toIso8601String();
            }
            row[key] = value;
          }
          if (table == 'transactions') row['splitData'] = null;
          if (table == 'categories' &&
              row['isDefault'] == 1 &&
              AppCategory.defaults.any((c) => c.id == row['id'])) continue;
          result[table]!.add(row);
        }
        if (page.length < 500) break;
      }
    }
    return result;
  }
}

class DeviceSyncService {
  DeviceSyncService({DeviceSyncRemote? remote, DatabaseService? database})
      : remote = remote ?? SupabaseDeviceSyncRemote(),
        database = database ?? DatabaseService();
  final DeviceSyncRemote remote;
  final DatabaseService database;
  Future<void> _queue = Future.value();
  bool ownsSession(String owner) => remote.ownsSession(owner);

  Future<void> sync(String owner, {bool? preferLocalConflicts}) {
    final work = _queue
        .then((_) => _sync(owner, preferLocalConflicts: preferLocalConflicts));
    _queue = work.catchError((Object _) {});
    return work;
  }

  void _check(String owner) {
    if (!remote.ownsSession(owner))
      throw const AuthException('Sign in to the same account to sync.');
  }

  Future<T> _network<T>(Future<T> work) =>
      work.timeout(const Duration(seconds: 25));

  Future<void> _sync(String owner, {bool? preferLocalConflicts}) async {
    for (int attempt = 0; attempt < 4; attempt++) {
      _check(owner);
      final captured = await database.exportSyncData(owner);
      final baseline = await database.syncBaseline(owner);
      final state = await _network(remote.read(owner));
      _check(owner);
      final legacy = state == null;
      final cloud = legacy
          ? await _network(remote.readLegacy(owner))
          : decodeSyncData(state['payload']);
      _check(owner);
      final local = decodeSyncData(captured);
      if (baseline == null) {
        // A newly signed-in tablet seeds an empty default account. It is not
        // an intentional edit of an existing cloud account balance.
        local['accounts']!.removeWhere((row) =>
            row['isDefault'] == 1 &&
            row['openingBalance'] == 0 &&
            row['currentBalance'] == 0 &&
            cloud['accounts']!.any((r) => r['id'] == row['id']) &&
            !local['transactions']!.any((t) => t['accountId'] == row['id']) &&
            !local['account_transfers']!.any(
                (t) => t['fromId'] == row['id'] || t['toId'] == row['id']));
        if (legacy) {
          // Respect deletes queued by the previous upload-only build.
          final removed = await database.pendingDeletedIds(owner);
          cloud['transactions']!.removeWhere((r) => removed.contains(r['id']));
        }
      }
      var merged = preferLocalConflicts == null
          ? mergeSyncData(baseline, local, cloud,
              preferLocalConflicts: legacy ? true : null)
          : (preferLocalConflicts ? local : cloud);
      // On the first legacy migration, preserve the phone's richer split details.
      validateSyncData(merged);
      if (legacy || !sameSyncValue(merged, cloud)) {
        final response = await _network(
            remote.commit((state?['revision'] as num?)?.toInt() ?? 0, merged));
        _check(owner);
        if (response['accepted'] != true) continue;
        merged = decodeSyncData(response['payload']);
      }
      _check(owner);
      final changed = await database.applySyncData(owner, captured, merged,
          ownsSession: () => remote.ownsSession(owner));
      if (!changed) return;
    }
    throw StateError('Records changed during sync. Tap Sync now to retry.');
  }
}
