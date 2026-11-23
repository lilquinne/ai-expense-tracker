import 'package:expense_tracker/utils/category_icons.dart';
import 'package:expense_tracker/utils/app_theme.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/screens/add_transaction_screen.dart';
import 'package:expense_tracker/screens/budget_screen.dart';
import 'package:expense_tracker/screens/home_screen.dart';
import 'package:expense_tracker/widgets/amount_keypad.dart';

class CompactProvider extends ExpenseProvider {
  CompactProvider({this.withBudget = false}) : super(initialize: false);
  final bool withBudget;
  @override
  List<BudgetModel> get budgets => withBudget
      ? [
          BudgetModel(
              id: 'b',
              category: TransactionCategory.food,
              limit: 100,
              month: DateTime.now())
        ]
      : [];
  @override
  Future<void> loadData() async {}
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final font = FontLoader('Sora')
      ..addFont(rootBundle.load('assets/fonts/Sora-Regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets(
      'keypad enters cents and supports plus/minus and empty operand',
      (tester) async {
    final controller = TextEditingController();
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AmountKeypad(
                controller: controller,
                onDone: () => saves++,
                onDate: () {},
                toolbar: const SizedBox.shrink()))));
    Future<void> key(String value) async {
      await tester.tap(find.text(value));
      await tester.pump();
    }

    for (final value in ['1', '2', '3']) {
      await key(value);
    }
    expect(controller.text, '1.23');
    await key('+');
    await key('2');
    await key('00');
    await key('=');
    expect(controller.text, '3.23');
    expect(saves, 0);
    await key('Done');
    expect(saves, 1);
    await key('−');
    await key('1');
    await key('00');
    await key('=');
    expect(controller.text, '2.23');
    await key('+');
    await key('=');
    expect(controller.text, '2.23');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets('full calculation remains visible and equals does not save',
      (tester) async {
    final provider = CompactProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme, home: const AddTransactionScreen())));
    await tester.pumpAndSettle();
    for (final key in ['3', '00', '+', '5', '1', '0', '+', '1', '0', '00']) {
      await tester.tap(find.text(key));
      await tester.pump();
    }
    expect(find.text('3.00 + 5.10 + 10.00'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(
                find.byWidgetPredicate((w) => w is TextField && w.readOnly))
            .controller!
            .text,
        '18.10');
    await tester.tap(find.text('='));
    await tester.pump();
    expect(find.text('3.00 + 5.10 + 10.00 = 18.10'), findsOneWidget);
    final note = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Add a note…');
    await tester.tap(note);
    await tester.enterText(note, 'Lunch with friends');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Lunch with friends'), findsOneWidget);
    expect(tester.testTextInput.isVisible, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'compact entry has four-column favourites, a keypad and date sheet',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = CompactProvider();
    addTearDown(provider.dispose);
    final capture = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: RepaintBoundary(
                key: capture, child: const AddTransactionScreen()))));
    await tester.pumpAndSettle();
    final food = tester
        .getTopLeft(find.byIcon(categoryIcon(TransactionCategory.food)).first);
    final entertainment = tester.getTopLeft(
        find.byIcon(categoryIcon(TransactionCategory.shopping)).first);
    expect(food.dy, entertainment.dy);
    expect(find.byType(AmountKeypad), findsOneWidget);
    await tester.tap(find.text('7'));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(
                find.byWidgetPredicate((w) => w is TextField && w.readOnly))
            .controller!
            .text,
        '0.07');
    await tester.tap(find.byTooltip('Date'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await Directory('tmp/ui').create(recursive: true);
      await File('tmp/ui/compact-entry.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  });
  testWidgets(
      'budget page lists only added budgets with one top-bar add action',
      (tester) async {
    final provider = CompactProvider(withBudget: true);
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme, home: const BudgetScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.text('Transport'), findsNothing);
    expect(find.text('Groceries'), findsNothing);
    expect(find.byTooltip('Add budget'), findsOneWidget);
    expect(find.text('Add Budget'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'more tools fits a small phone as a centered grid with budget tracker',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = CompactProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child:
            MaterialApp(theme: AppTheme.darkTheme, home: const HomeScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Coming later'), findsOneWidget);
    expect(find.text('Budget Tracker'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Budget Tracker')).dy,
        tester.getTopLeft(find.text('Split bills')).dy);
    expect(tester.takeException(), isNull);
  });
}
