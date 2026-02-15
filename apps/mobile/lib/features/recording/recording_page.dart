import "dart:convert";

import "package:flutter/material.dart";

import "../../core/network/babylog_api.dart";

class RecordingPage extends StatefulWidget {
  const RecordingPage({super.key});

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  final TextEditingController _transcriptController = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _parsed;
  Map<String, dynamic>? _confirmed;

  @override
  void dispose() {
    _transcriptController.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    setState(() {
      _loading = true;
      _error = null;
      _confirmed = null;
    });

    try {
      final Map<String, dynamic> result = await BabyLogApi.instance.parseVoice(
        _transcriptController.text,
      );
      setState(() => _parsed = result);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirm() async {
    final Map<String, dynamic>? parsed = _parsed;
    if (parsed == null) {
      return;
    }
    final String? clipId = parsed["clip_id"] as String?;
    final List<Map<String, dynamic>> events = ((parsed["parsed_events"] as List<dynamic>?) ?? <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> item) => item.map(
              (dynamic key, dynamic value) => MapEntry(key.toString(), value),
            ))
        .toList();
    if (clipId == null || events.isEmpty) {
      setState(() => _error = "No parsed events to confirm.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = await BabyLogApi.instance.confirmVoiceEvents(
        clipId: clipId,
        events: events,
      );
      setState(() => _confirmed = result);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Voice Recording")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text("Parse voice input and confirm events into the backend."),
          const SizedBox(height: 12),
          TextField(
            controller: _transcriptController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: "Transcript hint (optional)",
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _parse,
            icon: const Icon(Icons.mic),
            label: const Text("Parse Voice"),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading || _parsed == null ? null : _confirm,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text("Confirm Parsed Events"),
          ),
          if (_loading) ...<Widget>[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_parsed != null) ...<Widget>[
            const SizedBox(height: 16),
            const Text(
              "Parsed Response",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _JsonPanel(data: _parsed!),
          ],
          if (_confirmed != null) ...<Widget>[
            const SizedBox(height: 16),
            const Text(
              "Confirm Response",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _JsonPanel(data: _confirmed!),
          ],
        ],
      ),
    );
  }
}

class _JsonPanel extends StatelessWidget {
  const _JsonPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final JsonEncoder encoder = const JsonEncoder.withIndent("  ");
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(encoder.convert(data)),
    );
  }
}
