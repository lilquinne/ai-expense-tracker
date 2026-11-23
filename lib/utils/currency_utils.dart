// lib/utils/currency_utils.dart

class CurrencyUtils {
  static String format(double amount, String symbol) {
    final isNegative = amount < 0;
    final abs = amount.abs();
    final formatted = abs.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '${isNegative ? '-' : ''}$symbol $formatted';
  }

  static String compact(double amount, String symbol) {
    if (amount >= 1000000) {
      return '$symbol ${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '$symbol ${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '$symbol ${amount.toStringAsFixed(2)}';
  }
}
