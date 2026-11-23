import 'package:flutter/material.dart';

/// Shared category presentation for the library and transaction rows.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge(
      {super.key,
      required this.icon,
      required this.colorValue,
      this.size = 44});
  final String icon;
  final int colorValue;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color(colorValue).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(icon, style: const TextStyle(fontSize: 20)),
      );
}
