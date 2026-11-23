import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/monthly_analysis.dart';
import '../models/transaction_model.dart';
import 'ledger_totals.dart';

class AnalyticsReportService {
  static String fileName(DateTime date, {bool annual = false}) =>
      'Spendly_${annual ? date.year.toString() : DateFormat('yyyy-MM').format(date)}.pdf';

  static Future<Uint8List> generate(
      {required MonthlyAnalysis analysis,
      required String currency,
      bool annual = false}) async {
    final regular =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Sora-Regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Sora-Bold.ttf'));
    final document = pw.Document(
        title: annual ? 'Spendly annual report' : 'Spendly monthly report',
        author: 'Spendly');
    final purple = PdfColor.fromHex('#6555D9');
    final muted = PdfColor.fromHex('#667085');
    String money(double value) =>
        '$currency ${NumberFormat('#,##0.00').format(value)}';
    final periodTitle = annual
        ? '${analysis.month.year}'
        : DateFormat('MMMM yyyy').format(analysis.month);
    final activityDays = analysis.transactions
        .map((t) => DateTime(t.date.year, t.date.month, t.date.day))
        .toSet()
        .length;
    final periodDays = annual
        ? DateTime(analysis.month.year + 1)
            .difference(DateTime(analysis.month.year))
            .inDays
        : DateTime(analysis.month.year, analysis.month.month + 1, 0).day;
    final bucketCount = annual ? 12 : (periodDays / 7).ceil();
    final incomes = List<int>.filled(bucketCount, 0);
    final expenses = List<int>.filled(bucketCount, 0);
    for (final t in analysis.transactions) {
      final index = annual ? t.date.month - 1 : (t.date.day - 1) ~/ 7;
      final values = t.type == TransactionType.income ? incomes : expenses;
      values[index] += LedgerTotals.sen(t.amount);
    }
    final labels = [
      for (var i = 0; i < bucketCount; i++)
        annual
            ? DateFormat('MMM').format(DateTime(2000, i + 1))
            : '${i * 7 + 1}-${((i + 1) * 7).clamp(1, periodDays)}'
    ];
    final maxExpense = expenses.reduce((a, b) => a > b ? a : b);
    final peak = expenses.indexOf(maxExpense);
    final chartMax =
        [...incomes, ...expenses].fold<int>(1, (a, b) => a > b ? a : b);
    final svg = StringBuffer(
        '<svg xmlns="http://www.w3.org/2000/svg" width="520" height="174" viewBox="0 0 520 174">');
    const left = 58.0, chartWidth = 452.0, chartHeight = 126.0;
    final step = chartWidth / bucketCount;
    for (var tick = 0; tick <= 3; tick++) {
      final y = 8 + chartHeight - tick * chartHeight / 3;
      final value = chartMax / 100 * tick / 3;
      svg.write(
          '<line x1="58" y1="$y" x2="510" y2="$y" stroke="#E7E9EE" stroke-width="1"/>');
      svg.write(
          '<text x="50" y="${y + 3}" text-anchor="end" font-family="Helvetica" font-size="9" fill="#667085">${NumberFormat.compact().format(value)}</text>');
    }
    for (var i = 0; i < bucketCount; i++) {
      final x = left + i * step + step * .18;
      final barWidth = step * .27;
      for (var j = 0; j < 2; j++) {
        final value = j == 0 ? incomes[i] : expenses[i];
        final height = value / chartMax * chartHeight;
        svg.write(
            '<rect x="${x + j * (barWidth + 2)}" y="${8 + chartHeight - height}" width="$barWidth" height="$height" fill="${j == 0 ? '#178A7B' : '#6555D9'}"/>');
      }
      svg.write(
          '<text x="${left + (i + .5) * step}" y="153" text-anchor="middle" font-family="Helvetica" font-size="9" fill="#667085">${labels[i]}</text>');
    }
    svg.write('</svg>');
    final chartCategories = analysis.rankedCategories.take(5).toList();
    if (analysis.rankedCategories.length > 5) {
      final other = CategoryTotal('Other categories', 0xFF85839B);
      other.amount = LedgerTotals.sum(
          analysis.rankedCategories.skip(5).map((c) => c.amount));
      chartCategories.add(other);
    }
    pw.Widget heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 20, bottom: 10),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)));
    pw.Widget metric(String label, double value) => pw.Expanded(
        child: pw.Container(
            padding: const pw.EdgeInsets.all(12),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(label,
                      style: pw.TextStyle(fontSize: 9, color: muted)),
                  pw.SizedBox(height: 8),
                  pw.Text(money(value),
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ])));
    document.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        maxPages: 500,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (context) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('SPENDLY',
                      style: pw.TextStyle(
                          color: purple,
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold)),
                  pw.Text(periodTitle,
                      style: pw.TextStyle(color: muted, fontSize: 9)),
                ]),
        footer: (context) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12),
            child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Personal spending report',
                      style: pw.TextStyle(color: muted, fontSize: 8)),
                  pw.Text('${context.pageNumber} / ${context.pagesCount}',
                      style: pw.TextStyle(color: muted, fontSize: 8)),
                ])),
        build: (context) => [
              pw.SizedBox(height: 24),
              pw.Text(annual ? 'Your year in money' : 'Your month in money',
                  style: pw.TextStyle(
                      fontSize: 25, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text(
                  'Generated ${DateFormat('dd-MM-yyyy').format(DateTime.now())} · ${analysis.transactions.length} recorded transactions',
                  style: pw.TextStyle(color: muted, fontSize: 10)),
              pw.SizedBox(height: 20),
              pw.Container(
                  decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F3F1FC'),
                      borderRadius: pw.BorderRadius.circular(10)),
                  child: pw.Row(children: [
                    metric('INCOME', analysis.income),
                    metric('EXPENSES', analysis.expense),
                    metric('NET CASH FLOW', analysis.net)
                  ])),
              heading('At a glance'),
              pw.Text(
                  analysis.transactions.isEmpty
                      ? 'No transactions recorded for this ${annual ? 'year' : 'month'}.'
                      : '${activityDays} days with activity. ${analysis.rankedCategories.isEmpty ? 'No expenses recorded.' : 'Largest expense category: ${analysis.rankedCategories.first.name} (${money(analysis.rankedCategories.first.amount)}).'}',
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 4)),
              pw.SizedBox(height: 6),
              pw.Text(
                  'Totals reflect recorded transactions only. Net cash flow is income minus expenses, not your bank balance.',
                  style: pw.TextStyle(fontSize: 9, color: muted)),
              if (analysis.expense > 0) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                    'Largest category accounts for ${(analysis.rankedCategories.first.amount / analysis.expense * 100).toStringAsFixed(1)}% of expenses. Average expense per calendar day: ${money(analysis.expense / periodDays)}.',
                    style: const pw.TextStyle(fontSize: 10, lineSpacing: 4)),
                pw.SizedBox(height: 6),
                pw.Text(
                    annual
                        ? 'Highest-spending month: ${labels[peak]} (${money(maxExpense / 100)}).'
                        : 'Highest-spending date range: ${labels[peak]} ${DateFormat('MMM').format(analysis.month)} (${money(maxExpense / 100)}).',
                    style: const pw.TextStyle(fontSize: 10, lineSpacing: 4)),
              ],
              if (analysis.income > 0) ...[
                pw.SizedBox(height: 6),
                pw.Text(
                    'Net cash flow is ${(analysis.net / analysis.income * 100).toStringAsFixed(1)}% of recorded income.',
                    style: const pw.TextStyle(fontSize: 10)),
              ],
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    heading(annual
                        ? 'Income and expenses by month'
                        : 'Income and expenses by date range'),
                    pw.Text('Amounts in $currency',
                        style: pw.TextStyle(fontSize: 8, color: muted)),
                    pw.SizedBox(height: 8),
                    pw.SvgImage(svg: svg.toString(), width: 520, height: 174),
                    pw.Row(children: [
                      pw.Container(
                          width: 8,
                          height: 8,
                          color: PdfColor.fromHex('#178A7B')),
                      pw.SizedBox(width: 5),
                      pw.Text('Income', style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(width: 20),
                      pw.Container(width: 8, height: 8, color: purple),
                      pw.SizedBox(width: 5),
                      pw.Text('Expenses',
                          style: const pw.TextStyle(fontSize: 9)),
                    ]),
                  ]),
              if (analysis.expense > 0)
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      heading('Where your money went'),
                      for (final c in chartCategories)
                        pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 10),
                            child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Row(
                                      mainAxisAlignment:
                                          pw.MainAxisAlignment.spaceBetween,
                                      children: [
                                        pw.Expanded(
                                            child: pw.Text(c.name,
                                                style: const pw.TextStyle(
                                                    fontSize: 9))),
                                        pw.SizedBox(width: 12),
                                        pw.Text(
                                            '${money(c.amount)}  |  ${(c.amount / analysis.expense * 100).toStringAsFixed(1)}%',
                                            style: const pw.TextStyle(
                                                fontSize: 9)),
                                      ]),
                                  pw.SizedBox(height: 4),
                                  pw.Container(
                                      height: 7,
                                      width: 510 * c.amount / analysis.expense,
                                      decoration: pw.BoxDecoration(
                                          color: purple,
                                          borderRadius:
                                              pw.BorderRadius.circular(3))),
                                ])),
                    ]),
              heading('Category rankings'),
              if (analysis.rankedCategories.isEmpty)
                pw.Text('No expenses recorded.',
                    style: const pw.TextStyle(fontSize: 10))
              else
                pw.TableHelper.fromTextArray(
                    headers: ['Category', 'Amount', 'Share'],
                    data: analysis.rankedCategories
                        .map((c) => [
                              c.name,
                              money(c.amount),
                              '${(c.amount / analysis.expense * 100).toStringAsFixed(1)}%'
                            ])
                        .toList(),
                    headerDecoration: pw.BoxDecoration(color: purple),
                    headerStyle: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9),
                    cellStyle: const pw.TextStyle(fontSize: 9),
                    cellPadding: const pw.EdgeInsets.all(8),
                    border: null,
                    oddRowDecoration:
                        const pw.BoxDecoration(color: PdfColors.grey100),
                    cellAlignments: {
                      1: pw.Alignment.centerRight,
                      2: pw.Alignment.centerRight
                    }),
              heading('Transactions'),
              if (analysis.transactions.isNotEmpty)
                pw.TableHelper.fromTextArray(
                    headers: [
                      'Date',
                      'Shop / description',
                      'Income',
                      'Expense'
                    ],
                    data: analysis.transactions
                        .map((t) => [
                              DateFormat('dd-MM-yyyy').format(t.date),
                              t.title.length > 160
                                  ? '${t.title.substring(0, 157)}...'
                                  : t.title,
                              t.type == TransactionType.income
                                  ? money(t.amount)
                                  : '-',
                              t.type == TransactionType.expense
                                  ? money(t.amount)
                                  : '-'
                            ])
                        .toList(),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2.5),
                      2: const pw.FlexColumnWidth(1.3),
                      3: const pw.FlexColumnWidth(1.3)
                    },
                    headerDecoration: pw.BoxDecoration(color: purple),
                    headerStyle: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9),
                    cellStyle: const pw.TextStyle(fontSize: 8),
                    cellPadding: const pw.EdgeInsets.all(7),
                    border: null,
                    oddRowDecoration:
                        const pw.BoxDecoration(color: PdfColors.grey100),
                    cellAlignments: {
                      2: pw.Alignment.centerRight,
                      3: pw.Alignment.centerRight
                    }),
            ]));
    return document.save();
  }

  /// Android/iOS write through the system picker, including cloud providers.
  /// Desktop pickers return a path which must be written by the caller.
  static Future<bool> save(Uint8List bytes, String name) async {
    final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save report',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: [name.split('.').last],
        bytes: bytes);
    if (path == null) return false;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return true;
  }

  static Future<void> share(Uint8List bytes, String name, Rect origin) async {
    final dir = await getTemporaryDirectory();
    final folder = await Directory(
            '${dir.path}/reports_${DateTime.now().microsecondsSinceEpoch}')
        .create();
    final file =
        await File('${folder.path}/$name').writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Spendly spending report', sharePositionOrigin: origin);
  }
}
