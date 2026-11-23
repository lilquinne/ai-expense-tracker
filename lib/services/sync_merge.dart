import 'dart:convert';
import '../models/transaction_model.dart';

typedef SyncData = Map<String, List<Map<String, dynamic>>>;
const syncTables = [
  'accounts',
  'categories',
  'budgets',
  'transactions',
  'treasure_jars',
  'jar_activity',
  'split_people',
  'split_payments',
  'account_transfers'
];

class SyncConflict implements Exception {
  const SyncConflict(this.records);
  final List<String> records;
  @override
  String toString() =>
      'Both devices changed ${records.take(3).join(', ')}. Your device copy is kept. Review sync in Settings.';
}

SyncData decodeSyncData(dynamic value) {
  if (value is! Map) throw const FormatException('Invalid sync data');
  return {
    for (final table in syncTables)
      table: ((value[table] ?? []) as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList()
  };
}

dynamic _canonical(dynamic v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final key in keys) key: _canonical(v[key])};
  }
  if (v is List) {
    final list = v.map(_canonical).toList();
    if (list.every((e) => e is Map && e.containsKey('id'))) {
      list.sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
    }
    return list;
  }
  if (v is num && v.isFinite && v == v.roundToDouble()) return v.toInt();
  return v;
}

bool sameSyncValue(dynamic a, dynamic b) =>
    jsonEncode(_canonical(a)) == jsonEncode(_canonical(b));

Map<String, Map<String, dynamic>> _rows(SyncData data, String table) => {
      for (final row in data[table] ?? <Map<String, dynamic>>[])
        row['id'].toString(): Map<String, dynamic>.from(row)
    };

// Account balances are derived from merged cash movements plus a separately
// merged adjustment. Adding expenses on two devices must never lose a debit.
int _cashDelta(SyncData data, Map<String, dynamic> account) {
  if (account['kind'] == AccountKind.other.index) return 0;
  final liability = account['kind'] == AccountKind.liability.index;
  int delta(int sen, bool income) => income != liability ? sen : -sen;
  int total = 0;
  final txns = _rows(data, 'transactions');
  for (final row in txns.values) {
    if (row['accountId'] != account['id']) continue;
    final t = TransactionModel.fromMap(row);
    total += delta(t.split?.cashSen ?? (t.amount * 100).round(),
        t.type == TransactionType.income);
  }
  for (final row in data['split_payments'] ?? <Map<String, dynamic>>[]) {
    if (row['accountId'] != account['id']) continue;
    final bill = txns[row['billId']];
    if (bill == null) throw const FormatException('Split payment has no bill');
    final split = TransactionModel.fromMap(bill).split;
    if (split == null)
      throw const FormatException('Split payment has no split details');
    total += delta((row['sen'] as num).toInt(), split.payer == 0);
  }
  for (final row in data['account_transfers'] ?? <Map<String, dynamic>>[]) {
    if (row['fromId'] == account['id'])
      total += delta((row['sen'] as num).toInt(), false);
    if (row['toId'] == account['id'])
      total += delta((row['sen'] as num).toInt(), true);
  }
  return total;
}

int _jarDelta(SyncData data, String id) =>
    (data['jar_activity'] ?? <Map<String, dynamic>>[])
        .where((r) => r['jarId'] == id)
        .fold<int>(0, (s, r) => s + (r['amountCents'] as num).toInt());

SyncData _normalized(SyncData data) => {
      for (final table in syncTables)
        table: (data[table] ?? <Map<String, dynamic>>[]).map((value) {
          final row = Map<String, dynamic>.from(value);
          if (table == 'accounts') {
            row['balanceAdjustmentSen'] =
                ((row.remove('currentBalance') as num) * 100).round() -
                    _cashDelta(data, value);
          }
          if (table == 'treasure_jars') {
            row['reservationAdjustmentSen'] =
                (row.remove('savedCents') as num).toInt() -
                    _jarDelta(data, row['id'] as String);
          }
          return row;
        }).toList()
    };

/// Three-way merge: remote absence is a deletion only after it was seen in the
/// baseline. Conflicting edits are blocked; neither copy is silently discarded.
SyncData mergeSyncData(SyncData? baseline, SyncData local, SyncData remote,
    {bool? preferLocalConflicts}) {
  final base = _normalized(baseline ?? {}),
      left = _normalized(local),
      right = _normalized(remote);
  final result = <String, List<Map<String, dynamic>>>{};
  final conflicts = <String>[];
  for (final table in syncTables) {
    final b = _rows(base, table),
        l = _rows(left, table),
        r = _rows(right, table);
    final merged = <Map<String, dynamic>>[];
    for (final id in {...b.keys, ...l.keys, ...r.keys}) {
      Map<String, dynamic>? chosen;
      if (sameSyncValue(l[id], r[id])) {
        chosen = l[id];
      } else if (sameSyncValue(l[id], b[id])) {
        chosen = r[id];
      } else if (sameSyncValue(r[id], b[id])) {
        chosen = l[id];
      } else if (preferLocalConflicts != null) {
        chosen = preferLocalConflicts ? l[id] : r[id];
      } else {
        conflicts.add('$table: ${l[id]?['name'] ?? l[id]?['title'] ?? id}');
      }
      if (chosen != null) merged.add(Map<String, dynamic>.from(chosen));
    }
    result[table] = merged;
  }
  if (conflicts.isNotEmpty) throw SyncConflict(conflicts);
  for (final row in result['accounts']!) {
    row['currentBalance'] =
        ((row.remove('balanceAdjustmentSen') as num).toInt() +
                _cashDelta(result, row)) /
            100;
  }
  for (final row in result['treasure_jars']!) {
    row['savedCents'] =
        (row.remove('reservationAdjustmentSen') as num).toInt() +
            _jarDelta(result, row['id'] as String);
  }
  for (final account in result['accounts']!) {
    int reserved(SyncData d) => (d['treasure_jars'] ?? <Map<String, dynamic>>[])
        .where((j) => j['accountId'] == account['id'])
        .fold<int>(0, (sum, j) => sum + (j['savedCents'] as num).toInt());
    final combined = reserved(result);
    if (combined > reserved(local) &&
        combined > reserved(remote) &&
        combined > ((account['currentBalance'] as num) * 100).round()) {
      throw const SyncConflict(
          ['jar contributions exceeding the available balance']);
    }
  }
  validateSyncData(result);
  return result;
}

void validateSyncData(SyncData data) {
  for (final table in syncTables) {
    final rows = data[table] ?? [];
    if (rows.any((r) => r['id'] == null || r['id'].toString().isEmpty) ||
        _rows(data, table).length != rows.length) {
      throw FormatException('Invalid or duplicate $table records');
    }
  }
  final accounts = _rows(data, 'accounts'),
      txns = _rows(data, 'transactions'),
      jars = _rows(data, 'treasure_jars');
  for (final row in txns.values) {
    final t = TransactionModel.fromMap(row);
    if (!t.amount.isFinite || t.amount < 0)
      throw const FormatException('Invalid transaction amount');
    // Legacy transactions may refer to accounts removed before sync existed.
  }
  for (final jar in jars.values) {
    if ((jar['targetCents'] as num) <= 0 ||
        (jar['savedCents'] as num) < 0 ||
        !accounts.containsKey(jar['accountId'])) {
      throw const SyncConflict(['a jar and its account']);
    }
  }
  for (final row in data['jar_activity'] ?? <Map<String, dynamic>>[]) {
    if (!jars.containsKey(row['jarId']))
      throw const SyncConflict(['a jar and its history']);
  }
  for (final row in data['split_payments'] ?? <Map<String, dynamic>>[]) {
    if (!txns.containsKey(row['billId']) ||
        !accounts.containsKey(row['accountId']))
      throw const SyncConflict(['a bill and its repayment']);
  }
  for (final bill in txns.values) {
    final split = TransactionModel.fromMap(bill).split;
    if (split == null) continue;
    split.validate();
    for (final person in split.people) {
      final paid = (data['split_payments'] ?? <Map<String, dynamic>>[])
          .where((p) => p['billId'] == bill['id'] && p['personId'] == person.id)
          .fold<int>(0, (sum, p) => sum + (p['sen'] as num).toInt());
      if (paid > person.sen)
        throw const SyncConflict(['repayments exceeding the amount owed']);
    }
  }
  final budgetKeys = <String>{};
  for (final budget in data['budgets'] ?? <Map<String, dynamic>>[]) {
    final date = DateTime.parse(budget['month'] as String);
    if (!budgetKeys.add('${budget['category']}:${date.year}:${date.month}')) {
      throw const SyncConflict(['two budgets for the same category and month']);
    }
  }
  for (final row in data['account_transfers'] ?? <Map<String, dynamic>>[]) {
    if (!accounts.containsKey(row['fromId']) ||
        !accounts.containsKey(row['toId']))
      throw const SyncConflict(['a transfer and its accounts']);
  }
  for (final row in accounts.values) {
    if (!(row['currentBalance'] as num).isFinite)
      throw const FormatException('Invalid balance');
  }
}
