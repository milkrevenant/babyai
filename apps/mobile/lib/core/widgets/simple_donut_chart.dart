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
    this.onSliceTap,
  });

  final List<DonutSliceData> slices;
  final double strokeWidth;
  final String emptyText;
  final ValueChanged<int>? onSliceTap;

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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: onSliceTap == null
          ? null
          : (TapUpDetails details) {
              final RenderBox? box = context.findRenderObject() as RenderBox?;
              if (box == null) {
                return;
              }
              final Offset local = box.globalToLocal(details.globalPosition);
              final int tapped = _findSliceIndex(
                localPosition: local,
                size: box.size,
                slices: slices,
                strokeWidth: strokeWidth,
              );
              if (tapped >= 0) {
                onSliceTap!(tapped);
              }
            },
      child: CustomPaint(
        painter: _SimpleDonutChartPainter(
          slices: slices,
          strokeWidth: strokeWidth,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

int _findSliceIndex({
  required Offset localPosition,
  required Size size,
  required List<DonutSliceData> slices,
  required double strokeWidth,
}) {
  if (size.isEmpty) {
    return -1;
  }

  final double total = slices.fold<double>(
    0,
    (double sum, DonutSliceData slice) => sum + slice.value,
  );
  if (total <= 0) {
    return -1;
  }

  final double shortestSide = math.min(size.width, size.height);
  final Offset center = Offset(size.width / 2, size.height / 2);
  final double outerRadius = (shortestSide - 8) / 2;
  final double innerRadius = math.max(0, outerRadius - strokeWidth);
  final double distance = (localPosition - center).distance;
  if (distance < innerRadius || distance > outerRadius) {
    return -1;
  }

  double angle = math.atan2(
    localPosition.dy - center.dy,
    localPosition.dx - center.dx,
  );
  angle += math.pi / 2;
  while (angle < 0) {
    angle += math.pi * 2;
  }
  while (angle >= math.pi * 2) {
    angle -= math.pi * 2;
  }

  double cursor = 0;
  for (int i = 0; i < slices.length; i++) {
    final DonutSliceData slice = slices[i];
    if (slice.value <= 0) {
      continue;
    }
    final double sweep = (slice.value / total) * math.pi * 2;
    final double next = cursor + sweep;
    if (angle >= cursor && angle < next) {
      return i;
    }
    cursor = next;
  }
  return -1;
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
