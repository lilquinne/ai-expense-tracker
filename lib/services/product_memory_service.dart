import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';

class ProductMemoryService {
  static String normalize(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  static Future<List<Map<String, dynamic>>> _read(String owner) async {
    if (owner.isEmpty) return [];
    final raw = (await SharedPreferences.getInstance())
        .getString('product_memory_v1:$owner');
    try {
      return raw == null
          ? []
          : (jsonDecode(raw) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> hasVisualMemory(String owner) async =>
      (await _read(owner))
          .any((r) => r['confirmed'] == true && r['hash'] is String);

  static Future<Map<String, dynamic>?> find(String owner,
      {String? hash, String? name, String labelText = ''}) async {
    for (final row in (await _read(owner)).reversed) {
      if (name != null &&
          row['confirmed'] == true &&
          row['key'] == normalize(name)) return row;
      final saved = row['hash'];
      if (hash == null || saved is! String || saved.length != hash.length)
        continue;
      var difference = 0;
      for (var i = 0; i < hash.length; i++) {
        if (hash[i] != saved[i]) difference++;
      }

      final words = normalize(row['name'] as String)
          .split(' ')
          .where((w) => w.length > 3)
          .toSet();
      final label = normalize(labelText);
      if (row['confirmed'] == true &&
          difference <= 2 &&
          words.length >= (difference == 0 ? 1 : 2) &&
          words.every(label.contains)) return row;
    }
    return null;
  }

  static Future<void> remember(
      String owner, String name, TransactionCategory category,
      {String? hash, bool confirmed = true}) async {
    if (owner.isEmpty || normalize(name).isEmpty) return;
    final records = await _read(owner);
    final key = normalize(name);
    final previous = records.where((r) => r['key'] == key).firstOrNull;
    records.removeWhere((r) => r['key'] == key);
    records.add({
      'key': key,
      'name': name,
      'category': category.name,
      'hash': hash ?? previous?['hash'],
      'confirmed': confirmed || previous?['confirmed'] == true
    });
    if (records.length > 100) records.removeRange(0, records.length - 100);
    await (await SharedPreferences.getInstance())
        .setString('product_memory_v1:$owner', jsonEncode(records));
  }
}
