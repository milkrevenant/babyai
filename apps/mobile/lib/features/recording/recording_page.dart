import "dart:async";

import "package:flutter/material.dart";

import "../../core/config/session_store.dart";
import "../../core/i18n/app_i18n.dart";
import "../../core/network/babyai_api.dart";
import "../../core/theme/app_theme_controller.dart";
import "../../core/widgets/simple_line_chart.dart";
import "record_entry_sheet.dart";

enum RecordRange { day, week, month }

class RecordingPage extends StatefulWidget {
  const RecordingPage({
    super.key,
    required this.range,
  });

  final RecordRange range;

  @override
  State<RecordingPage> createState() => RecordingPageState();
}

class RecordingPageState extends State<RecordingPage> {
  bool _snapshotLoading = false;
  bool _entrySaving = false;

  String? _snapshotError;
  Map<String, dynamic>? _snapshot;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLandingSnapshot());
  }

  @override
  void didUpdateWidget(covariant RecordingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.range != widget.range) {
      unawaited(_loadLandingSnapshot());
    }
  }

  Future<void> refreshData() async {
    await _loadLandingSnapshot();
  }

  String _rangeApiValue() {
    switch (widget.range) {
      case RecordRange.day:
        return "day";
      case RecordRange.week:
        return "week";
      case RecordRange.month:
        return "month";
    }
  }

  Future<void> _loadLandingSnapshot() async {
    setState(() {
      _snapshotLoading = true;
      _snapshotError = null;
    });

    try {
      final Map<String, dynamic> result = await BabyAIApi.instance
          .quickLandingSnapshot(range: _rangeApiValue());
      if (!mounted) {
        return;
      }
      setState(() => _snapshot = result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _snapshotError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _snapshotLoading = false);
      }
    }
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  String? _asString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  List<String> _asStringList(dynamic value) {
    if (value is! List<dynamic>) {
      return <String>[];
    }
    return value
        .map((dynamic item) => item.toString().trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }

  List<double> _asDoubleList(dynamic value) {
    if (value is! List<dynamic>) {
      return <double>[];
    }
    return value
        .map((dynamic item) => _asDouble(item))
        .whereType<double>()
        .toList();
  }

  Map<String, int> _asBandMap(dynamic value) {
    if (value is! Map<dynamic, dynamic>) {
      return <String, int>{
        "night": 0,
        "morning": 0,
        "afternoon": 0,
        "evening": 0,
      };
    }
    return <String, int>{
      "night": _asInt(value["night"]) ?? 0,
      "morning": _asInt(value["morning"]) ?? 0,
      "afternoon": _asInt(value["afternoon"]) ?? 0,
      "evening": _asInt(value["evening"]) ?? 0,
    };
  }

  String _formatTime(String? isoDateTime) {
    if (isoDateTime == null) {
      return "-";
    }
    try {
      final DateTime dt = DateTime.parse(isoDateTime).toLocal();
      final String hour = dt.hour.toString().padLeft(2, "0");
      final String minute = dt.minute.toString().padLeft(2, "0");
      return "$hour:$minute";
    } catch (_) {
      return isoDateTime;
    }
  }

  String _formatDuration(int? minutes) {
    if (minutes == null) {
      return "-";
    }
    final int hours = minutes ~/ 60;
    final int mins = minutes % 60;
    if (hours == 0) {
      return "${mins}m";
    }
    return "${hours}h ${mins}m";
  }

  int? _intFromPrefill(Map<String, dynamic> prefill, String key) {
    final Object? raw = prefill[key];
    if (raw is int) {
      return raw;
    }
    if (raw is double) {
      return raw.round();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  String? _stringFromPrefill(Map<String, dynamic> prefill, String key) {
    final Object? raw = prefill[key];
    if (raw == null) {
      return null;
    }
    final String text = raw.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    return text;
  }

  int? _extractAmountMlFromText(String? text) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    final RegExpMatch? match = RegExp(
      r"(\d{1,4})\s*(ml|mL|ML|cc|㎖|밀리)",
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1) ?? "");
  }

  int? _extractDurationMinFromText(String? text) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    final RegExp hourRegExp = RegExp(
      r"(\d{1,2})\s*(시간|hour|hours|hr|hrs)",
      caseSensitive: false,
    );
    final RegExp minuteRegExp = RegExp(
      r"(\d{1,3})\s*(분|min|mins|minute|minutes)",
      caseSensitive: false,
    );

    int total = 0;
    final RegExpMatch? hourMatch = hourRegExp.firstMatch(text);
    final RegExpMatch? minuteMatch = minuteRegExp.firstMatch(text);
    if (hourMatch != null) {
      total += (int.tryParse(hourMatch.group(1) ?? "") ?? 0) * 60;
    }
    if (minuteMatch != null) {
      total += int.tryParse(minuteMatch.group(1) ?? "") ?? 0;
    }
    if (total > 0) {
      return total;
    }
    return null;
  }

  DateTime? _parseIsoDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(value).toLocal();
    } catch (_) {
      return null;
    }
  }

  RecordEntryInput? _buildAutoEntryFromPrefill(
    HomeTileType tile,
    Map<String, dynamic> prefill,
  ) {
    final DateTime now = DateTime.now();
    final String query = _stringFromPrefill(prefill, "query") ?? "";

    switch (tile) {
      case HomeTileType.formula:
        final int amount = _intFromPrefill(prefill, "amount_ml") ??
            _extractAmountMlFromText(query) ??
            0;
        if (amount <= 0) {
          return null;
        }
        return RecordEntryInput(
          type: "FORMULA",
          startTime: now,
          value: <String, dynamic>{"ml": amount},
        );
      case HomeTileType.breastfeed:
        final int duration = _intFromPrefill(prefill, "duration_min") ??
            _extractDurationMinFromText(query) ??
            0;
        return RecordEntryInput(
          type: "BREASTFEED",
          startTime: now,
          endTime: duration > 0 ? now.add(Duration(minutes: duration)) : null,
          value: <String, dynamic>{"duration_min": duration},
        );
      case HomeTileType.weaning:
        return null;
      case HomeTileType.diaper:
        String diaperType =
            (_stringFromPrefill(prefill, "diaper_type") ?? "").toUpperCase();
        if (diaperType != "PEE" && diaperType != "POO") {
          final String lowered = query.toLowerCase();
          if (lowered.contains("대변") ||
              lowered.contains("응가") ||
              lowered.contains("똥") ||
              lowered.contains("poo") ||
              lowered.contains("poop")) {
            diaperType = "POO";
          } else if (lowered.contains("소변") ||
              lowered.contains("오줌") ||
              lowered.contains("pee") ||
              lowered.contains("urine")) {
            diaperType = "PEE";
          } else {
            return null;
          }
        }
        return RecordEntryInput(
          type: diaperType,
          startTime: now,
          value: const <String, dynamic>{"count": 1},
        );
      case HomeTileType.sleep:
        final String action =
            (_stringFromPrefill(prefill, "sleep_action") ?? "").toLowerCase();
        if (action == "start") {
          return RecordEntryInput(
            type: "SLEEP",
            startTime: now,
            value: const <String, dynamic>{
              "duration_min": 0,
              "sleep_action": "START",
            },
          );
        }
        if (action == "end") {
          final DateTime? storedStart = _parseIsoDateTime(
                  _stringFromPrefill(prefill, "sleep_start_time")) ??
              AppSessionStore.pendingSleepStart?.toLocal();
          final DateTime start = storedStart == null || storedStart.isAfter(now)
              ? now
              : storedStart;
          final int duration = now.difference(start).inMinutes;
          return RecordEntryInput(
            type: "SLEEP",
            startTime: start,
            endTime: now,
            value: <String, dynamic>{
              "duration_min": duration < 0 ? 0 : duration,
              "sleep_action": "END",
            },
          );
        }
        final int duration = _intFromPrefill(prefill, "duration_min") ??
            _extractDurationMinFromText(query) ??
            0;
        return RecordEntryInput(
          type: "SLEEP",
          startTime: now,
          endTime: duration > 0 ? now.add(Duration(minutes: duration)) : null,
          value: <String, dynamic>{"duration_min": duration},
        );
      case HomeTileType.medication:
        final String? name = _stringFromPrefill(prefill, "medication_name") ??
            _stringFromPrefill(prefill, "memo") ??
            _stringFromPrefill(prefill, "query");
        if (name == null || name.isEmpty) {
          return null;
        }
        final int? dose = _intFromPrefill(prefill, "dose");
        return RecordEntryInput(
          type: "MEDICATION",
          startTime: now,
          value: <String, dynamic>{
            "name": name,
            if (dose != null && dose > 0) "dose": dose,
          },
        );
      case HomeTileType.memo:
        final String? memo = _stringFromPrefill(prefill, "memo") ??
            _stringFromPrefill(prefill, "query");
        if (memo == null || memo.isEmpty) {
          return null;
        }
        return RecordEntryInput(
          type: "MEMO",
          startTime: now,
          value: <String, dynamic>{"memo": memo},
        );
    }
  }

  Future<void> _persistSleepMarker(RecordEntryInput input) async {
    if (input.type != "SLEEP") {
      return;
    }
    if (input.endTime == null) {
      await AppSessionStore.setPendingSleepStart(input.startTime.toUtc());
    } else {
      await AppSessionStore.setPendingSleepStart(null);
    }
  }

  Future<void> _saveEntryInput(
    RecordEntryInput input, {
    String? successMessage,
  }) async {
    setState(() => _entrySaving = true);
    try {
      await BabyAIApi.instance.createManualEvent(
        type: input.type,
        startTime: input.startTime,
        endTime: input.endTime,
        value: input.value,
        metadata: input.metadata,
      );
      await _persistSleepMarker(input);
      await _loadLandingSnapshot();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successMessage ??
                tr(
                  context,
                  ko: "기록이 저장되었습니다.",
                  en: "Record saved.",
                  es: "Registro guardado.",
                ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _entrySaving = false);
      }
    }
  }

  Future<void> _openQuickEntry(
    HomeTileType tile, {
    Map<String, dynamic>? prefill,
  }) async {
    final RecordEntryInput? input = await showRecordEntrySheet(
      context: context,
      tile: tile,
      prefill: prefill,
    );
    if (!mounted || input == null) {
      return;
    }
    await _saveEntryInput(input);
  }

  Future<void> openQuickEntryFromExternal(
    HomeTileType tile, {
    Map<String, dynamic>? prefill,
    bool autoSubmit = false,
  }) async {
    final Map<String, dynamic> normalizedPrefill =
        prefill ?? <String, dynamic>{};
    if (autoSubmit) {
      final RecordEntryInput? autoInput =
          _buildAutoEntryFromPrefill(tile, normalizedPrefill);
      if (autoInput != null) {
        await _saveEntryInput(
          autoInput,
          successMessage: tr(
            context,
            ko: "어시스턴트 명령으로 기록했어요.",
            en: "Saved from assistant command.",
            es: "Guardado desde comando del asistente.",
          ),
        );
        return;
      }
    }
    await _openQuickEntry(tile, prefill: prefill);
  }

  Widget _tileMetaLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _metricTile({
    required String title,
    required String headline,
    required IconData icon,
    List<Widget> meta = const <Widget>[],
    VoidCallback? onTap,
  }) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Material(
      color: color.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                headline,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (meta.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                ...meta,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _graphChip(String label, double value) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        "$label ${value.round()}ml",
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> snapshot = _snapshot ?? <String, dynamic>{};
    final Map<String, int> formulaBands =
        _asBandMap(snapshot["formula_amount_by_time_band_ml"]);

    final bool isDay = widget.range == RecordRange.day;
    final bool isWeek = widget.range == RecordRange.week;
    final bool isMonth = widget.range == RecordRange.month;

    final int formulaTotal = _asInt(snapshot["formula_total_ml"]) ??
        formulaBands.values.fold<int>(0, (int sum, int value) => sum + value);
    final int formulaCount = _asInt(snapshot["formula_count"]) ?? 0;
    final int breastfeedCount = _asInt(snapshot["breastfeed_count"]) ?? 0;
    final int feedingsCount =
        _asInt(snapshot["feedings_count"]) ?? (formulaCount + breastfeedCount);
    final int weaningCount = _asInt(snapshot["weaning_count"]) ?? 0;
    final int diaperPeeCount = _asInt(snapshot["diaper_pee_count"]) ?? 0;
    final int diaperPooCount = _asInt(snapshot["diaper_poo_count"]) ?? 0;
    final int medicationCount = _asInt(snapshot["medication_count"]) ?? 0;

    final double avgFormulaPerDay =
        _asDouble(snapshot["avg_formula_ml_per_day"]) ??
            formulaTotal.toDouble();
    final double avgFeedingsPerDay =
        _asDouble(snapshot["avg_feedings_per_day"]) ?? feedingsCount.toDouble();
    final double avgSleepPerDayMin =
        _asDouble(snapshot["avg_sleep_minutes_per_day"]) ?? 0;
    final double avgNapPerDayMin =
        _asDouble(snapshot["avg_nap_minutes_per_day"]) ?? 0;
    final double avgNightPerDayMin =
        _asDouble(snapshot["avg_night_sleep_minutes_per_day"]) ?? 0;
    final double avgPeePerDay = _asDouble(snapshot["avg_diaper_pee_per_day"]) ??
        diaperPeeCount.toDouble();
    final double avgPooPerDay = _asDouble(snapshot["avg_diaper_poo_per_day"]) ??
        diaperPooCount.toDouble();

    final String lastFormula =
        _formatTime(_asString(snapshot["last_formula_time"]));
    final String lastBreastfeed =
        _formatTime(_asString(snapshot["last_breastfeed_time"]));
    final String recentSleep =
        _formatTime(_asString(snapshot["recent_sleep_time"]));
    final String recentSleepDuration =
        _formatDuration(_asInt(snapshot["recent_sleep_duration_min"]));
    final String lastSleepEnd =
        _formatTime(_asString(snapshot["last_sleep_end_time"]));
    final String lastPee = _formatTime(_asString(snapshot["last_pee_time"]));
    final String lastPoo = _formatTime(_asString(snapshot["last_poo_time"]));
    final String lastWeaning =
        _formatTime(_asString(snapshot["last_weaning_time"]));

    final String specialMemo = _asString(snapshot["special_memo"]) ??
        tr(
          context,
          ko: "선택 범위에 특별 메모가 없습니다.",
          en: "No special memo in this range.",
          es: "No hay nota especial en este rango.",
        );

    final List<String> graphLabels =
        _asStringList(snapshot["feeding_graph_labels"]);
    final List<double> graphPointsRaw =
        _asDoubleList(snapshot["feeding_graph_points"]);
    final int graphCount = graphLabels.length < graphPointsRaw.length
        ? graphLabels.length
        : graphPointsRaw.length;
    final List<String> graphLabelsSafe =
        graphCount == 0 ? <String>["-"] : graphLabels.sublist(0, graphCount);
    final List<double> graphPoints =
        graphCount == 0 ? <double>[0] : graphPointsRaw.sublist(0, graphCount);

    String decimalLabel(double value) {
      if (value.isNaN || value.isInfinite) {
        return "0";
      }
      final double rounded = (value * 10).roundToDouble() / 10;
      if ((rounded - rounded.roundToDouble()).abs() < 0.05) {
        return rounded.round().toString();
      }
      return rounded.toStringAsFixed(1);
    }

    final String formulaHeadline =
        isDay ? "$formulaTotal ml" : "${decimalLabel(avgFormulaPerDay)} ml";
    final String sleepHeadline = isDay
        ? recentSleepDuration
        : _formatDuration(avgSleepPerDayMin.round());
    final String diaperHeadline = isMonth
        ? "${decimalLabel(avgPooPerDay)} / ${decimalLabel(avgPeePerDay)}"
        : "$diaperPooCount / $diaperPeeCount";

    final String graphTitle = isDay
        ? tr(context,
            ko: "수유 텀별 수유량",
            en: "Feeding amount by session",
            es: "Cantidad por sesion")
        : isWeek
            ? tr(context,
                ko: "1일 총 수유량 (주간)",
                en: "Daily total feeding (week)",
                es: "Total diario (semana)")
            : tr(context,
                ko: "일자별 총 수유량 (월간)",
                en: "Daily total feeding (month)",
                es: "Total diario (mes)");
    final String graphHint = isMonth
        ? tr(
            context,
            ko: "월 화면은 일자별 총 수유량 추이를 제공합니다.",
            en: "Month view shows daily total feeding trend.",
            es: "La vista mensual muestra tendencia diaria de formula.",
          )
        : "";

    return RefreshIndicator(
      onRefresh: _loadLandingSnapshot,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_snapshotLoading || _entrySaving) const LinearProgressIndicator(),
          if (_snapshotError != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _snapshotError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: Text(
                tr(
                  context,
                  ko: "특별 메모",
                  en: "Special memo",
                  es: "Nota especial",
                ),
              ),
              subtitle: Text(specialMemo),
            ),
          ),
          const SizedBox(height: 10),
          Builder(
            builder: (BuildContext context) {
              final AppThemeController? settings =
                  AppSettingsScope.maybeOf(context);
              final int tileColumns =
                  (settings?.homeTileColumns ?? 2).clamp(2, 3);

              final List<Widget> tiles = <Widget>[
                if (settings?.isHomeTileEnabled(HomeTileType.formula) ?? true)
                  _metricTile(
                    title: tr(
                      context,
                      ko: "분유",
                      en: "Formula",
                      es: "Formula",
                    ),
                    headline: formulaHeadline,
                    icon: Icons.local_drink_outlined,
                    meta: <Widget>[
                      _tileMetaLine(
                        isDay
                            ? tr(context, ko: "총 수유량", en: "Total", es: "Total")
                            : tr(context,
                                ko: "1일 평균 수유량",
                                en: "Avg/day amount",
                                es: "Promedio diario"),
                        isDay
                            ? "$formulaTotal ml"
                            : "${decimalLabel(avgFormulaPerDay)} ml",
                      ),
                      _tileMetaLine(
                        isDay
                            ? tr(context,
                                ko: "수유 횟수", en: "Feedings", es: "Tomas")
                            : tr(context,
                                ko: "1일 평균 수유 횟수",
                                en: "Avg/day feedings",
                                es: "Promedio de tomas"),
                        isDay
                            ? "$feedingsCount"
                            : decimalLabel(avgFeedingsPerDay),
                      ),
                      _tileMetaLine(
                        tr(context,
                            ko: "마지막 분유/모유",
                            en: "Last formula/breast",
                            es: "Ultima formula/lactancia"),
                        "$lastFormula / $lastBreastfeed",
                      ),
                    ],
                    onTap: _entrySaving
                        ? null
                        : () => _openQuickEntry(HomeTileType.formula),
                  ),
                if (settings?.isHomeTileEnabled(HomeTileType.sleep) ?? true)
                  _metricTile(
                    title: tr(
                      context,
                      ko: "수면",
                      en: "Sleep",
                      es: "Sueno",
                    ),
                    headline: sleepHeadline,
                    icon: Icons.bedtime_outlined,
                    meta: <Widget>[
                      _tileMetaLine(
                        isDay
                            ? tr(context,
                                ko: "최근 잠 지속", en: "Duration", es: "Duracion")
                            : tr(context,
                                ko: "1일 평균 수면 시간",
                                en: "Avg/day sleep",
                                es: "Sueno diario"),
                        isDay
                            ? recentSleepDuration
                            : _formatDuration(avgSleepPerDayMin.round()),
                      ),
                      _tileMetaLine(
                        isDay
                            ? tr(context,
                                ko: "마지막 잠 종료",
                                en: "Last sleep end",
                                es: "Fin del sueno")
                            : tr(context,
                                ko: "1일 평균 낮잠 지속",
                                en: "Avg/day nap",
                                es: "Siesta diaria"),
                        isDay
                            ? lastSleepEnd
                            : _formatDuration(avgNapPerDayMin.round()),
                      ),
                      _tileMetaLine(
                        isDay
                            ? tr(context,
                                ko: "최근 잠 시작",
                                en: "Recent sleep start",
                                es: "Inicio reciente")
                            : tr(context,
                                ko: "1일 평균 밤잠 지속",
                                en: "Avg/day night sleep",
                                es: "Sueno nocturno diario"),
                        isDay
                            ? recentSleep
                            : _formatDuration(avgNightPerDayMin.round()),
                      ),
                    ],
                    onTap: _entrySaving
                        ? null
                        : () => _openQuickEntry(HomeTileType.sleep),
                  ),
                if (settings?.isHomeTileEnabled(HomeTileType.diaper) ?? true)
                  _metricTile(
                    title: tr(
                      context,
                      ko: "기저귀",
                      en: "Diaper",
                      es: "Panal",
                    ),
                    headline: diaperHeadline,
                    icon: Icons.baby_changing_station_outlined,
                    meta: <Widget>[
                      _tileMetaLine(
                        isMonth
                            ? tr(context,
                                ko: "1일 평균 대변 횟수",
                                en: "Avg/day poo",
                                es: "Promedio heces")
                            : isWeek
                                ? tr(context,
                                    ko: "주 총 대변 횟수",
                                    en: "Weekly poo total",
                                    es: "Total heces semana")
                                : tr(context,
                                    ko: "마지막 대변",
                                    en: "Last poo",
                                    es: "Ultimas heces"),
                        isMonth
                            ? decimalLabel(avgPooPerDay)
                            : isWeek
                                ? "$diaperPooCount"
                                : lastPoo,
                      ),
                      _tileMetaLine(
                        isMonth
                            ? tr(context,
                                ko: "1일 평균 소변 횟수",
                                en: "Avg/day pee",
                                es: "Promedio orina")
                            : isWeek
                                ? tr(context,
                                    ko: "주 총 소변 횟수",
                                    en: "Weekly pee total",
                                    es: "Total orina semana")
                                : tr(context,
                                    ko: "마지막 소변",
                                    en: "Last pee",
                                    es: "Ultima orina"),
                        isMonth
                            ? decimalLabel(avgPeePerDay)
                            : isWeek
                                ? "$diaperPeeCount"
                                : lastPee,
                      ),
                    ],
                    onTap: _entrySaving
                        ? null
                        : () => _openQuickEntry(HomeTileType.diaper),
                  ),
                if (settings?.isHomeTileEnabled(HomeTileType.weaning) ?? true)
                  _metricTile(
                    title: tr(
                      context,
                      ko: "이유식",
                      en: "Weaning",
                      es: "Destete",
                    ),
                    headline: lastWeaning,
                    icon: Icons.rice_bowl_outlined,
                    meta: <Widget>[
                      _tileMetaLine(
                        tr(context, ko: "오늘 횟수", en: "Count", es: "Conteo"),
                        "$weaningCount",
                      ),
                    ],
                    onTap: _entrySaving
                        ? null
                        : () => _openQuickEntry(HomeTileType.weaning),
                  ),
                if (settings?.isHomeTileEnabled(HomeTileType.medication) ??
                    true)
                  _metricTile(
                    title: tr(
                      context,
                      ko: "투약",
                      en: "Medication",
                      es: "Medicacion",
                    ),
                    headline: _formatTime(
                        _asString(snapshot["last_medication_time"])),
                    icon: Icons.medication_outlined,
                    meta: <Widget>[
                      _tileMetaLine(
                        tr(context, ko: "오늘 횟수", en: "Count", es: "Conteo"),
                        "$medicationCount",
                      ),
                    ],
                    onTap: _entrySaving
                        ? null
                        : () => _openQuickEntry(HomeTileType.medication),
                  ),
              ];

              return GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: tileColumns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: tileColumns == 3 ? 0.9 : 1.1,
                ),
                children: tiles,
              );
            },
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    graphTitle,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (graphHint.isNotEmpty) Text(graphHint),
                  if (!isDay) ...<Widget>[
                    Text(
                      "${tr(context, ko: "밤", en: "Night", es: "Noche")}: ${formulaBands["night"]} / "
                      "${tr(context, ko: "아침", en: "Morning", es: "Manana")}: ${formulaBands["morning"]} / "
                      "${tr(context, ko: "오후", en: "Afternoon", es: "Tarde")}: ${formulaBands["afternoon"]} / "
                      "${tr(context, ko: "저녁", en: "Evening", es: "Noche")}: ${formulaBands["evening"]}",
                    ),
                  ],
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List<Widget>.generate(
                        graphPoints.length,
                        (int index) => _graphChip(
                          index < graphLabelsSafe.length
                              ? graphLabelsSafe[index]
                              : "-",
                          graphPoints[index],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 120,
                    child: SimpleLineChart(
                      points: graphPoints,
                      lineColor: const Color(0xFF8C8ED4),
                      fillColor: const Color(0xFF8C8ED4).withValues(alpha: 0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "${tr(context, ko: "기록 요약", en: "Records summary", es: "Resumen")}: "
            "${tr(context, ko: "분유", en: "Formula", es: "Formula")} $formulaCount, "
            "${tr(context, ko: "모유", en: "Breastfeed", es: "Lactancia")} $breastfeedCount, "
            "${tr(context, ko: "이유식", en: "Weaning", es: "Destete")} $weaningCount, "
            "${tr(context, ko: "투약", en: "Medication", es: "Medicacion")} $medicationCount",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
