import "dart:math" as math;

import "package:flutter/material.dart";

class DonutSliceData {
  const DonutSliceData({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class SimpleDonutChart extends StatelessWidget {
  const SimpleDonutChart({
    super.key,
    required this.slices,
    this.strokeWidth = 24,
    this.emptyText = "No data",
  });

  final List<DonutSliceData> slices;
  final double strokeWidth;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final double total = slices.fold<double>(
      0,
      (double sum, DonutSliceData slice) => sum + slice.value,
    );
    if (total <= 0) {
      return Center(
        child: Text(
          emptyText,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return CustomPaint(
      painter: _SimpleDonutChartPainter(
        slices: slices,
        strokeWidth: strokeWidth,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _SimpleDonutChartPainter extends CustomPainter {
  _SimpleDonutChartPainter({
    required this.slices,
    required this.strokeWidth,
  });

  final List<DonutSliceData> slices;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final double total = slices.fold<double>(
      0,
      (double sum, DonutSliceData slice) => sum + slice.value,
    );
    if (total <= 0) {
      return;
    }

    final double shortestSide = math.min(size.width, size.height);
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Rect arcRect = Rect.fromCenter(
      center: center,
      width: shortestSide - 8,
      height: shortestSide - 8,
    );

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    double startAngle = -math.pi / 2;
    for (final DonutSliceData slice in slices) {
      if (slice.value <= 0) {
        continue;
      }
      final double sweep = (slice.value / total) * math.pi * 2;
      paint.color = slice.color;
      canvas.drawArc(arcRect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _SimpleDonutChartPainter oldDelegate) {
    return oldDelegate.slices != slices ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
