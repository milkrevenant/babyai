import "dart:convert";

import "package:flutter/material.dart";

import "../../core/network/babyai_api.dart";

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _questionController = TextEditingController();
  bool _loading = false;
  String? _error;
  String _result = "Run a quick question or ask custom AI query.";

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = await action();
      const JsonEncoder encoder = JsonEncoder.withIndent("  ");
      setState(() => _result = encoder.convert(result));
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _askCustom() async {
    final String question = _questionController.text.trim();
    if (question.isEmpty) {
      setState(() => _error = "Enter a question first.");
      return;
    }
    await _run(() => BabyAIApi.instance.queryAi(question));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI Query")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text("Quick backend-powered AI endpoints"),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _QuickAskButton(
                label: "Last poo time",
                onPressed: _loading ? null : () => _run(BabyAIApi.instance.quickLastPooTime),
              ),
              _QuickAskButton(
                label: "Next feeding ETA",
                onPressed: _loading ? null : () => _run(BabyAIApi.instance.quickNextFeedingEta),
              ),
              _QuickAskButton(
                label: "Today summary",
                onPressed: _loading ? null : () => _run(BabyAIApi.instance.quickTodaySummary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _questionController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: "Custom question",
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loading ? null : _askCustom,
            icon: const Icon(Icons.send),
            label: const Text("Ask AI"),
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
          const SizedBox(height: 16),
          const Text(
            "Response",
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(_result),
          ),
        ],
      ),
    );
  }
}

class _QuickAskButton extends StatelessWidget {
  const _QuickAskButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
