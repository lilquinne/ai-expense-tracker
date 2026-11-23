import 'local_coach_service.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_service.dart';
import 'supabase_sync_service.dart';

typedef CoachRequest = Future<dynamic> Function(Map<String, dynamic> body);

class CoachException implements Exception {
  const CoachException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CoachReply {
  CoachReply(
      {required this.answer,
      required this.evidence,
      required this.fallback,
      required this.suggestPlan,
      this.goalHint});
  final String answer;
  final Map<String, dynamic> evidence;
  final bool fallback;
  final bool suggestPlan;
  final Map<String, dynamic>? goalHint;
  static CoachReply parse(dynamic data) {
    if (data is! Map ||
        data['answer'] is! String ||
        (data['answer'] as String).isEmpty ||
        (data['answer'] as String).length > 6000 ||
        data['evidence'] is! Map ||
        data['fallback'] is! bool ||
        data['suggestPlan'] is! bool) {
      throw const FormatException('Invalid coach response');
    }
    final evidence = Map<String, dynamic>.from(data['evidence']);
    if (evidence['metrics'] is! Map ||
        evidence['summary'] is! Map ||
        evidence['selectedMonth'] is! String) {
      throw const FormatException('Invalid evidence');
    }
    return CoachReply(
        answer: data['answer'],
        evidence: evidence,
        fallback: data['fallback'],
        suggestPlan: data['suggestPlan'],
        goalHint: data['goalHint'] is Map
            ? Map<String, dynamic>.from(data['goalHint'])
            : null);
  }
}

class SpendingCoachService {
  SpendingCoachService(
      {CoachRequest? request,
      this.timeout = const Duration(seconds: 65),
      Future<Map<String, dynamic>?> Function(String, String, DateTime, String)?
          localAnswer})
      : _request = request ?? _invoke,
        _localAnswer =
            localAnswer ?? (request == null ? LocalCoachService.answer : null);
  final Future<Map<String, dynamic>?> Function(
      String, String, DateTime, String)? _localAnswer;
  Future<CoachReply?> askLocal(
      {required String owner,
      required String message,
      required DateTime month,
      required String currency}) async {
    if (message.trim().isEmpty || message.length > 1600) return null;
    final result = await _localAnswer?.call(owner, message, month, currency);
    return result == null ? null : CoachReply.parse(result);
  }

  final CoachRequest _request;
  final Duration timeout;

  static Future<dynamic> _invoke(Map<String, dynamic> body) async {
    final client = Supabase.instance.client;
    final owner = client.auth.currentUser?.id;
    if (owner == null || client.auth.currentSession == null) {
      throw const AuthException('Sign in to use Coach.');
    }
    final response =
        await client.functions.invoke('spending-coach', body: body);
    if (client.auth.currentUser?.id != owner)
      throw const AuthException('Account changed.');
    if (response.status != 200)
      throw const CoachException('Coach is unavailable. Please try again.');
    return response.data;
  }

  static bool ownsSession(String owner) =>
      SupabaseSyncService.instance.ownsSession(owner);

  static Future<void> prepare(String owner, {DateTime? month}) async {
    if (!ownsSession(owner))
      throw const CoachException(
          'Sign in to your online account to use Coach.');
    try {
      final db = DatabaseService();
      final selected = month ?? DateTime.now();
      final start = DateTime(selected.year, selected.month - 5);
      final end = DateTime(selected.year, selected.month + 1);
      final transactions = (await db.getAllTransactions(userId: owner))
          .where((t) => !t.date.isBefore(start) && t.date.isBefore(end))
          .toList();
      final categories = await db.getCategories(userId: owner);
      await SupabaseSyncService.instance
          .syncForCoach(
              userId: owner, transactions: transactions, categories: categories)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const CoachException(
          'Could not sync your records. Check your connection and try again.');
    }
  }

  Future<CoachReply> ask(
      {required String message,
      required DateTime month,
      required String currency,
      List<Map<String, String>> history = const [],
      Map<String, dynamic>? plan}) async {
    if (message.trim().isEmpty || message.length > 1600) {
      throw const CoachException('Write a question of up to 1,600 characters.');
    }
    try {
      final data = await _request({
        'ai_consent': true,
        'message': message.trim(),
        'month': DateFormat('yyyy-MM').format(month),
        'currency': currency,
        'history': history.length > 10
            ? history.sublist(history.length - 10)
            : history,
        if (plan != null) 'plan': plan,
      }).timeout(timeout);
      return CoachReply.parse(data);
    } on AuthException {
      throw const CoachException(
          'Sign in to your online account to use Coach.');
    } on FunctionException catch (e) {
      throw CoachException(switch (e.status) {
        401 || 403 => 'Your session expired. Please sign in again.',
        429 => 'Your daily AI allowance is used up. Try again tomorrow.',
        422 => 'This period has too many records for Coach. Contact support.',
        _ => 'Coach could not load your records. Please try again.',
      });
    } on TimeoutException {
      throw const CoachException('Coach took too long. Please try again.');
    } on CoachException {
      rethrow;
    } catch (_) {
      throw const CoachException(
          'Coach is unavailable. Check your connection and try again.');
    }
  }
}
