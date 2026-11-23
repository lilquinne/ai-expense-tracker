import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Conservative local brand matching plus corrections explicitly saved by a user.
class MerchantService {
  static String _user = '';
  static Map<String, String> _saved = {};
  static const _brands = [
    'Borneo Mart',
    'Bataras',
    'Ninso',
    'Jaya Grocer',
    'MR DIY',
    'Watsons',
    'Guardian',
    'KKV',
    'Lotus\'s',
    '99 Speedmart',
    'AEON',
    'Giant',
    'Eco-Shop'
  ];
  static String _key(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Future<void> load(String user) async {
    _user = user;
    _saved = {};
    final prefs = await SharedPreferences.getInstance();
    if (_user != user) return;
    try {
      final data = jsonDecode(prefs.getString('merchant_names_$user') ?? '{}');
      if (data is Map) _saved = data.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      _saved = {};
    }
  }

  static Future<void> remember(String? detected, String corrected) async {
    if (_user.isEmpty || corrected.trim().isEmpty) return;
    final user = _user;
    final name = corrected.trim();
    _saved[_key(name)] = name;
    if (detected != null && _key(detected).isNotEmpty) {
      _saved[_key(detected)] = name;
    }
    while (_saved.length > 500) {
      _saved.remove(_saved.keys.first);
    }
    final value = jsonEncode(_saved);
    await (await SharedPreferences.getInstance())
        .setString('merchant_names_$user', value);
  }

  static void includeSavedShops(Iterable<String> shops) {
    for (final shop in shops.take(500)) {
      final name = canonicalize(shop);
      if (name != null) _saved.putIfAbsent(_key(name), () => name);
    }
  }

  static String? canonicalize(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final key = _key(text);
    if (_saved.containsKey(key)) return _saved[key];
    final tokens = text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final names = {
      ..._saved.values,
      ..._brands.where(
          (brand) => !_saved.values.any((saved) => _key(saved) == _key(brand)))
    };
    final matches = <String>{};
    for (final name in names) {
      final target = _key(name);
      if (key == target ||
          tokens.contains(target) ||
          (target.length >= 6 && tokens.any((t) => _oneEdit(t, target)))) {
        matches.add(name);
      } else if (_key(name) == 'bataras' &&
          tokens.any((t) =>
              ['erbataras', 'erataras', 'ataras', 'batanas'].contains(t))) {
        matches.add(name);
      } else if (name.contains(' ') &&
          text.toLowerCase().contains(name.toLowerCase())) {
        matches.add(name);
      } else if (target.length >= 6 && name.contains(' ')) {
        final count = name.split(RegExp(r'\s+')).length;
        for (var i = 0; i + count <= tokens.length; i++) {
          if (_oneEdit(tokens.sublist(i, i + count).join(), target)) {
            matches.add(name);
          }
        }
      }
    }
    return matches.length == 1 ? matches.single : text.trim();
  }

  static bool _oneEdit(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length >= b.length) i++;
      if (b.length >= a.length) j++;
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }
}
