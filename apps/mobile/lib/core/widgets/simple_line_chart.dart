import "dart:math" as math;

import "package:flutter/material.dart";

class SimpleLineChart extends StatelessWidget {
  const SimpleLineChart({
    super.key,
    required this.points,
    this.lineColor,
    this.fillColor,
    this.showDots = true,
  });

  final List<double> points;
  final Color? lineColor;
  final Color? fillColor;
  final bool showDots;

  @override
  Widget build(BuildContext context) {
    final List<double> safePoints = points.isEmpty ? <double>[0, 0] : points;
    final Color resolvedLine =
        lineColor ?? Theme.of(context).colorScheme.primary;
    final Color resolvedFill =
        fillColor ?? resolvedLine.withValues(alpha: 0.15);
    return CustomPaint(
      painter: _SimpleLineChartPainter(
        points: safePoints,
        lineColor: resolvedLine,
        fillColor: resolvedFill,
        showDots: showDots,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _SimpleLineChartPainter extends CustomPainter {
  _SimpleLineChartPainter({
    required this.points,
    required this.lineColor,
    required this.fillColor,
    required this.showDots,
  });

  final List<double> points;
  final Color lineColor;
  final Color fillColor;
  final bool showDots;

  @override
  void paint(Canvas canvas, Size size) {
    const double padding = 10;
    final Rect area = Rect.fromLTWH(
      padding,
      padding,
      size.width - (padding * 2),
      size.height - (padding * 2),
    );
    if (area.width <= 0 || area.height <= 0 || points.length < 2) {
      return;
    }

    final Paint gridPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    for (int i = 0; i < 3; i++) {
      final double y = area.top + (area.height * i / 2);
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), gridPaint);
    }

    final double minValue = points.reduce(math.min);
    final double maxValue = points.reduce(math.max);
    final double range =
        (maxValue - minValue).abs() < 0.0001 ? 1 : (maxValue - minValue);

    final List<Offset> offsets = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final double x = area.left + (area.width * i / (points.length - 1));
      final double normalized = (points[i] - minValue) / range;
      final double y = area.bottom - (normalized * area.height);
      offsets.add(Offset(x, y));
    }

    final Path linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final Offset point in offsets.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }

    final Path fillPath = Path.from(linePath)
      ..lineTo(offsets.last.dx, area.bottom)
      ..lineTo(offsets.first.dx, area.bottom)
      ..close();

    final Paint fillPaint = Paint()..color = fillColor;
    canvas.drawPath(fillPath, fillPaint);

    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, linePaint);

    if (showDots) {
      final Paint dotPaint = Paint()..color = lineColor;
      for (final Offset point in offsets) {
        canvas.drawCircle(point, 2.6, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SimpleLineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.showDots != showDots;
  }
}
