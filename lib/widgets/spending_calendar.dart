import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/monthly_analysis.dart';
import '../models/transaction_model.dart';
import '../utils/app_theme.dart';

class SpendingCalendar extends StatelessWidget {
  const SpendingCalendar(
      {super.key, required this.analysis, required this.currency});
  final MonthlyAnalysis analysis;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(analysis.month.year, analysis.month.month);
    final offset = first.weekday % 7;
    final count = DateTime(first.year, first.month + 1, 0).day;
    final cells = ((offset + count) / 7).ceil() * 7;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.calendar_month_rounded, size: 21),
        SizedBox(width: 8),
        Text('Calendar',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))
      ]),
      const SizedBox(height: 8),
      Text('Tap a day for income and expenses',
          style:
              TextStyle(color: AppPalette.of(context).textMuted, fontSize: 11)),
      const SizedBox(height: 18),
      Row(
          children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
              .map((d) => Expanded(
                  child: Center(
                      child: Text(d,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppPalette.of(context).textMuted)))))
              .toList()),
      const SizedBox(height: 10),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1,
            crossAxisSpacing: 4,
            mainAxisSpacing: 5),
        itemCount: cells,
        itemBuilder: (context, index) {
          final day = index - offset + 1;
          if (day < 1 || day > count) return const SizedBox.shrink();
          final flow = analysis.days[day];
          final now = DateTime.now();
          final today = now.year == first.year &&
              now.month == first.month &&
              now.day == day;
          final date = DateTime(first.year, first.month, day);
          return Semantics(
            label:
                '${DateFormat('dd MMMM yyyy').format(date)}, income $currency ${flow?.income.toStringAsFixed(2) ?? '0.00'}, expenses $currency ${flow?.expense.toStringAsFixed(2) ?? '0.00'}',
            button: true,
            child: Material(
                color: today
                    ? AppTheme.primary.withValues(alpha: .15)
                    : AppPalette.of(context).bgDark.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: ValueKey('calendar-day-$day'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _showDay(context, date, flow),
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 4),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: today
                                  ? AppTheme.primary
                                  : Colors.white.withValues(alpha: .06))),
                      child: Column(children: [
                        Text('$day',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: today
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        const Spacer(),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (flow != null && flow.income > 0)
                                Container(
                                    width: 4,
                                    height: 4,
                                    margin: const EdgeInsets.all(1),
                                    decoration: const BoxDecoration(
                                        color: AppTheme.incomeColor,
                                        shape: BoxShape.circle)),
                              if (flow != null && flow.expense > 0)
                                Container(
                                    width: 4,
                                    height: 4,
                                    margin: const EdgeInsets.all(1),
                                    decoration: const BoxDecoration(
                                        color: AppTheme.expenseColor,
                                        shape: BoxShape.circle)),
                            ]),
                      ])),
                )),
          );
        },
      ),
    ]);
  }

  void _showDay(BuildContext context, DateTime date, DayCashFlow? flow) {
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppPalette.of(context).bgCard,
        showDragHandle: true,
        builder: (context) => SafeArea(
                child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .6,
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(DateFormat('dd MMMM yyyy').format(date),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600))),
                if (flow == null)
                  const Expanded(
                      child: Center(child: Text('No transactions on this day')))
                else ...[
                  Text(
                      'In $currency ${flow.income.toStringAsFixed(2)}  ·  Out $currency ${flow.expense.toStringAsFixed(2)}'),
                  const SizedBox(height: 12),
                  Expanded(
                      child: ListView.builder(
                          itemCount: flow.transactions.length,
                          itemBuilder: (context, index) {
                            final t = flow.transactions[index];
                            final income = t.type == TransactionType.income;
                            return ListTile(
                                title: Text(t.title),
                                trailing: Text(
                                    '${income ? '+' : '−'}$currency ${t.amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        color: income
                                            ? AppTheme.incomeColor
                                            : AppTheme.expenseColor)));
                          })),
                ],
              ]),
            )));
  }
}
