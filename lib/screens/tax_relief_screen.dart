import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../providers/expense_provider.dart';
import '../services/tax_relief_service.dart';
import '../utils/app_theme.dart';
import 'transaction_detail_screen.dart';

class TaxReliefScreen extends StatefulWidget {
  const TaxReliefScreen({super.key});
  @override
  State<TaxReliefScreen> createState() => _TaxReliefScreenState();
}

class _TaxReliefScreenState extends State<TaxReliefScreen> {
  int year = DateTime.now().year;
  String? owner;
  int? revision;
  Future<List<TransactionModel>>? future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.watch<ExpenseProvider>();
    if (owner != provider.userId ||
        revision != provider.chartRevision ||
        future == null) {
      if (owner != provider.userId) year = DateTime.now().year;
      owner = provider.userId;
      revision = provider.chartRevision;
      future = provider.loadChartTransactions();
    }
  }

  void reference() => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: const Text('About these hints'),
              content: const SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        'Reference: HASiL resident individual relief summary, YA 2025. Other years are organising hints only; their eligibility rules are not verified here.'),
                    SizedBox(height: 12),
                    Text(
                        'Matches come from saved names and notes. Missing matches do not mean an expense is ineligible. Check the selected assessment year, personal conditions and receipts before filing. No claim total is calculated.'),
                    SizedBox(height: 12),
                    SelectableText(TaxReliefService.referenceUrl,
                        style: TextStyle(fontSize: 11)),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Got it'))
              ]));
  void receipt(TransactionModel transaction) {
    final path = transaction.receiptImagePath;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Saved receipt')),
                  body: path != null && File(path).existsSync()
                      ? InteractiveViewer(
                          minScale: .5,
                          maxScale: 5,
                          child: Center(
                              child: Image.file(File(path),
                                  errorBuilder: (_, __, ___) => const Text(
                                      'Receipt could not be opened.'))))
                      : const Center(
                          child: Text(
                              'This receipt is not available on this device.')),
                  bottomNavigationBar: SafeArea(
                      child: TextButton(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => TransactionDetailScreen(
                                      transaction: transaction))),
                          child: const Text('View transaction'))),
                )));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    return Scaffold(
        appBar: AppBar(title: const Text('Possible tax relief'), actions: [
          IconButton(
              tooltip: 'About tax relief hints',
              onPressed: reference,
              icon: const Icon(Icons.info_outline))
        ]),
        body: FutureBuilder<List<TransactionModel>>(
            key: ValueKey('$owner:$revision'),
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(
                    child: TextButton(
                        onPressed: () => setState(
                            () => future = provider.loadChartTransactions()),
                        child: const Text('Could not load expenses. Retry')));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final rows = snapshot.data!;
              final years = {
                year,
                DateTime.now().year,
                TaxReliefService.verifiedReferenceYear,
                ...rows
                    .where((t) => !t.date.isAfter(DateTime.now()))
                    .map((t) => t.date.year)
              }.toList()
                ..sort((a, b) => b.compareTo(a));
              final matches = TaxReliefService.find(rows, year);
              final groups = matches.map((m) => m.group).toSet().toList();
              return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    Row(children: [
                      const Expanded(
                          child: Text('Assessment year',
                              style: TextStyle(fontSize: 12))),
                      DropdownButton<int>(
                          value: year,
                          borderRadius: BorderRadius.circular(16),
                          items: [
                            for (final y in years)
                              DropdownMenuItem(value: y, child: Text('YA $y'))
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => year = value);
                          })
                    ]),
                    const SizedBox(height: 8),
                    Text(
                        year == TaxReliefService.verifiedReferenceYear
                            ? 'Possible matches · Needs checking'
                            : 'Organising hints · YA $year rules not verified',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.warningColor)),
                    const SizedBox(height: 8),
                    const Text(
                        'Expense totals below are not claim amounts. For mixed receipts, check the eligible items. This list stays on your device.',
                        style: TextStyle(fontSize: 12, height: 1.5)),
                    const SizedBox(height: 18),
                    if (matches.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Text(
                              'No possible matches yet. More detailed expense names and receipt notes can help.')),
                    for (var i = 0; i < groups.length; i++) ...[
                      Text('${i + 1}. ${groups[i]}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      for (final match
                          in matches.where((m) => m.group == groups[i]))
                        Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                            child: Text(match.transaction.title,
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w500))),
                                        const SizedBox(width: 8),
                                        Text(
                                            '${provider.currencySymbol} ${match.transaction.amount.toStringAsFixed(2)}',
                                            style:
                                                const TextStyle(fontSize: 12))
                                      ]),
                                      const SizedBox(height: 5),
                                      Text(
                                          '${DateFormat('d MMM yyyy').format(match.transaction.date)} · Expense total',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: AppPalette.of(context)
                                                  .textMuted)),
                                      const SizedBox(height: 8),
                                      Text(match.reason,
                                          style: const TextStyle(
                                              fontSize: 11, height: 1.5)),
                                      Row(children: [
                                        const Expanded(
                                            child: Text('Needs checking',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: AppTheme
                                                        .warningColor))),
                                        TextButton.icon(
                                            onPressed: match.transaction.receiptImagePath == null
                                                ? () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                        builder: (_) =>
                                                            TransactionDetailScreen(
                                                                transaction: match
                                                                    .transaction)))
                                                : () =>
                                                    receipt(match.transaction),
                                            icon: Icon(
                                                match.transaction.receiptImagePath == null
                                                    ? Icons
                                                        .receipt_long_outlined
                                                    : Icons.attach_file,
                                                size: 15),
                                            label: Text(
                                                match.transaction.receiptImagePath == null ? 'No receipt · View' : 'View receipt',
                                                style: const TextStyle(fontSize: 10)))
                                      ]),
                                    ]))),
                      const SizedBox(height: 12),
                    ],
                  ]);
            }));
  }
}
