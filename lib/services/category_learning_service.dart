import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';

/// Explicitly confirmed exact matches, kept on this device and scoped to user.
/// Receipt baskets are learned as a whole, never assigning every item the same category.
class CategoryLearningService {
  static String _user = '';
  static Map<String, String> _choices = {};
  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r"[’']"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  static String textKey(String text, TransactionType type) =>
      '${type.name}:${normalize(text)}';
  static String receiptKey(String? merchant, List<String> items) {
    final names = items.map(normalize).where((s) => s.isNotEmpty).toList()
      ..sort();
    return 'receipt:${normalize(merchant ?? '')}:${names.join('|')}';
  }

  static Future<void> load(String user) async {
    _user = user;
    _choices = {};
    final prefs = await SharedPreferences.getInstance();
    if (user != _user) return;
    try {
      final decoded =
          jsonDecode(prefs.getString('category_choices_$user') ?? '{}');
      if (decoded is Map) {
        _choices = decoded.map((key, value) => MapEntry('$key', '$value'));
      }
    } catch (_) {
      _choices = {};
    }
  }

  static TransactionCategory? lookup(String key, TransactionType type) {
    final name = _choices[key];
    for (final category in TransactionCategory.values) {
      if (category.name == name &&
          category.isIncomeCategory == (type == TransactionType.income)) {
        return category;
      }
    }
    return null;
  }

  static Future<void> remember(String key, TransactionCategory category) async {
    if (_user.isEmpty || key.endsWith(':')) return;
    _choices.remove(key);
    _choices[key] = category.name;
    while (_choices.length > 500) {
      _choices.remove(_choices.keys.first);
    }
    final user = _user;
    final encoded = jsonEncode(_choices);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('category_choices_$user', encoded);
  }
}
