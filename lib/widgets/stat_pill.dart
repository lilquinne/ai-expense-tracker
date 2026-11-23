// lib/widgets/stat_pill.dart

import 'package:flutter/material.dart';

class StatPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const StatPill({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: color.withValues(alpha: 0.7), fontSize: 11)),
              Text(value,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          )),
        ],
      ),
    );
  }
}
