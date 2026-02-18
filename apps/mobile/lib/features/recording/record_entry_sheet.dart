import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";

import "../../core/i18n/app_i18n.dart";
import "../../core/theme/app_theme_controller.dart";

class RecordEntryInput {
  const RecordEntryInput({
    required this.type,
    required this.startTime,
    required this.value,
    this.endTime,
    this.metadata,
    this.lifecycleAction = RecordLifecycleAction.createClosed,
    this.targetEventId,
  });

  final String type;
  final DateTime startTime;
  final DateTime? endTime;
  final Map<String, dynamic> value;
  final Map<String, dynamic>? metadata;
  final RecordLifecycleAction lifecycleAction;
  final String? targetEventId;
}

enum RecordLifecycleAction { createClosed, startOnly, completeOpen }

Future<RecordEntryInput?> showRecordEntrySheet({
  required BuildContext context,
  required HomeTileType tile,
  Map<String, dynamic>? prefill,
  bool lockClosedLifecycle = false,
}) {
  return showModalBottomSheet<RecordEntryInput>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) {
      return RecordEntrySheet(
        tile: tile,
        prefill: prefill,
        lockClosedLifecycle: lockClosedLifecycle,
      );
    },
  );
}

class RecordEntrySheet extends StatefulWidget {
  const RecordEntrySheet({
    super.key,
    required this.tile,
    this.prefill,
    this.lockClosedLifecycle = false,
  });

  final HomeTileType tile;
  final Map<String, dynamic>? prefill;
  final bool lockClosedLifecycle;

  @override
  State<RecordEntrySheet> createState() => _RecordEntrySheetState();
}

enum _TimeField { start, end }

class _RecordEntrySheetState extends State<RecordEntrySheet> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _doseController = TextEditingController();
  final TextEditingController _gramsController = TextEditingController();

  DateTime _startTime = DateTime.now();
  late DateTime _endTime;
  String _diaperType = "PEE";
  String _weaningType = "meal";
  _TimeField _activeTimeField = _TimeField.start;
  bool _startOnlyMode = false;
  String? _openEventId;
  String? _error;

  String _tileOpenEventKey() {
    switch (widget.tile) {
      case HomeTileType.formula:
        return "open_formula_event_id";
      case HomeTileType.breastfeed:
        return "open_breastfeed_event_id";
      case HomeTileType.weaning:
        return "open_weaning_event_id";
      case HomeTileType.diaper:
        return "open_diaper_event_id";
      case HomeTileType.sleep:
        return "open_sleep_event_id";
      case HomeTileType.medication:
        return "open_medication_event_id";
      case HomeTileType.memo:
        return "open_memo_event_id";
    }
  }

  String _tileOpenStartKey() {
    switch (widget.tile) {
      case HomeTileType.formula:
        return "open_formula_start_time";
      case HomeTileType.breastfeed:
        return "open_breastfeed_start_time";
      case HomeTileType.weaning:
        return "open_weaning_start_time";
      case HomeTileType.diaper:
        return "open_diaper_start_time";
      case HomeTileType.sleep:
        return "open_sleep_start_time";
      case HomeTileType.medication:
        return "open_medication_start_time";
      case HomeTileType.memo:
        return "open_memo_start_time";
    }
  }

  String _tileOpenValueKey() {
    switch (widget.tile) {
      case HomeTileType.formula:
        return "open_formula_value";
      case HomeTileType.breastfeed:
        return "open_breastfeed_value";
      case HomeTileType.weaning:
        return "open_weaning_value";
      case HomeTileType.diaper:
        return "open_diaper_value";
      case HomeTileType.sleep:
        return "open_sleep_value";
      case HomeTileType.medication:
        return "open_medication_value";
      case HomeTileType.memo:
        return "open_memo_value";
    }
  }

  RecordLifecycleAction _resolveLifecycleAction() {
    if (widget.lockClosedLifecycle) {
      return RecordLifecycleAction.createClosed;
    }
    if (_hasOpenEvent) {
      return RecordLifecycleAction.completeOpen;
    }
    if (_isStartableTile && _startOnlyMode) {
      return RecordLifecycleAction.startOnly;
    }
    return RecordLifecycleAction.createClosed;
  }

  @override
  void initState() {
    super.initState();
    _endTime = _startTime.add(const Duration(hours: 1));
    _applyPrefill();
  }

  void _applyPrefill() {
    final Map<String, dynamic>? prefill = widget.prefill;
    if (prefill == null || prefill.isEmpty) {
      return;
    }

    final Object? amountMl = prefill["amount_ml"];
    final Object? durationMin = prefill["duration_min"];
    final Object? grams = prefill["grams"];
    final Object? memo = prefill["memo"];
    final Object? query = prefill["query"];
    final Object? diaperType = prefill["diaper_type"];
    final Object? weaningType = prefill["weaning_type"];
    final Object? sleepAction = prefill["sleep_action"];

    final String openEventId =
        (prefill["open_event_id"] ?? prefill[_tileOpenEventKey()] ?? "")
            .toString()
            .trim();
    if (openEventId.isNotEmpty) {
      _openEventId = openEventId;
      _startOnlyMode = false;
    }

    final DateTime? prefilledStart =
        _parseDateTimeFromRaw(prefill["start_time"]) ??
            _parseDateTimeFromRaw(prefill["sleep_start_time"]) ??
            _parseDateTimeFromRaw(prefill["open_start_time"]) ??
            _parseDateTimeFromRaw(prefill[_tileOpenStartKey()]) ??
            _parseDateTimeFromRaw(prefill["open_formula_start_time"]) ??
            _parseDateTimeFromRaw(prefill["open_sleep_start_time"]);
    final DateTime? prefilledEnd = _parseDateTimeFromRaw(prefill["end_time"]) ??
        _parseDateTimeFromRaw(prefill["sleep_end_time"]);
    final Map<String, dynamic> tileOpenValue =
        _asStringDynamicMap(prefill[_tileOpenValueKey()]);
    final Map<String, dynamic> openValue = tileOpenValue.isNotEmpty
        ? tileOpenValue
        : _asStringDynamicMap(prefill["open_value"]);

    if (prefilledStart != null) {
      _startTime = prefilledStart;
    }
    if (prefilledEnd != null) {
      _endTime = prefilledEnd;
    } else if (_hasOpenEvent) {
      _endTime = DateTime.now();
    }

    final Object? mergedAmount =
        amountMl ?? openValue["ml"] ?? openValue["amount_ml"];
    if (mergedAmount is int && mergedAmount > 0) {
      _amountController.text = mergedAmount.toString();
    } else if (mergedAmount is double && mergedAmount > 0) {
      _amountController.text = mergedAmount.round().toString();
    } else if (mergedAmount is String && mergedAmount.trim().isNotEmpty) {
      _amountController.text = mergedAmount.trim();
    }

    final Object? mergedDuration = durationMin ??
        openValue["duration_min"] ??
        openValue["duration_minutes"];
    if (mergedDuration is int && mergedDuration > 0) {
      _durationController.text = mergedDuration.toString();
      if (prefilledEnd == null && !_hasOpenEvent) {
        _endTime = _startTime.add(Duration(minutes: mergedDuration));
      }
    } else if (mergedDuration is String && mergedDuration.trim().isNotEmpty) {
      _durationController.text = mergedDuration.trim();
      final int? parsed = int.tryParse(mergedDuration.trim());
      if (parsed != null &&
          parsed > 0 &&
          prefilledEnd == null &&
          !_hasOpenEvent) {
        _endTime = _startTime.add(Duration(minutes: parsed));
      }
    }

    if (grams is int && grams > 0) {
      _gramsController.text = grams.toString();
    } else if (grams is String && grams.trim().isNotEmpty) {
      _gramsController.text = grams.trim();
    }

    final Object? mergedMemo = memo ?? openValue["memo"] ?? openValue["note"];
    if (mergedMemo is String && mergedMemo.trim().isNotEmpty) {
      _memoController.text = mergedMemo.trim();
    } else if (query is String && query.trim().isNotEmpty) {
      _memoController.text = query.trim();
    }

    if (query is String &&
        query.trim().isNotEmpty &&
        _nameController.text.isEmpty) {
      _nameController.text = query.trim();
    }

    final Object? medicationName = prefill["medication_name"] ??
        openValue["name"] ??
        openValue["medication_type"];
    if (medicationName is String &&
        medicationName.trim().isNotEmpty &&
        _nameController.text.isEmpty) {
      _nameController.text = medicationName.trim();
    }
    final Object? medicationDose = prefill["dose"] ?? openValue["dose"];
    if (medicationDose is int && medicationDose > 0) {
      _doseController.text = medicationDose.toString();
    } else if (medicationDose is String && medicationDose.trim().isNotEmpty) {
      _doseController.text = medicationDose.trim();
    }

    final Object? mergedDiaperType =
        diaperType ?? prefill["open_diaper_type"] ?? openValue["diaper_type"];
    if (mergedDiaperType is String && mergedDiaperType.trim().isNotEmpty) {
      final String normalized = mergedDiaperType.trim().toUpperCase();
      if (normalized == "PEE" || normalized == "POO") {
        _diaperType = normalized;
      }
    } else if (widget.tile == HomeTileType.diaper && _hasOpenEvent) {
      final String normalized =
          (prefill["type"] ?? "").toString().trim().toUpperCase();
      if (normalized == "PEE" || normalized == "POO") {
        _diaperType = normalized;
      }
    }

    if (diaperType is String && diaperType.trim().isNotEmpty) {
      final String normalized = diaperType.trim().toUpperCase();
      if (normalized == "PEE" || normalized == "POO") {
        _diaperType = normalized;
      }
    }

    if (weaningType is String && weaningType.trim().isNotEmpty) {
      final String normalized = weaningType.trim().toLowerCase();
      if (const <String>{"meal", "snack", "fruit", "soup"}
          .contains(normalized)) {
        _weaningType = normalized;
      }
    } else {
      final String normalized =
          (openValue["weaning_type"] ?? "").toString().trim().toLowerCase();
      if (const <String>{"meal", "snack", "fruit", "soup"}
          .contains(normalized)) {
        _weaningType = normalized;
      }
    }

    if (sleepAction is String && sleepAction.trim().isNotEmpty) {
      final String action = sleepAction.trim().toLowerCase();
      if (action == "end" && prefilledEnd == null) {
        _endTime = DateTime.now();
      }
      if (action == "start" && prefilledEnd == null && !_hasOpenEvent) {
        _endTime = _startTime.add(const Duration(minutes: 30));
      }
    }

    if (!_endTime.isAfter(_startTime)) {
      _endTime = _startTime.add(const Duration(minutes: 30));
    }
  }

  bool get _isStartableTile {
    switch (widget.tile) {
      case HomeTileType.formula:
      case HomeTileType.breastfeed:
      case HomeTileType.weaning:
      case HomeTileType.diaper:
      case HomeTileType.sleep:
      case HomeTileType.medication:
        return true;
      case HomeTileType.memo:
        return false;
    }
  }

  bool get _hasOpenEvent => _openEventId != null && _openEventId!.isNotEmpty;

  bool get _shouldCollectEndTime {
    if (widget.lockClosedLifecycle) {
      return true;
    }
    if (!_isStartableTile) {
      return false;
    }
    return _hasOpenEvent || !_startOnlyMode;
  }

  Widget _lifecycleModeSelector() {
    if (widget.lockClosedLifecycle || !_isStartableTile || _hasOpenEvent) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      children: <Widget>[
        ChoiceChip(
          label: Text(
            tr(context, ko: "시작만 저장", en: "Start only", es: "Solo inicio"),
          ),
          selected: _startOnlyMode,
          onSelected: (_) => setState(() => _startOnlyMode = true),
        ),
        ChoiceChip(
          label: Text(
            tr(context, ko: "시작+종료 저장", en: "Start + end", es: "Inicio + fin"),
          ),
          selected: !_startOnlyMode,
          onSelected: (_) => setState(() => _startOnlyMode = false),
        ),
      ],
    );
  }

  Widget _openEventBanner() {
    if (!_hasOpenEvent) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              const Icon(Icons.timelapse_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(
                    context,
                    ko: "진행 중 기록이 있어 완료 입력으로 저장됩니다.",
                    en: "An in-progress record was found. Save will complete it.",
                    es: "Se encontro un registro en progreso. Guardar lo completa.",
                  ),
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _durationController.dispose();
    _memoController.dispose();
    _nameController.dispose();
    _doseController.dispose();
    _gramsController.dispose();
    super.dispose();
  }

  String _tileLabel(BuildContext context) {
    switch (widget.tile) {
      case HomeTileType.formula:
        return tr(context, ko: "분유", en: "Formula", es: "Formula");
      case HomeTileType.breastfeed:
        return tr(context, ko: "모유", en: "Breastfeed", es: "Lactancia");
      case HomeTileType.weaning:
        return tr(context, ko: "이유식", en: "Weaning", es: "Destete");
      case HomeTileType.diaper:
        return tr(context, ko: "기저귀", en: "Diaper", es: "Panal");
      case HomeTileType.sleep:
        return tr(context, ko: "수면", en: "Sleep", es: "Sueno");
      case HomeTileType.medication:
        return tr(context, ko: "투약", en: "Medication", es: "Medicacion");
      case HomeTileType.memo:
        return tr(context, ko: "메모", en: "Memo", es: "Memo");
    }
  }

  String _timeLabel(DateTime value) {
    final String year = value.year.toString();
    final String month = value.month.toString().padLeft(2, "0");
    final String day = value.day.toString().padLeft(2, "0");
    final String hour = value.hour.toString().padLeft(2, "0");
    final String minute = value.minute.toString().padLeft(2, "0");
    return "$year-$month-$day $hour:$minute";
  }

  DateTime? _parseDateTimeFromRaw(Object? raw) {
    if (raw == null) {
      return null;
    }
    final String text = raw.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(text).toLocal();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _asStringDynamicMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map(
        (dynamic key, dynamic value) => MapEntry<String, dynamic>(
          key.toString(),
          value,
        ),
      );
    }
    return const <String, dynamic>{};
  }

  int _sleepDurationMinutes() {
    final int minutes = _endTime.difference(_startTime).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  String _sleepDurationLabel() {
    final int minutes = _sleepDurationMinutes();
    final int hours = minutes ~/ 60;
    final int mins = minutes % 60;
    if (hours <= 0) {
      return "${mins}m";
    }
    return "${hours}h ${mins}m";
  }

  void _onInlineDateTimeChanged(DateTime value, {required bool includeEnd}) {
    final _TimeField target = includeEnd ? _activeTimeField : _TimeField.start;
    setState(() {
      if (target == _TimeField.start) {
        _startTime = value;
        if (includeEnd && !_endTime.isAfter(_startTime)) {
          _endTime = _startTime.add(const Duration(minutes: 30));
        }
      } else {
        _endTime = value;
        if (!_endTime.isAfter(_startTime)) {
          _endTime = _startTime.add(const Duration(minutes: 1));
        }
      }
    });
  }

  Widget _timeChip({
    required String label,
    required DateTime value,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: selected
            ? color.primaryContainer.withValues(alpha: 0.95)
            : color.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(
                  _timeLabel(value),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inlineTimeEditor({required bool includeEnd}) {
    final _TimeField selectedField =
        includeEnd ? _activeTimeField : _TimeField.start;
    final DateTime initialValue =
        selectedField == _TimeField.start ? _startTime : _endTime;

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            _timeChip(
              label: tr(
                context,
                ko: "시작 시간",
                en: "Start time",
                es: "Hora de inicio",
              ),
              value: _startTime,
              selected: selectedField == _TimeField.start,
              onTap: () => setState(() => _activeTimeField = _TimeField.start),
            ),
            if (includeEnd) ...<Widget>[
              const SizedBox(width: 8),
              _timeChip(
                label: tr(
                  context,
                  ko: "종료 시간",
                  en: "End time",
                  es: "Hora de fin",
                ),
                value: _endTime,
                selected: selectedField == _TimeField.end,
                onTap: () => setState(() => _activeTimeField = _TimeField.end),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 172,
          child: CupertinoDatePicker(
            key: ValueKey<String>("picker_${selectedField.name}"),
            mode: CupertinoDatePickerMode.dateAndTime,
            use24hFormat: true,
            initialDateTime: initialValue,
            onDateTimeChanged: (DateTime value) =>
                _onInlineDateTimeChanged(value, includeEnd: includeEnd),
          ),
        ),
      ],
    );
  }

  int? _parsePositiveInt(TextEditingController controller) {
    final String raw = controller.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    return int.tryParse(raw);
  }

  InputDecoration _dropdownDecoration(String label) {
    final ColorScheme color = Theme.of(context).colorScheme;
    final BorderRadius borderRadius = BorderRadius.circular(14);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: color.surfaceContainerHighest.withValues(alpha: 0.24),
      border: OutlineInputBorder(borderRadius: borderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: color.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: color.primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  void _submit() {
    final DateTime start = _startTime;

    switch (widget.tile) {
      case HomeTileType.formula:
        final int? amount = _parsePositiveInt(_amountController);
        final String memo = _memoController.text.trim();
        if (_shouldCollectEndTime && !_endTime.isAfter(start)) {
          setState(() {
            _error = tr(
              context,
              ko: "종료 시각은 시작 시각보다 뒤여야 합니다.",
              en: "End time must be after start time.",
              es: "La hora de fin debe ser posterior al inicio.",
            );
          });
          return;
        }
        final Map<String, dynamic> value = <String, dynamic>{
          if (amount != null && amount > 0) "ml": amount,
          if (_shouldCollectEndTime) "duration_min": _sleepDurationMinutes(),
          if (memo.isNotEmpty) "memo": memo,
        };
        final RecordLifecycleAction action = _resolveLifecycleAction();
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "FORMULA",
            startTime: start,
            endTime: _shouldCollectEndTime ? _endTime : null,
            value: value,
            lifecycleAction: action,
            targetEventId: _hasOpenEvent ? _openEventId : null,
          ),
        );
        return;
      case HomeTileType.breastfeed:
        final String memo = _memoController.text.trim();
        if (_shouldCollectEndTime && !_endTime.isAfter(start)) {
          setState(() {
            _error = tr(
              context,
              ko: "종료 시각은 시작 시각보다 뒤여야 합니다.",
              en: "End time must be after start time.",
              es: "La hora de fin debe ser posterior al inicio.",
            );
          });
          return;
        }
        final int duration = _shouldCollectEndTime
            ? _sleepDurationMinutes()
            : (_parsePositiveInt(_durationController) ?? 0);
        final RecordLifecycleAction action = _resolveLifecycleAction();
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "BREASTFEED",
            startTime: start,
            endTime: _shouldCollectEndTime ? _endTime : null,
            value: <String, dynamic>{
              if (duration > 0) "duration_min": duration,
              if (memo.isNotEmpty) "memo": memo,
            },
            lifecycleAction: action,
            targetEventId: _hasOpenEvent ? _openEventId : null,
          ),
        );
        return;
      case HomeTileType.weaning:
        final int grams = _parsePositiveInt(_gramsController) ?? 0;
        final String memo = _memoController.text.trim();
        if (_shouldCollectEndTime && !_endTime.isAfter(start)) {
          setState(() {
            _error = tr(
              context,
              ko: "종료 시각은 시작 시각보다 뒤여야 합니다.",
              en: "End time must be after start time.",
              es: "La hora de fin debe ser posterior al inicio.",
            );
          });
          return;
        }
        final RecordLifecycleAction action = _resolveLifecycleAction();
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "MEMO",
            startTime: start,
            endTime: _shouldCollectEndTime ? _endTime : null,
            value: <String, dynamic>{
              "memo": memo.isEmpty
                  ? "이유식(${_weaningTypeLabel(_weaningType)})"
                  : memo,
              if (grams > 0) "grams": grams,
              "category": "WEANING",
              "weaning_type": _weaningType,
              if (_shouldCollectEndTime)
                "duration_min": _sleepDurationMinutes(),
            },
            metadata: <String, dynamic>{
              "entry_kind": "WEANING",
              "weaning_type": _weaningType,
            },
            lifecycleAction: action,
            targetEventId: _hasOpenEvent ? _openEventId : null,
          ),
        );
        return;
      case HomeTileType.diaper:
        final String memo = _memoController.text.trim();
        if (_shouldCollectEndTime && !_endTime.isAfter(start)) {
          setState(() {
            _error = tr(
              context,
              ko: "종료 시각은 시작 시각보다 뒤여야 합니다.",
              en: "End time must be after start time.",
              es: "La hora de fin debe ser posterior al inicio.",
            );
          });
          return;
        }
        final RecordLifecycleAction action = _resolveLifecycleAction();
        Navigator.of(context).pop(
          RecordEntryInput(
            type: _diaperType,
            startTime: start,
            endTime: _shouldCollectEndTime ? _endTime : null,
            value: <String, dynamic>{
              "count": 1,
              "diaper_type": _diaperType,
              if (memo.isNotEmpty) "memo": memo,
              if (_shouldCollectEndTime)
                "duration_min": _sleepDurationMinutes(),
            },
            lifecycleAction: action,
            targetEventId: _hasOpenEvent ? _openEventId : null,
          ),
        );
        return;
      case HomeTileType.sleep:
        final String memo = _memoController.text.trim();
        if (_shouldCollectEndTime && !_endTime.isAfter(start)) {
          setState(() {
            _error = tr(
              context,
              ko: "수면 종료 시각은 시작 시각보다 뒤여야 합니다.",
              en: "Sleep end time must be after start time.",
              es: "La hora de fin debe ser posterior al inicio.",
            );
          });
          return;
        }
        final int duration =
            _shouldCollectEndTime ? _sleepDurationMinutes() : 0;
        final RecordLifecycleAction action = _resolveLifecycleAction();
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "SLEEP",
            startTime: start,
            endTime: _shouldCollectEndTime ? _endTime : null,
            value: <String, dynamic>{
              "duration_min": duration,
              "sleep_action": _shouldCollectEndTime ? "END" : "START",
              if (memo.isNotEmpty) "memo": memo,
            },
            lifecycleAction: action,
            targetEventId: _hasOpenEvent ? _openEventId : null,
          ),
        );
        return;
      case HomeTileType.medication:
        final String memo = _memoController.text.trim();
        final String medicationType = _nameController.text.trim();
        if (_shouldCollectEndTime && !_endTime.isAfter(start)) {
          setState(() {
            _error = tr(
              context,
              ko: "종료 시각은 시작 시각보다 뒤여야 합니다.",
              en: "End time must be after start time.",
              es: "La hora de fin debe ser posterior al inicio.",
            );
          });
          return;
        }
        final RecordLifecycleAction action = _resolveLifecycleAction();
        if (medicationType.isEmpty &&
            action != RecordLifecycleAction.startOnly) {
          setState(() {
            _error = tr(
              context,
              ko: "투약 종류를 입력해 주세요.",
              en: "Enter medication type.",
              es: "Ingrese tipo de medicacion.",
            );
          });
          return;
        }
        final int? dose = _parsePositiveInt(_doseController);
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "MEDICATION",
            startTime: start,
            endTime: _shouldCollectEndTime ? _endTime : null,
            value: <String, dynamic>{
              if (medicationType.isNotEmpty) "name": medicationType,
              if (medicationType.isNotEmpty) "medication_type": medicationType,
              if (dose != null && dose > 0) "dose": dose,
              if (memo.isNotEmpty) "memo": memo,
              if (_shouldCollectEndTime)
                "duration_min": _sleepDurationMinutes(),
            },
            lifecycleAction: action,
            targetEventId: _hasOpenEvent ? _openEventId : null,
          ),
        );
        return;
      case HomeTileType.memo:
        final String memo = _memoController.text.trim();
        if (memo.isEmpty) {
          setState(() {
            _error = tr(
              context,
              ko: "메모를 입력해 주세요.",
              en: "Enter memo text.",
              es: "Ingrese texto de memo.",
            );
          });
          return;
        }
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "MEMO",
            startTime: start,
            value: <String, dynamic>{"memo": memo},
          ),
        );
        return;
    }
  }

  String _weaningTypeLabel(String value) {
    switch (value) {
      case "snack":
        return tr(context, ko: "간식", en: "Snack", es: "Snack");
      case "fruit":
        return tr(context, ko: "과일", en: "Fruit", es: "Fruta");
      case "soup":
        return tr(context, ko: "국/죽", en: "Soup", es: "Sopa");
      default:
        return tr(context, ko: "식사", en: "Meal", es: "Comida");
    }
  }

  Widget _buildBody() {
    switch (widget.tile) {
      case HomeTileType.formula:
        return Column(
          children: <Widget>[
            _openEventBanner(),
            _lifecycleModeSelector(),
            if (_isStartableTile && !_hasOpenEvent) const SizedBox(height: 8),
            _inlineTimeEditor(includeEnd: _shouldCollectEndTime),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "분유량 (ml)",
                  en: "Amount (ml)",
                  es: "Cantidad (ml)",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "특별 메모 (선택)",
                  en: "Special memo (optional)",
                  es: "Nota especial (opcional)",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        );
      case HomeTileType.breastfeed:
        return Column(
          children: <Widget>[
            _openEventBanner(),
            _lifecycleModeSelector(),
            if (_isStartableTile && !_hasOpenEvent) const SizedBox(height: 8),
            _inlineTimeEditor(includeEnd: _shouldCollectEndTime),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "수유시간",
                  en: "Feeding duration",
                  es: "Duracion de lactancia",
                ),
                border: const OutlineInputBorder(),
              ),
              child: Text(
                _shouldCollectEndTime
                    ? _sleepDurationLabel()
                    : tr(
                        context,
                        ko: "시작만 저장 모드",
                        en: "Start-only mode",
                        es: "Modo solo inicio",
                      ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "수유 시간(분, 선택)",
                  en: "Duration (min, optional)",
                  es: "Duracion (min, opcional)",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "특별 메모 (선택)",
                  en: "Special memo (optional)",
                  es: "Nota especial (opcional)",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        );
      case HomeTileType.weaning:
        return Column(
          children: <Widget>[
            _openEventBanner(),
            _lifecycleModeSelector(),
            if (_isStartableTile && !_hasOpenEvent) const SizedBox(height: 8),
            _inlineTimeEditor(includeEnd: _shouldCollectEndTime),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _weaningType,
              isExpanded: true,
              borderRadius: BorderRadius.circular(14),
              icon: const Icon(Icons.expand_more_rounded, size: 20),
              decoration: _dropdownDecoration(
                tr(
                  context,
                  ko: "이유식 종류",
                  en: "Weaning type",
                  es: "Tipo de destete",
                ),
              ),
              items: const <String>["meal", "snack", "fruit", "soup"]
                  .map(
                    (String value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(_weaningTypeLabel(value)),
                    ),
                  )
                  .toList(),
              onChanged: (String? value) {
                if (value != null && value.isNotEmpty) {
                  setState(() => _weaningType = value);
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "특별 메모 (선택)",
                  en: "Special memo (optional)",
                  es: "Nota especial (opcional)",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _gramsController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "섭취량 (g, 선택)",
                  en: "Amount (g, optional)",
                  es: "Cantidad (g, opcional)",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        );
      case HomeTileType.diaper:
        return Column(
          children: <Widget>[
            _openEventBanner(),
            _lifecycleModeSelector(),
            if (_isStartableTile && !_hasOpenEvent) const SizedBox(height: 8),
            _inlineTimeEditor(includeEnd: _shouldCollectEndTime),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _diaperType,
              isExpanded: true,
              menuMaxHeight: 280,
              borderRadius: BorderRadius.circular(14),
              icon: const Icon(Icons.expand_more_rounded, size: 20),
              decoration: _dropdownDecoration(
                tr(
                  context,
                  ko: "기저귀 종류",
                  en: "Diaper type",
                  es: "Tipo de panal",
                ),
              ),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: "PEE",
                  child: Text(tr(context, ko: "소변", en: "Pee", es: "Orina")),
                ),
                DropdownMenuItem<String>(
                  value: "POO",
                  child: Text(tr(context, ko: "대변", en: "Poo", es: "Heces")),
                ),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() => _diaperType = value);
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "특별 메모 (선택)",
                  en: "Special memo (optional)",
                  es: "Nota especial (opcional)",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        );
      case HomeTileType.sleep:
        return Column(
          children: <Widget>[
            _openEventBanner(),
            _lifecycleModeSelector(),
            if (_isStartableTile && !_hasOpenEvent) const SizedBox(height: 8),
            _inlineTimeEditor(includeEnd: _shouldCollectEndTime),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "자동 계산 수면시간",
                  en: "Auto-calculated duration",
                  es: "Duracion calculada automaticamente",
                ),
                border: const OutlineInputBorder(),
              ),
              child: Text(
                _shouldCollectEndTime
                    ? _sleepDurationLabel()
                    : tr(
                        context,
                        ko: "시작만 저장 모드",
                        en: "Start-only mode",
                        es: "Modo solo inicio",
                      ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "특별 메모 (선택)",
                  en: "Special memo (optional)",
                  es: "Nota especial (opcional)",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        );
      case HomeTileType.medication:
        return Column(
          children: <Widget>[
            _openEventBanner(),
            _lifecycleModeSelector(),
            if (_isStartableTile && !_hasOpenEvent) const SizedBox(height: 8),
            _inlineTimeEditor(includeEnd: _shouldCollectEndTime),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "투약 종류",
                  en: "Medication type",
                  es: "Tipo de medicacion",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _doseController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "용량 (선택)",
                  en: "Dose (optional)",
                  es: "Dosis (opcional)",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "특별 메모 (선택)",
                  en: "Special memo (optional)",
                  es: "Nota especial (opcional)",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        );
      case HomeTileType.memo:
        return Column(
          children: <Widget>[
            _inlineTimeEditor(includeEnd: false),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "메모 내용",
                  en: "Memo",
                  es: "Memo",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottomInset + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              "${_tileLabel(context)} ${tr(context, ko: "기록", en: "Entry", es: "Registro")}",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _buildBody(),
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
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                        tr(context, ko: "취소", en: "Cancel", es: "Cancelar")),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: Icon(
                      _hasOpenEvent
                          ? Icons.task_alt_rounded
                          : (_isStartableTile && _startOnlyMode
                              ? Icons.play_circle_outline_rounded
                              : Icons.check_circle_outline),
                    ),
                    label: Text(
                      _hasOpenEvent
                          ? tr(
                              context,
                              ko: "완료 저장",
                              en: "Complete",
                              es: "Completar",
                            )
                          : (_isStartableTile && _startOnlyMode)
                              ? tr(
                                  context,
                                  ko: "시작 저장",
                                  en: "Save start",
                                  es: "Guardar inicio",
                                )
                              : tr(
                                  context,
                                  ko: "저장",
                                  en: "Save",
                                  es: "Guardar",
                                ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
