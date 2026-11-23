import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// An in-app cents-first amount pad. Arithmetic uses integer cents.
class AmountKeypad extends StatefulWidget {
  const AmountKeypad(
      {super.key,
      required this.controller,
      required this.onDone,
      required this.onDate,
      required this.toolbar,
      this.busy = false,
      this.onExpressionChanged,
      this.onTotalChanged,
      this.noteEditing = false});
  final TextEditingController controller;
  final VoidCallback onDone, onDate;
  final Widget toolbar;
  final bool busy, noteEditing;
  final ValueChanged<String>? onExpressionChanged, onTotalChanged;
  @override
  State<AmountKeypad> createState() => _AmountKeypadState();
}

class _AmountKeypadState extends State<AmountKeypad> {
  final List<String> terms = [];
  bool replace = false;
  String get expression => [
        ...terms,
        if (!replace || terms.isEmpty) widget.controller.text
      ].join(' ');
  int parseCents(String value) {
    final parts = value.split('.');
    return (int.tryParse(parts.first) ?? 0) * 100 +
        int.parse((parts.length > 1 ? parts[1] : '')
            .padRight(2, '0')
            .substring(0, 2));
  }

  void report() {
    final tokens = [
      ...terms,
      if (!replace || terms.isEmpty) widget.controller.text
    ];
    if (tokens.isEmpty) return;
    if (tokens.last == '+' || tokens.last == '−') tokens.removeLast();
    var total = tokens.isEmpty ? 0 : parseCents(tokens.first);
    for (var i = 1; i + 1 < tokens.length; i += 2) {
      total += (tokens[i] == '+' ? 1 : -1) * parseCents(tokens[i + 1]);
    }
    widget.onTotalChanged?.call((total / 100).toStringAsFixed(2));
    widget.onExpressionChanged?.call(expression);
  }

  void evaluate() {
    if (terms.isEmpty) return;
    final tokens = [...terms, if (!replace) widget.controller.text];
    if (tokens.last == '+' || tokens.last == '−') tokens.removeLast();
    var total = parseCents(tokens.first);
    for (var i = 1; i + 1 < tokens.length; i += 2) {
      total += (tokens[i] == '+' ? 1 : -1) * parseCents(tokens[i + 1]);
    }
    if (total < 0 || total > 10000000000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The total must be between 0 and 100,000,000.')));
      return;
    }
    final original = tokens.join(' ');
    widget.controller.text = (total / 100).toStringAsFixed(2);
    terms.clear();
    replace = true;
    widget.onTotalChanged?.call(widget.controller.text);
    widget.onExpressionChanged?.call('$original = ${widget.controller.text}');
  }

  void press(String key) {
    if (widget.busy) return;
    setState(() {
      if (key == '+' || key == '−') {
        if (terms.isNotEmpty && replace) {
          terms[terms.length - 1] = key;
        } else {
          terms.add(
              widget.controller.text.isEmpty ? '0' : widget.controller.text);
          terms.add(key);
        }
        replace = true;
        report();
        return;
      }
      if (key == '=' || (key == 'Done' && terms.isNotEmpty)) {
        evaluate();
        return;
      }
      if (key == 'Done') {
        widget.onDone();
        return;
      }
      var cents = replace ? 0 : parseCents(widget.controller.text);
      final startingNew = replace;
      replace = false;
      if (key == '⌫') {
        if (startingNew && terms.isNotEmpty) {
          terms.removeLast();
          cents = parseCents(terms.removeLast());
        } else {
          cents ~/= 10;
        }
      } else {
        cents = cents * (key == '00' ? 100 : 10) + int.parse(key);
        if (cents > 10000000000) return;
      }
      widget.controller.text = (cents / 100).toStringAsFixed(2);
      report();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.bgCard,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              widget.toolbar,
              const SizedBox(height: 6),
              if (!widget.noteEditing)
                for (final row in [
                  ['7', '8', '9', 'Date'],
                  ['4', '5', '6', '+'],
                  ['1', '2', '3', '−'],
                  ['00', '0', '⌫', 'Done']
                ])
                  Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(children: [
                        for (final key in row)
                          Expanded(
                              child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 3),
                                  child: Tooltip(
                                    message: key == 'Done'
                                        ? terms.isNotEmpty
                                            ? 'Calculate total'
                                            : 'Save Transaction'
                                        : key == '⌫'
                                            ? 'Delete digit'
                                            : key,
                                    child: SizedBox(
                                        height: ((MediaQuery.sizeOf(context)
                                                            .height *
                                                        .38 -
                                                    140) /
                                                4)
                                            .clamp(44.0, 54.0),
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              backgroundColor: key == 'Done'
                                                  ? AppTheme.primary
                                                  : palette.bgCardLight,
                                              foregroundColor: key == 'Done'
                                                  ? Colors.white
                                                  : palette.textPrimary,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12))),
                                          onPressed: widget.busy
                                              ? null
                                              : () => key == 'Date'
                                                  ? widget.onDate()
                                                  : press(key),
                                          child: key == 'Date'
                                              ? const Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                      Icon(
                                                          Icons
                                                              .calendar_today_outlined,
                                                          size: 18),
                                                      Text('Today/Custom',
                                                          style: TextStyle(
                                                              fontSize: 9))
                                                    ])
                                              : key == '⌫'
                                                  ? const Icon(
                                                      Icons.backspace_outlined,
                                                      size: 22)
                                                  : Text(
                                                      key == 'Done' &&
                                                              widget.busy
                                                          ? 'Saving…'
                                                          : key == 'Done' &&
                                                                  terms
                                                                      .isNotEmpty
                                                              ? '='
                                                              : key,
                                                      style: TextStyle(
                                                          fontSize:
                                                              key == 'Done'
                                                                  ? 14
                                                                  : 23)),
                                        )),
                                  ))),
                      ])),
            ]),
          )),
    );
  }
}
