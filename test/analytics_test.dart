import 'package:expense_tracker/widgets/category_doughnut_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/screens/analytics_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/monthly_analysis.dart';
import 'package:expense_tracker/models/analytics_period.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/services/analytics_report_service.dart';
import 'package:expense_tracker/models/report_selection.dart';
import 'package:expense_tracker/widgets/report_export_sheet.dart';
import 'package:expense_tracker/widgets/spending_calendar.dart';
import 'package:expense_tracker/utils/app_theme.dart';

TransactionModel transaction(String name, double amount, DateTime date,
        {bool income = false}) =>
    TransactionModel(
        id: name,
        title: name,
        amount: amount,
        type: income ? TransactionType.income : TransactionType.expense,
        category:
            income ? TransactionCategory.salary : TransactionCategory.groceries,
        date: date);

class TestPicker extends FilePicker {
  String? destination;
  Uint8List? received;
  @override
  Future<String?> saveFile(
      {String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Uint8List? bytes,
      bool lockParentWindow = false}) async {
    received = bytes;
    return destination;
  }
}

class AnalyticsExpenses extends ExpenseProvider {
  AnalyticsExpenses(this.records) : super(initialize: false);
  final List<TransactionModel> records;
  DateTime month = DateTime(2026, 10);
  @override
  List<TransactionModel> get transactions => records;
  @override
  List<TransactionModel> get allTransactions => records;
  @override
  DateTime get selectedMonth => month;
  @override
  void setSelectedMonth(DateTime value) {
    month = value;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final month = DateTime(2026, 10);
  final sample = [
    transaction('Salary', 10000, DateTime(2026, 10, 9), income: true),
    transaction('Bataras', 46.5, DateTime(2026, 10, 13)),
    transaction('Weekly groceries', 100, DateTime(2026, 10, 9)),
    transaction('Outside month', 999, DateTime(2026, 9, 30))
  ];

  testWidgets(
      'analytics fits a narrow phone, navigates months and offers exports',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('Sora')
      ..addFont(rootBundle.load('assets/fonts/Sora-Regular.ttf'));
    await font.load();
    final provider = AnalyticsExpenses(sample);
    addTearDown(provider.dispose);
    final capture = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: RepaintBoundary(
                key: capture, child: const AnalyticsScreen()))));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await Directory('tmp/pdfs').create(recursive: true);
      await File('tmp/pdfs/analytics-screen.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Save PDF'), findsNothing);
    expect(find.text('Preview text report'), findsNothing);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Annually'), findsOneWidget);
    expect(find.text('Share PDF'), findsOneWidget);
    expect(find.text('Save text report'), findsNothing);
    expect(find.text('Share text to…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart keeps top five categories and combines remaining amounts',
      (tester) async {
    final categories = TransactionCategory.values
        .where((c) => !c.isIncomeCategory)
        .take(7)
        .toList();
    final provider = AnalyticsExpenses([
      for (var i = 0; i < categories.length; i++)
        TransactionModel(
            id: 'group-$i',
            title: 'Expense',
            amount: (i + 1) * 10.0,
            type: TransactionType.expense,
            category: categories[i],
            date: DateTime(2026, 10, 1)),
    ]);
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider, child: const MaterialApp(home: AnalyticsScreen())));
    await tester.pumpAndSettle();
    final sections =
        tester.widget<PieChart>(find.byType(PieChart)).data.sections;
    final chart = tester
        .widget<CategoryDoughnutChart>(find.byType(CategoryDoughnutChart));
    for (final category in chart.categories.take(5)) {
      expect(
          find.descendant(
              of: find.byType(CategoryDoughnutChart),
              matching: find.text(category.name)),
          findsOneWidget);
    }
    expect(sections.length, 6);
    expect(sections.last.value, 30);
    expect(sections.fold<double>(0, (total, c) => total + c.value), 280);
    expect(find.text('Show more'), findsNothing);
    await tester.scrollUntilVisible(find.text('Category rankings'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Category rankings'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Category rankings')).dy,
        greaterThan(tester.getTopLeft(find.text('Calendar')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('small slices keep their names and long labels fit enlarged text',
      (tester) async {
    final main = CategoryTotal('Home appliances', 0xFF4ECDC4)..amount = 4002.8;
    final grocery = CategoryTotal('Groceries', 0xFF80AA00)..amount = 221.8;
    final tiny = CategoryTotal('Entertainment', 0xFFAA00AA)..amount = 20;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
      child: Scaffold(
          body: Center(
              child: SizedBox(
                  width: 280,
                  child: CategoryDoughnutChart(
                      categories: [main, grocery, tiny],
                      total: 4244.6,
                      currency: 'RM')))),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Home appliances'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Entertainment'), findsOneWidget);
    expect(
        tester.widget<PieChart>(find.byType(PieChart)).data.sections.length, 3);
    expect(tester.takeException(), isNull);
  });

  test('child categories combine under their parent name', () {
    final categories = AppCategory.defaults;
    final children =
        categories.where((c) => c.parentId == 'food').take(2).toList();
    final analysis = MonthlyAnalysis([
      for (var i = 0; i < children.length; i++)
        TransactionModel(
            id: 'child-$i',
            title: children[i].name,
            amount: 25.25,
            type: TransactionType.expense,
            category: TransactionCategory.food,
            categoryId: children[i].id,
            date: month),
      TransactionModel(
          id: 'parent',
          title: 'Food',
          amount: 10,
          type: TransactionType.expense,
          category: TransactionCategory.food,
          date: month),
    ], month, categories: categories);
    expect(analysis.rankedCategories.length, 1);
    expect(
        analysis.rankedCategories.single.name, TransactionCategory.food.label);
    expect(analysis.rankedCategories.single.amount, 60.5);
  });

  testWidgets('reference chart fits five bold labels on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = GlobalKey();
    final names = [
      'Home appliances',
      'Education',
      'Groceries',
      'Entertainment',
      'Travel',
      'Others'
    ];
    final amounts = [4002.8, 800.0, 245.4, 120.0, 92.0, 213.0];
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
            body: Center(
                child: RepaintBoundary(
                    key: capture,
                    child: Container(
                        color: const Color(0xFF25211D),
                        padding: const EdgeInsets.all(16),
                        child: CategoryDoughnutChart(categories: [
                          for (var i = 0; i < names.length; i++)
                            CategoryTotal(names[i], 0xFFFFFFFF)
                              ..amount = amounts[i],
                        ], total: 5473.2, currency: 'RM')))))));
    await tester.pumpAndSettle();
    for (final name in names.take(5)) {
      expect(tester.widget<Text>(find.text(name)).style!.fontWeight,
          FontWeight.w700);
    }
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File('tmp/pdfs/analytics-reference.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  });

  for (final size in [
    const Size(320, 800),
    const Size(800, 1280),
    const Size(1280, 800)
  ]) {
    testWidgets(
        'chart stays inside its bounds at ${size.width} x ${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      final names = [
        'Home appliances',
        'Education',
        'Groceries',
        'Entertainment',
        'Travel',
        'Others'
      ];
      final amounts = [4002.8, 800.0, 245.4, 120.0, 92.0, 213.0];
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
              data: MediaQueryData(
                  size: size, textScaler: const TextScaler.linear(1.4)),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: RepaintBoundary(
                              key: capture,
                              child: CategoryDoughnutChart(categories: [
                                for (var i = 0; i < names.length; i++)
                                  CategoryTotal(names[i], 0xFFFFFFFF)
                                    ..amount = amounts[i],
                              ], total: 5473.2, currency: 'RM'))))))));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find
          .descendant(
              of: find.byType(CategoryDoughnutChart),
              matching: find.byType(Stack))
          .first);
      final ring = tester.getRect(find.byType(PieChart));
      expect(ring.top, greaterThanOrEqualTo(bounds.top));
      expect(ring.bottom, lessThanOrEqualTo(bounds.bottom));
      expect(ring.width, closeTo(ring.height, .01));
      for (final name in names.take(5)) {
        final label = tester.getRect(find.text(name));
        expect(label.top, greaterThanOrEqualTo(bounds.top));
        expect(label.bottom, lessThanOrEqualTo(bounds.bottom));
        expect(label.left, greaterThanOrEqualTo(bounds.left));
        expect(label.right, lessThanOrEqualTo(bounds.right));
      }
      expect(tester.takeException(), isNull);
      if (size.width == 800) {
        await tester.runAsync(() async {
          final boundary = capture.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          final picture = await boundary.toImage(pixelRatio: 1);
          final bytes =
              await picture.toByteData(format: ui.ImageByteFormat.png);
          await File('tmp/pdfs/analytics-tablet.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
    });
  }

  test('week and year ranges include boundary dates exactly once', () {
    final date = DateTime(2026, 1, 1);
    final records = [
      transaction('Before week', 99, DateTime(2025, 12, 28, 23, 59)),
      transaction('Week start', 10, DateTime(2025, 12, 29)),
      transaction('New year', 20, date),
      transaction('Week end', 30, DateTime(2026, 1, 4, 23, 59)),
      transaction('Next week', 40, DateTime(2026, 1, 5)),
      transaction('Last day', 50, DateTime(2026, 12, 31, 23, 59)),
      transaction('Next year', 999, DateTime(2027)),
    ];
    MonthlyAnalysis period(AnalyticsPeriod period) =>
        MonthlyAnalysis(records, date,
            periodStart: period.start(date), periodEnd: period.end(date));
    expect(period(AnalyticsPeriod.week).expense, 60);
    expect(period(AnalyticsPeriod.year).expense, 140);
    expect(AnalyticsPeriod.week.move(date, -1), DateTime(2025, 12, 25));
    expect(AnalyticsPeriod.year.move(date, -1), DateTime(2025, 1, 1));
  });

  testWidgets(
      'week and year views navigate and year months open monthly analysis',
      (tester) async {
    final provider = AnalyticsExpenses([
      transaction('October', 100, DateTime(2026, 10, 1)),
      transaction('September', 200, DateTime(2026, 9, 30)),
      transaction('January', 400, DateTime(2026, 1, 1)),
      transaction('Old year', 900, DateTime(2025, 1, 1)),
    ]);
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: const AnalyticsScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CategoryDoughnutChart>(find.byType(CategoryDoughnutChart))
            .total,
        300);
    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    expect(find.text('No expenses this week'), findsWidgets);
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CategoryDoughnutChart>(find.byType(CategoryDoughnutChart))
            .total,
        700);
    await tester.tap(find.byTooltip('Previous year'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CategoryDoughnutChart>(find.byType(CategoryDoughnutChart))
            .total,
        900);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('overview-month-1')), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const ValueKey('overview-month-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('overview-month-1')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 1500));
    await tester.pumpAndSettle();
    expect(find.text('January 2025'), findsOneWidget);
    expect(
        tester
            .widget<CategoryDoughnutChart>(find.byType(CategoryDoughnutChart))
            .total,
        900);
    expect(tester.takeException(), isNull);
  });

  test('month filtering and separate daily flows agree with report totals',
      () async {
    final analysis = MonthlyAnalysis(sample, month);
    expect(analysis.income, 10000);
    expect(analysis.expense, 146.5);
    expect(analysis.net, 9853.5);
    expect(analysis.days[9]!.income, 10000);
    expect(analysis.days[9]!.expense, 100);
    expect(analysis.transactions.length, 3);
    expect(
        analysis.transactions.any((t) => t.title == 'Outside month'), isFalse);
  });

  test('year boundary excludes matching month in a different year', () {
    final analysis = MonthlyAnalysis([
      transaction('Old', 9, DateTime(2025, 1)),
      transaction('New', 10, DateTime(2026, 1))
    ], DateTime(2026, 1));
    expect(analysis.expense, 10);
  });

  test('save cancellation does not claim success; selected path receives bytes',
      () async {
    final picker = TestPicker();
    FilePicker.platform = picker;
    final bytes = Uint8List.fromList(utf8.encode('Monthly report'));
    expect(await AnalyticsReportService.save(bytes, 'report.txt'), isFalse);
    final dir = await Directory.systemTemp.createTemp('spendly_test_');
    addTearDown(() => dir.delete(recursive: true));
    picker.destination = '${dir.path}/report.txt';
    expect(await AnalyticsReportService.save(bytes, 'report.txt'), isTrue);
    expect(picker.received, bytes);
    expect(await File(picker.destination!).readAsString(), 'Monthly report');
  });

  test('PDF generation handles multiple pages and empty months', () async {
    final bytes = await AnalyticsReportService.generate(
        analysis: MonthlyAnalysis([
          ...sample,
          for (var i = 0; i < 90; i++)
            transaction(
                'Groceries purchase $i', 2.50, DateTime(2026, 10, i % 31 + 1)),
        ], month),
        currency: 'RM');
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    await Directory('tmp/pdfs').create(recursive: true);
    await File('tmp/pdfs/analytics-sample.pdf').writeAsBytes(bytes);
    final empty = await AnalyticsReportService.generate(
        analysis: MonthlyAnalysis([], month), currency: 'RM');
    expect(empty.length, greaterThan(1000));
  });

  test(
      'report years include income-only years and filter month and annual boundaries',
      () {
    final records = [
      transaction('Old year', 999, DateTime(2024, 12, 31)),
      transaction('January', 100, DateTime(2025, 1, 1)),
      transaction('Last day', 200, DateTime(2025, 12, 31, 23, 59)),
      transaction('Next year income', 400, DateTime(2026), income: true),
    ];
    expect(ReportSelection.recordedYears(records), [2026, 2025, 2024]);
    final year =
        ReportSelection(DateTime(2025), annual: true).analyze(records, []);
    expect(year.expense, 300);
    expect(year.transactions.length, 2);
    expect(
        ReportSelection(DateTime(2025, 12)).analyze(records, []).expense, 200);
    expect(AnalyticsReportService.fileName(DateTime(2025), annual: true),
        'Spendly_2025.pdf');
    expect(AnalyticsReportService.fileName(DateTime(2025, 12)),
        'Spendly_2025-12.pdf');
  });

  testWidgets('PDF picker offers recorded years and a selectable month',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
            body: ReportExportSheet(initialDate: DateTime(2026, 10), records: [
          transaction('Old', 10, DateTime(2024)),
          transaction('Income', 20, DateTime(2025), income: true),
        ]))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annually'));
    await tester.pumpAndSettle();
    expect(find.text('Month'), findsNothing);
    expect(find.text('2025'), findsOneWidget);
    await tester.tap(find.text('2025'));
    await tester.pumpAndSettle();
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('2026'), findsNothing);
    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('Month'), findsOneWidget);
    await tester.tap(find.text('October'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('January').last);
    await tester.tap(find.text('January').last);
    await tester.pumpAndSettle();
    expect(find.text('January'), findsOneWidget);
    expect(find.text('Share PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PDF picker returns the selected annual period and disables annual with no records',
      (tester) async {
    ReportSelection? selected;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    child: const Text('Export'),
                    onPressed: () async {
                      selected = await showModalBottomSheet<ReportSelection>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => ReportExportSheet(
                                  initialDate: DateTime(2026, 10),
                                  initialAnnual: true,
                                  records: [
                                    transaction('Prior year', 50,
                                        DateTime(2025, 12, 31))
                                  ]));
                    })))));
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsOneWidget);
    await tester.tap(find.text('Share PDF'));
    await tester.pumpAndSettle();
    expect(selected!.annual, isTrue);
    expect(selected!.date.year, 2025);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReportExportSheet(
                initialDate: DateTime(2026), records: const []))));
    await tester.pumpAndSettle();
    final toggle = tester
        .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    expect(toggle.segments.singleWhere((segment) => segment.value).enabled,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  test('annual PDF generates charts with sparse and income-only records',
      () async {
    final records = [
      transaction('Income Jan', 10000, DateTime(2025, 1, 1), income: true),
      transaction('January shop', 500, DateTime(2025, 1, 5)),
      transaction('December shop', 750, DateTime(2025, 12, 31)),
      transaction('Outside year', 99999, DateTime(2026)),
    ];
    final bytes = await AnalyticsReportService.generate(
        analysis:
            ReportSelection(DateTime(2025), annual: true).analyze(records, []),
        currency: 'RM',
        annual: true);
    await File('tmp/pdfs/analytics-annual.pdf').writeAsBytes(bytes);
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    final incomeOnly = await AnalyticsReportService.generate(
        analysis: MonthlyAnalysis([records.first], DateTime(2025, 1)),
        currency: 'RM');
    expect(incomeOnly.length, greaterThan(1000));
  });

  testWidgets('calendar supports leap February and taps show exact flows',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = MonthlyAnalysis([
      transaction('Leap day shop', 46.5, DateTime(2024, 2, 29)),
      transaction('Leap salary', 1000, DateTime(2024, 2, 29), income: true)
    ], DateTime(2024, 2));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(14),
                child: SpendingCalendar(analysis: data, currency: 'RM')))));
    expect(find.byKey(const ValueKey('calendar-day-29')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-day-30')), findsNothing);
    final daySize =
        tester.getSize(find.byKey(const ValueKey('calendar-day-29')));
    expect(daySize.width, closeTo(daySize.height, 1));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('calendar-day-29')));
    await tester.pumpAndSettle();
    expect(find.text('Leap day shop'), findsOneWidget);
    expect(find.text('In RM 1000.00  ·  Out RM 46.50'), findsOneWidget);
  });
}
