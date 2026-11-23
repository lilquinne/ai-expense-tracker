import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/services/sync_merge.dart';
import 'package:expense_tracker/services/device_sync_service.dart';
import 'package:expense_tracker/services/database_service.dart';
import 'package:expense_tracker/models/transaction_model.dart';

SyncData copy(SyncData data) => decodeSyncData(jsonDecode(jsonEncode(data)));
SyncData initial() => {
      for (final t in syncTables)
        t: t == 'accounts'
            ? [
                {
                  'id': 'bank',
                  'name': 'Bank',
                  'kind': 0,
                  'subtype': 0,
                  'openingBalance': 100.0,
                  'currentBalance': 100.0,
                  'icon': 'B',
                  'colorValue': 0,
                  'isDefault': 0,
                  'includeInNetWorth': 1,
                  'includeInBalance': 1,
                  'counterpartyName': null,
                  'linkedAccountId': null,
                }
              ]
            : []
    };
Map<String, dynamic> expense(String id, double amount) => TransactionModel(
        id: id,
        title: id,
        amount: amount,
        type: TransactionType.expense,
        category: TransactionCategory.groceries,
        accountId: 'bank',
        date: DateTime(2026, 10, 27))
    .toMap()
  ..remove('receiptImagePath');
void spend(SyncData data, String id, double amount) {
  data['transactions']!.add(expense(id, amount));
  data['accounts']!.single['currentBalance'] =
      (data['accounts']!.single['currentBalance'] as num) - amount;
}

class MemoryDb extends DatabaseService {
  MemoryDb(this.data);
  SyncData data;
  SyncData? base;
  int applies = 0;
  @override
  Future<SyncData> exportSyncData(String owner) async => copy(data);
  @override
  Future<SyncData?> syncBaseline(String owner) async =>
      base == null ? null : copy(base!);
  @override
  Future<Set<String>> pendingDeletedIds(String owner) async => {};
  @override
  Future<bool> applySyncData(String owner, SyncData captured, SyncData accepted,
      {required bool Function() ownsSession}) async {
    if (!ownsSession()) throw StateError('Account changed');
    final changed = !sameSyncValue(data, captured);
    data = mergeSyncData(captured, data, accepted);
    base = copy(accepted);
    applies++;
    return changed;
  }
}

class MemoryRemote implements DeviceSyncRemote {
  SyncData? data;
  SyncData legacy = initial();
  int revision = 0;
  bool signedIn = true;
  bool offline = false;
  bool race = false;
  void Function()? beforeCommit;
  @override
  bool ownsSession(String owner) => signedIn && owner == 'owner';
  @override
  Future<Map<String, dynamic>?> read(String owner) async {
    if (offline) throw StateError('Offline');
    return data == null ? null : {'revision': revision, 'payload': copy(data!)};
  }

  @override
  Future<SyncData> readLegacy(String owner) async => copy(legacy);
  @override
  Future<Map<String, dynamic>> commit(
      int expectedRevision, SyncData payload) async {
    beforeCommit?.call();
    beforeCommit = null;
    if (race) {
      revision++;
      race = false;
    }
    if (expectedRevision != revision)
      return {'accepted': false, 'revision': revision, 'payload': data};
    data = copy(payload);
    revision++;
    return {'accepted': true, 'revision': revision, 'payload': copy(data!)};
  }
}

void main() {
  test('a seeded empty tablet account restores the cloud balance', () async {
    final cloud = initial();
    cloud['accounts']!.single['isDefault'] = 1;
    final remote = MemoryRemote()..data = cloud;
    remote.revision = 1;
    final local = initial();
    local['accounts']!
        .single
        .addAll({'isDefault': 1, 'openingBalance': 0, 'currentBalance': 0});
    final db = MemoryDb(local);
    await DeviceSyncService(remote: remote, database: db).sync('owner');
    expect(db.data['accounts']!.single['currentBalance'], 100);
    expect(remote.revision, 1);
  });
  test('concurrent jar reservations cannot over-reserve an account', () {
    final base = initial();
    base['treasure_jars']!.add({
      'id': 'jar',
      'name': 'Trip',
      'accountId': 'bank',
      'targetCents': 100000,
      'savedCents': 0,
      'deadline': null
    });
    final a = copy(base), b = copy(base);
    for (final pair in [(a, 'a'), (b, 'b')]) {
      pair.$1['jar_activity']!.add({
        'id': pair.$2,
        'jarId': 'jar',
        'amountCents': 8000,
        'date': '2026-10-27'
      });
      pair.$1['treasure_jars']!.single['savedCents'] = 8000;
    }
    expect(() => mergeSyncData(base, a, b), throwsA(isA<SyncConflict>()));
  });
  test('two devices add different expenses without losing an account debit',
      () {
    final base = initial(), phone = initial(), tablet = initial();
    spend(phone, 'phone', 10);
    spend(tablet, 'tablet', 20);
    final merged = mergeSyncData(base, phone, tablet);
    expect(merged['transactions']!.length, 2);
    expect(merged['accounts']!.single['currentBalance'], 70);
  });
  test('offline edits and remote deletions do not resurrect records', () {
    final base = initial();
    spend(base, 'old', 10);
    final phone = copy(base), tablet = copy(base);
    phone['transactions']!.clear();
    phone['accounts']!.single['currentBalance'] = 100;
    spend(tablet, 'new', 20);
    final merged = mergeSyncData(base, tablet, phone);
    expect(merged['transactions']!.single['id'], 'new');
    expect(merged['accounts']!.single['currentBalance'], 80);
  });
  test('same record edited differently and delete versus edit require review',
      () {
    final base = initial();
    spend(base, 'old', 10);
    final a = copy(base), b = copy(base);
    a['transactions']!.single['title'] = 'Phone edit';
    b['transactions']!.single['title'] = 'Tablet edit';
    expect(() => mergeSyncData(base, a, b), throwsA(isA<SyncConflict>()));
    b['transactions']!.clear();
    b['accounts']!.single['currentBalance'] = 100;
    expect(() => mergeSyncData(base, a, b), throwsA(isA<SyncConflict>()));
  });
  test('jar contributions from two devices merge using unique history IDs', () {
    final base = initial();
    base['treasure_jars']!.add({
      'id': 'jar',
      'name': 'Trip',
      'accountId': 'bank',
      'targetCents': 10000,
      'savedCents': 0,
      'deadline': null
    });
    final a = copy(base), b = copy(base);
    for (final pair in [(a, 'phone', 500), (b, 'tablet', 1000)]) {
      pair.$1['jar_activity']!.add({
        'id': pair.$2,
        'jarId': 'jar',
        'amountCents': pair.$3,
        'date': '2026-10-27'
      });
      pair.$1['treasure_jars']!.single['savedCents'] = pair.$3;
    }
    final result = mergeSyncData(base, a, b);
    expect(result['treasure_jars']!.single['savedCents'], 1500);
    expect(result['jar_activity']!.length, 2);
    expect(result['accounts']!.single['currentBalance'], 100);
  });
  test(
      'phone uploads, empty tablet restores, both exchange edits and deletions',
      () async {
    final remote = MemoryRemote();
    final phone = MemoryDb(initial());
    spend(phone.data, 'phone', 10);
    final tablet = MemoryDb({for (final t in syncTables) t: []});
    final p = DeviceSyncService(remote: remote, database: phone),
        t = DeviceSyncService(remote: remote, database: tablet);
    await p.sync('owner');
    await t.sync('owner');
    expect(sameSyncValue(phone.data, tablet.data), true);
    spend(phone.data, 'second', 20);
    spend(tablet.data, 'third', 5);
    await p.sync('owner');
    remote.race = true;
    await t.sync('owner');
    await p.sync('owner');
    expect(phone.data['accounts']!.single['currentBalance'], 65);
    expect(phone.data['transactions']!.length, 3);
    tablet.data['transactions']!.removeWhere((r) => r['id'] == 'phone');
    tablet.data['accounts']!.single['currentBalance'] = 75;
    await t.sync('owner');
    await p.sync('owner');
    expect(phone.data['transactions']!.any((r) => r['id'] == 'phone'), false);
    expect(phone.data['accounts']!.single['currentBalance'], 75);
    final rev = remote.revision;
    await p.sync('owner');
    expect(remote.revision, rev);
  });
  test('offline failure and wrong session never replace local records',
      () async {
    final db = MemoryDb(initial()), remote = MemoryRemote()..offline = true;
    final service = DeviceSyncService(remote: remote, database: db);
    await expectLater(service.sync('owner'), throwsStateError);
    expect(db.applies, 0);
    expect(db.data['accounts']!.single['currentBalance'], 100);
    remote.offline = false;
    remote.signedIn = false;
    await expectLater(service.sync('owner'), throwsA(anything));
    expect(db.applies, 0);
  });
  test('a local edit during the request is rebased and uploaded on retry',
      () async {
    final db = MemoryDb(initial()), remote = MemoryRemote();
    remote.beforeCommit = () => spend(db.data, 'during-upload', 15);
    await DeviceSyncService(remote: remote, database: db).sync('owner');
    expect(db.data['transactions']!.single['id'], 'during-upload');
    expect(remote.data!['accounts']!.single['currentBalance'], 85);
  });
  test('session switch during upload prevents importing another account',
      () async {
    final db = MemoryDb(initial()), remote = MemoryRemote();
    remote.beforeCommit = () => remote.signedIn = false;
    await expectLater(
        DeviceSyncService(remote: remote, database: db).sync('owner'),
        throwsA(anything));
    expect(db.applies, 0);
  });
}
