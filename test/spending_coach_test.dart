import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/services/spending_coach_service.dart';
import 'package:expense_tracker/screens/spending_coach_screen.dart';
import 'package:expense_tracker/widgets/savings_plan_dialog.dart';
import 'package:expense_tracker/utils/app_theme.dart';

Map<String, dynamic> reply(
        {String answer = 'Your recorded expenses are RM 46.50.'}) =>
    {
      'answer': answer,
      'fallback': false,
      'suggestPlan': true,
      'goalHint': {'target': 500, 'months': 2},
      'evidence': {
        'selectedMonth': '2026-10',
        'metrics': {'expenses_0': 'RM 46.50'},
        'summary': {'income': 0, 'expenses': 46.5},
        'baseline': {'months': 0, 'salary': null, 'expenses': null}
      },
    };

class CoachExpenses extends ExpenseProvider {
  CoachExpenses() : super(initialize: false);
  String owner = 'person-a';
  @override
  String get userId => owner;
  @override
  DateTime get selectedMonth => DateTime(2026, 10);
  void changeOwner(String id) {
    owner = id;
    notifyListeners();
  }
}

void main() {
  test(
      'request carries bounded conversation and confirmed plan, not an owner ID',
      () async {
    Map<String, dynamic>? sent;
    final service = SpendingCoachService(request: (body) async {
      sent = body;
      return reply();
    });
    await service.ask(
        message: 'Help me save',
        month: DateTime(2026, 10),
        currency: 'RM',
        history: List.generate(14, (i) => {'role': 'user', 'content': '$i'}),
        plan: {'target': 500});
    expect(sent!['history'], hasLength(10));
    expect(sent!['month'], '2026-10');
    expect(sent!['plan'], {'target': 500});
    expect(sent!.containsKey('user_id'), isFalse);
  });

  test('malformed or timed-out responses become useful errors', () async {
    final invalid =
        SpendingCoachService(request: (_) async => {'answer': 'bad'});
    expect(
        () => invalid.ask(
            message: 'Help', month: DateTime(2026, 10), currency: 'RM'),
        throwsA(isA<CoachException>()));
    final slow = SpendingCoachService(
        request: (_) => Completer<dynamic>().future,
        timeout: const Duration(milliseconds: 1));
    expect(
        () => slow.ask(
            message: 'Help', month: DateTime(2026, 10), currency: 'RM'),
        throwsA(isA<CoachException>()));
  });

  testWidgets('chat sends, shows evidence and clears the session',
      (tester) async {
    final provider = CoachExpenses();
    addTearDown(provider.dispose);
    var calls = 0;
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: SpendingCoachScreen(
                sessionCheck: (_) => true,
                prepare: (_) async {},
                service: SpendingCoachService(request: (_) async {
                  calls++;
                  return reply(
                      answer: '**Your recorded expenses are RM 46.50.**');
                })))));
    await tester.tap(find.text('Where does most of my money go?'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Your recorded expenses are RM 46.50.'), findsOneWidget);
    final answer = tester.widget<SelectableText>(find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText() ==
                'Your recorded expenses are RM 46.50.'));
    expect(
        answer.textSpan!.children!
            .whereType<TextSpan>()
            .any((span) => span.style?.fontWeight == FontWeight.w700),
        isTrue);
    expect(answer.textSpan!.toPlainText(), isNot(contains('**')));
    expect(find.text('Numbers used'), findsOneWidget);
    await tester.tap(find.byTooltip('New chat'));
    await tester.pumpAndSettle();
    expect(find.text('Your recorded expenses are RM 46.50.'), findsNothing);
    expect(find.text('Make room for your goals'), findsOneWidget);
  });

  testWidgets('switching users discards a pending answer and conversation',
      (tester) async {
    final provider = CoachExpenses();
    addTearDown(provider.dispose);
    final completion = Completer<dynamic>();
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            home: SpendingCoachScreen(
                sessionCheck: (_) => true,
                prepare: (_) async {},
                service:
                    SpendingCoachService(request: (_) => completion.future)))));
    await tester.tap(find.text('Where does most of my money go?'));
    await tester.pumpAndSettle();

    provider.changeOwner('person-b');
    await tester.pump();
    completion.complete(reply(answer: 'Private previous account answer'));
    await tester.pumpAndSettle();
    expect(find.text('Private previous account answer'), findsNothing);
    expect(find.text('Make room for your goals'), findsOneWidget);
  });

  testWidgets('signed-out chat does not invoke the service', (tester) async {
    final provider = CoachExpenses();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            home: SpendingCoachScreen(
                sessionCheck: (_) => false,
                service: SpendingCoachService(
                    request: (_) async => throw StateError('Must not run'))))));
    expect(find.text('Sign in to chat about your spending'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
      'local answer bypasses sync and AI even when both are unavailable',
      (tester) async {
    final provider = CoachExpenses();
    addTearDown(provider.dispose);
    var reads = 0;
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            home: SpendingCoachScreen(
                sessionCheck: (_) => true,
                prepare: (_) async => throw StateError('Must not sync'),
                service: SpendingCoachService(
                    request: (_) async => throw StateError('Must not call AI'),
                    localAnswer: (owner, question, month, currency) async {
                      reads++;
                      expect(owner, 'person-a');
                      return {
                        ...reply(
                            answer:
                                'RM 20.00 remaining in your recorded budget.'),
                        'suggestPlan': false,
                        'evidence': {
                          'source': 'local',
                          'selectedMonth': '2026-10',
                          'metrics': {'budget_food': 'RM 20.00'},
                          'summary': {}
                        }
                      };
                    })))));
    await tester.tap(find.text('How much budget is remaining?'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('RM 20.00 remaining in your recorded budget.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan requires estimates and protects essential expenses',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const SavingsPlanDialog(
                            currency: 'RM',
                            hint: {'target': 500, 'months': 2})),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check plan'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid amount'), findsWidgets);
    for (final entry in {
      'income': '3000',
      'expenses': '2000',
      'essentials': '2500',
      'buffer': '100'
    }.entries) {
      final field = find.byKey(ValueKey('plan-${entry.key}'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '${entry.value}.00');
    }
    await tester.tap(find.text('Check plan'));
    await tester.pumpAndSettle();
    expect(find.text('Cannot exceed total monthly expenses'), findsOneWidget);
  });
}
