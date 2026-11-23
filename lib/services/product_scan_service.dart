import 'product_memory_service.dart';
import 'ai_categorization_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/transaction_model.dart';

class ProductSuggestion {
  const ProductSuggestion(this.name, this.category);
  final String name;
  final TransactionCategory category;
  static ProductSuggestion parse(dynamic data) {
    if (data is! Map ||
        data['is_product'] != true ||
        data['name'] is! String ||
        (data['name'] as String).trim().isEmpty ||
        (data['name'] as String).length > 120) {
      throw const FormatException(
          'No clear product found. Retake a photo of one product.');
    }
    final category = TransactionCategory.values
        .where((c) => !c.isIncomeCategory && c.name == data['category'])
        .firstOrNull;
    final name = (data['name'] as String).trim();
    final local = category == null || category == TransactionCategory.other
        ? AiCategorizationService.categorize(name, TransactionType.expense)
        : null;
    return ProductSuggestion(
        name,
        local != null && local.confidence >= .6
            ? local.category
            : category ?? TransactionCategory.other);
  }
}

String _encodeProduct(img.Image image) {
  final resized = image.width > 1280 || image.height > 1280
      ? img.copyResize(image,
          width: image.width >= image.height ? 1280 : null,
          height: image.height > image.width ? 1280 : null)
      : image;
  return base64Encode(img.encodeJpg(resized, quality: 80));
}

String _fingerprint(img.Image source) {
  final image = img.copyResize(source, width: 9, height: 8);
  final bits = StringBuffer();
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      final a = image.getPixel(x, y), b = image.getPixel(x + 1, y);
      bits.write((a.r + a.g + a.b) > (b.r + b.g + b.b) ? '1' : '0');
    }
  }
  return bits.toString();
}

img.Image _decodeProduct(Uint8List bytes) {
  try {
    final image = img.decodeImage(bytes);
    if (image != null) return img.bakeOrientation(image);
  } catch (_) {
    // Image decoders may throw for truncated files as well as returning null.
  }
  throw const FormatException('Could not open this photo.');
}

String prepareProductPhoto(Uint8List bytes) =>
    _encodeProduct(_decodeProduct(bytes));
String productFingerprint(Uint8List bytes) =>
    _fingerprint(_decodeProduct(bytes));

/// Decode and orient only once for both the upload and recognition memory.
Map<String, String> prepareProductScan(Uint8List bytes) {
  final image = _decodeProduct(bytes);
  return {'image': _encodeProduct(image), 'hash': _fingerprint(image)};
}

class ProductScanService {
  Future<ProductSuggestion> identify(File photo,
      {String labelText = '', Future<String> Function()? readLabel}) async {
    final client = Supabase.instance.client;
    final owner = client.auth.currentUser?.id;
    if (owner == null)
      throw const AuthException('Sign in to identify products.');
    final bytes = await photo.readAsBytes();
    final preparedFuture = compute(prepareProductScan, bytes);
    // A first-time product cannot match memory, so skip label OCR entirely.
    final needsLabel =
        readLabel != null && await ProductMemoryService.hasVisualMemory(owner);
    final labelFuture = needsLabel
        ? readLabel().catchError((Object _) => '')
        : Future<String>.value(labelText);
    final prepared = await preparedFuture;
    final label = await labelFuture;
    if (client.auth.currentUser?.id != owner)
      throw const AuthException('Account changed. Please reopen the scanner.');
    final hash = prepared['hash']!;
    final remembered =
        await ProductMemoryService.find(owner, hash: hash, labelText: label);
    if (remembered != null)
      return ProductSuggestion.parse({'is_product': true, ...remembered});
    final image = prepared['image']!;
    final response = await client.functions.invoke('identify-product', body: {
      'ai_consent': true,
      'image': image
    }).timeout(const Duration(seconds: 40));
    if (client.auth.currentUser?.id != owner)
      throw const AuthException('Account changed. Please reopen the scanner.');
    final suggestion = ProductSuggestion.parse(response.data);
    final memory =
        await ProductMemoryService.find(owner, name: suggestion.name);
    final result = memory == null
        ? suggestion
        : ProductSuggestion.parse({'is_product': true, ...memory});
    await ProductMemoryService.remember(owner, result.name, result.category,
        hash: hash, confirmed: false);
    return result;
  }
}
