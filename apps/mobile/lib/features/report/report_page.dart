import "dart:async";
import "dart:math" as math;

import "package:flutter/material.dart";

import "../../core/i18n/app_i18n.dart";
import "../../core/network/babyai_api.dart";
import "../../core/widgets/simple_donut_chart.dart";
import "../../core/widgets/simple_line_chart.dart";
import "../../core/widgets/app_svg_icon.dart";

const Duration _kTabAnimationDuration = Duration(milliseconds: 220);
const int _minutesPerDay = 24 * 60;

class _SemanticColors {
  static const Color sleep = Color(0xFF9B7AD8);
  static const Color feed = Color(0xFF2D9CDB);
  static const Color diaper = Color(0xFF1CA79A);
  static const Color play = Color(0xFFF09819);
  static const Color medication = Color(0xFFE84076);
  static const Color hospital = Color(0xFF8E44AD);
  static const Color memo = Color(0xFFA546C9);
  static const Color other = Color(0xFF9AA4B2);
}

enum ReportRange { daily, weekly, monthly }

class ReportPage extends StatefulWidget {
  const ReportPage({
    super.key,
    this.initialRange = ReportRange.daily,
  });

  final ReportRange initialRange;

  @override
  State<ReportPage> createState() => ReportPageState();
}

class ReportPageState extends State<ReportPage> {
  bool _loading = false;
  String? _error;

  ReportRange _selected = ReportRange.daily;
  // Anchor day used across daily/weekly/monthly views.
  DateTime _todayUtc = _utcDate(DateTime.now().toUtc());
  DateTime _weekStartUtc = _toWeekStart(_utcDate(DateTime.now().toUtc()));
  DateTime _monthStartUtc = DateTime.utc(
    DateTime.now().toUtc().year,
    DateTime.now().toUtc().month,
    1,
  );

  Map<DateTime, _DayStats> _statsByDay = <DateTime, _DayStats>{};
  Map<String, dynamic>? _weeklyReport;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialRange;
    unawaited(_loadReports());
  }

  ReportRange get selectedRange => _selected;
  String get navigationDateLabel => _selectedRangeDateLabel();
  DateTime get datePickerInitialDateLocal {
    switch (_selected) {
      case ReportRange.daily:
        return _todayUtc.toLocal();
      case ReportRange.weekly:
        return _weekStartUtc.toLocal();
      case ReportRange.monthly:
        return _monthStartUtc.toLocal();
    }
  }

  void setRange(ReportRange next) {
    if (_selected == next) {
      return;
    }
    setState(() => _selected = next);
  }

  Future<void> setFocusDate(DateTime pickedDate) async {
    final DateTime nextUtc = _utcDate(pickedDate.toUtc());
    if (_isSameUtcDate(_todayUtc, nextUtc)) {
      await _loadReports();
      return;
    }
    setState(() {
      _todayUtc = nextUtc;
      _weekStartUtc = _toWeekStart(nextUtc);
      _monthStartUtc = DateTime.utc(nextUtc.year, nextUtc.month, 1);
    });
    await _loadReports();
  }

  Future<void> setFocusWeekStart(DateTime pickedDate) async {
    final DateTime pickedUtc = _utcDate(pickedDate.toUtc());
    final DateTime weekStartUtc = _toWeekStart(pickedUtc);
    if (_isSameUtcDate(_weekStartUtc, weekStartUtc)) {
      await _loadReports();
      return;
    }
    setState(() {
      _todayUtc = weekStartUtc;
      _weekStartUtc = weekStartUtc;
      _monthStartUtc = DateTime.utc(weekStartUtc.year, weekStartUtc.month, 1);
    });
    await _loadReports();
  }

  Future<void> setFocusMonthStart(DateTime pickedDate) async {
    final DateTime pickedUtc = _utcDate(pickedDate.toUtc());
    final DateTime monthStartUtc =
        DateTime.utc(pickedUtc.year, pickedUtc.month, 1);
    if (_isSameUtcDate(_monthStartUtc, monthStartUtc)) {
      await _loadReports();
      return;
    }
    setState(() {
      _todayUtc = monthStartUtc;
      _weekStartUtc = _toWeekStart(monthStartUtc);
      _monthStartUtc = monthStartUtc;
    });
    await _loadReports();
  }

  Future<void> refreshData() async {
    await _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final DateTime focusedDayUtc = _utcDate(_todayUtc.toUtc());
    final DateTime weekStartUtc = _toWeekStart(focusedDayUtc);
    final DateTime monthStartUtc =
        DateTime.utc(focusedDayUtc.year, focusedDayUtc.month, 1);
    final int monthDayCount =
        DateUtils.getDaysInMonth(monthStartUtc.year, monthStartUtc.month);

    final List<DateTime> weekDays = List<DateTime>.generate(
      7,
      (int i) => weekStartUtc.add(Duration(days: i)),
    );
    final List<DateTime> monthDays = List<DateTime>.generate(
      monthDayCount,
      (int i) => monthStartUtc.add(Duration(days: i)),
    );

    final Map<String, DateTime> uniqueDays = <String, DateTime>{
      for (final DateTime day in monthDays) _dayKey(day): day,
      for (final DateTime day in weekDays) _dayKey(day): day,
      _dayKey(focusedDayUtc): focusedDayUtc,
    };

    try {
      final Future<Map<String, dynamic>> weeklyFuture =
          _loadWeeklySafe(weekStartUtc);
      final Map<String, _DayStats> parsed = <String, _DayStats>{};

      await Future.wait(uniqueDays.entries.map(
        (MapEntry<String, DateTime> entry) async {
          final Map<String, dynamic> report = await _loadDailySafe(entry.value);
          parsed[entry.key] = _DayStats.fromReport(entry.value, report);
        },
      ));

      if (!mounted) {
        return;
      }

      setState(() {
        _todayUtc = focusedDayUtc;
        _weekStartUtc = weekStartUtc;
        _monthStartUtc = monthStartUtc;
        _statsByDay = <DateTime, _DayStats>{
          for (final MapEntry<String, DateTime> entry in uniqueDays.entries)
            entry.value: parsed[entry.key] ?? _DayStats.empty(entry.value),
        };
      });

      final Map<String, dynamic> weekly = await weeklyFuture;
      if (!mounted) {
        return;
      }
      setState(() => _weeklyReport = weekly);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<Map<String, dynamic>> _loadDailySafe(DateTime dayUtc) async {
    try {
      return await BabyAIApi.instance.dailyReport(dayUtc);
    } catch (_) {
      return <String, dynamic>{"summary": <String>[], "events": <dynamic>[]};
    }
  }

  Future<Map<String, dynamic>> _loadWeeklySafe(DateTime weekStartUtc) async {
    try {
      return await BabyAIApi.instance.weeklyReport(weekStartUtc);
    } catch (_) {
      return <String, dynamic>{
        "trend": <String, dynamic>{},
        "suggestions": <String>[]
      };
    }
  }

  _DayStats _stats(DateTime dayUtc) {
    return _statsByDay[dayUtc] ?? _DayStats.empty(dayUtc);
  }

  String _selectedRangeDateLabel() {
    String ymd(DateTime dayUtc) {
      final DateTime local = dayUtc.toLocal();
      final String y = local.year.toString().padLeft(4, "0");
      final String m = local.month.toString().padLeft(2, "0");
      final String d = local.day.toString().padLeft(2, "0");
      return "$y-$m-$d";
    }

    switch (_selected) {
      case ReportRange.daily:
        return ymd(_todayUtc);
      case ReportRange.weekly:
        final DateTime start = _weekStartUtc;
        final DateTime end = _weekStartUtc.add(const Duration(days: 6));
        return "${ymd(start)} ~ ${ymd(end)}";
      case ReportRange.monthly:
        final DateTime local = _monthStartUtc.toLocal();
        final String y = local.year.toString().padLeft(4, "0");
        final String m = local.month.toString().padLeft(2, "0");
        return "$y-$m";
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<_DayStats> weekDays = List<_DayStats>.generate(
      7,
      (int i) => _stats(_weekStartUtc.add(Duration(days: i))),
      growable: false,
    );
    final List<_DayStats> monthDays = List<_DayStats>.generate(
      DateUtils.getDaysInMonth(_monthStartUtc.year, _monthStartUtc.month),
      (int i) => _stats(_monthStartUtc.add(Duration(days: i))),
      growable: false,
    );

    final Map<dynamic, dynamic> weeklyTrend =
        (_weeklyReport?["trend"] as Map<dynamic, dynamic>?) ??
            <dynamic, dynamic>{};
    final List<String> suggestions =
        ((_weeklyReport?["suggestions"] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic item) => item.toString())
            .toList(growable: false);
    final DateTime nowUtc = DateTime.now().toUtc();
    final List<_EventDetail> knownEvents = _statsByDay.values
        .expand((_DayStats day) => day.events)
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          if (_loading) ...<Widget>[
            const SizedBox(height: 2),
            const LinearProgressIndicator(minHeight: 3),
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
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: _kTabAnimationDuration,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            transitionBuilder: (Widget child, Animation<double> animation) {
              final Animation<Offset> slide = Tween<Offset>(
                begin: const Offset(0.015, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _buildBody(
              context,
              today: _stats(_todayUtc),
              weekDays: weekDays,
              monthDays: monthDays,
              weeklyTrend: weeklyTrend,
              suggestions: suggestions,
              nowUtc: nowUtc,
              knownEvents: knownEvents,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required _DayStats today,
    required List<_DayStats> weekDays,
    required List<_DayStats> monthDays,
    required Map<dynamic, dynamic> weeklyTrend,
    required List<String> suggestions,
    required DateTime nowUtc,
    required List<_EventDetail> knownEvents,
  }) {
    switch (_selected) {
      case ReportRange.daily:
        return _DailyView(
          key: const ValueKey<String>("daily"),
          day: today,
          nowUtc: nowUtc,
          history: knownEvents,
        );
      case ReportRange.weekly:
        return _WeeklyView(
          key: const ValueKey<String>("weekly"),
          days: weekDays,
          weeklyTrend: weeklyTrend,
          suggestions: suggestions,
        );
      case ReportRange.monthly:
        return _MonthlyView(
          key: const ValueKey<String>("monthly"),
          days: monthDays,
        );
    }
  }
}

DateTime _utcDate(DateTime value) {
  return DateTime.utc(value.year, value.month, value.day);
}

DateTime _toWeekStart(DateTime dayUtc) {
  return dayUtc.subtract(Duration(days: dayUtc.weekday - DateTime.monday));
}

String _dayKey(DateTime dayUtc) {
  final String y = dayUtc.year.toString().padLeft(4, "0");
  final String m = dayUtc.month.toString().padLeft(2, "0");
  final String d = dayUtc.day.toString().padLeft(2, "0");
  return "$y-$m-$d";
}

bool _isSameUtcDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DailyView extends StatelessWidget {
  const _DailyView({
    super.key,
    required this.day,
    required this.nowUtc,
    required this.history,
  });

  final _DayStats day;
  final DateTime nowUtc;
  final List<_EventDetail> history;

  @override
  Widget build(BuildContext context) {
    final List<_DonutCategory> ringSegments =
        _buildDailyClockSegments(context, day);
    final List<DonutSliceData> ring =
        ringSegments.map((_DonutCategory item) => item.slice).toList();
    final List<DonutSliceData> legendSlices = _buildDonutCategories(
      context,
      day,
    ).map((_DonutCategory item) => item.slice).toList();
    final int totalEvents = day.events.length;
    final _RecentEventHighlights highlights =
        _buildRecentEventHighlights(history, nowUtc);

    return Column(
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _DailyHighlightTile(
                    title: "Since last feed",
                    elapsed:
                        _formatElapsedSince(highlights.lastFeedUtc, nowUtc),
                    timestamp: _formatHighlightStamp(highlights.lastFeedUtc),
                    accent: _SemanticColors.feed,
                    iconAsset: AppSvgAsset.feeding,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DailyHighlightTile(
                    title: "Since sleep ended",
                    elapsed: _formatElapsedSince(
                      highlights.lastSleepEndUtc,
                      nowUtc,
                    ),
                    timestamp:
                        _formatHighlightStamp(highlights.lastSleepEndUtc),
                    accent: _SemanticColors.sleep,
                    iconAsset: AppSvgAsset.sleepCrescentPurple,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  tr(context,
                      ko: "Daily Activity",
                      en: "Daily Activity",
                      es: "Actividad diaria"),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 280,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      SimpleDonutChart(
                        slices: ring,
                        strokeWidth: 30,
                        onSliceTap: (int index) {
                          if (index < 0 || index >= ringSegments.length) {
                            return;
                          }
                          final _DonutCategory selected = ringSegments[index];
                          if (selected.events.isEmpty) {
                            return;
                          }
                          _showEventDetailsSheet(
                            context,
                            title: selected.slice.label,
                            events: selected.events,
                          );
                        },
                      ),
                      const _DailyClockDialLabels(),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            "$totalEvents",
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr(context,
                                ko: "Total Events",
                                en: "Total Events",
                                es: "Eventos totales"),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _LegendRow(slices: legendSlices),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  tr(context,
                      ko: "Timeline", en: "Timeline", es: "Linea de tiempo"),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const _TimelineAxisLabels(),
                const SizedBox(height: 8),
                _TimelineBand(
                  blocks: day.sleepBlocks,
                  feed: day.feedMarks,
                  diaper: day.diaperMarks,
                  health: day.healthMarks,
                  notes: day.noteMarks,
                  dense: false,
                  onEventTap: (_EventDetail event) {
                    _showEventDetailsSheet(
                      context,
                      title: _eventTypeLabel(context, event.displayType),
                      events: <_EventDetail>[event],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _InfoPill(label: "Feeds", value: "${day.feedCount}"),
                    _InfoPill(label: "Formula", value: "${day.formulaMl} ml"),
                    _InfoPill(label: "Pee", value: "${day.peeCount}"),
                    _InfoPill(label: "Poo", value: "${day.pooCount}"),
                    _InfoPill(
                        label: "Medication", value: "${day.medicationCount}"),
                    _InfoPill(label: "Clinic", value: "${day.clinicVisits}"),
                    _InfoPill(label: "Memo", value: "${day.memoCount}"),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WeeklyView extends StatelessWidget {
  const _WeeklyView({
    super.key,
    required this.days,
    required this.weeklyTrend,
    required this.suggestions,
  });

  final List<_DayStats> days;
  final Map<dynamic, dynamic> weeklyTrend;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    final int totalSleepMinutes =
        days.fold<int>(0, (int s, _DayStats d) => s + d.sleepMinutes);
    final int totalFormulaMl =
        days.fold<int>(0, (int s, _DayStats d) => s + d.formulaMl);
    final int totalPee =
        days.fold<int>(0, (int s, _DayStats d) => s + d.peeCount);
    final int totalPoo =
        days.fold<int>(0, (int s, _DayStats d) => s + d.pooCount);
    final int totalMedication =
        days.fold<int>(0, (int s, _DayStats d) => s + d.medicationCount);
    final String insight = suggestions.isNotEmpty
        ? suggestions.first
        : "Feed trend: ${weeklyTrend["feeding_total_ml"] ?? "-"}. "
            "Sleep trend: ${weeklyTrend["sleep_total_min"] ?? "-"}.";
    const double dateLabelWidth = 44;

    return Column(
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text("Weekly Timeline",
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                const Row(
                  children: <Widget>[
                    SizedBox(width: dateLabelWidth),
                    SizedBox(width: 8),
                    Expanded(
                      child: _TimelineAxisLabels(hourOnly: true),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...days.map(
                  (_DayStats day) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: dateLabelWidth,
                          child: Text(
                            "${day.dayUtc.month}/${day.dayUtc.day}",
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TimelineBand(
                            blocks: day.sleepBlocks,
                            feed: day.feedMarks,
                            diaper: day.diaperMarks,
                            health: day.healthMarks,
                            notes: day.noteMarks,
                            dense: true,
                            onEventTap: (_EventDetail event) {
                              _showEventDetailsSheet(
                                context,
                                title: _eventTypeLabel(
                                  context,
                                  event.displayType,
                                ),
                                events: <_EventDetail>[event],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _WeeklyMetricChip(
                      iconAsset: AppSvgAsset.sleepCrescentPurple,
                      accent: _SemanticColors.sleep,
                      label: "수면",
                      value: _formatDurationMinutes(totalSleepMinutes),
                    ),
                    _WeeklyMetricChip(
                      iconAsset: AppSvgAsset.feeding,
                      accent: _SemanticColors.feed,
                      label: "분유",
                      value: "${totalFormulaMl}ml",
                    ),
                    _WeeklyMetricChip(
                      iconAsset: AppSvgAsset.diaper,
                      accent: _SemanticColors.diaper,
                      label: "소변",
                      value: "$totalPee",
                    ),
                    _WeeklyMetricChip(
                      iconAsset: AppSvgAsset.diaper,
                      accent: _SemanticColors.diaper,
                      label: "대변",
                      value: "$totalPoo",
                    ),
                    _WeeklyMetricChip(
                      iconAsset: AppSvgAsset.medicine,
                      accent: _SemanticColors.medication,
                      label: "투약",
                      value: "$totalMedication",
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text("Weekly Insight",
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  insight,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthlyView extends StatelessWidget {
  const _MonthlyView({super.key, required this.days});

  final List<_DayStats> days;

  @override
  Widget build(BuildContext context) {
    final int dayCount = days.isEmpty ? 1 : days.length;
    final int avgSleep =
        (days.fold<int>(0, (int s, _DayStats d) => s + d.sleepMinutes) /
                dayCount)
            .round();
    final double avgFeed =
        days.fold<int>(0, (int s, _DayStats d) => s + d.feedCount) / dayCount;
    final int clinicVisits =
        days.fold<int>(0, (int s, _DayStats d) => s + d.clinicVisits);

    final List<double> points =
        days.map((_DayStats d) => d.sleepMinutes / 60).toList(growable: false);
    final double trendDelta = _sleepTrendDelta(days);
    final List<_WeekBreakdown> breakdown = _buildWeeklyBreakdown(days);
    final _MonthlyInsights insights = _buildMonthlyInsights(days);
    final String sleepPattern = _monthlySleepPatternText(insights);
    final String feedPattern = _monthlyFeedPatternText(insights);

    return Column(
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = (constraints.maxWidth - 16) / 3;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                SizedBox(
                  width: width,
                  child: _StatsCard(
                    title: "Avg Sleep",
                    value: _formatHour(avgSleep / 60),
                    iconAsset: AppSvgAsset.sleepCrescentPurple,
                    accent: _SemanticColors.sleep,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _StatsCard(
                    title: "Avg Feedings/Day",
                    value: _formatCount(avgFeed),
                    iconAsset: AppSvgAsset.feeding,
                    accent: _SemanticColors.feed,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _StatsCard(
                    title: "Clinic Visits",
                    value: "$clinicVisits",
                    iconAsset: AppSvgAsset.clinicStethoscope,
                    accent: _SemanticColors.hospital,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text("Sleep Trend",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    _TrendBadge(delta: trendDelta),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 188,
                  child: SimpleLineChart(
                    points: points,
                    lineColor: Theme.of(context).colorScheme.primary,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.16),
                  ),
                ),
                const SizedBox(height: 6),
                _MonthAxis(lastDay: days.isEmpty ? 1 : days.last.dayUtc.day),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  "Monthly Insights",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _InfoPill(
                      label: "Avg Bedtime",
                      value: _formatMinuteOfDay(insights.avgBedtimeMinute),
                    ),
                    _InfoPill(
                      label: "Avg Wake-up",
                      value: _formatMinuteOfDay(insights.avgWakeMinute),
                    ),
                    _InfoPill(
                      label: "Longest Sleep",
                      value:
                          _formatDurationMinutes(insights.longestSleepMinutes),
                    ),
                    _InfoPill(
                      label: "Avg Feed Gap",
                      value: _formatDurationMinutes(
                        insights.avgFeedIntervalMinutes,
                      ),
                    ),
                    _InfoPill(
                      label: "Peak Feed",
                      value: _formatFeedWindow(insights.peakFeedHour),
                    ),
                    _InfoPill(
                      label: "Formula Total",
                      value: "${insights.totalFormulaMl} ml",
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "Sleep pattern: $sleepPattern",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Feed pattern: $feedPattern",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Weekly Breakdown",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        if (breakdown.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text("No weekly records."),
            ),
          )
        else
          ...breakdown.map(
            (_WeekBreakdown item) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  child: Center(
                    child: AppSvgIcon(
                      AppSvgAsset.stats,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                title: Text(item.title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(item.range),
                trailing: Text(
                  _formatHour(item.avgSleepMinutes / 60),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.title,
    required this.value,
    required this.iconAsset,
    required this.accent,
  });

  final String title;
  final String value;
  final String iconAsset;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppSvgIcon(iconAsset, size: 16, color: accent),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyHighlightTile extends StatelessWidget {
  const _DailyHighlightTile({
    required this.title,
    required this.elapsed,
    required this.timestamp,
    required this.accent,
    required this.iconAsset,
  });

  final String title;
  final String elapsed;
  final String timestamp;
  final Color accent;
  final String iconAsset;

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppSvgIcon(iconAsset, size: 15, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            elapsed,
            style: TextStyle(
              color: accent,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            timestamp,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.slices});

  final List<DonutSliceData> slices;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: slices
          .where((DonutSliceData item) => item.value > 0)
          .map(
            (DonutSliceData item) =>
                _Legend(color: item.color, label: item.label),
          )
          .toList(growable: false),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _DailyClockDialLabels extends StatelessWidget {
  const _DailyClockDialLabels();

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    final TextStyle style = TextStyle(
      color: color.onSurfaceVariant,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );

    Widget label(String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: color.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Text(value, style: style),
      );
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double dialSize =
              math.min(constraints.maxWidth, constraints.maxHeight);
          return Center(
            child: SizedBox(
              width: dialSize,
              height: dialSize,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Stack(
                  children: <Widget>[
                    Align(
                        alignment: Alignment.topCenter, child: label("00:00")),
                    Align(
                      alignment: Alignment.centerRight,
                      child: label("06:00"),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: label("12:00"),
                    ),
                    Align(
                        alignment: Alignment.centerLeft, child: label("18:00")),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TimelineAxisLabels extends StatelessWidget {
  const _TimelineAxisLabels({this.hourOnly = false});

  final bool hourOnly;

  @override
  Widget build(BuildContext context) {
    final List<String> labels = hourOnly
        ? const <String>["00", "06", "12", "18", "24"]
        : const <String>["00:00", "06:00", "12:00", "18:00", "24:00"];
    final TextStyle style = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: hourOnly ? 10 : 11,
      fontWeight: FontWeight.w600,
    );

    return Row(
      children: List<Widget>.generate(labels.length, (int index) {
        final TextAlign align;
        if (index == 0) {
          align = TextAlign.left;
        } else if (index == labels.length - 1) {
          align = TextAlign.right;
        } else {
          align = TextAlign.center;
        }
        return Expanded(
          child: Text(
            labels[index],
            textAlign: align,
            style: style,
          ),
        );
      }),
    );
  }
}

class _TimelineBand extends StatelessWidget {
  const _TimelineBand({
    required this.blocks,
    required this.feed,
    required this.diaper,
    required this.health,
    required this.notes,
    required this.dense,
    this.onEventTap,
  });

  final List<_Block> blocks;
  final List<_Mark> feed;
  final List<_Mark> diaper;
  final List<_Mark> health;
  final List<_Mark> notes;
  final bool dense;
  final ValueChanged<_EventDetail>? onEventTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    final double top = dense ? 10 : 12;
    final double bottom = dense ? 10 : 12;
    final int maxIcons = dense ? 4 : 9;

    return SizedBox(
      height: dense ? 38 : 48,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;

          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                top: top,
                bottom: bottom,
                child: Container(
                  decoration: BoxDecoration(
                    color: color.surfaceContainerHighest
                        .withValues(alpha: dense ? 0.48 : 0.42),
                    borderRadius: BorderRadius.circular(dense ? 6 : 8),
                    border: Border.all(
                      color: color.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
              ...List<Widget>.generate(5, (int i) {
                final double x = width * (i / 4);
                return Positioned(
                  left: _clampD(x - 0.5, 0, width - 1),
                  top: top,
                  bottom: bottom,
                  child: Container(
                    width: 1,
                    color: color.outlineVariant.withValues(alpha: 0.25),
                  ),
                );
              }),
              ...blocks.map((_Block b) {
                final double left = width * (b.start / _minutesPerDay);
                final double raw = width * ((b.end - b.start) / _minutesPerDay);
                Widget child = Container(
                  decoration: BoxDecoration(
                    color: _SemanticColors.sleep
                        .withValues(alpha: dense ? 0.9 : 0.82),
                    borderRadius: BorderRadius.circular(dense ? 4 : 6),
                    border: Border.all(
                      color: color.surface.withValues(alpha: 0.82),
                      width: dense ? 0.5 : 0.8,
                    ),
                  ),
                );
                if (onEventTap != null && b.event != null) {
                  child = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onEventTap!(b.event!),
                    child: child,
                  );
                }
                return Positioned(
                  left: _clampD(left, 0, width),
                  width: math.max(raw, dense ? 3 : 5),
                  top: top + 1,
                  bottom: bottom + 1,
                  child: child,
                );
              }),
              ...feed.map((_Mark mark) {
                final double x = width * (mark.minute / _minutesPerDay);
                final double hitWidth = dense ? 10 : 12;
                Widget child = Center(
                  child: Container(
                    width: dense ? 3 : 4,
                    height: dense ? 12 : 16,
                    decoration: BoxDecoration(
                      color: _SemanticColors.feed,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: color.surface.withValues(alpha: 0.9),
                        width: dense ? 0.45 : 0.7,
                      ),
                    ),
                  ),
                );
                if (onEventTap != null && mark.event != null) {
                  child = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onEventTap!(mark.event!),
                    child: child,
                  );
                }
                return Positioned(
                  left: _clampD(x - (hitWidth / 2), 0, width - hitWidth),
                  width: hitWidth,
                  top: top + 1,
                  bottom: bottom + 1,
                  child: child,
                );
              }),
              ...diaper.map((_Mark mark) {
                final double x = width * (mark.minute / _minutesPerDay);
                final double hitWidth = dense ? 10 : 12;
                Widget child = Center(
                  child: Container(
                    width: dense ? 3 : 4,
                    height: dense ? 10 : 14,
                    decoration: BoxDecoration(
                      color: _SemanticColors.diaper,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: color.surface.withValues(alpha: 0.9),
                        width: dense ? 0.45 : 0.7,
                      ),
                    ),
                  ),
                );
                if (onEventTap != null && mark.event != null) {
                  child = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onEventTap!(mark.event!),
                    child: child,
                  );
                }
                return Positioned(
                  left: _clampD(x - (hitWidth / 2), 0, width - hitWidth),
                  width: hitWidth,
                  top: top + 2,
                  bottom: bottom + 2,
                  child: child,
                );
              }),
              ...health.take(maxIcons).map((_Mark mark) {
                final double x = width * (mark.minute / _minutesPerDay);
                final double size = dense ? 15 : 18;
                final _EventVisualStyle style = _eventVisualStyle(mark.type);
                Widget child = Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: dense ? 0.22 : 0.26),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: style.color.withValues(alpha: 0.92),
                      width: dense ? 1 : 1.2,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color:
                            style.color.withValues(alpha: dense ? 0.22 : 0.3),
                        blurRadius: dense ? 3 : 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Center(
                    child: AppSvgIcon(
                      style.iconAsset,
                      size: dense ? 9 : 11,
                      color: style.color,
                    ),
                  ),
                );
                if (onEventTap != null && mark.event != null) {
                  child = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onEventTap!(mark.event!),
                    child: child,
                  );
                }
                return Positioned(
                  left: _clampD(x - (size / 2), 0, width - size),
                  top: dense ? -4 : -7,
                  child: child,
                );
              }),
              ...notes.take(maxIcons).map((_Mark mark) {
                final double x = width * (mark.minute / _minutesPerDay);
                final double size = dense ? 15 : 18;
                final _EventVisualStyle style = _eventVisualStyle(mark.type);
                Widget child = Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: dense ? 0.22 : 0.26),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: style.color.withValues(alpha: 0.92),
                      width: dense ? 1 : 1.2,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color:
                            style.color.withValues(alpha: dense ? 0.22 : 0.3),
                        blurRadius: dense ? 3 : 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Center(
                    child: AppSvgIcon(
                      style.iconAsset,
                      size: dense ? 9 : 11,
                      color: style.color,
                    ),
                  ),
                );
                if (onEventTap != null && mark.event != null) {
                  child = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onEventTap!(mark.event!),
                    child: child,
                  );
                }
                return Positioned(
                  left: _clampD(x - (size / 2), 0, width - size),
                  bottom: dense ? -4 : -7,
                  child: child,
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _WeeklyMetricChip extends StatelessWidget {
  const _WeeklyMetricChip({
    required this.iconAsset,
    required this.accent,
    required this.label,
    required this.value,
  });

  final String iconAsset;
  final Color accent;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppSvgIcon(iconAsset, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            "$label $value",
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        "$label $value",
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.delta});

  final double delta;

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    final bool up = delta >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (up ? color.primaryContainer : color.errorContainer)
            .withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _formatTrend(delta),
        style: TextStyle(
          color: up ? color.primary : color.error,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MonthAxis extends StatelessWidget {
  const _MonthAxis({required this.lastDay});

  final int lastDay;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text("1", style: style),
        Text("${math.min(7, lastDay)}", style: style),
        Text("${math.min(14, lastDay)}", style: style),
        Text("${math.min(21, lastDay)}", style: style),
        Text("$lastDay", style: style),
      ],
    );
  }
}

class _DonutCategory {
  const _DonutCategory({
    required this.slice,
    required this.events,
  });

  final DonutSliceData slice;
  final List<_EventDetail> events;
}

class _ClockPaintSpan {
  const _ClockPaintSpan({
    required this.startMinute,
    required this.endMinute,
    required this.category,
    required this.event,
  });

  final int startMinute;
  final int endMinute;
  final String category;
  final _EventDetail event;
}

class _EventDetail {
  const _EventDetail({
    required this.type,
    required this.displayType,
    required this.category,
    required this.startUtc,
    required this.endUtc,
    required this.value,
  });

  final String type;
  final String displayType;
  final String category;
  final DateTime startUtc;
  final DateTime? endUtc;
  final Map<String, dynamic> value;
}

class _DayStats {
  const _DayStats({
    required this.dayUtc,
    required this.sleepMinutes,
    required this.feedEstimatedMinutes,
    required this.feedCount,
    required this.breastfeedCount,
    required this.formulaMl,
    required this.peeCount,
    required this.pooCount,
    required this.medicationCount,
    required this.clinicVisits,
    required this.memoCount,
    required this.otherCount,
    required this.sleepBlocks,
    required this.feedMarks,
    required this.diaperMarks,
    required this.healthMarks,
    required this.noteMarks,
    required this.events,
    required this.summary,
  });

  final DateTime dayUtc;
  final int sleepMinutes;
  final int feedEstimatedMinutes;
  final int feedCount;
  final int breastfeedCount;
  final int formulaMl;
  final int peeCount;
  final int pooCount;
  final int medicationCount;
  final int clinicVisits;
  final int memoCount;
  final int otherCount;
  final List<_Block> sleepBlocks;
  final List<_Mark> feedMarks;
  final List<_Mark> diaperMarks;
  final List<_Mark> healthMarks;
  final List<_Mark> noteMarks;
  final List<_EventDetail> events;
  final List<String> summary;

  factory _DayStats.empty(DateTime dayUtc) {
    return _DayStats(
      dayUtc: dayUtc,
      sleepMinutes: 0,
      feedEstimatedMinutes: 0,
      feedCount: 0,
      breastfeedCount: 0,
      formulaMl: 0,
      peeCount: 0,
      pooCount: 0,
      medicationCount: 0,
      clinicVisits: 0,
      memoCount: 0,
      otherCount: 0,
      sleepBlocks: const <_Block>[],
      feedMarks: const <_Mark>[],
      diaperMarks: const <_Mark>[],
      healthMarks: const <_Mark>[],
      noteMarks: const <_Mark>[],
      events: const <_EventDetail>[],
      summary: const <String>[],
    );
  }

  factory _DayStats.fromReport(DateTime dayUtc, Map<String, dynamic>? report) {
    final List<String> summary =
        ((report?["summary"] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false);

    final List<Map<String, dynamic>> events =
        ((report?["events"] as List<dynamic>?) ?? <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) => <String, dynamic>{
                  for (final MapEntry<dynamic, dynamic> entry in e.entries)
                    entry.key.toString(): entry.value,
                })
            .toList(growable: false);

    int sleepMinutes = 0;
    int feedEstimatedMinutes = 0;
    int feedCount = 0;
    int breastfeedCount = 0;
    int formulaMl = 0;
    int peeCount = 0;
    int pooCount = 0;
    int medicationCount = 0;
    int clinicVisits = 0;
    int memoCount = 0;
    int otherCount = 0;

    final List<_Block> sleepBlocks = <_Block>[];
    final List<_Mark> feedMarks = <_Mark>[];
    final List<_Mark> diaperMarks = <_Mark>[];
    final List<_Mark> healthMarks = <_Mark>[];
    final List<_Mark> noteMarks = <_Mark>[];
    final List<_EventDetail> parsedEvents = <_EventDetail>[];

    for (final Map<String, dynamic> event in events) {
      final String type = (event["type"] ?? "").toString().trim().toUpperCase();
      final DateTime? start = _parseUtc(event["start_time"]);
      if (type.isEmpty || start == null) {
        continue;
      }

      final int startMinute = _clampI(
        _minuteInDisplayLocalDay(start, dayUtc),
        0,
        _minutesPerDay - 1,
      );
      final DateTime? end = _parseUtc(event["end_time"]);
      final Map<String, dynamic> value = _normalizeValueMap(event["value"]);
      final bool clinicMemo = type == "MEMO" && _isClinicMemo(value);
      final String displayType = clinicMemo ? "CLINIC" : type;
      final _EventDetail detail = _EventDetail(
        type: type,
        displayType: displayType,
        category: _eventCategory(type, clinicMemo: clinicMemo),
        startUtc: start,
        endUtc: end,
        value: value,
      );
      parsedEvents.add(detail);

      switch (type) {
        case "SLEEP":
          if (end == null) {
            break;
          }
          final int endMinute = _clampI(
            _minuteInDisplayLocalDay(end, dayUtc),
            0,
            _minutesPerDay,
          );
          if (endMinute > startMinute) {
            sleepMinutes += endMinute - startMinute;
            sleepBlocks.add(
              _Block(start: startMinute, end: endMinute, event: detail),
            );
          }
          break;
        case "FORMULA":
          feedCount += 1;
          feedEstimatedMinutes += 15;
          formulaMl += _extractMl(value);
          feedMarks.add(_Mark(type: type, minute: startMinute, event: detail));
          break;
        case "BREASTFEED":
          feedCount += 1;
          breastfeedCount += 1;
          feedEstimatedMinutes +=
              (end == null) ? 18 : math.max(1, end.difference(start).inMinutes);
          feedMarks.add(_Mark(type: type, minute: startMinute, event: detail));
          break;
        case "MEDICATION":
          medicationCount += 1;
          healthMarks
              .add(_Mark(type: type, minute: startMinute, event: detail));
          break;
        case "SYMPTOM":
        case "GROWTH":
          clinicVisits += 1;
          healthMarks
              .add(_Mark(type: type, minute: startMinute, event: detail));
          break;
        case "MEMO":
          memoCount += 1;
          if (clinicMemo) {
            clinicVisits += 1;
            healthMarks.add(
              _Mark(type: "CLINIC", minute: startMinute, event: detail),
            );
          } else {
            noteMarks
                .add(_Mark(type: "MEMO", minute: startMinute, event: detail));
          }
          break;
        case "PEE":
          peeCount += _extractCount(value);
          diaperMarks
              .add(_Mark(type: "PEE", minute: startMinute, event: detail));
          break;
        case "POO":
          pooCount += _extractCount(value);
          diaperMarks
              .add(_Mark(type: "POO", minute: startMinute, event: detail));
          break;
        default:
          otherCount += 1;
          noteMarks.add(_Mark(type: type, minute: startMinute, event: detail));
          break;
      }
    }

    if (sleepMinutes == 0) {
      sleepMinutes =
          _summaryInt(summary, <String>["sleep total", "sleep logged"]);
    }
    if (feedCount == 0) {
      feedCount = _summaryInt(summary, <String>["feeding events", "feedings"]);
    }
    if (formulaMl == 0) {
      formulaMl = _summaryInt(summary, <String>["formula total"]);
    }
    if (peeCount == 0) {
      peeCount = _summaryDiaperCount(summary, "pee");
    }
    if (pooCount == 0) {
      pooCount = _summaryDiaperCount(summary, "poo");
    }
    if (feedEstimatedMinutes == 0 && feedCount > 0) {
      feedEstimatedMinutes = feedCount * 16;
    }

    final List<_Block> blocks = sleepBlocks.isEmpty && sleepMinutes > 0
        ? _estimatedSleepBlocks(sleepMinutes)
        : sleepBlocks;
    final List<_Mark> feeds = feedMarks.isEmpty && feedCount > 0
        ? _estimatedFeedMarks(feedCount)
        : feedMarks;
    final int diaperTotal = peeCount + pooCount;
    final List<_Mark> diapers = diaperMarks.isEmpty && diaperTotal > 0
        ? _estimatedDiaperMarks(diaperTotal)
        : diaperMarks;
    final int healthFallbackCount = medicationCount + clinicVisits;
    final List<_Mark> health = healthMarks.isEmpty && healthFallbackCount > 0
        ? _estimatedHealthMarks(healthFallbackCount)
        : healthMarks;
    final List<_Mark> notes = noteMarks.isEmpty && (memoCount + otherCount) > 0
        ? _estimatedNoteMarks(memoCount + otherCount)
        : noteMarks;
    final List<_EventDetail> sortedEvents =
        List<_EventDetail>.from(parsedEvents)
          ..sort(
            (_EventDetail a, _EventDetail b) =>
                a.startUtc.compareTo(b.startUtc),
          );

    return _DayStats(
      dayUtc: dayUtc,
      sleepMinutes: sleepMinutes,
      feedEstimatedMinutes: feedEstimatedMinutes,
      feedCount: feedCount,
      breastfeedCount: breastfeedCount,
      formulaMl: formulaMl,
      peeCount: peeCount,
      pooCount: pooCount,
      medicationCount: medicationCount,
      clinicVisits: clinicVisits,
      memoCount: memoCount,
      otherCount: otherCount,
      sleepBlocks: blocks,
      feedMarks: feeds,
      diaperMarks: diapers,
      healthMarks: health,
      noteMarks: notes,
      events: sortedEvents,
      summary: summary,
    );
  }
}

class _Block {
  const _Block({required this.start, required this.end, this.event});

  final int start;
  final int end;
  final _EventDetail? event;
}

class _Mark {
  const _Mark({required this.type, required this.minute, this.event});

  final String type;
  final int minute;
  final _EventDetail? event;
}

class _EventVisualStyle {
  const _EventVisualStyle({
    required this.iconAsset,
    required this.color,
  });

  final String iconAsset;
  final Color color;
}

class _WeekBreakdown {
  const _WeekBreakdown(
      {required this.title,
      required this.range,
      required this.avgSleepMinutes});

  final String title;
  final String range;
  final int avgSleepMinutes;
}

class _RecentEventHighlights {
  const _RecentEventHighlights({
    required this.lastFeedUtc,
    required this.lastSleepEndUtc,
  });

  final DateTime? lastFeedUtc;
  final DateTime? lastSleepEndUtc;
}

class _MonthlyInsights {
  const _MonthlyInsights({
    required this.avgBedtimeMinute,
    required this.avgWakeMinute,
    required this.longestSleepMinutes,
    required this.avgFeedIntervalMinutes,
    required this.peakFeedHour,
    required this.totalFormulaMl,
    required this.feedEvents,
  });

  final int? avgBedtimeMinute;
  final int? avgWakeMinute;
  final int longestSleepMinutes;
  final int? avgFeedIntervalMinutes;
  final int? peakFeedHour;
  final int totalFormulaMl;
  final int feedEvents;
}

DateTime? _parseUtc(dynamic raw) {
  if (raw == null) {
    return null;
  }
  final String text = raw.toString().trim();
  if (text.isEmpty) {
    return null;
  }
  try {
    return DateTime.parse(text).toUtc();
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _normalizeValueMap(dynamic value) {
  if (value is! Map<dynamic, dynamic>) {
    return <String, dynamic>{};
  }
  return <String, dynamic>{
    for (final MapEntry<dynamic, dynamic> entry in value.entries)
      entry.key.toString(): entry.value,
  };
}

String _eventCategory(String type, {required bool clinicMemo}) {
  switch (type) {
    case "SLEEP":
      return "sleep";
    case "FORMULA":
    case "BREASTFEED":
      return "feed";
    case "PEE":
    case "POO":
      return "diaper";
    case "MEDICATION":
      return "medication";
    case "SYMPTOM":
    case "GROWTH":
      return "hospital";
    case "MEMO":
      return clinicMemo ? "hospital" : "memo";
    default:
      return "other";
  }
}

_EventVisualStyle _eventVisualStyle(String type) {
  switch (type) {
    case "SLEEP":
      return const _EventVisualStyle(
        iconAsset: AppSvgAsset.sleepCrescentPurple,
        color: _SemanticColors.sleep,
      );
    case "FORMULA":
    case "BREASTFEED":
      return const _EventVisualStyle(
        iconAsset: AppSvgAsset.feeding,
        color: _SemanticColors.feed,
      );
    case "PEE":
    case "POO":
      return const _EventVisualStyle(
        iconAsset: AppSvgAsset.diaper,
        color: _SemanticColors.diaper,
      );
    case "MEDICATION":
      return const _EventVisualStyle(
        iconAsset: AppSvgAsset.medicine,
        color: _SemanticColors.medication,
      );
    case "MEMO":
      return const _EventVisualStyle(
        iconAsset: AppSvgAsset.memoLucide,
        color: _SemanticColors.memo,
      );
    case "GROWTH":
      return const _EventVisualStyle(
        iconAsset: AppSvgAsset.stats,
        color: _SemanticColors.play,
      );
    case "CLINIC":
    case "SYMPTOM":
      return const _EventVisualStyle(
        iconAsset: AppSvgAsset.clinicStethoscope,
        color: _SemanticColors.hospital,
      );
    default:
      return const _EventVisualStyle(
        iconAsset: AppSvgAsset.stats,
        color: _SemanticColors.other,
      );
  }
}

int _extractMl(dynamic value) {
  if (value is! Map<dynamic, dynamic>) {
    return 0;
  }
  for (final String key in <String>["ml", "amount_ml", "volume_ml"]) {
    final dynamic raw = value[key];
    if (raw is int) {
      return raw;
    }
    if (raw is double) {
      return raw.round();
    }
    if (raw is String) {
      final int? parsed = int.tryParse(raw.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return 0;
}

int _extractCount(dynamic value) {
  if (value is! Map<dynamic, dynamic>) {
    return 1;
  }
  for (final String key in <String>["count", "times", "qty", "quantity"]) {
    final dynamic raw = value[key];
    if (raw is int && raw > 0) {
      return raw;
    }
    if (raw is double && raw > 0) {
      return raw.round();
    }
    if (raw is String) {
      final int? parsed = int.tryParse(raw.trim());
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
  }
  return 1;
}

bool _isClinicMemo(dynamic value) {
  if (value is! Map<dynamic, dynamic>) {
    return false;
  }
  final String raw = <String>[
    (value["memo"] ?? "").toString(),
    (value["note"] ?? "").toString(),
    (value["text"] ?? "").toString(),
    (value["content"] ?? "").toString(),
    (value["message"] ?? "").toString(),
  ].join(" ");
  if (raw.trim().isEmpty) {
    return false;
  }
  final String lower = raw.toLowerCase();
  return lower.contains("clinic") ||
      lower.contains("hospital") ||
      lower.contains("pediatric") ||
      lower.contains("doctor") ||
      lower.contains("소아과") ||
      lower.contains("병원") ||
      lower.contains("진료");
}

int _summaryInt(List<String> summary, List<String> keys) {
  for (final String line in summary) {
    final String lower = line.toLowerCase();
    if (keys.any(lower.contains)) {
      final RegExpMatch? match = RegExp(r"\d+").firstMatch(line);
      return int.tryParse(match?.group(0) ?? "0") ?? 0;
    }
  }
  return 0;
}

int _summaryDiaperCount(List<String> summary, String diaperType) {
  final RegExp reg = RegExp("$diaperType\\s*(\\d+)", caseSensitive: false);
  for (final String line in summary) {
    final RegExpMatch? match = reg.firstMatch(line);
    final int parsed = int.tryParse(match?.group(1) ?? "0") ?? 0;
    if (parsed > 0) {
      return parsed;
    }
  }
  return 0;
}

List<_Block> _estimatedSleepBlocks(int total) {
  final int a = (total * 0.42).round();
  final int b = (total * 0.33).round();
  final int c = math.max(0, total - a - b);
  final List<int> starts = <int>[40, 520, 980];
  final List<int> durations = <int>[a, b, c];

  final List<_Block> blocks = <_Block>[];
  for (int i = 0; i < starts.length; i++) {
    final int dur = durations[i];
    if (dur <= 0) {
      continue;
    }
    final int start = _clampI(starts[i], 0, _minutesPerDay - 1);
    final int end = _clampI(start + dur, start + 20, _minutesPerDay);
    blocks.add(_Block(start: start, end: end));
  }
  return blocks;
}

List<_Mark> _estimatedFeedMarks(int count) {
  if (count <= 0) {
    return <_Mark>[];
  }
  if (count == 1) {
    return const <_Mark>[_Mark(type: "FORMULA", minute: 12 * 60)];
  }

  const int startMinute = 4 * 60;
  const int span = 16 * 60;
  final double step = span / (count - 1);

  return List<_Mark>.generate(count, (int i) {
    final int minute = _clampI(
      (startMinute + (step * i)).round(),
      0,
      _minutesPerDay - 1,
    );
    return _Mark(type: "FORMULA", minute: minute);
  });
}

List<_Mark> _estimatedDiaperMarks(int count) {
  if (count <= 0) {
    return <_Mark>[];
  }
  const List<int> base = <int>[6 * 60, 10 * 60, 14 * 60, 18 * 60, 22 * 60];
  return List<_Mark>.generate(count, (int index) {
    final int minute = base[index % base.length];
    final String type = index.isEven ? "PEE" : "POO";
    return _Mark(type: type, minute: minute);
  });
}

List<_Mark> _estimatedHealthMarks(int count) {
  if (count <= 0) {
    return <_Mark>[];
  }
  const List<int> base = <int>[9 * 60, 13 * 60, 17 * 60, 21 * 60];
  return List<_Mark>.generate(count, (int index) {
    final int minute = base[index % base.length];
    return _Mark(type: "CLINIC", minute: minute);
  });
}

List<_Mark> _estimatedNoteMarks(int count) {
  if (count <= 0) {
    return <_Mark>[];
  }
  const List<int> base = <int>[8 * 60, 12 * 60, 16 * 60, 20 * 60];
  return List<_Mark>.generate(count, (int index) {
    final int minute = base[index % base.length];
    return _Mark(type: "MEMO", minute: minute);
  });
}

double _sleepTrendDelta(List<_DayStats> days) {
  if (days.length < 2) {
    return 0;
  }
  final List<_DayStats> sorted = List<_DayStats>.from(days)
    ..sort((_DayStats a, _DayStats b) => a.dayUtc.compareTo(b.dayUtc));

  final int split = sorted.length ~/ 2;
  if (split == 0 || split >= sorted.length) {
    return 0;
  }

  final double first = sorted
          .take(split)
          .fold<int>(0, (int s, _DayStats d) => s + d.sleepMinutes) /
      split;
  final double second = sorted
          .skip(split)
          .fold<int>(0, (int s, _DayStats d) => s + d.sleepMinutes) /
      (sorted.length - split);

  return (second - first) / 60;
}

List<_WeekBreakdown> _buildWeeklyBreakdown(List<_DayStats> days) {
  if (days.isEmpty) {
    return <_WeekBreakdown>[];
  }

  final Map<DateTime, List<_DayStats>> grouped = <DateTime, List<_DayStats>>{};
  for (final _DayStats day in days) {
    final DateTime start = _toWeekStart(day.dayUtc);
    grouped.putIfAbsent(start, () => <_DayStats>[]).add(day);
  }

  final List<MapEntry<DateTime, List<_DayStats>>> entries = grouped.entries
      .toList()
    ..sort((MapEntry<DateTime, List<_DayStats>> a,
            MapEntry<DateTime, List<_DayStats>> b) =>
        b.key.compareTo(a.key));

  final int total = entries.length;
  final List<_WeekBreakdown> list = <_WeekBreakdown>[];

  for (int i = 0; i < entries.length; i++) {
    final List<_DayStats> week = List<_DayStats>.from(entries[i].value)
      ..sort((_DayStats a, _DayStats b) => a.dayUtc.compareTo(b.dayUtc));

    final int avg =
        (week.fold<int>(0, (int s, _DayStats d) => s + d.sleepMinutes) /
                week.length)
            .round();

    final DateTime start = week.first.dayUtc;
    final DateTime end = week.last.dayUtc;
    list.add(
      _WeekBreakdown(
        title: "Week ${total - i}",
        range:
            "${_month(start.month)} ${start.day} - ${_month(end.month)} ${end.day}",
        avgSleepMinutes: avg,
      ),
    );
  }

  return list;
}

String _formatHour(double value) {
  if (!value.isFinite) {
    return "0h";
  }
  final double rounded = (value * 10).round() / 10;
  if ((rounded - rounded.round()).abs() < 0.001) {
    return "${rounded.round()}h";
  }
  return "${rounded.toStringAsFixed(1)}h";
}

String _formatCount(double value) {
  if (!value.isFinite || value <= 0) {
    return "0x";
  }
  final double rounded = (value * 10).round() / 10;
  if ((rounded - rounded.round()).abs() < 0.001) {
    return "${rounded.round()}x";
  }
  return "${rounded.toStringAsFixed(1)}x";
}

String _formatTrend(double value) {
  final double rounded = (value * 10).round() / 10;
  final String sign = rounded >= 0 ? "+" : "";
  return "$sign${rounded.toStringAsFixed(1)}h";
}

_RecentEventHighlights _buildRecentEventHighlights(
  List<_EventDetail> history,
  DateTime nowUtc,
) {
  DateTime? lastFeedUtc;
  DateTime? lastSleepEndUtc;

  for (final _EventDetail event in history) {
    if (event.startUtc.isAfter(nowUtc)) {
      continue;
    }

    if (event.type == "FORMULA" || event.type == "BREASTFEED") {
      if (lastFeedUtc == null || event.startUtc.isAfter(lastFeedUtc)) {
        lastFeedUtc = event.startUtc;
      }
    }

    if (event.type == "SLEEP" && event.endUtc != null) {
      final DateTime endUtc = event.endUtc!;
      if (!endUtc.isAfter(nowUtc) &&
          (lastSleepEndUtc == null || endUtc.isAfter(lastSleepEndUtc))) {
        lastSleepEndUtc = endUtc;
      }
    }
  }

  return _RecentEventHighlights(
    lastFeedUtc: lastFeedUtc,
    lastSleepEndUtc: lastSleepEndUtc,
  );
}

_MonthlyInsights _buildMonthlyInsights(List<_DayStats> days) {
  if (days.isEmpty) {
    return const _MonthlyInsights(
      avgBedtimeMinute: null,
      avgWakeMinute: null,
      longestSleepMinutes: 0,
      avgFeedIntervalMinutes: null,
      peakFeedHour: null,
      totalFormulaMl: 0,
      feedEvents: 0,
    );
  }

  final List<_EventDetail> events =
      days.expand((_DayStats day) => day.events).toList(growable: false)
        ..sort(
          (_EventDetail a, _EventDetail b) => a.startUtc.compareTo(b.startUtc),
        );

  final List<int> bedtimeSamples = <int>[];
  final List<int> wakeSamples = <int>[];
  int longestSleepMinutes = 0;

  for (final _EventDetail event in events) {
    if (event.type != "SLEEP" || event.endUtc == null) {
      continue;
    }
    final DateTime endUtc = event.endUtc!;
    if (!endUtc.isAfter(event.startUtc)) {
      continue;
    }

    final int duration = endUtc.difference(event.startUtc).inMinutes;
    if (duration > longestSleepMinutes) {
      longestSleepMinutes = duration;
    }

    final DateTime startLocal = event.startUtc.toLocal();
    final int startMinute = startLocal.hour * 60 + startLocal.minute;
    if (startMinute >= 18 * 60 || startMinute <= 6 * 60) {
      bedtimeSamples.add(
        startMinute < 12 * 60 ? startMinute + _minutesPerDay : startMinute,
      );
    }

    final DateTime endLocal = endUtc.toLocal();
    final int endMinute = endLocal.hour * 60 + endLocal.minute;
    if (endMinute <= 13 * 60) {
      wakeSamples.add(endMinute);
    }
  }

  if (wakeSamples.isEmpty) {
    for (final _EventDetail event in events) {
      if (event.type != "SLEEP" || event.endUtc == null) {
        continue;
      }
      final DateTime endLocal = event.endUtc!.toLocal();
      wakeSamples.add(endLocal.hour * 60 + endLocal.minute);
    }
  }

  final List<_EventDetail> feedEvents = events
      .where(
        (_EventDetail event) =>
            event.type == "FORMULA" || event.type == "BREASTFEED",
      )
      .toList(growable: false)
    ..sort(
      (_EventDetail a, _EventDetail b) => a.startUtc.compareTo(b.startUtc),
    );

  final List<int> feedIntervals = <int>[];
  for (int i = 1; i < feedEvents.length; i++) {
    final int gap =
        feedEvents[i].startUtc.difference(feedEvents[i - 1].startUtc).inMinutes;
    if (gap >= 20 && gap <= 12 * 60) {
      feedIntervals.add(gap);
    }
  }

  final List<int> hourBuckets = List<int>.filled(24, 0, growable: false);
  for (final _EventDetail event in feedEvents) {
    final int hour = event.startUtc.toLocal().hour;
    hourBuckets[hour] += 1;
  }

  int peakFeedCount = 0;
  int? peakFeedHour;
  for (int hour = 0; hour < hourBuckets.length; hour++) {
    if (hourBuckets[hour] > peakFeedCount) {
      peakFeedCount = hourBuckets[hour];
      peakFeedHour = hour;
    }
  }
  if (peakFeedCount == 0) {
    peakFeedHour = null;
  }

  return _MonthlyInsights(
    avgBedtimeMinute: _avgMinuteWrapped(bedtimeSamples),
    avgWakeMinute: _avgInt(wakeSamples),
    longestSleepMinutes: longestSleepMinutes,
    avgFeedIntervalMinutes: _avgInt(feedIntervals),
    peakFeedHour: peakFeedHour,
    totalFormulaMl: days.fold<int>(
      0,
      (int sum, _DayStats day) => sum + day.formulaMl,
    ),
    feedEvents: feedEvents.length,
  );
}

int? _avgInt(List<int> values) {
  if (values.isEmpty) {
    return null;
  }
  final int sum = values.fold<int>(0, (int a, int b) => a + b);
  return (sum / values.length).round();
}

int? _avgMinuteWrapped(List<int> values) {
  final int? avg = _avgInt(values);
  if (avg == null) {
    return null;
  }
  return avg % _minutesPerDay;
}

String _formatElapsedSince(DateTime? instantUtc, DateTime nowUtc) {
  if (instantUtc == null) {
    return "No record";
  }
  final int minutes = nowUtc.difference(instantUtc).inMinutes;
  if (minutes <= 0) {
    return "Just now";
  }
  return "${_formatDurationSpan(minutes)} ago";
}

String _formatHighlightStamp(DateTime? instantUtc) {
  if (instantUtc == null) {
    return "Log a record to track";
  }
  return "at ${_formatClock(instantUtc.toLocal())}";
}

String _formatDurationSpan(int minutes) {
  final int safe = math.max(0, minutes);
  final int hour = safe ~/ 60;
  final int min = safe % 60;
  if (hour <= 0) {
    return "${min}m";
  }
  if (min == 0) {
    return "${hour}h";
  }
  return "${hour}h ${min}m";
}

String _formatDurationMinutes(int? minutes) {
  if (minutes == null || minutes <= 0) {
    return "-";
  }
  return _formatDurationSpan(minutes);
}

String _formatMinuteOfDay(int? minuteOfDay) {
  if (minuteOfDay == null) {
    return "-";
  }
  return _clockMinuteLabel(minuteOfDay);
}

String _formatFeedWindow(int? startHour) {
  if (startHour == null) {
    return "-";
  }
  final int endHour = (startHour + 2) % 24;
  final String start = startHour.toString().padLeft(2, "0");
  final String end = endHour.toString().padLeft(2, "0");
  return "$start:00-$end:00";
}

String _monthlySleepPatternText(_MonthlyInsights insights) {
  if (insights.longestSleepMinutes <= 0 &&
      insights.avgBedtimeMinute == null &&
      insights.avgWakeMinute == null) {
    return "Not enough sleep records yet.";
  }
  final String bedtime = _formatMinuteOfDay(insights.avgBedtimeMinute);
  final String wake = _formatMinuteOfDay(insights.avgWakeMinute);
  final String longest = _formatDurationMinutes(insights.longestSleepMinutes);
  return "Bedtime around $bedtime, wake-up around $wake, longest stretch $longest.";
}

String _monthlyFeedPatternText(_MonthlyInsights insights) {
  if (insights.feedEvents <= 0) {
    return "Not enough feeding records yet.";
  }
  final String gap = _formatDurationMinutes(insights.avgFeedIntervalMinutes);
  final String peak = _formatFeedWindow(insights.peakFeedHour);
  return "Average interval $gap, peak window $peak, total formula ${insights.totalFormulaMl} ml.";
}

List<_DonutCategory> _buildDailyClockSegments(
  BuildContext context,
  _DayStats day,
) {
  final List<String> minuteCategory =
      List<String>.filled(_minutesPerDay, "idle", growable: false);
  final List<int> minutePriority =
      List<int>.filled(_minutesPerDay, 0, growable: false);
  final List<List<_EventDetail>> minuteEvents =
      List<List<_EventDetail>>.generate(
    _minutesPerDay,
    (_) => <_EventDetail>[],
    growable: false,
  );

  final List<_ClockPaintSpan> spans = day.events
      .map((_EventDetail event) => _clockSpanForEvent(day, event))
      .toList(growable: false);

  for (final _ClockPaintSpan span in spans) {
    final int priority = _clockCategoryPriority(span.category);
    for (int minute = span.startMinute; minute < span.endMinute; minute++) {
      if (priority >= minutePriority[minute]) {
        minutePriority[minute] = priority;
        minuteCategory[minute] = span.category;
      }
      minuteEvents[minute].add(span.event);
    }
  }

  final List<_DonutCategory> slices = <_DonutCategory>[];
  int cursor = 0;
  while (cursor < _minutesPerDay) {
    final String category = minuteCategory[cursor];
    int next = cursor + 1;
    while (next < _minutesPerDay && minuteCategory[next] == category) {
      next += 1;
    }

    final Map<String, _EventDetail> unique = <String, _EventDetail>{};
    for (int minute = cursor; minute < next; minute++) {
      for (final _EventDetail event in minuteEvents[minute]) {
        unique.putIfAbsent(_eventIdentityKey(event), () => event);
      }
    }

    slices.add(
      _DonutCategory(
        slice: DonutSliceData(
          label: _clockSliceLabel(context, category, cursor, next),
          value: (next - cursor).toDouble(),
          color: _clockCategoryColor(context, category),
        ),
        events: unique.values.toList(growable: false),
      ),
    );
    cursor = next;
  }

  return slices;
}

_ClockPaintSpan _clockSpanForEvent(_DayStats day, _EventDetail event) {
  final int startMinute = _clampI(
    _minuteInDisplayLocalDay(event.startUtc, day.dayUtc),
    0,
    _minutesPerDay - 1,
  );

  final int endMinute = _clampI(
    event.endUtc == null
        ? startMinute + _clockDefaultSpanMinutes(event.displayType)
        : _minuteInDisplayLocalDay(event.endUtc!, day.dayUtc),
    startMinute + 1,
    _minutesPerDay,
  );

  return _ClockPaintSpan(
    startMinute: startMinute,
    endMinute: endMinute,
    category: event.category,
    event: event,
  );
}

int _clockDefaultSpanMinutes(String type) {
  switch (type) {
    case "SLEEP":
      return 30;
    case "FORMULA":
      return 10;
    case "BREASTFEED":
      return 18;
    case "PEE":
    case "POO":
      return 8;
    case "MEDICATION":
    case "SYMPTOM":
    case "GROWTH":
    case "CLINIC":
      return 12;
    case "MEMO":
      return 10;
    default:
      return 9;
  }
}

int _clockCategoryPriority(String category) {
  switch (category) {
    case "sleep":
      return 1;
    case "other":
      return 2;
    case "feed":
      return 3;
    case "diaper":
      return 4;
    case "medication":
      return 5;
    case "memo":
      return 6;
    case "hospital":
      return 7;
    case "idle":
      return 0;
    default:
      return 1;
  }
}

Color _clockCategoryColor(BuildContext context, String category) {
  switch (category) {
    case "sleep":
      return _SemanticColors.sleep;
    case "feed":
      return _SemanticColors.feed;
    case "diaper":
      return _SemanticColors.diaper;
    case "medication":
      return _SemanticColors.medication;
    case "hospital":
      return _SemanticColors.hospital;
    case "memo":
      return _SemanticColors.memo;
    case "other":
      return _SemanticColors.other.withValues(alpha: 0.75);
    case "idle":
      return Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.55);
    default:
      return _SemanticColors.other.withValues(alpha: 0.75);
  }
}

String _clockCategoryLabel(BuildContext context, String category) {
  switch (category) {
    case "sleep":
      return tr(context, ko: "Sleep", en: "Sleep", es: "Sueno");
    case "feed":
      return tr(context, ko: "Feed", en: "Feed", es: "Alimentacion");
    case "diaper":
      return tr(context, ko: "Diaper", en: "Diaper", es: "Panal");
    case "medication":
      return tr(context, ko: "Medication", en: "Medication", es: "Medicina");
    case "hospital":
      return tr(context, ko: "Hospital", en: "Hospital", es: "Hospital");
    case "memo":
      return tr(context, ko: "Memo", en: "Memo", es: "Memo");
    case "other":
      return tr(context, ko: "Other", en: "Other", es: "Otro");
    case "idle":
      return tr(context, ko: "No Event", en: "No Event", es: "Sin eventos");
    default:
      return category;
  }
}

String _clockSliceLabel(
  BuildContext context,
  String category,
  int startMinute,
  int endMinute,
) {
  final String range =
      "${_clockMinuteLabel(startMinute)}-${_clockMinuteLabel(endMinute)}";
  if (category == "idle") {
    return range;
  }
  return "${_clockCategoryLabel(context, category)} $range";
}

String _eventIdentityKey(_EventDetail event) {
  return "${event.displayType}|${event.startUtc.toIso8601String()}|"
      "${event.endUtc?.toIso8601String() ?? ""}";
}

String _clockMinuteLabel(int minute) {
  final int safe = _clampI(minute, 0, _minutesPerDay);
  if (safe == _minutesPerDay) {
    return "24:00";
  }
  final int hour = safe ~/ 60;
  final int mins = safe % 60;
  return "${hour.toString().padLeft(2, "0")}:${mins.toString().padLeft(2, "0")}";
}

int _minuteInDisplayLocalDay(DateTime instantUtc, DateTime dayUtc) {
  final DateTime dayLocal = dayUtc.toLocal();
  final DateTime dayStartLocal =
      DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
  return instantUtc.toLocal().difference(dayStartLocal).inMinutes;
}

List<_DonutCategory> _buildDonutCategories(
    BuildContext context, _DayStats day) {
  final Map<String, List<_EventDetail>> grouped =
      <String, List<_EventDetail>>{};
  for (final _EventDetail event in day.events) {
    grouped.putIfAbsent(event.category, () => <_EventDetail>[]).add(event);
  }

  final List<_DonutCategory> categories = <_DonutCategory>[];
  void addCategory({
    required String key,
    required String label,
    required double value,
    required Color color,
  }) {
    if (value <= 0) {
      return;
    }
    categories.add(
      _DonutCategory(
        slice: DonutSliceData(label: label, value: value, color: color),
        events: grouped[key] ?? const <_EventDetail>[],
      ),
    );
  }

  final double sleepValue = (grouped["sleep"]?.length ?? 0) > 0
      ? (grouped["sleep"]?.length ?? 0).toDouble()
      : (day.sleepMinutes > 0 ? 1 : 0).toDouble();
  final double feedValue = math.max(
    day.feedCount.toDouble(),
    (grouped["feed"]?.length ?? 0).toDouble(),
  );
  final double diaperValue = math.max(
    (day.peeCount + day.pooCount).toDouble(),
    (grouped["diaper"]?.length ?? 0).toDouble(),
  );
  final double medicationValue = math.max(
    day.medicationCount.toDouble(),
    (grouped["medication"]?.length ?? 0).toDouble(),
  );
  final double hospitalValue = math.max(
    day.clinicVisits.toDouble(),
    (grouped["hospital"]?.length ?? 0).toDouble(),
  );
  final double memoValue = math.max(
    day.memoCount.toDouble(),
    (grouped["memo"]?.length ?? 0).toDouble(),
  );
  final double otherValue = math.max(
    day.otherCount.toDouble(),
    (grouped["other"]?.length ?? 0).toDouble(),
  );

  addCategory(
    key: "sleep",
    label: tr(context, ko: "Sleep", en: "Sleep", es: "Sueno"),
    value: sleepValue,
    color: _SemanticColors.sleep,
  );
  addCategory(
    key: "feed",
    label: tr(context, ko: "Feed", en: "Feed", es: "Alimentacion"),
    value: feedValue,
    color: _SemanticColors.feed,
  );
  addCategory(
    key: "diaper",
    label: tr(context, ko: "Diaper", en: "Diaper", es: "Panal"),
    value: diaperValue,
    color: _SemanticColors.diaper,
  );
  addCategory(
    key: "medication",
    label: tr(context, ko: "Medication", en: "Medication", es: "Medicina"),
    value: medicationValue,
    color: _SemanticColors.medication,
  );
  addCategory(
    key: "hospital",
    label: tr(context, ko: "Hospital", en: "Hospital", es: "Hospital"),
    value: hospitalValue,
    color: _SemanticColors.hospital,
  );
  addCategory(
    key: "memo",
    label: tr(context, ko: "Memo", en: "Memo", es: "Memo"),
    value: memoValue,
    color: _SemanticColors.memo,
  );
  addCategory(
    key: "other",
    label: tr(context, ko: "Other", en: "Other", es: "Otro"),
    value: otherValue,
    color: _SemanticColors.other,
  );

  return categories;
}

Future<void> _showEventDetailsSheet(
  BuildContext context, {
  required String title,
  required List<_EventDetail> events,
}) async {
  final List<_EventDetail> sorted = List<_EventDetail>.from(events)
    ..sort(
      (_EventDetail a, _EventDetail b) => a.startUtc.compareTo(b.startUtc),
    );

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) {
      final double maxHeight = MediaQuery.of(context).size.height * 0.72;
      if (sorted.isEmpty) {
        return SafeArea(
          child: SizedBox(
            height: 180,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "No detailed records for this item.",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      "${sorted.length} logs",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (BuildContext context, int index) {
                    final _EventDetail event = sorted[index];
                    final _EventVisualStyle style =
                        _eventVisualStyle(event.displayType);
                    final String detail = _eventSummaryText(event);
                    final String time = _formatEventWindow(event);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: style.color.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: AppSvgIcon(
                            style.iconAsset,
                            size: 14,
                            color: style.color,
                          ),
                        ),
                      ),
                      title: Text(
                        _eventTypeLabel(context, event.displayType),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        detail.isEmpty ? time : "$time · $detail",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _eventTypeLabel(BuildContext context, String type) {
  switch (type) {
    case "SLEEP":
      return tr(context, ko: "Sleep", en: "Sleep", es: "Sueno");
    case "FORMULA":
      return tr(context, ko: "Formula", en: "Formula", es: "Formula");
    case "BREASTFEED":
      return tr(context, ko: "Breastfeed", en: "Breastfeed", es: "Lactancia");
    case "PEE":
      return tr(context, ko: "Pee", en: "Pee", es: "Orina");
    case "POO":
      return tr(context, ko: "Poo", en: "Poo", es: "Heces");
    case "MEDICATION":
      return tr(context, ko: "Medication", en: "Medication", es: "Medicina");
    case "SYMPTOM":
      return tr(context, ko: "Symptom", en: "Symptom", es: "Sintoma");
    case "GROWTH":
      return tr(context, ko: "Growth", en: "Growth", es: "Crecimiento");
    case "CLINIC":
      return tr(context, ko: "Hospital", en: "Hospital", es: "Hospital");
    case "MEMO":
      return tr(context, ko: "Memo", en: "Memo", es: "Memo");
    default:
      return type;
  }
}

String _eventSummaryText(_EventDetail event) {
  final Map<String, dynamic> value = event.value;
  final List<String> parts = <String>[];

  final int ml = _extractMl(value);
  if (ml > 0) {
    parts.add("$ml ml");
  }

  final int duration = _extractPositiveInt(value["duration_min"]);
  if (duration > 0) {
    parts.add("$duration min");
  }

  final int grams = _extractPositiveInt(value["grams"]);
  if (grams > 0) {
    parts.add("$grams g");
  }

  if (event.type == "PEE" || event.type == "POO") {
    final int count = _extractCount(value);
    if (count > 0) {
      parts.add("${count}x");
    }
  }

  final String name = _firstText(value, <String>["name", "med_name"]);
  if (name.isNotEmpty) {
    parts.add(name);
  }
  final String dose = _firstText(value, <String>["dose_text", "dose"]);
  if (dose.isNotEmpty) {
    parts.add("dose $dose");
  }
  final String route = _firstText(value, <String>["route", "side", "poo_type"]);
  if (route.isNotEmpty) {
    parts.add(route);
  }

  final String temp = _firstText(
    value,
    <String>["temp_c", "temperature_c", "temp"],
  );
  if (temp.isNotEmpty) {
    parts.add("$temp C");
  }

  final String text = _firstText(
    value,
    <String>["memo", "note", "text", "content", "message"],
  );
  if (text.isNotEmpty) {
    parts.add(text.length > 36 ? "${text.substring(0, 36)}..." : text);
  }

  if (parts.isEmpty) {
    return _compactValueMap(value);
  }
  return parts.join(" · ");
}

String _firstText(Map<String, dynamic> value, List<String> keys) {
  for (final String key in keys) {
    final dynamic raw = value[key];
    if (raw == null) {
      continue;
    }
    final String text = raw.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
  }
  return "";
}

int _extractPositiveInt(dynamic raw) {
  if (raw is int && raw > 0) {
    return raw;
  }
  if (raw is double && raw > 0) {
    return raw.round();
  }
  if (raw is String) {
    final int? parsed = int.tryParse(raw.trim());
    if (parsed != null && parsed > 0) {
      return parsed;
    }
  }
  return 0;
}

String _compactValueMap(Map<String, dynamic> value) {
  if (value.isEmpty) {
    return "";
  }
  final List<String> entries = <String>[];
  for (final MapEntry<String, dynamic> entry in value.entries) {
    final String key = entry.key.trim();
    final String text = entry.value.toString().trim();
    if (key.isEmpty || text.isEmpty) {
      continue;
    }
    entries.add("$key $text");
    if (entries.length >= 2) {
      break;
    }
  }
  return entries.join(" · ");
}

String _formatEventWindow(_EventDetail event) {
  final DateTime start = event.startUtc.toLocal();
  final String startText = _formatMonthDayClock(start);
  if (event.endUtc == null) {
    return startText;
  }

  final DateTime end = event.endUtc!.toLocal();
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return "$startText - ${_formatClock(end)}";
  }
  return "$startText - ${_formatMonthDayClock(end)}";
}

String _formatMonthDayClock(DateTime value) {
  return "${value.month}/${value.day} ${_formatClock(value)}";
}

String _formatClock(DateTime value) {
  final String h = value.hour.toString().padLeft(2, "0");
  final String m = value.minute.toString().padLeft(2, "0");
  return "$h:$m";
}

String _month(int month) {
  const List<String> names = <String>[
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  return names[_clampI(month, 1, 12) - 1];
}

int _clampI(int value, int min, int max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

double _clampD(double value, double min, double max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}
