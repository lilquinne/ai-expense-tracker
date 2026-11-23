class ReceiptItemCleanup {
  static String? clean(String text) {
    var name = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final compact = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (RegExp(r'^(?:t[o0]ta[l1i]|[o0]ta[l1i]|ta[l1i]|subt[o0]ta[l1i]|grandtotal|nettotal|rounding|change|cash|bankcard|bankkard|payment|subtotal|tax|sst|gst|discount|balance|amountdue)\d*$')
            .hasMatch(compact) ||
        RegExp(r'^(?:item\s*#|receipt\b|invoice\b|approval\b|card\s*no|total\b|sub\s*total\b|rounding\b|payment\b)',
                caseSensitive: false)
            .hasMatch(name)) return null;
    name = name.replaceAll(RegExp(r'^\d{6,}\s+'), '');
    if (!RegExp(r'[A-Za-z]{3}').hasMatch(name)) return null;
    // Repair embedded digit/letter confusion only inside alphabetic words.
    name = name.replaceAll(RegExp(r'\b4(?=[A-Za-z]{2})'), 'A');
    name = name.replaceAllMapped(
        RegExp(r'([A-Za-z])4(?=[A-Za-z])'), (m) => '${m[1]}A');
    name = name.replaceAllMapped(
        RegExp(r'([A-Za-z])0(?=[A-Za-z])'), (m) => '${m[1]}O');
    if (name == name.toUpperCase()) {
      name = name
          .split(' ')
          .map((word) => word.isEmpty
              ? word
              : '${word[0]}${word.substring(1).toLowerCase()}')
          .join(' ');
    }
    return name;
  }
}
