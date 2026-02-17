import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../../core/network/babyai_api.dart";
import "../../core/widgets/simple_line_chart.dart";

enum _LandingRange { day, week, month }

class RecordingPage extends StatefulWidget {
  const RecordingPage({super.key});

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  final TextEditingController _transcriptController = TextEditingController();

  bool _recordLoading = false;
  bool _snapshotLoading = false;

  String? _recordError;
  String? _snapshotError;

  Map<String, dynamic>? _snapshot;
  Map<String, dynamic>? _parsed;
  Map<String, dynamic>? _confirmed;

  _LandingRange _range = _LandingRange.week;

  @override
  void initState() {
    super.initState();
    _loadLandingSnapshot();
  }

  @override
  void dispose() {
    _transcriptController.dispose();
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
      setState(() => _snapshot = result);
    } catch (error) {
      setState(() => _snapshotError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _snapshotLoading = false);
      }
    }
  }

  Future<void> _parse() async {
    setState(() {
      _recordLoading = true;
      _recordError = null;
      _confirmed = null;
    });

    try {
      final Map<String, dynamic> result = await BabyAIApi.instance.parseVoice(
        _transcriptController.text,
      );
      setState(() => _parsed = result);
    } catch (error) {
      setState(() => _recordError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _recordLoading = false);
      }
    }
  }

  Future<void> _confirm() async {
    final Map<String, dynamic>? parsed = _parsed;
    if (parsed == null) {
      return;
    }
    final String? clipId = parsed["clip_id"] as String?;
    final List<Map<String, dynamic>> events =
        ((parsed["parsed_events"] as List<dynamic>?) ?? <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> item) => item.map(
                  (dynamic key, dynamic value) =>
                      MapEntry(key.toString(), value),
                ))
            .toList();
    if (clipId == null || events.isEmpty) {
      setState(() => _recordError = "No parsed events to confirm.");
      return;
    }

    setState(() {
      _recordLoading = true;
      _recordError = null;
    });

    try {
      final Map<String, dynamic> result =
          await BabyAIApi.instance.confirmVoiceEvents(
        clipId: clipId,
        events: events,
      );
      setState(() => _confirmed = result);
      await _loadLandingSnapshot();
    } catch (error) {
      setState(() => _recordError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _recordLoading = false);
      }
    }
  }

  Future<void> _copyPhrase(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Phrase copied.")),
    );
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
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
    if (value is List<dynamic>) {
      return value.map((dynamic item) => item.toString()).toList();
    }
    return <String>[];
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

  String _rangeLabel() {
    final DateTime now = DateTime.now();
    switch (_range) {
      case _LandingRange.day:
        return "${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}";
      case _LandingRange.week:
        final DateTime monday = now.subtract(Duration(days: now.weekday - 1));
        final DateTime sunday = monday.add(const Duration(days: 6));
        return "${monday.month}/${monday.day} - ${sunday.month}/${sunday.day}";
      case _LandingRange.month:
        return "${now.year}-${now.month.toString().padLeft(2, "0")}";
    }
  }

  Widget _statTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> snapshot = _snapshot ?? <String, dynamic>{};
    final List<String> formulaTimes = _asStringList(snapshot["formula_times"]);
    final Map<String, int> formulaBands =
        _asBandMap(snapshot["formula_amount_by_time_band_ml"]);
    final String lastFormula =
        _formatTime(_asString(snapshot["last_formula_time"]));
    final String recentSleep =
        _formatTime(_asString(snapshot["recent_sleep_time"]));
    final String recentSleepDuration =
        _formatDuration(_asInt(snapshot["recent_sleep_duration_min"]));
    final String sinceLastSleep =
        _formatDuration(_asInt(snapshot["minutes_since_last_sleep"]));
    final String specialMemo =
        _asString(snapshot["special_memo"]) ?? "No special memo for today.";

    final int formulaTotal =
        formulaBands.values.fold<int>(0, (int sum, int value) => sum + value);
    final List<double> formulaSeries = <double>[
      formulaBands["night"]!.toDouble(),
      formulaBands["morning"]!.toDouble(),
      formulaBands["afternoon"]!.toDouble(),
      formulaBands["evening"]!.toDouble(),
    ];

    return RefreshIndicator(
      onRefresh: _loadLandingSnapshot,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SegmentedButton<_LandingRange>(
            segments: const <ButtonSegment<_LandingRange>>[
              ButtonSegment<_LandingRange>(
                value: _LandingRange.day,
                label: Text("Day"),
              ),
              ButtonSegment<_LandingRange>(
                value: _LandingRange.week,
                label: Text("Week"),
              ),
              ButtonSegment<_LandingRange>(
                value: _LandingRange.month,
                label: Text("Month"),
              ),
            ],
            selected: <_LandingRange>{_range},
            onSelectionChanged: (Set<_LandingRange> values) {
              setState(() => _range = values.first);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Icon(Icons.calendar_month, size: 18),
              const SizedBox(width: 6),
              Text(
                _rangeLabel(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: _snapshotLoading ? null : _loadLandingSnapshot,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_snapshotLoading) const LinearProgressIndicator(),
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
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          "Today Baby Snapshot",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text("Total Formula $formulaTotal ml"),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.4,
                    children: <Widget>[
                      _statTile(
                        label: "Last formula time",
                        value: lastFormula,
                        icon: Icons.local_drink_outlined,
                      ),
                      _statTile(
                        label: "Recent sleep time",
                        value: recentSleep,
                        icon: Icons.bedtime_outlined,
                      ),
                      _statTile(
                        label: "Recent sleep duration",
                        value: recentSleepDuration,
                        icon: Icons.timelapse_outlined,
                      ),
                      _statTile(
                        label: "Time since last sleep",
                        value: sinceLastSleep,
                        icon: Icons.hourglass_top_outlined,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    "Formula by time band (night/morning/afternoon/evening)",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Night ${formulaBands["night"]} / Morning ${formulaBands["morning"]} / Afternoon ${formulaBands["afternoon"]} / Evening ${formulaBands["evening"]}",
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 130,
                    child: SimpleLineChart(
                      points: formulaSeries,
                      lineColor: const Color(0xFF8C8ED4),
                      fillColor: const Color(0xFF8C8ED4).withValues(alpha: 0.2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formulaTimes.isEmpty
                        ? "Formula times: no records"
                        : "Formula times: ${formulaTimes.map(_formatTime).join(", ")}",
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text("Special memo"),
              subtitle: Text(specialMemo),
            ),
          ),
          const SizedBox(height: 10),
          ExpansionTile(
            title: const Text("Record now"),
            subtitle: const Text("Parse and confirm events directly from Home"),
            initiallyExpanded: false,
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: <Widget>[
              TextField(
                controller: _transcriptController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Transcript hint (optional)",
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _recordLoading ? null : _parse,
                icon: const Icon(Icons.graphic_eq_outlined),
                label: const Text("Parse voice text"),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _recordLoading || _parsed == null ? null : _confirm,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("Confirm parsed events"),
              ),
              if (_recordLoading) ...<Widget>[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
              if (_recordError != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _recordError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_parsed != null) ...<Widget>[
                const SizedBox(height: 10),
                _JsonPanel(title: "Parsed response", data: _parsed!),
              ],
              if (_confirmed != null) ...<Widget>[
                const SizedBox(height: 10),
                _JsonPanel(title: "Confirm response", data: _confirmed!),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    "Device assistant input (Siri / Bixby / Gemini)",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Use the phone assistant button from Home/lock screen/other apps. "
                    "This is external voice invocation, not an in-app mic tab.",
                  ),
                  const SizedBox(height: 10),
                  const _AssistantStepRow(
                    icon: Icons.smartphone,
                    text:
                        "1) Press and hold side/home assistant button or use voice wake word.",
                  ),
                  const _AssistantStepRow(
                    icon: Icons.record_voice_over_outlined,
                    text:
                        "2) Say a phrase like \"Ask BabyAI to record formula 120 ml now\".",
                  ),
                  const _AssistantStepRow(
                    icon: Icons.sync_outlined,
                    text:
                        "3) Assistant routes into app intent/shortcut and syncs event logs.",
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: () => _copyPhrase(
                          "Ask BabyAI to record formula 120 ml now",
                        ),
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text("Copy formula phrase"),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _copyPhrase(
                          "Ask BabyAI to log diaper pee now",
                        ),
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text("Copy diaper phrase"),
                      ),
                    ],
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

class _AssistantStepRow extends StatelessWidget {
  const _AssistantStepRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _JsonPanel extends StatelessWidget {
  const _JsonPanel({
    required this.title,
    required this.data,
  });

  final String title;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    const JsonEncoder encoder = JsonEncoder.withIndent("  ");
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(encoder.convert(data)),
        ),
      ],
    );
  }
}
