import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/models/treasure_jar.dart';
import 'package:expense_tracker/services/local_coach_service.dart';
import 'package:expense_tracker/services/spending_coach_service.dart';
import 'package:expense_tracker/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final month = DateTime(2026, 10), now = DateTime(2026, 10, 15);
  TransactionModel expense(String id, double amount, DateTime date) =>
      TransactionModel(
          id: id,
          title: id,
          amount: amount,
          date: date,
          type: TransactionType.expense,
          category: TransactionCategory.groceries);
  final rows = [
    expense('food', 15, DateTime(2026, 10, 1)),
    expense('future', 200, DateTime(2026, 10, 25))
  ];
  test(
      'local budget calculations preserve confirmed total and exclude future entries',
      () {
    final response = CoachReply.parse(LocalCoachService.calculate(
        LocalCoachIntent.budget,
        message: 'groceries budget',
        month: month,
        asOf: now,
        currency: 'RM',
        records: rows,
        budgets: [
          BudgetModel(
              id: 'b',
              category: TransactionCategory.groceries,
              limit: 10,
              month: month)
        ]));
    expect(response.answer, contains('RM 5.00 over budget'));
    expect(response.evidence['metrics']['expenses_0'], 'RM 15.00');
    expect(response.evidence['source'], 'local');
    expect(response.fallback, isFalse);
  });
  test('jar progress is a reservation, not actual funds or a new transaction',
      () {
    final response = LocalCoachService.calculate(LocalCoachIntent.jars,
        message: 'my jars',
        month: month,
        asOf: now,
        currency: 'RM',
        jars: [
          const TreasureJar(
              id: 'j',
              name: 'Holiday',
              accountId: 'a',
              targetCents: 10000,
              savedCents: 2500)
        ]);
    expect(response['answer'], contains('RM 75.00 remaining'));
    expect(response['answer'], contains('do not add money to your bank'));
  });
  test('future/sparse periods do not invent predictions or comparisons', () {
    for (final kind in [LocalCoachIntent.pace, LocalCoachIntent.comparison]) {
      final response = LocalCoachService.calculate(kind,
          message: 'compare',
          month: month,
          asOf: now,
          currency: 'RM',
          records: rows);
      expect(response['answer'], contains('I need'));
    }
    expect(
        LocalCoachService.calculate(LocalCoachIntent.pace,
            message: 'pace',
            month: DateTime(2026, 11),
            asOf: now,
            currency: 'RM')['answer'],
        contains('has not started'));
  });
  test(
      'routing leaves contextual advice, explicit other periods and unsupported questions remote',
      () {
    for (final q in [
      'Why did my budget increase?',
      'Can I afford a holiday?',
      'budget next month',
      'budget September',
      'budget last month',
      'hello'
    ]) {
      expect(LocalCoachService.intent(q), isNull, reason: q);
    }
    expect(LocalCoachService.intent('How much budget is remaining?'),
        LocalCoachIntent.budget);
    expect(LocalCoachService.intent('How are my jars progressing?'),
        LocalCoachIntent.jars);
  });
  test(
      'database retrieval is owner scoped and only uses current actual records',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final folder =
        await Directory.systemTemp.createTemp('spendly-local-coach-');
    await databaseFactory.setDatabasesPath(folder.path);
    final service = DatabaseService();
    final db = await service.database;
    try {
      await service.insertTransaction(expense('mine', 15, month),
          userId: 'mine');
      await service.insertTransaction(expense('private', 999, month),
          userId: 'other');
      await service.upsertBudget(
          BudgetModel(
              id: 'mine-budget',
              category: TransactionCategory.groceries,
              limit: 20,
              month: month),
          userId: 'mine');
      await service.upsertBudget(
          BudgetModel(
              id: 'other-budget',
              category: TransactionCategory.groceries,
              limit: 9999,
              month: month),
          userId: 'other');
      final result = await LocalCoachService.answer(
          'mine', 'budget remaining', month, 'RM',
          asOf: now);
      expect(result!['answer'], contains('RM 5.00 remaining'));
      expect(result['answer'], isNot(contains('999')));
    } finally {
      await db.close();
      if (folder.path.startsWith(Directory.systemTemp.path))
        await folder.delete(recursive: true);
    }
  });
}
