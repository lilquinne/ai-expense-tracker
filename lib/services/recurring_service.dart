import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import '../models/transaction_model.dart';

class RecurringOccurrence {
  RecurringOccurrence(this.template, this.date, String owner)
      : id = const Uuid().v5(Uuid.NAMESPACE_URL,
            'spendly:recurring:$owner:${template.id}:${date.toIso8601String()}');
  final TransactionModel template;
  final DateTime date;
  final String id;

  TransactionModel transaction() => TransactionModel(
      id: id,
      title: template.title,
      amount: template.amount,
      type: template.type,
      category: template.category,
      categoryId: template.categoryId,
      accountId: template.accountId,
      date: date,
      note: template.note);
}

class RecurringService {
  static DateTime? dateAt(TransactionModel t, int index) {
    final d = t.date;
    switch (t.recurringFrequency) {
      case 'daily':
        return DateTime(d.year, d.month, d.day + index);
      case 'weekly':
        return DateTime(d.year, d.month, d.day + index * 7);
      case 'monthly':
        final month = DateTime(d.year, d.month + index);
        return DateTime(month.year, month.month,
            math.min(d.day, DateTime(month.year, month.month + 1, 0).day));
      case 'yearly':
        final year = d.year + index;
        return DateTime(
            year, d.month, math.min(d.day, DateTime(year, d.month + 1, 0).day));
      default:
        return null;
    }
  }

  static List<RecurringOccurrence> due(
      String owner, List<TransactionModel> records, DateTime now,
      {int futureCount = 0}) {
    if (owner.isEmpty) return [];
    final end = DateTime(now.year, now.month, now.day + 1);
    final existing = records.map((t) => t.id).toSet();
    final result = <RecurringOccurrence>[];
    for (final t in records.where((t) => t.isRecurring)) {
      var future = 0;
      for (var i = 1;; i++) {
        final date = dateAt(t, i);
        if (date == null) break;
        if (!date.isBefore(end) && ++future > futureCount) break;
        final occurrence = RecurringOccurrence(t, date, owner);
        if (!existing.contains(occurrence.id)) result.add(occurrence);
      }
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }
}
