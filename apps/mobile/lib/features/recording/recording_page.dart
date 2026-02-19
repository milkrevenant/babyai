import "dart:async";

import "package:flutter/material.dart";

import "../../core/config/session_store.dart";
import "../../core/i18n/app_i18n.dart";
import "../../core/network/babyai_api.dart";
import "../../core/theme/app_theme_controller.dart";
import "../../core/widgets/app_svg_icon.dart";
import "record_entry_sheet.dart";

enum RecordRange { day, week, month }

enum _TimerActivity {
  sleep,
  formula,
  breastfeed,
  diaper,
}

class _CompletedTimerEntry {
  const _CompletedTimerEntry({
    required this.activity,
    required this.startAt,
    required this.endAt,
  });

  final _TimerActivity activity;
  final DateTime startAt;
  final DateTime endAt;

  Duration get duration => endAt.difference(startAt);
}

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
  Timer? _clockTicker;
  DateTime _now = DateTime.now();
  _TimerActivity _selectedTimerActivity = _TimerActivity.sleep;
  _TimerActivity? _activeTimerActivity;
  DateTime? _activeTimerStartedAt;
  _CompletedTimerEntry? _latestTimerEntry;

  @override
  void initState() {
    super.initState();
    final DateTime? pendingSleepStart =
        AppSessionStore.pendingSleepStart?.toLocal();
    if (pendingSleepStart != null) {
      _selectedTimerActivity = _TimerActivity.sleep;
      _activeTimerActivity = _TimerActivity.sleep;
      _activeTimerStartedAt = pendingSleepStart;
    }
    _clockTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
    unawaited(_loadLandingSnapshot());
  }

  @override
  void dispose() {
    _clockTicker?.cancel();
    super.dispose();
  }

  Future<void> _loadLandingSnapshot() async {
    setState(() {
      _snapshotLoading = true;
      _snapshotError = null;
    });

    try {
      final Map<String, dynamic> result =
          await BabyAIApi.instance.quickLandingSnapshot();
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

  Future<void> refreshData() async {
    await _loadLandingSnapshot();
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

  String? _asString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
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
      r"(\d{1,4})\s*(ml|mL|ML|cc|밀리|미리)",
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
      r"(\d{1,2})\s*(hour|hours|hr|hrs|h|시간)",
      caseSensitive: false,
    );
    final RegExp minuteRegExp = RegExp(
      r"(\d{1,3})\s*(min|mins|minute|minutes|m|분)",
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

  String _rangeLabel() {
    final DateTime now = DateTime.now();
    switch (widget.range) {
      case RecordRange.day:
        return "${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}";
      case RecordRange.week:
        final DateTime monday = now.subtract(Duration(days: now.weekday - 1));
        final DateTime sunday = monday.add(const Duration(days: 6));
        return "${monday.month}/${monday.day} - ${sunday.month}/${sunday.day}";
      case RecordRange.month:
        return "${now.year}-${now.month.toString().padLeft(2, "0")}";
    }
  }

  String _formatActivityClock(Duration duration) {
    final int safeSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final int hours = safeSeconds ~/ 3600;
    final int minutes = (safeSeconds % 3600) ~/ 60;
    final int seconds = safeSeconds % 60;
    return "${hours.toString().padLeft(2, "0")} : "
        "${minutes.toString().padLeft(2, "0")} : "
        "${seconds.toString().padLeft(2, "0")}";
  }

  String _formatAmPm(DateTime value) {
    final int hour24 = value.hour;
    final int hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final String minute = value.minute.toString().padLeft(2, "0");
    final String period = hour24 >= 12 ? "오후" : "오전";
    return "$hour12:$minute $period";
  }

  String _formatDateTimeLabel(DateTime? value) {
    if (value == null) {
      return "-";
    }
    final String month = value.month.toString().padLeft(2, "0");
    final String day = value.day.toString().padLeft(2, "0");
    return "$month/$day ${_formatAmPm(value)}";
  }

  String _formatCompactDuration(Duration duration) {
    final int safeSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final int hours = safeSeconds ~/ 3600;
    final int minutes = (safeSeconds % 3600) ~/ 60;
    final int seconds = safeSeconds % 60;
    return "${hours.toString().padLeft(2, "0")}:"
        "${minutes.toString().padLeft(2, "0")}:"
        "${seconds.toString().padLeft(2, "0")}";
  }

  String _timerActivityLabel(_TimerActivity activity) {
    switch (activity) {
      case _TimerActivity.sleep:
        return "수면";
      case _TimerActivity.formula:
        return "수유";
      case _TimerActivity.breastfeed:
        return "모유";
      case _TimerActivity.diaper:
        return "기저귀";
    }
  }

  String _timerActivityAsset(_TimerActivity activity) {
    switch (activity) {
      case _TimerActivity.sleep:
        return AppSvgAsset.sleepCrescentYellow;
      case _TimerActivity.formula:
      case _TimerActivity.breastfeed:
        return AppSvgAsset.feeding;
      case _TimerActivity.diaper:
        return AppSvgAsset.diaper;
    }
  }

  Color _timerActivityAccent(_TimerActivity activity) {
    switch (activity) {
      case _TimerActivity.sleep:
        return const Color(0xFF9B7AD8);
      case _TimerActivity.formula:
      case _TimerActivity.breastfeed:
        return const Color(0xFF2D9CDB);
      case _TimerActivity.diaper:
        return const Color(0xFF1CA79A);
    }
  }

  String _relativeAgo(String? isoDateTime) {
    final DateTime? parsed = _parseIsoDateTime(isoDateTime);
    if (parsed == null) {
      return "-";
    }
    final Duration diff = _now.difference(parsed);
    if (diff.inMinutes < 1) {
      return "방금 전";
    }
    if (diff.inMinutes < 60) {
      return "${diff.inMinutes}분 전";
    }
    if (diff.inHours < 24) {
      return "${diff.inHours}시간 전";
    }
    return "${diff.inDays}일 전";
  }

  List<HomeTileType> _visibleTiles(AppThemeController controller) {
    final List<HomeTileType> tiles = HomeTileType.values
        .where((HomeTileType tile) => controller.isHomeTileEnabled(tile))
        .toList();
    if (tiles.isNotEmpty) {
      return tiles;
    }
    return <HomeTileType>[
      HomeTileType.formula,
      HomeTileType.diaper,
      HomeTileType.sleep,
    ];
  }

  List<HomeTileType> _dashboardTiles(AppThemeController controller) {
    final List<HomeTileType> base = _visibleTiles(controller);
    const List<HomeTileType> fallbackOrder = <HomeTileType>[
      HomeTileType.formula,
      HomeTileType.breastfeed,
      HomeTileType.sleep,
      HomeTileType.diaper,
      HomeTileType.weaning,
      HomeTileType.medication,
      HomeTileType.memo,
    ];
    for (final HomeTileType tile in fallbackOrder) {
      if (!base.contains(tile)) {
        base.add(tile);
      }
      if (base.length >= 6) {
        break;
      }
    }
    return base.take(6).toList();
  }

  String _dashboardTileAsset(HomeTileType tile) {
    switch (tile) {
      case HomeTileType.formula:
      case HomeTileType.breastfeed:
        return AppSvgAsset.feeding;
      case HomeTileType.sleep:
        return AppSvgAsset.sleepCrescentYellow;
      case HomeTileType.diaper:
        return AppSvgAsset.diaper;
      case HomeTileType.weaning:
        return AppSvgAsset.playCar;
      case HomeTileType.medication:
        return AppSvgAsset.medicine;
      case HomeTileType.memo:
        return AppSvgAsset.clinicStethoscope;
    }
  }

  String _dashboardTileLabel(HomeTileType tile) {
    switch (tile) {
      case HomeTileType.formula:
        return "수유";
      case HomeTileType.breastfeed:
        return "모유";
      case HomeTileType.sleep:
        return "수면";
      case HomeTileType.diaper:
        return "기저귀";
      case HomeTileType.weaning:
        return "놀이";
      case HomeTileType.medication:
        return "투약";
      case HomeTileType.memo:
        return "진료";
    }
  }

  Color _dashboardTileAccent(HomeTileType tile) {
    switch (tile) {
      case HomeTileType.formula:
      case HomeTileType.breastfeed:
        return const Color(0xFF2D9CDB);
      case HomeTileType.sleep:
        return const Color(0xFF9B7AD8);
      case HomeTileType.diaper:
        return const Color(0xFF1CA79A);
      case HomeTileType.weaning:
        return const Color(0xFFF09819);
      case HomeTileType.medication:
        return const Color(0xFFE84076);
      case HomeTileType.memo:
        return const Color(0xFFA546C9);
    }
  }

  RecordEntryInput _buildTimerRecordInput({
    required _TimerActivity activity,
    required DateTime startAt,
    required DateTime endAt,
  }) {
    final int durationSeconds = endAt.difference(startAt).inSeconds;
    final int safeDurationSeconds = durationSeconds < 0 ? 0 : durationSeconds;
    final int safeDurationMinutes = safeDurationSeconds ~/ 60;
    switch (activity) {
      case _TimerActivity.sleep:
        return RecordEntryInput(
          type: "SLEEP",
          startTime: startAt,
          endTime: endAt,
          value: <String, dynamic>{
            "duration_min": safeDurationMinutes,
            "duration_sec": safeDurationSeconds,
          },
          metadata: const <String, dynamic>{"timer_activity": "SLEEP"},
        );
      case _TimerActivity.formula:
        return RecordEntryInput(
          type: "FORMULA",
          startTime: startAt,
          endTime: endAt,
          value: <String, dynamic>{
            "duration_min": safeDurationMinutes,
            "duration_sec": safeDurationSeconds,
          },
          metadata: const <String, dynamic>{"timer_activity": "FORMULA"},
        );
      case _TimerActivity.breastfeed:
        return RecordEntryInput(
          type: "BREASTFEED",
          startTime: startAt,
          endTime: endAt,
          value: <String, dynamic>{
            "duration_min": safeDurationMinutes,
            "duration_sec": safeDurationSeconds,
          },
          metadata: const <String, dynamic>{"timer_activity": "BREASTFEED"},
        );
      case _TimerActivity.diaper:
        return RecordEntryInput(
          type: "PEE",
          startTime: startAt,
          endTime: endAt,
          value: <String, dynamic>{
            "count": 1,
            "duration_min": safeDurationMinutes,
            "duration_sec": safeDurationSeconds,
          },
          metadata: const <String, dynamic>{"timer_activity": "PEE"},
        );
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
          if (lowered.contains("poo") ||
              lowered.contains("poop") ||
              lowered.contains("대변") ||
              lowered.contains("응가")) {
            diaperType = "POO";
          } else if (lowered.contains("pee") ||
              lowered.contains("urine") ||
              lowered.contains("소변") ||
              lowered.contains("오줌")) {
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
                _stringFromPrefill(prefill, "sleep_start_time"),
              ) ??
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

  Future<bool> _saveEntryInput(
    RecordEntryInput input, {
    String? successMessage,
  }) async {
    setState(() => _entrySaving = true);
    bool saved = false;
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
        return false;
      }
      saved = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successMessage ??
                tr(context,
                    ko: "기록이 저장되었어요.",
                    en: "Record saved.",
                    es: "Registro guardado."),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _entrySaving = false);
      }
    }
    return saved;
  }

  Future<void> _startSelectedTimer() async {
    if (_entrySaving || _activeTimerStartedAt != null) {
      return;
    }
    final DateTime startedAt = DateTime.now();
    final _TimerActivity selected = _selectedTimerActivity;
    setState(() {
      _activeTimerActivity = selected;
      _activeTimerStartedAt = startedAt;
    });
    if (selected == _TimerActivity.sleep) {
      await AppSessionStore.setPendingSleepStart(startedAt.toUtc());
    }
  }

  Future<void> _stopActiveTimer() async {
    if (_entrySaving ||
        _activeTimerStartedAt == null ||
        _activeTimerActivity == null) {
      return;
    }
    final DateTime startAt = _activeTimerStartedAt!;
    final DateTime endAt = DateTime.now();
    final _TimerActivity activity = _activeTimerActivity!;
    final RecordEntryInput input = _buildTimerRecordInput(
      activity: activity,
      startAt: startAt,
      endAt: endAt,
    );
    final bool saved = await _saveEntryInput(
      input,
      successMessage: tr(
        context,
        ko: "${_timerActivityLabel(activity)} 타이머 기록이 저장되었어요.",
        en: "Timer record saved.",
        es: "Registro de temporizador guardado.",
      ),
    );
    if (!mounted || !saved) {
      return;
    }
    setState(() {
      _latestTimerEntry = _CompletedTimerEntry(
        activity: activity,
        startAt: startAt,
        endAt: endAt,
      );
      _activeTimerActivity = null;
      _activeTimerStartedAt = null;
    });
  }

  Widget _buildTimerInfoItem({
    required ColorScheme color,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
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
            ko: "어시스턴트 명령으로 저장했어요.",
            en: "Saved from assistant command.",
            es: "Guardado desde comando del asistente.",
          ),
        );
        return;
      }
    }
    await _openQuickEntry(tile, prefill: prefill);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    final AppThemeController controller = AppSettingsScope.of(context);
    final Map<String, dynamic> snapshot = _snapshot ?? <String, dynamic>{};
    final List<HomeTileType> tiles = _dashboardTiles(controller);
    final int aiBalance = _asInt(snapshot["ai_credit_balance"]) ?? 0;
    final int aiGraceUsed = _asInt(snapshot["ai_grace_used_today"]) ?? 0;
    final int aiGraceLimit = _asInt(snapshot["ai_grace_limit"]) ?? 3;

    final String greeting = _now.hour < 12
        ? "좋은 아침이에요,"
        : (_now.hour < 18 ? "좋은 오후예요," : "편안한 저녁이에요,");
    final String babyName = _asString(snapshot["baby_name"]) ?? "우리 아기";
    final String lastFormulaAgo =
        _relativeAgo(_asString(snapshot["last_formula_time"]));
    final String lastDiaperAgo =
        _relativeAgo(_asString(snapshot["last_diaper_time"]));

    final bool timerRunning =
        _activeTimerActivity != null && _activeTimerStartedAt != null;
    final _TimerActivity cardActivity =
        timerRunning ? _activeTimerActivity! : _selectedTimerActivity;
    final DateTime? timerStartAt =
        timerRunning ? _activeTimerStartedAt : _latestTimerEntry?.startAt;
    final DateTime? timerEndAt = timerRunning ? null : _latestTimerEntry?.endAt;
    final Duration timerDuration = timerRunning
        ? _now.difference(_activeTimerStartedAt!)
        : (_latestTimerEntry?.duration ?? Duration.zero);
    final String timerDurationLabel =
        (timerRunning || _latestTimerEntry != null)
            ? _formatCompactDuration(timerDuration)
            : "-";
    final String activityTitle = timerRunning
        ? "${_timerActivityLabel(cardActivity)} 진행 중"
        : _timerActivityLabel(cardActivity);
    final String activityClock = _formatActivityClock(timerDuration);
    final String activitySubtitle = timerRunning
        ? "시작 ${_formatAmPm(_activeTimerStartedAt!)}"
        : (_latestTimerEntry == null
            ? "활동을 선택하고 시작 버튼을 눌러 주세요."
            : "최근 완료 ${_formatAmPm(_latestTimerEntry!.endAt)}");

    return RefreshIndicator(
      onRefresh: _loadLandingSnapshot,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: <Widget>[
          Row(
            children: <Widget>[
              const CircleAvatar(
                radius: 26,
                backgroundColor: Color(0xFFFFF2D9),
                child: Center(
                  child: AppSvgIcon(
                    AppSvgAsset.profile,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      greeting,
                      style: TextStyle(
                        color: color.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      babyName,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _rangeLabel(),
                      style: TextStyle(
                        color: color.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          color.surfaceContainerHighest.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          "AI $aiBalance cr",
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          "Grace $aiGraceUsed/$aiGraceLimit",
                          style: TextStyle(
                            fontSize: 10,
                            color: color.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: color.surfaceContainerHighest.withValues(alpha: 0.7),
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: _snapshotLoading ? null : _loadLandingSnapshot,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_snapshotLoading || _entrySaving) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (_snapshotError != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _snapshotError!,
              style: TextStyle(color: color.error, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              const Text(
                "타이머",
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                "실시간 추적",
                style: TextStyle(
                    color: color.primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: const Color(0xFFE7DECF)),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _timerActivityAccent(cardActivity)
                            .withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: AppSvgIcon(
                          _timerActivityAsset(cardActivity),
                          color: _timerActivityAccent(cardActivity),
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            activityTitle,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activitySubtitle,
                            style: TextStyle(
                              color: color.onSurfaceVariant,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      activityClock,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: color.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      _TimerActivity.values.map((_TimerActivity activity) {
                    final bool selected = _selectedTimerActivity == activity;
                    final Color accent = _timerActivityAccent(activity);
                    return ChoiceChip(
                      selected: selected,
                      label: Text(_timerActivityLabel(activity)),
                      avatar: AppSvgIcon(
                        _timerActivityAsset(activity),
                        size: 15,
                        color: selected
                            ? color.onPrimaryContainer
                            : color.onSurfaceVariant,
                      ),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? color.onPrimaryContainer
                            : color.onSurfaceVariant,
                      ),
                      selectedColor: accent.withValues(alpha: 0.22),
                      side: BorderSide(
                        color: selected
                            ? accent.withValues(alpha: 0.6)
                            : color.outline.withValues(alpha: 0.32),
                      ),
                      onSelected: (_entrySaving || timerRunning)
                          ? null
                          : (bool value) {
                              if (!value) {
                                return;
                              }
                              setState(() => _selectedTimerActivity = activity);
                            },
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        color.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _buildTimerInfoItem(
                          color: color,
                          label: "시작시각",
                          value: _formatDateTimeLabel(timerStartAt),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: color.outline.withValues(alpha: 0.2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildTimerInfoItem(
                          color: color,
                          label: "종료시각",
                          value: _formatDateTimeLabel(timerEndAt),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: color.outline.withValues(alpha: 0.2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildTimerInfoItem(
                          color: color,
                          label: "총 시간",
                          value: timerDurationLabel,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: (_entrySaving || timerRunning)
                            ? null
                            : _startSelectedTimer,
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text("시작"),
                        style: FilledButton.styleFrom(
                          backgroundColor: color.primary,
                          foregroundColor: color.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_entrySaving || !timerRunning)
                            ? null
                            : _stopActiveTimer,
                        icon: const Icon(Icons.stop_rounded, size: 20),
                        label: const Text("종료"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color.error,
                          side: BorderSide(
                            color: color.error.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "빠른 기록",
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tiles.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.02,
            ),
            itemBuilder: (BuildContext context, int index) {
              final HomeTileType tile = tiles[index];
              final Color accent = _dashboardTileAccent(tile);
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(34),
                child: InkWell(
                  borderRadius: BorderRadius.circular(34),
                  onTap: _entrySaving ? null : () => _openQuickEntry(tile),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: AppSvgIcon(
                              _dashboardTileAsset(tile),
                              color: accent,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _dashboardTileLabel(tile),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            "마지막 수유: $lastFormulaAgo · 기저귀 교체: $lastDiaperAgo",
            style: TextStyle(
              color: color.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
