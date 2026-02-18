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

class _RecordEntrySheetState extends State<RecordEntrySheet> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _doseController = TextEditingController();
  final TextEditingController _gramsController = TextEditingController();

  DateTime _startTime = DateTime.now();
  late DateTime _sleepEndTime;
  String _diaperType = "PEE";
  String? _error;

  @override
  void initState() {
    super.initState();
    _sleepEndTime = _startTime.add(const Duration(hours: 1));
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
      _sleepEndTime = prefilledEnd;
    }

    if (amountMl is int && amountMl > 0) {
      _amountController.text = amountMl.toString();
    } else if (amountMl is String && amountMl.trim().isNotEmpty) {
      _amountController.text = amountMl.trim();
    }

    if (durationMin is int && durationMin > 0) {
      _durationController.text = durationMin.toString();
      if (prefilledEnd == null) {
        _sleepEndTime = _startTime.add(Duration(minutes: durationMin));
      }
    } else if (durationMin is String && durationMin.trim().isNotEmpty) {
      _durationController.text = durationMin.trim();
      final int? parsed = int.tryParse(durationMin.trim());
      if (parsed != null && parsed > 0 && prefilledEnd == null) {
        _sleepEndTime = _startTime.add(Duration(minutes: parsed));
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

    if (sleepAction is String && sleepAction.trim().isNotEmpty) {
      final String action = sleepAction.trim().toLowerCase();
      if (action == "end" && prefilledEnd == null) {
        _sleepEndTime = DateTime.now();
      }
      if (action == "start" && prefilledEnd == null) {
        _sleepEndTime = _startTime.add(const Duration(minutes: 30));
      }
    }

    if (!_sleepEndTime.isAfter(_startTime)) {
      _sleepEndTime = _startTime.add(const Duration(minutes: 30));
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
    final int minutes = _sleepEndTime.difference(_startTime).inMinutes;
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

  Future<DateTime?> _pickDateTimeScrollable({
    required DateTime initialValue,
  }) async {
    DateTime selected = initialValue;
    return showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SizedBox(
          height: 320,
          child: Column(
            children: <Widget>[
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  use24hFormat: true,
                  initialDateTime: initialValue,
                  onDateTimeChanged: (DateTime value) {
                    selected = value;
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(tr(context,
                            ko: "취소", en: "Cancel", es: "Cancelar")),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(selected),
                        child: Text(
                            tr(context, ko: "확인", en: "Done", es: "Listo")),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickSleepStartTime() async {
    final DateTime? picked =
        await _pickDateTimeScrollable(initialValue: _startTime);
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _startTime = picked;
      if (!_sleepEndTime.isAfter(_startTime)) {
        _sleepEndTime = _startTime.add(const Duration(minutes: 30));
      }
    });
  }

  Future<void> _pickSleepEndTime() async {
    final DateTime? picked =
        await _pickDateTimeScrollable(initialValue: _sleepEndTime);
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _sleepEndTime = picked;
    });
  }

  Future<void> _pickStartTime() async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (date == null || !mounted) {
      return;
    }
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (time == null) {
      return;
    }
    setState(() {
      _startTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
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
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "FORMULA",
            startTime: start,
            value: <String, dynamic>{"ml": amount},
          ),
        );
        return;
      case HomeTileType.breastfeed:
        final int duration = _parsePositiveInt(_durationController) ?? 0;
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "BREASTFEED",
            startTime: start,
            endTime:
                duration > 0 ? start.add(Duration(minutes: duration)) : null,
            value: <String, dynamic>{"duration_min": duration},
          ),
        );
        return;
      case HomeTileType.weaning:
        final String food = _memoController.text.trim();
        final int grams = _parsePositiveInt(_gramsController) ?? 0;
        if (food.isEmpty) {
          setState(() {
            _error = tr(
              context,
              ko: "이유식 내용을 입력해 주세요.",
              en: "Enter weaning food details.",
              es: "Ingrese detalle del alimento.",
            );
          });
          return;
        }
        Navigator.of(context).pop(
          RecordEntryInput(
            type: "MEMO",
            startTime: start,
            value: <String, dynamic>{
              "memo": "이유식: $food",
              if (grams > 0) "grams": grams,
              "category": "WEANING",
            },
            metadata: <String, dynamic>{"entry_kind": "WEANING"},
          ),
        );
        return;
      case HomeTileType.diaper:
        Navigator.of(context).pop(
          RecordEntryInput(
            type: _diaperType,
            startTime: start,
            value: const <String, dynamic>{"count": 1},
          ),
        );
        return;
      case HomeTileType.sleep:
        if (!_sleepEndTime.isAfter(start)) {
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
            endTime: _sleepEndTime,
            value: <String, dynamic>{"duration_min": duration},
          ),
        );
        return;
      case HomeTileType.medication:
        final String name = _nameController.text.trim();
        if (name.isEmpty) {
          setState(() {
            _error = tr(
              context,
              ko: "투약명을 입력해 주세요.",
              en: "Enter medication name.",
              es: "Ingrese nombre del medicamento.",
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
              "name": name,
              if (dose != null && dose > 0) "dose": dose,
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

  Widget _sleepTimeTile({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(label)),
              Text(
                _timeLabel(value),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.unfold_more, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (widget.tile) {
      case HomeTileType.formula:
        return TextField(
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
        );
      case HomeTileType.breastfeed:
        return TextField(
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
        );
      case HomeTileType.weaning:
        return Column(
          children: <Widget>[
            TextField(
              controller: _memoController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "이유식 메뉴",
                  en: "Food name",
                  es: "Nombre del alimento",
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
        return DropdownButtonFormField<String>(
          initialValue: _diaperType,
          isExpanded: true,
          menuMaxHeight: 280,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.expand_more_rounded, size: 20),
          decoration: _dropdownDecoration(
            tr(
              context,
              ko: "기록 유형",
              en: "Type",
              es: "Tipo",
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
        );
      case HomeTileType.sleep:
        return Column(
          children: <Widget>[
            _sleepTimeTile(
              label: tr(
                context,
                ko: "잠 시작 시각",
                en: "Sleep start",
                es: "Inicio del sueno",
              ),
              value: _startTime,
              onTap: _pickSleepStartTime,
            ),
            const SizedBox(height: 8),
            _sleepTimeTile(
              label: tr(
                context,
                ko: "잠 종료 시각",
                en: "Sleep end",
                es: "Fin del sueno",
              ),
              value: _sleepEndTime,
              onTap: _pickSleepEndTime,
            ),
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
          ],
        );
      case HomeTileType.medication:
        return Column(
          children: <Widget>[
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "약 이름",
                  en: "Medication name",
                  es: "Nombre del medicamento",
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
          ],
        );
      case HomeTileType.memo:
        return TextField(
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
            if (widget.tile != HomeTileType.sleep) ...<Widget>[
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr(
                    context,
                    ko: "기록 시각",
                    en: "Date & time",
                    es: "Fecha y hora",
                  ),
                ),
                subtitle: Text(_timeLabel(_startTime)),
                trailing: const Icon(Icons.schedule_outlined),
                onTap: _pickStartTime,
              ),
              const SizedBox(height: 8),
            ],
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
