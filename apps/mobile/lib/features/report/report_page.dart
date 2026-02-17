import "package:flutter/material.dart";

import "../../core/network/babyai_api.dart";
import "../../core/widgets/simple_donut_chart.dart";
import "../../core/widgets/simple_stacked_bar_chart.dart";

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _daily;
  Map<String, dynamic>? _weekly;
  List<Map<String, dynamic>> _weeklyDailyReports = <Map<String, dynamic>>[];
  DateTime? _weekStartUtc;

  static const Map<String, Color> _categoryColors = <String, Color>{
    "sleep": Color(0xFF8C8ED4),
    "breastfeed": Color(0xFFE05A67),
    "formula": Color(0xFFE0B44C),
    "pee": Color(0xFF6FA8DC),
    "poo": Color(0xFF8A6A5A),
    "medication": Color(0xFF72B37E),
  };

  static const Map<String, String> _categoryLabels = <String, String>{
    "sleep": "Sleep",
    "breastfeed": "Breastfeed",
    "formula": "Formula",
    "pee": "Diaper (pee)",
    "poo": "Diaper (poo)",
    "medication": "Medication",
  };

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  DateTime _toWeekStart(DateTime day) {
    final DateTime utc = DateTime.utc(day.year, day.month, day.day);
    return utc.subtract(Duration(days: utc.weekday - DateTime.monday));
  }

  Future<Map<String, dynamic>> _loadDailySafe(DateTime day) async {
    try {
      return await BabyAIApi.instance.dailyReport(day);
    } catch (_) {
      return <String, dynamic>{
        "date": day.toIso8601String().split("T").first,
        "summary": <String>[],
      };
    }
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final DateTime now = DateTime.now().toUtc();
    final DateTime weekStart = _toWeekStart(now);
    try {
      final Future<Map<String, dynamic>> dailyFuture =
          BabyAIApi.instance.dailyReport(now);
      final Future<Map<String, dynamic>> weeklyFuture =
          BabyAIApi.instance.weeklyReport(weekStart);
      final List<Future<Map<String, dynamic>>> dayFutures =
          List<Future<Map<String, dynamic>>>.generate(
        7,
        (int index) => _loadDailySafe(weekStart.add(Duration(days: index))),
      );

      final Map<String, dynamic> daily = await dailyFuture;
      final Map<String, dynamic> weekly = await weeklyFuture;
      final List<Map<String, dynamic>> weeklyDaily = await Future.wait(
        dayFutures,
      );

      setState(() {
        _daily = daily;
        _weekly = weekly;
        _weeklyDailyReports = weeklyDaily;
        _weekStartUtc = weekStart;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int _firstInt(String line) {
    final RegExpMatch? match = RegExp(r"\d+").firstMatch(line);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(0) ?? "0") ?? 0;
  }

  _DayMetrics _parseDaily(Map<String, dynamic>? report) {
    final List<String> summary =
        ((report?["summary"] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic item) => item.toString())
            .toList();

    int feedings = 0;
    int breastfeedEvents = 0;
    int formulaML = 0;
    int sleepMinutes = 0;
    int peeCount = 0;
    int pooCount = 0;
    int medicationCount = 0;

    for (final String line in summary) {
      final String lower = line.toLowerCase();
      if (lower.contains("feeding events") || lower.startsWith("feedings")) {
        feedings = _firstInt(line);
      } else if (lower.contains("breastfeed")) {
        breastfeedEvents = _firstInt(line);
      } else if (lower.contains("formula total")) {
        formulaML = _firstInt(line);
      } else if (lower.contains("sleep total") ||
          lower.contains("sleep logged")) {
        sleepMinutes = _firstInt(line);
      } else if (lower.contains("diaper")) {
        final RegExpMatch? pee = RegExp(r"pee\s*(\d+)").firstMatch(lower);
        final RegExpMatch? poo = RegExp(r"poo\s*(\d+)").firstMatch(lower);
        peeCount = int.tryParse(pee?.group(1) ?? "0") ?? 0;
        pooCount = int.tryParse(poo?.group(1) ?? "0") ?? 0;
      } else if (lower.contains("medication")) {
        medicationCount = _firstInt(line);
      }
    }

    return _DayMetrics(
      feedings: feedings,
      breastfeedEvents: breastfeedEvents,
      formulaML: formulaML,
      sleepMinutes: sleepMinutes,
      peeCount: peeCount,
      pooCount: pooCount,
      medicationCount: medicationCount,
    );
  }

  Map<String, double> _toEstimatedMinutes(_DayMetrics metrics) {
    final int estimatedFormulaSessions = metrics.formulaML <= 0
        ? 0
        : (metrics.formulaML / 120).round().clamp(1, 12);
    final int inferredBreastfeedSessions = metrics.breastfeedEvents > 0
        ? metrics.breastfeedEvents
        : (metrics.feedings - estimatedFormulaSessions).clamp(0, 12);
    final int estimatedFormulaMinutes = metrics.feedings > 0
        ? estimatedFormulaSessions * 15
        : (metrics.formulaML <= 0 ? 0 : (metrics.formulaML / 30).round());

    return <String, double>{
      "sleep": metrics.sleepMinutes.toDouble(),
      "breastfeed": (inferredBreastfeedSessions * 18).toDouble(),
      "formula": estimatedFormulaMinutes.toDouble(),
      "pee": (metrics.peeCount * 5).toDouble(),
      "poo": (metrics.pooCount * 7).toDouble(),
      "medication": (metrics.medicationCount * 4).toDouble(),
    };
  }

  String _weekLabel() {
    final DateTime? start = _weekStartUtc;
    if (start == null) {
      return "-";
    }
    final DateTime end = start.add(const Duration(days: 6));
    return "${start.month}/${start.day} - ${end.month}/${end.day}";
  }

  String _dayLabel(DateTime day) {
    const List<String> labels = <String>[
      "Mon",
      "Tue",
      "Wed",
      "Thu",
      "Fri",
      "Sat",
      "Sun",
    ];
    return labels[day.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final _DayMetrics dailyMetrics = _parseDaily(_daily);
    final Map<String, double> dailyMinutes = _toEstimatedMinutes(dailyMetrics);
    final double dailyTotal =
        dailyMinutes.values.fold<double>(0, (a, b) => a + b);

    final List<DonutSliceData> pieSlices = _categoryLabels.keys
        .map(
          (String key) => DonutSliceData(
            label: _categoryLabels[key]!,
            value: dailyMinutes[key] ?? 0,
            color: _categoryColors[key]!,
          ),
        )
        .toList();

    final DateTime base = _weekStartUtc ?? _toWeekStart(DateTime.now().toUtc());
    final List<StackedBarData> weeklyBars = List<StackedBarData>.generate(
      7,
      (int index) {
        final DateTime day = base.add(Duration(days: index));
        final _DayMetrics metrics = _parseDaily(
          index < _weeklyDailyReports.length
              ? _weeklyDailyReports[index]
              : null,
        );
        final Map<String, double> minutes = _toEstimatedMinutes(metrics);
        return StackedBarData(
          label: _dayLabel(day),
          segments: <StackedBarSegment>[
            StackedBarSegment(
              value: minutes["sleep"] ?? 0,
              color: _categoryColors["sleep"]!,
            ),
            StackedBarSegment(
              value: minutes["breastfeed"] ?? 0,
              color: _categoryColors["breastfeed"]!,
            ),
            StackedBarSegment(
              value: minutes["formula"] ?? 0,
              color: _categoryColors["formula"]!,
            ),
            StackedBarSegment(
              value: minutes["pee"] ?? 0,
              color: _categoryColors["pee"]!,
            ),
            StackedBarSegment(
              value: minutes["poo"] ?? 0,
              color: _categoryColors["poo"]!,
            ),
            StackedBarSegment(
              value: minutes["medication"] ?? 0,
              color: _categoryColors["medication"]!,
            ),
          ],
        );
      },
    );

    final Map<dynamic, dynamic> trend =
        (_weekly?["trend"] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
    final List<String> suggestions =
        ((_weekly?["suggestions"] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic item) => item.toString())
            .toList();

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  "Statistics",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _loadReports,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text(
            "Week: ${_weekLabel()}",
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Text(
            "Color mapping: Sleep purple, Breastfeed red, Formula yellow",
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          if (_loading) ...<Widget>[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    "Daily activity share (estimated minutes)",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        SimpleDonutChart(slices: pieSlices),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Text(
                              "Today",
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text("${dailyTotal.toStringAsFixed(0)} min"),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categoryLabels.keys
                        .map(
                          (String key) => _LegendChip(
                            color: _categoryColors[key]!,
                            label: _categoryLabels[key]!,
                            value: "${(dailyMinutes[key] ?? 0).round()}m",
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    "Weekly activity bars (estimated minutes per day)",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 230,
                    child: SimpleStackedBarChart(bars: weeklyBars),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categoryLabels.keys
                        .map(
                          (String key) => _LegendChip(
                            color: _categoryColors[key]!,
                            label: _categoryLabels[key]!,
                            value: "",
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    "Weekly trend",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text("Formula total: ${trend["feeding_total_ml"] ?? "n/a"}"),
                  Text("Sleep total: ${trend["sleep_total_min"] ?? "n/a"}"),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    "Suggestions",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (suggestions.isEmpty)
                    const Text("No suggestions available."),
                  ...suggestions.map(
                    (String item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text("- $item"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text("$label ${value.isEmpty ? "" : value}"),
        ],
      ),
    );
  }
}

class _DayMetrics {
  const _DayMetrics({
    required this.feedings,
    required this.breastfeedEvents,
    required this.formulaML,
    required this.sleepMinutes,
    required this.peeCount,
    required this.pooCount,
    required this.medicationCount,
  });

  final int feedings;
  final int breastfeedEvents;
  final int formulaML;
  final int sleepMinutes;
  final int peeCount;
  final int pooCount;
  final int medicationCount;
}
