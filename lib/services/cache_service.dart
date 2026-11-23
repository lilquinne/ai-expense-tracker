import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

class CacheService {
  static Future<int> clear() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    final root = await getTemporaryDirectory();
    var bytes = 0;
    // Only our generated scratch folders; never camera files or saved receipts.
    await for (final entry in root.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entry is! Directory ||
          !(name.startsWith('receipt-ocr-') ||
              RegExp(r'^reports_\d+$').hasMatch(name))) continue;
      final stat = await entry.stat();
      if (DateTime.now().difference(stat.modified) < const Duration(days: 1))
        continue;
      await for (final file
          in entry.list(recursive: true, followLinks: false)) {
        if (file is File) bytes += await file.length();
      }
      await entry.delete(recursive: true);
    }
    return bytes;
  }
}
