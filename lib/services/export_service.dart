// lib/services/export_service.dart
// Generates CSV export of all transactions

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';

class ExportService {
  /// Export transactions to CSV file
  static Future<String> exportToCsv(
    List<TransactionModel> transactions,
    String currencySymbol, {
    List<AppCategory> categories = const [],
    List<AppAccount> accounts = const [],
    DateTime? month,
  }) async {
    final buffer = StringBuffer();

    // Header
    buffer.writeln(
        'Date,Title,Type,Category,Account,Amount ($currencySymbol),Note');

    // Rows
    for (final t in transactions) {
      final date = DateFormat('yyyy-MM-dd').format(t.date);
      final type = t.type == TransactionType.income ? 'Income' : 'Expense';
      final amount = t.type == TransactionType.expense
          ? '-${t.amount.toStringAsFixed(2)}'
          : t.amount.toStringAsFixed(2);
      final note = (t.note ?? '').replaceAll(',', ';');
      final title = t.title.replaceAll(',', ';');
      final categoryName = _categoryName(t, categories).replaceAll(',', ';');
      final accountName = _accountName(t, accounts).replaceAll(',', ';');

      buffer.writeln(
          '$date,$title,$type,$categoryName,$accountName,$amount,$note');
    }

    // Save to Downloads when available; fall back to app documents.
    final dir = await _exportDirectory();
    final monthPart = month != null
        ? DateFormat('yyyyMM').format(month)
        : DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'spendly_report_$monthPart.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buffer.toString());

    return file.path;
  }

  static String _categoryName(
      TransactionModel transaction, List<AppCategory> categories) {
    for (final category in categories) {
      if (category.id == transaction.categoryId) return category.name;
    }
    return transaction.category.label;
  }

  static String _accountName(
      TransactionModel transaction, List<AppAccount> accounts) {
    for (final account in accounts) {
      if (account.id == transaction.accountId) return account.name;
    }
    return 'Cash';
  }

  static Future<Directory> _exportDirectory() async {
    Directory? downloads;
    try {
      downloads = await getDownloadsDirectory();
    } catch (_) {
      downloads = null;
    }
    if (downloads != null) return downloads;
    return getApplicationDocumentsDirectory();
  }
}
