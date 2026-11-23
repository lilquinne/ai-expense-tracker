import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class TransactionNotes extends StatefulWidget {
  final String note;
  const TransactionNotes({super.key, required this.note});

  @override
  State<TransactionNotes> createState() => _TransactionNotesState();
}

class _TransactionNotesState extends State<TransactionNotes> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notes',
              style: TextStyle(
                  color: AppPalette.of(context).textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Text(widget.note,
              maxLines: _expanded ? null : 3,
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: TextStyle(
                  color: AppPalette.of(context).textPrimary,
                  fontSize: 14,
                  height: 1.45)),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Show less' : 'Show more'),
          ),
        ],
      );
}
