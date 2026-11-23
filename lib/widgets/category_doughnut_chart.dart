import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/monthly_analysis.dart';
import '../utils/app_theme.dart';

class CategoryDoughnutChart extends StatelessWidget {
  const CategoryDoughnutChart(
      {super.key,
      required this.categories,
      required this.total,
      required this.currency});
  final List<CategoryTotal> categories;
  final double total;
  final String currency;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: LayoutBuilder(builder: (context, box) {
              final palette = AppPalette.of(context);
              final width = box.maxWidth;
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final deviceScale = (width / 360).clamp(1.0, 1.4);
              final labelHeight = 52.0 * scale * deviceScale;
              final totalHeight = 64.0 * scale * deviceScale;
              final radius = width * .225;
              final labels = <_Label>[];
              // Center the largest slice on the right so small slices fan out
              // across the left rather than bunching together at the top.
              final startAngle = total > 0 && categories.isNotEmpty
                  ? -categories.first.amount / total * math.pi
                  : -math.pi / 2;
              var angle = startAngle;
              for (final category in categories) {
                final sweep =
                    total > 0 ? category.amount / total * math.pi * 2 : 0.0;
                final middle = angle + sweep / 2;
                if (labels.length < 5) {
                  labels.add(_Label(category, middle, math.cos(middle) >= 0));
                }
                angle += sweep;
              }
              final count = math.max(labels.where((l) => l.right).length,
                  labels.where((l) => !l.right).length);
              final height = math.max(
                  270.0,
                  math.max(radius * 2 + labelHeight + 24,
                      count * (labelHeight + 8) + 24));
              final center = Offset(width / 2, height / 2);
              for (final right in [false, true]) {
                final side = labels.where((l) => l.right == right).toList()
                  ..sort(
                      (a, b) => math.sin(a.angle).compareTo(math.sin(b.angle)));
                final spacing = math.max(
                    labelHeight + 8, radius * 2 / math.max(1, side.length - 1));
                final first = center.dy - (side.length - 1) * spacing / 2;
                for (var i = 0; i < side.length; i++) {
                  side[i].y = first + i * spacing;
                }
              }
              final labelWidth = width * .23;
              final shades = Theme.of(context).brightness == Brightness.dark
                  ? [
                      0xFFF6F6F8,
                      0xFFE1E2E6,
                      0xFFBFC3CC,
                      0xFF9CA3B0,
                      0xFF798290,
                      0xFF596270
                    ]
                  : [
                      0xFF566170,
                      0xFF77818E,
                      0xFF929BA6,
                      0xFFADB4BD,
                      0xFFC4C9D0,
                      0xFFD7DBE0
                    ];
              return SizedBox(
                  height: height,
                  child: Stack(children: [
                    Positioned.fill(
                        child: CustomPaint(
                            painter: _SmoothLines(
                                labels,
                                center,
                                radius,
                                labelWidth,
                                palette.textMuted.withValues(alpha: .55)))),
                    Positioned(
                        left: center.dx - radius,
                        top: center.dy - radius,
                        width: radius * 2,
                        height: radius * 2,
                        child: PieChart(PieChartData(
                            startDegreeOffset: startAngle * 180 / math.pi,
                            centerSpaceRadius: radius * .74,
                            sectionsSpace: 2.5,
                            sections: [
                              for (var i = 0; i < categories.length; i++)
                                PieChartSectionData(
                                    value: categories[i].amount,
                                    color: Color(shades[i % shades.length]),
                                    radius: radius * .26,
                                    showTitle: false)
                            ]))),
                    Positioned(
                        left: center.dx - radius * .64,
                        top: center.dy - totalHeight / 2,
                        width: radius * 1.28,
                        height: totalHeight,
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Total',
                                  style: TextStyle(
                                      fontSize: 11 * deviceScale,
                                      color: palette.textMuted)),
                              const SizedBox(height: 5),
                              FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                      '$currency${(NumberFormat.compact()..maximumFractionDigits = 1).format(total).toLowerCase()}',
                                      style: TextStyle(
                                          fontSize: 18 * deviceScale,
                                          fontWeight: FontWeight.w700))),
                            ])),
                    for (final label in labels)
                      Positioned(
                          left: label.right ? width - labelWidth : 0,
                          top: label.y - labelHeight / 2,
                          width: labelWidth,
                          height: labelHeight,
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: label.right
                                  ? CrossAxisAlignment.start
                                  : CrossAxisAlignment.end,
                              children: [
                                FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(label.category.name,
                                        maxLines: 1,
                                        style: TextStyle(
                                            fontSize: 11 * deviceScale,
                                            height: 1.2,
                                            fontWeight: FontWeight.w700))),
                                const SizedBox(height: 2),
                                Text(
                                    '${(total > 0 ? label.category.amount / total * 100 : 0).toStringAsFixed(1)}%',
                                    style: TextStyle(
                                        fontSize: 10 * deviceScale,
                                        height: 1.2,
                                        color: palette.textMuted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ])),
                  ]));
            })),
      );
}

class _Label {
  _Label(this.category, this.angle, this.right);
  final CategoryTotal category;
  final double angle;
  final bool right;
  double y = 0;
}

class _SmoothLines extends CustomPainter {
  _SmoothLines(
      this.labels, this.center, this.radius, this.labelWidth, this.color);
  final List<_Label> labels;
  final Offset center;
  final double radius, labelWidth;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final label in labels) {
      final direction = Offset(math.cos(label.angle), math.sin(label.angle));
      final start = center + direction * (radius + 1);
      final end = Offset(
          label.right ? size.width - labelWidth - 4 : labelWidth + 4, label.y);
      final radial = center + direction * (radius + 8);
      final control = Offset(
          radial.dx
              .clamp(math.min(start.dx, end.dx), math.max(start.dx, end.dx)),
          radial.dy);
      final outerX = (control.dx + end.dx) / 2;
      canvas.drawPath(
          Path()
            ..moveTo(start.dx, start.dy)
            ..cubicTo(control.dx, control.dy, outerX, end.dy, end.dx, end.dy),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SmoothLines oldDelegate) => true;
}
