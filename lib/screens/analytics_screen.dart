import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/category_doughnut_chart.dart';
import 'package:intl/intl.dart';
import '../providers/expense_provider.dart';
import '../models/monthly_analysis.dart';
import '../models/analytics_period.dart';
import '../services/analytics_report_service.dart';
import '../models/report_selection.dart';
import '../widgets/report_export_sheet.dart';
import '../widgets/spending_calendar.dart';
import '../utils/app_theme.dart';
import 'spending_coach_screen.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _exporting = false;
  AnalyticsPeriod _period = AnalyticsPeriod.month;
  DateTime? _anchor;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final anchor = _anchor ?? provider.selectedMonth;
    final records = provider.allTransactions;
    final analysis = MonthlyAnalysis(records, anchor,
        categories: provider.categories,
        periodStart: _period.start(anchor),
        periodEnd: _period.end(anchor));
    final calendarAnalysis =
        MonthlyAnalysis(records, anchor, categories: provider.categories);
    return Scaffold(
        backgroundColor: AppPalette.of(context).bgDark,
        appBar: AppBar(title: const Text('Analytics'), actions: [
          IconButton(
              tooltip: 'Spending coach AI',
              icon: const Icon(Icons.auto_awesome_rounded),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SpendingCoachScreen()))),
          if (_exporting)
            const Padding(
                padding: EdgeInsets.all(18),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(
                tooltip: 'Reports',
                onPressed: provider.isLoading ? null : _reports,
                icon: const Icon(Icons.ios_share_rounded)),
        ]),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Center(
                  child: SegmentedButton<AnalyticsPeriod>(
                showSelectedIcon: false,
                segments: [
                  for (final period in AnalyticsPeriod.values)
                    ButtonSegment(value: period, label: Text(period.label))
                ],
                selected: {_period},
                onSelectionChanged: (value) =>
                    setState(() => _period = value.single),
              )),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(
                    tooltip: 'Previous ${_period.label.toLowerCase()}',
                    onPressed: provider.isLoading
                        ? null
                        : () => _movePeriod(provider, -1),
                    icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                    child: Text(_periodTitle(anchor),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: _period == AnalyticsPeriod.week ? 15 : 20,
                            fontWeight: FontWeight.w600))),
                IconButton(
                    tooltip: 'Next ${_period.label.toLowerCase()}',
                    onPressed: provider.isLoading
                        ? null
                        : () => _movePeriod(provider, 1),
                    icon: const Icon(Icons.chevron_right_rounded)),
              ]),
              const SizedBox(height: 16),
              if (provider.isLoading)
                const Padding(
                    padding: EdgeInsets.all(80),
                    child: Center(child: CircularProgressIndicator()))
              else ...[
                _card(
                    Row(children: [
                      _metric('Expenses', analysis.expense,
                          provider.currencySymbol, AppTheme.expenseColor),
                      _metric('Income', analysis.income,
                          provider.currencySymbol, AppTheme.incomeColor),
                      _metric(
                          'Net flow',
                          analysis.net,
                          provider.currencySymbol,
                          analysis.net >= 0
                              ? AppTheme.incomeColor
                              : AppTheme.expenseColor),
                    ]),
                    padding: 12),
                const SizedBox(height: 18),
                _card(_chart(analysis, provider.currencySymbol)),
                const SizedBox(height: 18),
                if (_period == AnalyticsPeriod.year)
                  _card(_yearOverview(provider, anchor), padding: 14)
                else
                  _card(
                      SpendingCalendar(
                          analysis: calendarAnalysis,
                          currency: provider.currencySymbol),
                      padding: 14),
                const SizedBox(height: 18),
                _card(_rankings(analysis, provider.currencySymbol)),
              ],
            ]));
  }

  String _periodTitle(DateTime anchor) {
    if (_period == AnalyticsPeriod.year) return '${anchor.year}';
    if (_period == AnalyticsPeriod.month)
      return DateFormat('MMMM yyyy').format(anchor);
    final start = _period.start(anchor);
    final end = _period.end(anchor).subtract(const Duration(days: 1));
    return '${DateFormat('d MMM yyyy').format(start)}  -  ${DateFormat('d MMM yyyy').format(end)}';
  }

  void _movePeriod(ExpenseProvider provider, int delta) {
    final next = _period.move(_anchor ?? provider.selectedMonth, delta);
    setState(() => _anchor = next);
    provider.setSelectedMonth(DateTime(next.year, next.month));
  }

  Widget _yearOverview(ExpenseProvider provider, DateTime anchor) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Monthly overview',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            childAspectRatio: 1.25,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (var month = 1; month <= 12; month++)
                Builder(builder: (context) {
                  final date = DateTime(anchor.year, month);
                  final summary = MonthlyAnalysis(
                      provider.allTransactions, date,
                      categories: provider.categories);
                  return Material(
                      color: AppPalette.of(context).bgCardLight,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                          key: ValueKey('overview-month-$month'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setState(() {
                              _anchor = date;
                              _period = AnalyticsPeriod.month;
                            });
                            provider.setSelectedMonth(date);
                          },
                          child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(DateFormat('MMM').format(date),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    FittedBox(
                                        child: Text(
                                            '${provider.currencySymbol} ${NumberFormat.compact().format(summary.expense)}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.expenseColor))),
                                  ]))));
                })
            ]),
      ]);

  Widget _card(Widget child, {double padding = 20}) => Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
          color: AppPalette.of(context).bgCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: child);

  Widget _metric(String label, double value, String currency, Color color) =>
      Expanded(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
              child: Column(children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: AppPalette.of(context).textMuted)),
                const SizedBox(height: 8),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                        '$currency ${NumberFormat('#,##0.00').format(value)}',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: color)))
              ])));

  List<CategoryTotal> _displayCategories(MonthlyAnalysis analysis) {
    final ranked = analysis.rankedCategories;
    if (ranked.length <= 5) return ranked;
    final others = CategoryTotal('Others', 0xFF85839B);
    others.amount = ranked
            .skip(5)
            .fold<int>(0, (sum, c) => sum + (c.amount * 100).round()) /
        100;
    return [...ranked.take(5), others];
  }

  Widget _chart(MonthlyAnalysis analysis, String currency) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Spending by category',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        if (analysis.expense == 0)
          SizedBox(
              height: 150,
              child: Center(
                  child: Text('No expenses this ${_period.label.toLowerCase()}',
                      style:
                          TextStyle(color: AppPalette.of(context).textMuted))))
        else
          CategoryDoughnutChart(
              categories: _displayCategories(analysis),
              total: analysis.expense,
              currency: currency),
      ]);

  Widget _rankings(MonthlyAnalysis analysis, String currency) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Category rankings',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        if (analysis.rankedCategories.isEmpty)
          Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text('No expenses this ${_period.label.toLowerCase()}',
                  style: TextStyle(color: AppPalette.of(context).textMuted))),
        ...analysis.rankedCategories.map((c) => Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(children: [
              Row(children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                        color: Color(c.color), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(c.name, style: const TextStyle(fontSize: 13))),
                const SizedBox(width: 8),
                Text('$currency ${c.amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600))
              ]),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: analysis.expense > 0
                      ? (c.amount / analysis.expense).clamp(0, 1)
                      : 0,
                  color: Color(c.color),
                  backgroundColor: AppPalette.of(context).bgCardLight,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(5)),
              const SizedBox(height: 5),
              Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                      '${analysis.expense > 0 ? (c.amount / analysis.expense * 100).toStringAsFixed(1) : '0.0'}%',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppPalette.of(context).textMuted))),
            ]))),
      ]);

  Future<void> _reports() async {
    final provider = context.read<ExpenseProvider>();
    final owner = provider.userId;
    final selection = await showModalBottomSheet<ReportSelection>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppPalette.of(context).bgCard,
        showDragHandle: true,
        builder: (_) => ReportExportSheet(
            records: provider.allTransactions,
            initialDate: _anchor ?? provider.selectedMonth,
            initialAnnual: _period == AnalyticsPeriod.year));
    if (selection == null || !mounted || provider.userId != owner) return;
    final analysis =
        selection.analyze(provider.allTransactions, provider.categories);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _exporting = true);
    try {
      final bytes = await AnalyticsReportService.generate(
          analysis: analysis,
          currency: provider.currencySymbol,
          annual: selection.annual);
      final name = AnalyticsReportService.fileName(selection.date,
          annual: selection.annual);
      if (!mounted || provider.userId != owner) return;
      await AnalyticsReportService.share(bytes, name, origin);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not export the PDF. Please try again.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
