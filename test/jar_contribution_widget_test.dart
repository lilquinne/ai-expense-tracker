import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:expense_tracker/models/treasure_jar.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/screens/treasure_jar_screen.dart';

class JarProvider extends ExpenseProvider {
  JarProvider() : super(initialize: false);
  bool deleted = false;
  @override
  Future<void> deleteJar(String id) async {
    deleted = true;
    notifyListeners();
  }

  @override
  List<TreasureJar> get jars => deleted
      ? []
      : [
          TreasureJar(
              id: 'goal',
              name: 'Holiday',
              accountId: AppAccount.defaults.first.id,
              targetCents: 10000,
              savedCents: 0,
              deadline: DateTime.now().add(const Duration(days: 30)))
        ];
  @override
  Future<void> adjustJar(String id, int cents) async =>
      throw StateError('Viewing must not reserve money');
}

void main() {
  testWidgets('swiping reveals delete and cancellation keeps jar',
      (tester) async {
    final provider = JarProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider, child: const MaterialApp(home: TreasureJarScreen())));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Holiday'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete jar?'), findsOneWidget);
    expect(find.textContaining('Released money will return to Total Balance'),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(provider.deleted, false);
    await tester.drag(find.text('Holiday'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(provider.deleted, true);
    expect(find.text('Holiday'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'contribution guidance wraps on a narrow screen without changing savings',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = JarProvider();
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider, child: const MaterialApp(home: TreasureJarScreen())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Starting today:'), findsNothing);
    expect(find.text('How jars work'), findsNothing);
    await tester.tap(find.byTooltip('How jars work'));
    await tester.pumpAndSettle();
    expect(find.text('How jars work'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details & history'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('Starting today:'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Stop when the target is reached'), findsOneWidget);
    expect(provider.jars.single.savedCents, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
}
