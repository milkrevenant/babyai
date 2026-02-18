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
  });

  final String type;
  final DateTime startTime;
  final DateTime? endTime;
  final Map<String, dynamic> value;
  final Map<String, dynamic>? metadata;
}

Future<RecordEntryInput?> showRecordEntrySheet({
  required BuildContext context,
  required HomeTileType tile,
  Map<String, dynamic>? prefill,
}) {
  return showModalBottomSheet<RecordEntryInput>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) {
      return RecordEntrySheet(tile: tile, prefill: prefill);
    },
  );
}

class RecordEntrySheet extends StatefulWidget {
  const RecordEntrySheet({
    super.key,
    required this.tile,
    this.prefill,
  });

  final HomeTileType tile;
  final Map<String, dynamic>? prefill;

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
  String? _error;

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

    final DateTime? prefilledStart =
        _parseDateTimeFromRaw(prefill["start_time"]) ??
            _parseDateTimeFromRaw(prefill["sleep_start_time"]);
    final DateTime? prefilledEnd = _parseDateTimeFromRaw(prefill["end_time"]) ??
        _parseDateTimeFromRaw(prefill["sleep_end_time"]);

    if (prefilledStart != null) {
      _startTime = prefilledStart;
    }
    if (prefilledEnd != null) {
      _endTime = prefilledEnd;
    }

    if (amountMl is int && amountMl > 0) {
      _amountController.text = amountMl.toString();
    } else if (amountMl is String && amountMl.trim().isNotEmpty) {
      _amountController.text = amountMl.trim();
    }

    if (durationMin is int && durationMin > 0) {
      _durationController.text = durationMin.toString();
      if (prefilledEnd == null) {
        _endTime = _startTime.add(Duration(minutes: durationMin));
      }
    } else if (durationMin is String && durationMin.trim().isNotEmpty) {
      _durationController.text = durationMin.trim();
      final int? parsed = int.tryParse(durationMin.trim());
      if (parsed != null && parsed > 0 && prefilledEnd == null) {
        _endTime = _startTime.add(Duration(minutes: parsed));
      }
    }

    if (grams is int && grams > 0) {
      _gramsController.text = grams.toString();
    } else if (grams is String && grams.trim().isNotEmpty) {
      _gramsController.text = grams.trim();
    }

    if (memo is String && memo.trim().isNotEmpty) {
      _memoController.text = memo.trim();
    } else if (query is String && query.trim().isNotEmpty) {
      _memoController.text = query.trim();
    }

    if (query is String &&
        query.trim().isNotEmpty &&
        _nameController.text.isEmpty) {
      _nameController.text = query.trim();
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
    }

    if (sleepAction is String && sleepAction.trim().isNotEmpty) {
      final String action = sleepAction.trim().toLowerCase();
      if (action == "end" && prefilledEnd == null) {
        _endTime = DateTime.now();
      }
      if (action == "start" && prefilledEnd == null) {
        _endTime = _startTime.add(const Duration(minutes: 30));
      }
    }

    if (!_endTime.isAfter(_startTime)) {
      _endTime = _startTime.add(const Duration(minutes: 30));
    }
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
        if (amount == null || amount <= 0) {
          setState(() {
            _error = tr(
              context,
              ko: "분유량(ml)을 입력해 주세요.",
              en: "Enter formula amount (ml).",
              es: "Ingrese cantidad de formula (ml).",
            );
          });
          return;
        }
        if (!_endTime.isAfter(start)) {
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
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "FORMULA",
            startTime: start,
            endTime: _endTime,
            value: <String, dynamic>{
              "ml": amount,
              "duration_min": _sleepDurationMinutes(),
              if (memo.isNotEmpty) "memo": memo,
            },
          ),
        );
        return;
      case HomeTileType.breastfeed:
        final int duration = _parsePositiveInt(_durationController) ?? 0;
        final String memo = _memoController.text.trim();
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "BREASTFEED",
            startTime: start,
            endTime:
                duration > 0 ? start.add(Duration(minutes: duration)) : null,
            value: <String, dynamic>{
              "duration_min": duration,
              if (memo.isNotEmpty) "memo": memo,
            },
          ),
        );
        return;
      case HomeTileType.weaning:
        final int grams = _parsePositiveInt(_gramsController) ?? 0;
        final String memo = _memoController.text.trim();
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "MEMO",
            startTime: start,
            value: <String, dynamic>{
              "memo": memo.isEmpty
                  ? "이유식(${_weaningTypeLabel(_weaningType)})"
                  : memo,
              if (grams > 0) "grams": grams,
              "category": "WEANING",
              "weaning_type": _weaningType,
            },
            metadata: <String, dynamic>{
              "entry_kind": "WEANING",
              "weaning_type": _weaningType,
            },
          ),
        );
        return;
      case HomeTileType.diaper:
        final String memo = _memoController.text.trim();
        Navigator.of(context).pop(
          RecordEntryInput(
            type: _diaperType,
            startTime: start,
            value: <String, dynamic>{
              "count": 1,
              if (memo.isNotEmpty) "memo": memo,
            },
          ),
        );
        return;
      case HomeTileType.sleep:
        final String memo = _memoController.text.trim();
        if (!_endTime.isAfter(start)) {
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
        final int duration = _sleepDurationMinutes();
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "SLEEP",
            startTime: start,
            endTime: _endTime,
            value: <String, dynamic>{
              "duration_min": duration,
              if (memo.isNotEmpty) "memo": memo,
            },
          ),
        );
        return;
      case HomeTileType.medication:
        final String memo = _memoController.text.trim();
        final String medicationType = _nameController.text.trim();
        if (medicationType.isEmpty) {
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
            value: <String, dynamic>{
              "name": medicationType,
              "medication_type": medicationType,
              if (dose != null && dose > 0) "dose": dose,
              if (memo.isNotEmpty) "memo": memo,
            },
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
            _inlineTimeEditor(includeEnd: true),
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
            _inlineTimeEditor(includeEnd: false),
            const SizedBox(height: 8),
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "수유 시간 (분)",
                  en: "Duration (min)",
                  es: "Duracion (min)",
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
            _inlineTimeEditor(includeEnd: false),
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
            _inlineTimeEditor(includeEnd: false),
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
            _inlineTimeEditor(includeEnd: true),
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
                _sleepDurationLabel(),
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
            _inlineTimeEditor(includeEnd: false),
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
                    icon: const Icon(Icons.check_circle_outline),
                    label:
                        Text(tr(context, ko: "저장", en: "Save", es: "Guardar")),
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
