import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../providers/expense_provider.dart';
import '../utils/app_theme.dart';

List<double> spendingSeries(List<TransactionModel> records,
    {required DateTime anchor, required bool yearly, bool monthly = false}) {
  final totals = List<int>.filled(
      yearly
          ? 12
          : monthly
              ? DateTime(anchor.year, anchor.month + 1, 0).day
              : 7,
      0);
  final today = DateTime(anchor.year, anchor.month, anchor.day);
  for (final t in records) {
    if (t.type != TransactionType.expense) continue;
    final day = DateTime(t.date.year, t.date.month, t.date.day);
    final index = yearly
        ? (t.date.year == anchor.year ? t.date.month - 1 : -1)
        : monthly
            ? (t.date.year == anchor.year && t.date.month == anchor.month
                ? t.date.day - 1
                : -1)
            : 6 - today.difference(day).inDays;
    if (index >= 0 && index < totals.length)
      totals[index] += (t.amount * 100).round();
  }
  return totals.map((c) => c / 100).toList();
}

class DashboardSpendingChart extends StatefulWidget {
  const DashboardSpendingChart(
      {super.key,
      this.compact = false,
      this.expanded = false,
      this.initialAnchor,
      this.initialYearly = false,
      this.initialMonthly = false});
  final bool compact;
  final bool expanded;
  final DateTime? initialAnchor;
  final bool initialYearly, initialMonthly;
  @override
  State<DashboardSpendingChart> createState() => _DashboardSpendingChartState();
}

class _DashboardSpendingChartState extends State<DashboardSpendingChart> {
  bool yearly = false;
  bool monthly = false;
  DateTime anchor = DateTime.now();
  int year = DateTime.now().year;
  Future<List<TransactionModel>>? future;
  List<TransactionModel>? lastRecords;
  int? lastRevision;
  String? owner;
  @override
  void initState() {
    super.initState();
    anchor = widget.initialAnchor ?? DateTime.now();
    year = anchor.year;
    yearly = widget.initialYearly;
    monthly = widget.initialMonthly;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.watch<ExpenseProvider>();
    if (owner != provider.userId ||
        lastRevision != provider.chartRevision ||
        !identical(lastRecords, provider.transactions) ||
        future == null) {
      owner = provider.userId;
      lastRecords = provider.transactions;
      lastRevision = provider.chartRevision;
      future = provider.loadChartTransactions();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: widget.compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppPalette.of(context).bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppPalette.of(context).border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(
                    yearly
                        ? (widget.compact ? 'Yearly' : 'Yearly spending')
                        : monthly
                            ? (widget.compact ? 'Monthly' : 'Monthly spending')
                            : (widget.compact ? 'Spending' : 'Weekly spending'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13))),
            DropdownButton<String>(
                value: yearly
                    ? 'Year'
                    : monthly
                        ? 'Month'
                        : 'Week',
                underline: const SizedBox(),
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 12,
                    color: AppPalette.of(context).textPrimary),
                items: [
                  for (final p in ['Week', 'Month', 'Year'])
                    DropdownMenuItem(value: p, child: Text(p))
                ],
                onChanged: (v) => setState(() {
                      yearly = v == 'Year';
                      monthly = v == 'Month';
                      year = anchor.year;
                    })),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                tooltip: yearly
                    ? 'Previous year'
                    : monthly
                        ? 'Previous month'
                        : 'Previous week',
                constraints:
                    const BoxConstraints.tightFor(width: 24, height: 36),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_left, size: 18),
                onPressed: () => setState(() {
                      anchor = yearly
                          ? DateTime(anchor.year - 1, anchor.month)
                          : monthly
                              ? DateTime(anchor.year, anchor.month - 1)
                              : anchor.subtract(const Duration(days: 7));
                      year = anchor.year;
                    })),
            Expanded(
                child: Text(
                    yearly
                        ? '$year'
                        : monthly
                            ? DateFormat.yMMM().format(anchor)
                            : '${DateFormat.MMMd().format(anchor.subtract(const Duration(days: 6)))} – ${DateFormat.MMMd().format(anchor)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600))),
            IconButton(
                tooltip: yearly
                    ? 'Next year'
                    : monthly
                        ? 'Next month'
                        : 'Next week',
                constraints:
                    const BoxConstraints.tightFor(width: 24, height: 36),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_right, size: 18),
                onPressed: (yearly
                        ? anchor.year >= DateTime.now().year
                        : monthly
                            ? anchor.year * 12 + anchor.month >=
                                DateTime.now().year * 12 + DateTime.now().month
                            : !DateTime(anchor.year, anchor.month, anchor.day)
                                .isBefore(DateTime(DateTime.now().year,
                                    DateTime.now().month, DateTime.now().day)))
                    ? null
                    : () => setState(() {
                          anchor = yearly
                              ? DateTime(anchor.year + 1, anchor.month)
                              : monthly
                                  ? DateTime(anchor.year, anchor.month + 1)
                                  : anchor.add(const Duration(days: 7));
                          if (anchor.isAfter(DateTime.now()))
                            anchor = DateTime.now();
                          year = anchor.year;
                        })),
          ]),
          FutureBuilder<List<TransactionModel>>(
              key: ValueKey(owner),
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return Column(children: [
                    const Text('Could not load spending history.'),
                    TextButton(
                        onPressed: () => setState(() => future = context
                            .read<ExpenseProvider>()
                            .loadChartTransactions()),
                        child: const Text('Retry'))
                  ]);
                if (!snapshot.hasData)
                  return const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()));
                final currency = context.read<ExpenseProvider>().currencySymbol;
                final now = anchor;
                final data = spendingSeries(snapshot.data!,
                    anchor: yearly ? DateTime(year) : now,
                    yearly: yearly,
                    monthly: monthly);
                final maximum = data.fold<double>(0, (a, b) => a > b ? a : b);
                final titles = FlTitlesData(
                    leftTitles: AxisTitles(
                        axisNameWidget: widget.expanded
                            ? Text(
                                'Spending (${context.read<ExpenseProvider>().currencySymbol})',
                                style: const TextStyle(fontSize: 11))
                            : null,
                        sideTitles: SideTitles(
                            showTitles: widget.expanded,
                            reservedSize: 48,
                            getTitlesWidget: (v, meta) => v == meta.max
                                ? const SizedBox.shrink()
                                : Text(NumberFormat.compact().format(v),
                                    style: const TextStyle(fontSize: 10)))),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                        axisNameWidget: widget.expanded
                            ? Text(
                                yearly
                                    ? 'Month'
                                    : monthly
                                        ? 'Day of month'
                                        : 'Day',
                                style: const TextStyle(fontSize: 11))
                            : null,
                        sideTitles: SideTitles(
                            showTitles: true,
                            interval: monthly ? 7 : 1,
                            reservedSize: 26,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= data.length || value != i)
                                return const SizedBox();
                              // Do not crowd the last day with a nearby weekly tick.
                              if (monthly &&
                                  i != data.length - 1 &&
                                  data.length - 1 - i < 4) {
                                return const SizedBox();
                              }
                              final label = yearly
                                  ? DateFormat('MMM')
                                      .format(DateTime(year, i + 1))
                                      .substring(0, 1)
                                  : monthly
                                      ? '${i + 1}'
                                      : DateFormat('E')
                                          .format(now
                                              .subtract(Duration(days: 6 - i)))
                                          .substring(0, 1);
                              return Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Text(label,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppPalette.of(context)
                                              .textMuted)));
                            })));
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '$currency ${data.fold<double>(0, (s, v) => s + v).toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: SizedBox(
                              key: ValueKey('$yearly-$monthly-$anchor'),
                              height: widget.expanded ? 320 : 92,
                              child: yearly || monthly
                                  ? LineChart(LineChartData(
                                      minX: 0,
                                      maxX: (data.length - 1).toDouble(),
                                      minY: 0,
                                      maxY: maximum > 0 ? maximum * 1.3 : 100,
                                      titlesData: titles,
                                      gridData: FlGridData(
                                          show: widget.expanded,
                                          drawVerticalLine: false),
                                      borderData: FlBorderData(show: false),
                                      lineTouchData: LineTouchData(
                                          touchTooltipData: LineTouchTooltipData(
                                              getTooltipItems: (spots) => spots
                                                  .map((spot) => LineTooltipItem(
                                                      '${monthly ? DateFormat.MMMd().format(DateTime(anchor.year, anchor.month, spot.x.toInt() + 1)) : DateFormat('MMM').format(DateTime(year, spot.x.toInt() + 1))}\n$currency ${spot.y.toStringAsFixed(2)}',
                                                      const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold)))
                                                  .toList())),
                                      lineBarsData: [
                                          LineChartBarData(
                                              spots: List.generate(
                                                  data.length,
                                                  (i) => FlSpot(
                                                      i.toDouble(), data[i])),
                                              isCurved: true,
                                              curveSmoothness: .25,
                                              preventCurveOverShooting: true,
                                              isStrokeCapRound: true,
                                              color: AppTheme.primary,
                                              barWidth: 3,
                                              dotData:
                                                  const FlDotData(show: false),
                                              belowBarData: BarAreaData(
                                                  show: true,
                                                  gradient: LinearGradient(
                                                      begin:
                                                          Alignment.topCenter,
                                                      end: Alignment
                                                          .bottomCenter,
                                                      colors: [
                                                        AppTheme.primary
                                                            .withValues(
                                                                alpha: .18),
                                                        AppTheme.primary
                                                            .withValues(
                                                                alpha: .01)
                                                      ])))
                                        ]))
                                  : BarChart(BarChartData(
                                      minY: 0,
                                      maxY: maximum > 0 ? maximum * 1.3 : 100,
                                      titlesData: titles,
                                      gridData: FlGridData(
                                          show: widget.expanded,
                                          drawVerticalLine: false),
                                      borderData: FlBorderData(show: false),
                                      barTouchData: BarTouchData(
                                          enabled: true,
                                          touchTooltipData: BarTouchTooltipData(
                                              getTooltipItem: (group,
                                                      groupIndex,
                                                      rod,
                                                      rodIndex) =>
                                                  BarTooltipItem(
                                                      '${DateFormat('dd MMM').format(now.subtract(Duration(days: 6 - group.x)))}\n$currency ${data[group.x].toStringAsFixed(2)}',
                                                      const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight
                                                              .bold)))),
                                      barGroups: List.generate(
                                          7,
                                          (i) =>
                                              BarChartGroupData(x: i, barRods: [
                                                BarChartRodData(
                                                    toY: data[i],
                                                    width: widget.compact
                                                        ? 10
                                                        : 20,
                                                    color: AppTheme.primary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            5))
                                              ])),
                                    )))),
                      const SizedBox(height: 8),
                      if (!widget.expanded)
                        Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                                tooltip: 'Enlarge spending chart',
                                icon: const Icon(Icons.open_in_full, size: 18),
                                onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (ctx) => Dialog(
                                        insetPadding: const EdgeInsets.all(12),
                                        child: SingleChildScrollView(
                                            child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                              Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: IconButton(
                                                      tooltip: 'Close',
                                                      icon: const Icon(
                                                          Icons.close),
                                                      onPressed: () =>
                                                          Navigator.pop(ctx))),
                                              DashboardSpendingChart(
                                                  expanded: true,
                                                  initialAnchor: anchor,
                                                  initialYearly: yearly,
                                                  initialMonthly: monthly),
                                            ])))))),
                    ]);
              }),
        ]),
      ));
}
