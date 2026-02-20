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

enum _BreastfeedSide { left, right }

class _CompletedTimerEntry {
  const _CompletedTimerEntry({
    required this.activity,
    required this.startAt,
    required this.endAt,
    this.eventId,
  });

  final _TimerActivity activity;
  final DateTime startAt;
  final DateTime endAt;
  final String? eventId;

  Duration get duration => endAt.difference(startAt);
}

class RecordingPage extends StatefulWidget {
  const RecordingPage({
    super.key,
    required this.range,
    this.onBabyNameChanged,
    this.onBabyPhotoChanged,
  });

  final RecordRange range;
  final ValueChanged<String>? onBabyNameChanged;
  final ValueChanged<String?>? onBabyPhotoChanged;

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
  String? _activeTimerEventId;
  _BreastfeedSide _breastfeedSide = _BreastfeedSide.left;
  _CompletedTimerEntry? _latestTimerEntry;
  int _landingSnapshotRequestSeq = 0;

  @override
  void initState() {
    super.initState();
    final DateTime? pendingSleepStart =
        AppSessionStore.pendingSleepStart?.toLocal();
    final DateTime? pendingFormulaStart =
        AppSessionStore.pendingFormulaStart?.toLocal();
    if (pendingSleepStart != null) {
      _selectedTimerActivity = _TimerActivity.sleep;
      _activeTimerActivity = _TimerActivity.sleep;
      _activeTimerStartedAt = pendingSleepStart;
    } else if (pendingFormulaStart != null) {
      _selectedTimerActivity = _TimerActivity.formula;
      _activeTimerActivity = _TimerActivity.formula;
      _activeTimerStartedAt = pendingFormulaStart;
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

  Future<void> _loadLandingSnapshot({
    bool preferOffline = true,
  }) async {
    final int requestSeq = ++_landingSnapshotRequestSeq;
    setState(() {
      _snapshotLoading = true;
      _snapshotError = null;
    });

    try {
      final String range = _rangeKey();
      final Map<String, dynamic> result =
          await BabyAIApi.instance.quickLandingSnapshot(
        range: range,
        preferOffline: preferOffline,
      );
      if (!mounted) {
        return;
      }
      if (requestSeq != _landingSnapshotRequestSeq) {
        return;
      }
      final String? babyName = _asString(result["baby_name"]);
      final String? babyPhoto = _asString(result["baby_profile_photo_url"]) ??
          _asString(result["profile_photo_url"]) ??
          _asString(result["baby_photo_url"]) ??
          _asString(result["avatar_url"]) ??
          _asString(result["image_url"]);
      setState(() {
        _snapshot = result;
        if (_activeTimerActivity != null &&
            (_activeTimerEventId == null || _activeTimerEventId!.isEmpty)) {
          _activeTimerEventId =
              _openEventIdForTimerActivity(result, _activeTimerActivity!);
        }
      });
      if (babyName != null && babyName.isNotEmpty) {
        widget.onBabyNameChanged?.call(babyName);
      }
      widget.onBabyPhotoChanged?.call(babyPhoto);
      if (preferOffline) {
        unawaited(_refreshLandingSnapshotFromServer(range, requestSeq));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (requestSeq != _landingSnapshotRequestSeq) {
        return;
      }
      setState(() => _snapshotError = error.toString());
    } finally {
      if (mounted) {
        if (requestSeq == _landingSnapshotRequestSeq) {
          setState(() => _snapshotLoading = false);
        }
      }
    }
  }

  String _rangeKey() {
    return switch (widget.range) {
      RecordRange.day => "day",
      RecordRange.week => "week",
      RecordRange.month => "month",
    };
  }

  Future<void> _refreshLandingSnapshotFromServer(
    String range,
    int parentRequestSeq,
  ) async {
    try {
      final Map<String, dynamic> remote =
          await BabyAIApi.instance.quickLandingSnapshot(
        range: range,
        preferOffline: false,
      );
      if (!mounted) {
        return;
      }
      if (parentRequestSeq != _landingSnapshotRequestSeq) {
        return;
      }
      final String? babyName = _asString(remote["baby_name"]);
      final String? babyPhoto = _asString(remote["baby_profile_photo_url"]) ??
          _asString(remote["profile_photo_url"]) ??
          _asString(remote["baby_photo_url"]) ??
          _asString(remote["avatar_url"]) ??
          _asString(remote["image_url"]);
      setState(() {
        _snapshot = remote;
        _snapshotError = null;
      });
      if (babyName != null && babyName.isNotEmpty) {
        widget.onBabyNameChanged?.call(babyName);
      }
      widget.onBabyPhotoChanged?.call(babyPhoto);
    } catch (_) {
      // Keep offline-first snapshot visible when remote refresh fails.
    }
  }

  Future<void> refreshData() async {
    await _loadLandingSnapshot(preferOffline: false);
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
        return "분유";
      case _TimerActivity.breastfeed:
        return "모유";
      case _TimerActivity.diaper:
        return "기저귀";
    }
  }

  String _breastfeedSideValue() {
    return _breastfeedSide == _BreastfeedSide.left ? "LEFT" : "RIGHT";
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
    final List<HomeTileType> tiles = <HomeTileType>[];
    for (final HomeTileType tile in controller.homeTileOrder) {
      if (controller.isHomeTileEnabled(tile)) {
        tiles.add(tile);
      }
    }
    for (final HomeTileType tile in HomeTileType.values) {
      if (controller.isHomeTileEnabled(tile) && !tiles.contains(tile)) {
        tiles.add(tile);
      }
    }
    if (tiles.isNotEmpty) {
      return tiles;
    }
    return <HomeTileType>[
      HomeTileType.formula,
      HomeTileType.weaning,
      HomeTileType.diaper,
      HomeTileType.sleep,
      HomeTileType.medication,
      HomeTileType.breastfeed,
    ];
  }

  List<HomeTileType> _dashboardTiles(AppThemeController controller) {
    final List<HomeTileType> base = _visibleTiles(controller);
    const List<HomeTileType> fallbackOrder = <HomeTileType>[
      HomeTileType.formula,
      HomeTileType.weaning,
      HomeTileType.diaper,
      HomeTileType.sleep,
      HomeTileType.medication,
      HomeTileType.breastfeed,
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
        return "분유";
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

  String _dashboardTileHeadline(
      HomeTileType tile, Map<String, dynamic> snapshot) {
    final bool isDay = widget.range == RecordRange.day;
    final bool isMonth = widget.range == RecordRange.month;
    final int formulaTotal = _asInt(snapshot["formula_total_ml"]) ?? 0;
    final int formulaCount = _asInt(snapshot["formula_count"]) ?? 0;
    final int breastfeedCount = _asInt(snapshot["breastfeed_count"]) ?? 0;
    final int feedingsCount =
        _asInt(snapshot["feedings_count"]) ?? (formulaCount + breastfeedCount);
    final int weaningCount = _asInt(snapshot["weaning_count"]) ?? 0;
    final int medicationCount = _asInt(snapshot["medication_count"]) ?? 0;
    final int rangeDayCount =
        (_asInt(snapshot["range_day_count"]) ?? (isDay ? 1 : 7)).clamp(1, 31);
    final double avgFormulaPerDay =
        _asDouble(snapshot["avg_formula_ml_per_day"]) ??
            formulaTotal.toDouble();
    final double avgFeedingsPerDay =
        _asDouble(snapshot["avg_feedings_per_day"]) ?? feedingsCount.toDouble();
    final double avgSleepPerDayMin =
        _asDouble(snapshot["avg_sleep_minutes_per_day"]) ?? 0;

    switch (tile) {
      case HomeTileType.formula:
        if (isDay) {
          return "${formulaTotal}ml";
        }
        return "${_decimal(avgFormulaPerDay)}ml / ${_decimal(avgFeedingsPerDay)}회";
      case HomeTileType.breastfeed:
        if (isDay) {
          return "$breastfeedCount회";
        }
        final double avg = breastfeedCount / rangeDayCount;
        return "${_decimal(avg)}회";
      case HomeTileType.sleep:
        if (isDay) {
          final int? duration = _asInt(snapshot["recent_sleep_duration_min"]);
          return duration == null ? "-" : _formatDuration(duration);
        }
        return _formatDuration(avgSleepPerDayMin.round());
      case HomeTileType.diaper:
        final int pee = _asInt(snapshot["diaper_pee_count"]) ?? 0;
        final int poo = _asInt(snapshot["diaper_poo_count"]) ?? 0;
        if (isMonth) {
          return "소${_decimal(pee / rangeDayCount)} · 대${_decimal(poo / rangeDayCount)}";
        }
        return "소$pee · 대$poo";
      case HomeTileType.weaning:
        if (isDay) {
          return "$weaningCount회";
        }
        return "${_decimal(weaningCount / rangeDayCount)}회";
      case HomeTileType.medication:
        if (isDay) {
          return "$medicationCount회";
        }
        return "${_decimal(medicationCount / rangeDayCount)}회";
      case HomeTileType.memo:
        return "${_asInt(snapshot["memo_count"]) ?? 0}개";
    }
  }

  String _dashboardTileSubtitle(
      HomeTileType tile, Map<String, dynamic> snapshot) {
    switch (tile) {
      case HomeTileType.formula:
        return "마지막 ${_relativeAgo(_asString(snapshot["last_formula_time"]))}";
      case HomeTileType.breastfeed:
        return "마지막 ${_relativeAgo(_asString(snapshot["last_breastfeed_time"]))}";
      case HomeTileType.sleep:
        final int? since = _asInt(snapshot["minutes_since_last_sleep"]);
        if (since == null) {
          return "최근 수면 기록 없음";
        }
        return "$since분 전 종료";
      case HomeTileType.diaper:
        return "마지막 ${_relativeAgo(_asString(snapshot["last_diaper_time"]))}";
      case HomeTileType.weaning:
        return "놀이/이유식 입력";
      case HomeTileType.medication:
        return "마지막 ${_relativeAgo(_asString(snapshot["last_medication_time"]))}";
      case HomeTileType.memo:
        final String memo = _asString(snapshot["special_memo"]) ?? "특별 메모 입력";
        return memo.length > 20 ? "${memo.substring(0, 20)}..." : memo;
    }
  }

  List<MapEntry<String, String>> _dashboardTileMetaLines(
    HomeTileType tile,
    Map<String, dynamic> snapshot,
  ) {
    final bool isDay = widget.range == RecordRange.day;
    final bool isWeek = widget.range == RecordRange.week;
    final bool isMonth = widget.range == RecordRange.month;
    final int rangeDayCount =
        (_asInt(snapshot["range_day_count"]) ?? (isDay ? 1 : 7)).clamp(1, 31);

    final int formulaTotal = _asInt(snapshot["formula_total_ml"]) ?? 0;
    final int formulaCount = _asInt(snapshot["formula_count"]) ?? 0;
    final int breastfeedCount = _asInt(snapshot["breastfeed_count"]) ?? 0;
    final int feedingsCount =
        _asInt(snapshot["feedings_count"]) ?? (formulaCount + breastfeedCount);
    final int weaningCount = _asInt(snapshot["weaning_count"]) ?? 0;
    final int diaperPeeCount = _asInt(snapshot["diaper_pee_count"]) ?? 0;
    final int diaperPooCount = _asInt(snapshot["diaper_poo_count"]) ?? 0;
    final int medicationCount = _asInt(snapshot["medication_count"]) ?? 0;
    final int memoCount = _asInt(snapshot["memo_count"]) ?? 0;

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

    final String lastFormulaAgo =
        _relativeAgo(_asString(snapshot["last_formula_time"]));
    final String lastBreastfeedAgo =
        _relativeAgo(_asString(snapshot["last_breastfeed_time"]));
    final String recentSleepAgo =
        _relativeAgo(_asString(snapshot["recent_sleep_time"]));
    final String recentSleepDuration =
        _formatDuration(_asInt(snapshot["recent_sleep_duration_min"]));
    final String lastSleepEndAgo =
        _relativeAgo(_asString(snapshot["last_sleep_end_time"]));
    final int? minutesSinceSleep = _asInt(snapshot["minutes_since_last_sleep"]);
    final String lastDiaperAgo =
        _relativeAgo(_asString(snapshot["last_diaper_time"]));
    final String lastPeeAgo =
        _relativeAgo(_asString(snapshot["last_pee_time"]));
    final String lastPooAgo =
        _relativeAgo(_asString(snapshot["last_poo_time"]));
    final String lastMedicationAgo =
        _relativeAgo(_asString(snapshot["last_medication_time"]));
    final String lastMedicationName =
        _asString(snapshot["last_medication_name"]) ?? "-";
    final String lastWeaningAgo =
        _relativeAgo(_asString(snapshot["last_weaning_time"]));
    final String specialMemo = _asString(snapshot["special_memo"]) ?? "-";
    final String clippedMemo = specialMemo.length > 24
        ? "${specialMemo.substring(0, 24)}..."
        : specialMemo;

    switch (tile) {
      case HomeTileType.formula:
        return <MapEntry<String, String>>[
          if (_hasOpenEventForTile(HomeTileType.formula, snapshot))
            MapEntry<String, String>("진행 중 시작",
                _openStartedAgo(HomeTileType.formula, snapshot) ?? "-"),
          MapEntry<String, String>(
            isDay ? "총 분유량" : "1일 평균 분유량",
            isDay ? "${formulaTotal}ml" : "${_decimal(avgFormulaPerDay)}ml",
          ),
          MapEntry<String, String>(
            isDay ? "분유 횟수" : "1일 평균 분유 횟수",
            isDay ? "$feedingsCount" : _decimal(avgFeedingsPerDay),
          ),
          MapEntry<String, String>(
            "마지막 분유/모유",
            "$lastFormulaAgo / $lastBreastfeedAgo",
          ),
        ];
      case HomeTileType.breastfeed:
        return <MapEntry<String, String>>[
          if (_hasOpenEventForTile(HomeTileType.breastfeed, snapshot))
            MapEntry<String, String>("진행 중 시작",
                _openStartedAgo(HomeTileType.breastfeed, snapshot) ?? "-"),
          MapEntry<String, String>(
            isDay ? "모유 횟수" : "평균 모유 횟수",
            isDay
                ? "$breastfeedCount"
                : _decimal(breastfeedCount / rangeDayCount),
          ),
          MapEntry<String, String>("마지막 모유", lastBreastfeedAgo),
          MapEntry<String, String>("최근 분유", lastFormulaAgo),
        ];
      case HomeTileType.sleep:
        return <MapEntry<String, String>>[
          if (_hasOpenEventForTile(HomeTileType.sleep, snapshot))
            MapEntry<String, String>("진행 중 시작",
                _openStartedAgo(HomeTileType.sleep, snapshot) ?? "-"),
          MapEntry<String, String>(
            isDay ? "최근 잠 지속" : "1일 평균 수면",
            isDay
                ? recentSleepDuration
                : _formatDuration(avgSleepPerDayMin.round()),
          ),
          MapEntry<String, String>(
            isDay ? "최근 잠 시작" : "1일 평균 낮잠",
            isDay ? recentSleepAgo : _formatDuration(avgNapPerDayMin.round()),
          ),
          MapEntry<String, String>(
            isDay ? "마지막 잠 종료/이후" : "1일 평균 밤잠",
            isDay
                ? "$lastSleepEndAgo / ${minutesSinceSleep == null ? "-" : "$minutesSinceSleep분"}"
                : _formatDuration(avgNightPerDayMin.round()),
          ),
        ];
      case HomeTileType.diaper:
        return <MapEntry<String, String>>[
          if (_hasOpenEventForTile(HomeTileType.diaper, snapshot))
            MapEntry<String, String>("진행 중 시작",
                _openStartedAgo(HomeTileType.diaper, snapshot) ?? "-"),
          MapEntry<String, String>(
            isMonth ? "1일 평균 대변 횟수" : (isWeek ? "주 총 대변 횟수" : "마지막 대변"),
            isMonth
                ? _decimal(avgPooPerDay)
                : isWeek
                    ? "$diaperPooCount"
                    : lastPooAgo,
          ),
          MapEntry<String, String>(
            isMonth ? "1일 평균 소변 횟수" : (isWeek ? "주 총 소변 횟수" : "마지막 소변"),
            isMonth
                ? _decimal(avgPeePerDay)
                : isWeek
                    ? "$diaperPeeCount"
                    : lastPeeAgo,
          ),
          MapEntry<String, String>(isDay ? "오늘 소/대 횟수" : "마지막 교체",
              isDay ? "소$diaperPeeCount · 대$diaperPooCount" : lastDiaperAgo),
        ];
      case HomeTileType.weaning:
        return <MapEntry<String, String>>[
          if (_hasOpenEventForTile(HomeTileType.weaning, snapshot))
            MapEntry<String, String>("진행 중 시작",
                _openStartedAgo(HomeTileType.weaning, snapshot) ?? "-"),
          MapEntry<String, String>(isDay ? "오늘 횟수" : "1일 평균 횟수",
              isDay ? "$weaningCount" : _decimal(weaningCount / rangeDayCount)),
          MapEntry<String, String>("마지막 기록", lastWeaningAgo),
          MapEntry<String, String>("최근 메모", clippedMemo),
        ];
      case HomeTileType.medication:
        return <MapEntry<String, String>>[
          if (_hasOpenEventForTile(HomeTileType.medication, snapshot))
            MapEntry<String, String>("진행 중 시작",
                _openStartedAgo(HomeTileType.medication, snapshot) ?? "-"),
          MapEntry<String, String>(
              isDay ? "오늘 횟수" : "1일 평균 횟수",
              isDay
                  ? "$medicationCount"
                  : _decimal(medicationCount / rangeDayCount)),
          MapEntry<String, String>("마지막 투약", lastMedicationAgo),
          MapEntry<String, String>("최근 약명", lastMedicationName),
        ];
      case HomeTileType.memo:
        return <MapEntry<String, String>>[
          MapEntry<String, String>("오늘 메모", "$memoCount"),
          MapEntry<String, String>("최근 메모", clippedMemo),
          const MapEntry<String, String>("입력", "탭해서 추가"),
        ];
    }
  }

  bool _hasOpenEventForTile(HomeTileType tile, Map<String, dynamic> snapshot) {
    final String? key = _openEventIdKey(tile);
    if (key == null) {
      return false;
    }
    return _asString(snapshot[key]) != null;
  }

  String? _openStartedAgo(HomeTileType tile, Map<String, dynamic> snapshot) {
    final String? key = _openStartTimeKey(tile);
    if (key == null) {
      return null;
    }
    final String? startTime = _asString(snapshot[key]);
    if (startTime == null) {
      return null;
    }
    return _relativeAgo(startTime);
  }

  String? _openEventIdKey(HomeTileType tile) {
    switch (tile) {
      case HomeTileType.formula:
        return "open_formula_event_id";
      case HomeTileType.breastfeed:
        return "open_breastfeed_event_id";
      case HomeTileType.sleep:
        return "open_sleep_event_id";
      case HomeTileType.diaper:
        return "open_diaper_event_id";
      case HomeTileType.weaning:
        return "open_weaning_event_id";
      case HomeTileType.medication:
        return "open_medication_event_id";
      case HomeTileType.memo:
        return null;
    }
  }

  String? _openStartTimeKey(HomeTileType tile) {
    switch (tile) {
      case HomeTileType.formula:
        return "open_formula_start_time";
      case HomeTileType.breastfeed:
        return "open_breastfeed_start_time";
      case HomeTileType.sleep:
        return "open_sleep_start_time";
      case HomeTileType.diaper:
        return "open_diaper_start_time";
      case HomeTileType.weaning:
        return "open_weaning_start_time";
      case HomeTileType.medication:
        return "open_medication_start_time";
      case HomeTileType.memo:
        return null;
    }
  }

  String? _openValueKey(HomeTileType tile) {
    switch (tile) {
      case HomeTileType.formula:
        return "open_formula_value";
      case HomeTileType.breastfeed:
        return "open_breastfeed_value";
      case HomeTileType.sleep:
        return "open_sleep_value";
      case HomeTileType.diaper:
        return "open_diaper_value";
      case HomeTileType.weaning:
        return "open_weaning_value";
      case HomeTileType.medication:
        return "open_medication_value";
      case HomeTileType.memo:
        return null;
    }
  }

  Map<String, dynamic>? _openPrefillForTile(
    HomeTileType tile,
    Map<String, dynamic> snapshot,
  ) {
    final String? eventIdKey = _openEventIdKey(tile);
    final String? startKey = _openStartTimeKey(tile);
    final String? valueKey = _openValueKey(tile);
    if (eventIdKey == null || startKey == null || valueKey == null) {
      return null;
    }
    final String? eventId = _asString(snapshot[eventIdKey]);
    final String? startTime = _asString(snapshot[startKey]);
    final Map<String, dynamic> value = _asStringDynamicMap(snapshot[valueKey]);
    if (eventId == null && startTime == null && value.isEmpty) {
      return null;
    }
    final Map<String, dynamic> prefill = <String, dynamic>{
      if (eventId != null) "open_event_id": eventId,
      if (eventId != null) eventIdKey: eventId,
      if (startTime != null) "open_start_time": startTime,
      if (startTime != null) "start_time": startTime,
      if (startTime != null) startKey: startTime,
      if (value.isNotEmpty) "open_value": value,
      if (value.isNotEmpty) valueKey: value,
    };
    if (tile == HomeTileType.diaper) {
      final String? diaperType = _asString(snapshot["open_diaper_type"]);
      if (diaperType != null) {
        prefill["open_diaper_type"] = diaperType;
        prefill["diaper_type"] = diaperType;
      }
    }
    return prefill;
  }

  Map<String, dynamic> _asStringDynamicMap(dynamic value) {
    if (value is! Map) {
      return <String, dynamic>{};
    }
    final Map<String, dynamic> result = <String, dynamic>{};
    value.forEach((dynamic key, dynamic item) {
      final String textKey = key?.toString().trim() ?? "";
      if (textKey.isNotEmpty) {
        result[textKey] = item;
      }
    });
    return result;
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

  String _decimal(double value) {
    if (value.isNaN || value.isInfinite) {
      return "0";
    }
    final double rounded = (value * 10).roundToDouble() / 10;
    if ((rounded - rounded.roundToDouble()).abs() < 0.05) {
      return rounded.round().toString();
    }
    return rounded.toStringAsFixed(1);
  }

  String _formatDuration(int? minutes) {
    if (minutes == null || minutes <= 0) {
      return "-";
    }
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    if (h > 0 && m > 0) {
      return "$h시간 $m분";
    }
    if (h > 0) {
      return "$h시간";
    }
    return "$m분";
  }

  HomeTileType _homeTileForTimerActivity(_TimerActivity activity) {
    switch (activity) {
      case _TimerActivity.sleep:
        return HomeTileType.sleep;
      case _TimerActivity.formula:
        return HomeTileType.formula;
      case _TimerActivity.breastfeed:
        return HomeTileType.breastfeed;
      case _TimerActivity.diaper:
        return HomeTileType.diaper;
    }
  }

  String _eventTypeForTimerActivity(_TimerActivity activity) {
    switch (activity) {
      case _TimerActivity.sleep:
        return "SLEEP";
      case _TimerActivity.formula:
        return "FORMULA";
      case _TimerActivity.breastfeed:
        return "BREASTFEED";
      case _TimerActivity.diaper:
        return "PEE";
    }
  }

  String? _openEventIdForTimerActivity(
    Map<String, dynamic> snapshot,
    _TimerActivity activity,
  ) {
    final String? key = _openEventIdKey(_homeTileForTimerActivity(activity));
    if (key == null) {
      return null;
    }
    return _asString(snapshot[key]);
  }

  RecordEntryInput _buildTimerRecordInput({
    required _TimerActivity activity,
    required DateTime startAt,
    required DateTime endAt,
    String? openEventId,
  }) {
    final int durationSeconds = endAt.difference(startAt).inSeconds;
    final int safeDurationSeconds = durationSeconds < 0 ? 0 : durationSeconds;
    final int safeDurationMinutes = safeDurationSeconds ~/ 60;
    final String normalizedOpenEventId = (openEventId ?? "").trim();
    final bool useOpenLifecycle =
        activity != _TimerActivity.diaper && normalizedOpenEventId.isNotEmpty;
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
          lifecycleAction: useOpenLifecycle
              ? RecordLifecycleAction.completeOpen
              : RecordLifecycleAction.createClosed,
          targetEventId: useOpenLifecycle ? normalizedOpenEventId : null,
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
          lifecycleAction: useOpenLifecycle
              ? RecordLifecycleAction.completeOpen
              : RecordLifecycleAction.createClosed,
          targetEventId: useOpenLifecycle ? normalizedOpenEventId : null,
        );
      case _TimerActivity.breastfeed:
        final String side = _breastfeedSideValue();
        return RecordEntryInput(
          type: "BREASTFEED",
          startTime: startAt,
          endTime: endAt,
          value: <String, dynamic>{
            "duration_min": safeDurationMinutes,
            "duration_sec": safeDurationSeconds,
            "side": side,
          },
          metadata: <String, dynamic>{
            "timer_activity": "BREASTFEED",
            "side": side,
          },
          lifecycleAction: useOpenLifecycle
              ? RecordLifecycleAction.completeOpen
              : RecordLifecycleAction.createClosed,
          targetEventId: useOpenLifecycle ? normalizedOpenEventId : null,
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
    if (input.type == "SLEEP") {
      if (input.lifecycleAction == RecordLifecycleAction.startOnly) {
        await AppSessionStore.setPendingSleepStart(input.startTime.toUtc());
      } else {
        await AppSessionStore.setPendingSleepStart(null);
      }
    }
    if (input.type == "FORMULA") {
      if (input.lifecycleAction == RecordLifecycleAction.startOnly) {
        await AppSessionStore.setPendingFormulaStart(input.startTime.toUtc());
      } else {
        await AppSessionStore.setPendingFormulaStart(null);
      }
    }
  }

  Future<bool> _saveEntryInput(
    RecordEntryInput input, {
    String? successMessage,
    ValueChanged<String?>? onSavedEventId,
  }) async {
    setState(() => _entrySaving = true);
    bool saved = false;
    String? savedEventId;
    try {
      switch (input.lifecycleAction) {
        case RecordLifecycleAction.startOnly:
          final Map<String, dynamic> response =
              await BabyAIApi.instance.startManualEvent(
            type: input.type,
            startTime: input.startTime,
            value: input.value,
            metadata: input.metadata,
          );
          savedEventId = _asString(response["event_id"]);
          break;
        case RecordLifecycleAction.completeOpen:
          final String targetEventId = (input.targetEventId ?? "").trim();
          if (targetEventId.isEmpty) {
            throw ApiFailure("Missing in-progress event id to complete.");
          }
          final Map<String, dynamic> response =
              await BabyAIApi.instance.completeManualEvent(
            eventId: targetEventId,
            endTime: input.endTime,
            value: input.value,
            metadata: input.metadata,
          );
          savedEventId = _asString(response["event_id"]) ?? targetEventId;
          break;
        case RecordLifecycleAction.createClosed:
          final Map<String, dynamic> response =
              await BabyAIApi.instance.createManualEvent(
            type: input.type,
            startTime: input.startTime,
            endTime: input.endTime,
            value: input.value,
            metadata: input.metadata,
          );
          savedEventId = _asString(response["event_id"]);
          break;
      }
      await _persistSleepMarker(input);
      await _loadLandingSnapshot(preferOffline: false);
      if (!mounted) {
        return false;
      }
      saved = true;
      onSavedEventId?.call(savedEventId);
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
    String? openEventId;
    if (selected != _TimerActivity.diaper) {
      setState(() => _entrySaving = true);
      try {
        final Map<String, dynamic> startValue =
            selected == _TimerActivity.breastfeed
                ? <String, dynamic>{"side": _breastfeedSideValue()}
                : <String, dynamic>{};
        final Map<String, dynamic> startMetadata = <String, dynamic>{
          "timer_activity": _eventTypeForTimerActivity(selected),
          if (selected == _TimerActivity.breastfeed)
            "side": _breastfeedSideValue(),
        };
        final Map<String, dynamic> started =
            await BabyAIApi.instance.startManualEvent(
          type: _eventTypeForTimerActivity(selected),
          startTime: startedAt,
          value: startValue,
          metadata: startMetadata,
        );
        final String parsedEventId =
            (started["event_id"] ?? "").toString().trim();
        if (parsedEventId.isNotEmpty) {
          openEventId = parsedEventId;
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString())),
          );
          setState(() => _entrySaving = false);
        }
        return;
      } finally {
        if (mounted) {
          setState(() => _entrySaving = false);
        }
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _activeTimerActivity = selected;
      _activeTimerStartedAt = startedAt;
      _activeTimerEventId = openEventId;
    });
    if (selected == _TimerActivity.sleep) {
      await AppSessionStore.setPendingSleepStart(startedAt.toUtc());
    } else if (selected == _TimerActivity.formula) {
      await AppSessionStore.setPendingFormulaStart(startedAt.toUtc());
    }
    await _loadLandingSnapshot(preferOffline: false);
  }

  Future<int?> _showFormulaMlDialog() async {
    final TextEditingController controller = TextEditingController();
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            tr(context, ko: "분유량 입력", en: "Formula Amount", es: "Cantidad"),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: "ml",
              suffixText: "ml",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(tr(context, ko: "취소", en: "Cancel", es: "Cancelar")),
            ),
            FilledButton(
              onPressed: () {
                final int? value = int.tryParse(controller.text.trim());
                if (value != null && value > 0) {
                  Navigator.of(context).pop(value);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(tr(context,
                          ko: "올바른 숫자를 입력해주세요.",
                          en: "Please enter a valid number.",
                          es: "Por favor ingrese un número válido.")),
                    ),
                  );
                }
              },
              child: Text(tr(context, ko: "저장하기", en: "Save", es: "Guardar")),
            ),
          ],
        );
      },
    );
  }

  Future<void> _stopActiveTimer() async {
    await _stopActiveTimerAt();
  }

  Future<void> _stopActiveTimerAt({
    DateTime? customEndAt,
  }) async {
    if (_entrySaving ||
        _activeTimerStartedAt == null ||
        _activeTimerActivity == null) {
      return;
    }
    final DateTime startAt = _activeTimerStartedAt!;
    final DateTime endAt = customEndAt ?? DateTime.now();
    if (endAt.isBefore(startAt)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                ko: "종료 시각은 시작 시각보다 뒤여야 합니다.",
                en: "End time must be after start time.",
                es: "La hora de fin debe ser posterior al inicio.",
              ),
            ),
          ),
        );
      }
      return;
    }
    final _TimerActivity activity = _activeTimerActivity!;

    int? enteredMl;
    if (activity == _TimerActivity.formula) {
      enteredMl = await _showFormulaMlDialog();
      if (enteredMl == null) {
        return; // user cancelled, do not save timer
      }
    }

    final RecordEntryInput input = _buildTimerRecordInput(
      activity: activity,
      startAt: startAt,
      endAt: endAt,
      openEventId: _activeTimerEventId,
    );

    if (enteredMl != null) {
      input.value["ml"] = enteredMl;
    }
    String? savedEventId;
    final bool saved = await _saveEntryInput(
      input,
      successMessage: tr(
        context,
        ko: "${_timerActivityLabel(activity)} 타이머 기록이 저장되었어요.",
        en: "Timer record saved.",
        es: "Registro de temporizador guardado.",
      ),
      onSavedEventId: (String? eventId) {
        savedEventId = eventId;
      },
    );
    if (!mounted || !saved) {
      return;
    }
    final String normalizedSavedEventId = (savedEventId ?? "").trim();
    final String fallbackOpenEventId = (_activeTimerEventId ?? "").trim();
    setState(() {
      _latestTimerEntry = _CompletedTimerEntry(
        activity: activity,
        startAt: startAt,
        endAt: endAt,
        eventId: normalizedSavedEventId.isNotEmpty
            ? normalizedSavedEventId
            : (fallbackOpenEventId.isNotEmpty ? fallbackOpenEventId : null),
      );
      _activeTimerActivity = null;
      _activeTimerStartedAt = null;
      _activeTimerEventId = null;
    });
  }

  Future<DateTime?> _pickTimerTime(DateTime base) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      helpText: tr(
        context,
        ko: "시간 선택",
        en: "Select time",
        es: "Seleccionar hora",
      ),
    );
    if (picked == null) {
      return null;
    }
    return DateTime(
      base.year,
      base.month,
      base.day,
      picked.hour,
      picked.minute,
    );
  }

  Future<void> _editTimerStartTime() async {
    if (_entrySaving) {
      return;
    }
    final bool timerRunning =
        _activeTimerStartedAt != null && _activeTimerActivity != null;
    if (!timerRunning && _latestTimerEntry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              ko: "수정할 최근 기록이 없습니다.",
              en: "You can edit start time after timer starts.",
              es: "Puedes editar la hora de inicio después de iniciar el temporizador.",
            ),
          ),
        ),
      );
      return;
    }
    if (timerRunning) {
      final String openEventId = (_activeTimerEventId ?? "").trim();
      if (_activeTimerActivity != _TimerActivity.diaper &&
          openEventId.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                ko: "진행 중 항목은 종료 후 시작 시각을 수정해 주세요.",
                en: "Edit start time after stopping the running event.",
                es: "Edita la hora de inicio después de detener el evento.",
              ),
            ),
          ),
        );
        return;
      }
    }
    final DateTime currentStart =
        timerRunning ? _activeTimerStartedAt! : _latestTimerEntry!.startAt;
    final DateTime? picked = await _pickTimerTime(currentStart);
    if (!mounted || picked == null) {
      return;
    }
    if (timerRunning) {
      final DateTime now = DateTime.now();
      if (picked.isAfter(now)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                ko: "시작 시각은 현재 시각보다 늦을 수 없습니다.",
                en: "Start time cannot be in the future.",
                es: "La hora de inicio no puede ser en el futuro.",
              ),
            ),
          ),
        );
        return;
      }
      final _TimerActivity activity = _activeTimerActivity!;
      setState(() => _activeTimerStartedAt = picked);
      if (activity == _TimerActivity.sleep) {
        await AppSessionStore.setPendingSleepStart(picked.toUtc());
      } else if (activity == _TimerActivity.formula) {
        await AppSessionStore.setPendingFormulaStart(picked.toUtc());
      }
      await _loadLandingSnapshot(preferOffline: false);
      return;
    }

    final _CompletedTimerEntry latest = _latestTimerEntry!;
    final String eventId = (latest.eventId ?? "").trim();
    if (eventId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              ko: "방금 종료한 기록만 바로 수정할 수 있어요.",
              en: "Only recently completed events can be edited here.",
              es: "Solo puedes editar aqui eventos completados recientemente.",
            ),
          ),
        ),
      );
      return;
    }
    if (picked.isAfter(latest.endAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              ko: "시작 시각은 종료 시각보다 늦을 수 없습니다.",
              en: "Start time must be before end time.",
              es: "La hora de inicio debe ser anterior a la de fin.",
            ),
          ),
        ),
      );
      return;
    }

    setState(() => _entrySaving = true);
    try {
      await BabyAIApi.instance.updateManualEvent(
        eventId: eventId,
        startTime: picked,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      setState(() => _entrySaving = false);
      return;
    } finally {
      if (mounted) {
        setState(() => _entrySaving = false);
      }
    }
    setState(() {
      _latestTimerEntry = _CompletedTimerEntry(
        activity: latest.activity,
        startAt: picked,
        endAt: latest.endAt,
        eventId: latest.eventId,
      );
    });
    await _loadLandingSnapshot(preferOffline: false);
  }

  Future<void> _editTimerEndTime() async {
    if (_entrySaving) {
      return;
    }
    final bool timerRunning =
        _activeTimerStartedAt != null && _activeTimerActivity != null;
    if (!timerRunning && _latestTimerEntry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              ko: "수정할 최근 기록이 없습니다.",
              en: "You can set end time while timer is running.",
              es: "Puedes establecer la hora de fin mientras el temporizador está activo.",
            ),
          ),
        ),
      );
      return;
    }
    if (timerRunning) {
      final DateTime startAt = _activeTimerStartedAt!;
      final DateTime initial = DateTime.now().isBefore(startAt)
          ? startAt.add(const Duration(minutes: 1))
          : DateTime.now();
      final DateTime? picked = await _pickTimerTime(initial);
      if (!mounted || picked == null) {
        return;
      }
      final DateTime now = DateTime.now();
      if (picked.isAfter(now)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                ko: "종료 시각은 현재 시각보다 늦을 수 없습니다.",
                en: "End time cannot be in the future.",
                es: "La hora de fin no puede ser en el futuro.",
              ),
            ),
          ),
        );
        return;
      }
      if (picked.isBefore(startAt)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                ko: "종료 시각은 시작 시각보다 뒤여야 합니다.",
                en: "End time must be after start time.",
                es: "La hora de fin debe ser posterior al inicio.",
              ),
            ),
          ),
        );
        return;
      }
      await _stopActiveTimerAt(customEndAt: picked);
      return;
    }

    final _CompletedTimerEntry latest = _latestTimerEntry!;
    final String eventId = (latest.eventId ?? "").trim();
    if (eventId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              ko: "방금 종료한 기록만 바로 수정할 수 있어요.",
              en: "Only recently completed events can be edited here.",
              es: "Solo puedes editar aqui eventos completados recientemente.",
            ),
          ),
        ),
      );
      return;
    }
    final DateTime? picked = await _pickTimerTime(latest.endAt);
    if (!mounted || picked == null) {
      return;
    }
    final DateTime now = DateTime.now();
    if (picked.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              ko: "종료 시각은 현재 시각보다 늦을 수 없습니다.",
              en: "End time cannot be in the future.",
              es: "La hora de fin no puede ser en el futuro.",
            ),
          ),
        ),
      );
      return;
    }
    if (picked.isBefore(latest.startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              ko: "종료 시각은 시작 시각보다 뒤여야 합니다.",
              en: "End time must be after start time.",
              es: "La hora de fin debe ser posterior al inicio.",
            ),
          ),
        ),
      );
      return;
    }

    setState(() => _entrySaving = true);
    try {
      await BabyAIApi.instance.updateManualEvent(
        eventId: eventId,
        endTime: picked,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      setState(() => _entrySaving = false);
      return;
    } finally {
      if (mounted) {
        setState(() => _entrySaving = false);
      }
    }
    setState(() {
      _latestTimerEntry = _CompletedTimerEntry(
        activity: latest.activity,
        startAt: latest.startAt,
        endAt: picked,
        eventId: latest.eventId,
      );
    });
    await _loadLandingSnapshot(preferOffline: false);
  }

  Widget _buildTimerInfoItem({
    required ColorScheme color,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: Column(
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
      ),
    );
    if (onTap == null) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
  }

  Widget _buildBreastfeedSideSelector({
    required ColorScheme color,
    required bool enabled,
  }) {
    Widget chip({
      required _BreastfeedSide side,
      required String label,
      required IconData icon,
    }) {
      final bool selected = _breastfeedSide == side;
      return ChoiceChip(
        selected: selected,
        onSelected: enabled
            ? (bool value) {
                if (!value) {
                  return;
                }
                setState(() => _breastfeedSide = side);
              }
            : null,
        label: Text(label),
        avatar: Icon(
          icon,
          size: 15,
          color: selected ? color.onPrimaryContainer : color.onSurfaceVariant,
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected ? color.onPrimaryContainer : color.onSurfaceVariant,
        ),
        selectedColor: color.primary.withValues(alpha: 0.2),
        side: BorderSide(
          color: selected
              ? color.primary.withValues(alpha: 0.55)
              : color.outline.withValues(alpha: 0.3),
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: chip(
            side: _BreastfeedSide.left,
            label: "왼쪽",
            icon: Icons.keyboard_arrow_left_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: chip(
            side: _BreastfeedSide.right,
            label: "오른쪽",
            icon: Icons.keyboard_arrow_right_rounded,
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

  Widget _tileMetaLine(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: <Widget>[
          Flexible(
            flex: 6,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color.onSurfaceVariant,
                fontSize: 11.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 4,
            child: Text(
              value,
              maxLines: 1,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _specialMemoPanel(BuildContext context, String memoText) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Material(
      color: color.surface,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: color.outlineVariant.withValues(alpha: 0.4),
          ),
          gradient: LinearGradient(
            colors: <Color>[
              color.surface,
              color.surfaceContainerHighest.withValues(alpha: 0.22),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              tr(
                context,
                ko: "특별 메모",
                en: "Special memo",
                es: "Nota especial",
              ),
              style: TextStyle(
                color: color.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              memoText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
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
    final int tileColumns = controller.homeTileColumns.clamp(1, 3);
    final int maxMetaLines = tileColumns == 3 ? 3 : 4;
    const double sectionSpacing = 14;
    final bool showSpecialMemo = controller.showSpecialMemo;
    final String specialMemoText = _asString(snapshot["special_memo"]) ??
        tr(
          context,
          ko: "기록된 특별 메모가 없습니다.",
          en: "No special memo recorded.",
          es: "No hay nota especial registrada.",
        );

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
        ? ""
        : (_latestTimerEntry == null
            ? ""
            : "최근 완료 ${_formatAmPm(_latestTimerEntry!.endAt)}");

    return RefreshIndicator(
      onRefresh: _loadLandingSnapshot,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
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
          const SizedBox(height: sectionSpacing),
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
                          if (activitySubtitle.isNotEmpty) ...<Widget>[
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _TimerActivity.values
                        .where((_TimerActivity a) => a != _TimerActivity.diaper)
                        .map((_TimerActivity activity) {
                      final bool selected = _selectedTimerActivity == activity;
                      final Color accent = _timerActivityAccent(activity);
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          selected: selected,
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          label: Text(_timerActivityLabel(activity)),
                          avatar: AppSvgIcon(
                            _timerActivityAsset(activity),
                            size: 14,
                            color: selected
                                ? color.onPrimaryContainer
                                : color.onSurfaceVariant,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12,
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
                                  setState(
                                    () => _selectedTimerActivity = activity,
                                  );
                                },
                        ),
                      );
                    }).toList(growable: false),
                  ),
                ),
                if (cardActivity == _TimerActivity.breastfeed) ...<Widget>[
                  const SizedBox(height: 10),
                  _buildBreastfeedSideSelector(
                    color: color,
                    enabled: !_entrySaving && !timerRunning,
                  ),
                ],
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
                          onTap: _editTimerStartTime,
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
                          onTap: _editTimerEndTime,
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
          const SizedBox(height: sectionSpacing),
          if (showSpecialMemo) ...<Widget>[
            _specialMemoPanel(context, specialMemoText),
            const SizedBox(height: sectionSpacing),
          ],
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tiles.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: tileColumns,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio:
                  tileColumns == 1 ? 2.35 : (tileColumns == 2 ? 0.9 : 0.68),
            ),
            itemBuilder: (BuildContext context, int index) {
              final HomeTileType tile = tiles[index];
              final Color accent = _dashboardTileAccent(tile);
              final String headline = _dashboardTileHeadline(tile, snapshot);
              final String subtitle = _dashboardTileSubtitle(tile, snapshot);
              final Map<String, dynamic>? openPrefill =
                  _openPrefillForTile(tile, snapshot);
              final List<MapEntry<String, String>> metaLines =
                  _dashboardTileMetaLines(tile, snapshot)
                      .take(maxMetaLines)
                      .toList(growable: false);
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(34),
                child: InkWell(
                  borderRadius: BorderRadius.circular(34),
                  onTap: _entrySaving
                      ? null
                      : () => _openQuickEntry(tile, prefill: openPrefill),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: AppSvgIcon(
                                  _dashboardTileAsset(tile),
                                  color: accent,
                                  size: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    _dashboardTileLabel(tile),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    headline,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (metaLines.isNotEmpty)
                          ...metaLines.map(
                            (MapEntry<String, String> line) => _tileMetaLine(
                              context,
                              label: line.key,
                              value: line.value,
                            ),
                          )
                        else
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
