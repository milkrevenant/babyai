import "dart:math" as math;

import "package:flutter/material.dart";

class StackedBarSegment {
  const StackedBarSegment({
    required this.value,
    required this.color,
  });

  final double value;
  final Color color;
}

class StackedBarData {
  const StackedBarData({
    required this.label,
    required this.segments,
  });

  final String label;
  final List<StackedBarSegment> segments;
}

class SimpleStackedBarChart extends StatelessWidget {
  const SimpleStackedBarChart({
    super.key,
    required this.bars,
    this.emptyText = "No data",
  });

  final List<StackedBarData> bars;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final bool hasData = bars.any(
      (StackedBarData bar) => bar.segments.any(
        (StackedBarSegment segment) => segment.value > 0,
      ),
    );
    if (!hasData) {
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

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Column(
          children: <Widget>[
            Expanded(
              child: CustomPaint(
                painter: _SimpleStackedBarPainter(
                  bars: bars,
                  gridColor: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.35),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: bars
                  .map(
                    (StackedBarData bar) => Expanded(
                      child: Text(
                        bar.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
    );
  }
}

class _SimpleStackedBarPainter extends CustomPainter {
  _SimpleStackedBarPainter({
    required this.bars,
    required this.gridColor,
  });

  final List<StackedBarData> bars;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) {
      return;
    }
    const double topPadding = 8;
    const double bottomPadding = 4;
    const int gridLines = 3;

    final Rect chartArea = Rect.fromLTWH(
      0,
      topPadding,
      size.width,
      size.height - topPadding - bottomPadding,
    );
    if (chartArea.width <= 0 || chartArea.height <= 0) {
      return;
    }

    final Paint gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (int i = 0; i <= gridLines; i++) {
      final double y = chartArea.top + (chartArea.height * i / gridLines);
      canvas.drawLine(
        Offset(chartArea.left, y),
        Offset(chartArea.right, y),
        gridPaint,
      );
    }

    double maxTotal = 0;
    for (final StackedBarData bar in bars) {
      final double total = bar.segments
          .fold<double>(0, (double s, StackedBarSegment seg) => s + seg.value);
      maxTotal = math.max(maxTotal, total);
    }
    if (maxTotal <= 0) {
      return;
    }

    final double slotWidth = chartArea.width / bars.length;
    final double barWidth = math.max(8, slotWidth * 0.56);

    for (int i = 0; i < bars.length; i++) {
      final StackedBarData bar = bars[i];
      final double x =
          chartArea.left + (slotWidth * i) + ((slotWidth - barWidth) / 2);

      double currentBottom = chartArea.bottom;
      for (final StackedBarSegment segment in bar.segments) {
        if (segment.value <= 0) {
          continue;
        }
        final double height = (segment.value / maxTotal) * chartArea.height;
        final Rect rect = Rect.fromLTWH(
          x,
          currentBottom - height,
          barWidth,
          height,
        );
        final Paint segmentPaint = Paint()..color = segment.color;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          segmentPaint,
        );
        currentBottom -= height;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SimpleStackedBarPainter oldDelegate) {
    return oldDelegate.bars != bars || oldDelegate.gridColor != gridColor;
  }
}
