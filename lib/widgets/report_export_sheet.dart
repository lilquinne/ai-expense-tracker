import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/report_selection.dart';
import '../models/transaction_model.dart';

class ReportExportSheet extends StatefulWidget {
  const ReportExportSheet(
      {super.key,
      required this.records,
      required this.initialDate,
      this.initialAnnual = false});
  final List<TransactionModel> records;
  final DateTime initialDate;
  final bool initialAnnual;
  @override
  State<ReportExportSheet> createState() => _ReportExportSheetState();
}

class _ReportExportSheetState extends State<ReportExportSheet> {
  late final List<int> _recordedYears;
  late final List<int> _monthlyYears;
  late bool _annual;
  late int _year, _month;
  @override
  void initState() {
    super.initState();
    _recordedYears = ReportSelection.recordedYears(widget.records);
    _monthlyYears = {
      ..._recordedYears,
      widget.initialDate.year,
      DateTime.now().year
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    _annual = widget.initialAnnual && _recordedYears.isNotEmpty;
    _year = _annual && !_recordedYears.contains(widget.initialDate.year)
        ? _recordedYears.first
        : widget.initialDate.year;
    _month = widget.initialDate.month;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: SingleChildScrollView(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Export PDF',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Choose a period for your spending report.'),
                    const SizedBox(height: 20),
                    SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          const ButtonSegment(
                              value: false, label: Text('Monthly')),
                          ButtonSegment(
                              value: true,
                              label: const Text('Annually'),
                              enabled: _recordedYears.isNotEmpty)
                        ],
                        selected: {_annual},
                        onSelectionChanged: (value) => setState(() {
                              _annual = value.single;
                              if (_annual && !_recordedYears.contains(_year))
                                _year = _recordedYears.first;
                            })),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<int>(
                        key: ValueKey('report-year-$_annual-$_year'),
                        initialValue: _year,
                        decoration: const InputDecoration(labelText: 'Year'),
                        items: [
                          for (final year
                              in _annual ? _recordedYears : _monthlyYears)
                            DropdownMenuItem(value: year, child: Text('$year'))
                        ],
                        onChanged: (value) => setState(() => _year = value!)),
                    if (!_annual) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                          initialValue: _month,
                          decoration: const InputDecoration(labelText: 'Month'),
                          items: [
                            for (var month = 1; month <= 12; month++)
                              DropdownMenuItem(
                                  value: month,
                                  child: Text(DateFormat('MMMM')
                                      .format(DateTime(2000, month))))
                          ],
                          onChanged: (value) =>
                              setState(() => _month = value!)),
                    ],
                    if (_recordedYears.isEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                          'Annual reports become available after you record income or an expense.'),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Share PDF'),
                        onPressed: () => Navigator.pop(
                            context,
                            ReportSelection(DateTime(_year, _month),
                                annual: _annual))),
                  ]))));
}
