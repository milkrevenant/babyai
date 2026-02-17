import "dart:async";

import "package:flutter/material.dart";
import "package:speech_to_text/speech_recognition_error.dart";
import "package:speech_to_text/speech_recognition_result.dart";
import "package:speech_to_text/speech_to_text.dart" as stt;

import "../../core/network/babyai_api.dart";

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speechToText = stt.SpeechToText();

  bool _loading = false;
  bool _speechReady = false;
  bool _isListening = false;
  String? _error;
  String? _speechError;

  final List<_ChatMessage> _messages = <_ChatMessage>[
    const _ChatMessage(
      role: _ChatRole.assistant,
      text:
          "Hi, I can answer about feeding ETA, sleep patterns, and today's logs.",
    ),
  ];

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    _speechToText.cancel();
    super.dispose();
  }

  Future<void> sendAssistantPrompt(String prompt) async {
    final String normalized = prompt.trim();
    if (normalized.isEmpty) {
      return;
    }
    _questionController
      ..text = normalized
      ..selection = TextSelection.collapsed(offset: normalized.length);
    await _sendQuestionText(normalized, clearInput: true);
  }

  Future<void> _appendAssistantFromAction(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = await action();
      final String answer = _extractAnswer(result);
      setState(() {
        _messages.add(_ChatMessage(role: _ChatRole.assistant, text: answer));
      });
      _scrollToBottom();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _extractAnswer(Map<String, dynamic> data) {
    for (final String key in <String>[
      "answer",
      "message",
      "dialog",
      "reference_text",
    ]) {
      final Object? value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    final Object? summaryLines = data["summary_lines"];
    if (summaryLines is List<dynamic> && summaryLines.isNotEmpty) {
      return summaryLines.map((dynamic line) => line.toString()).join("\n");
    }
    return data.toString();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendQuestionText(
    String question, {
    bool clearInput = false,
  }) async {
    final String normalized = question.trim();
    if (normalized.isEmpty || _loading) {
      return;
    }
    if (clearInput) {
      _questionController.clear();
    }
    setState(() {
      _messages.add(_ChatMessage(role: _ChatRole.user, text: normalized));
      _error = null;
    });
    _scrollToBottom();
    await _appendAssistantFromAction(
      () => BabyAIApi.instance.queryAi(normalized),
    );
  }

  Future<void> _sendCustomQuestion() async {
    await _sendQuestionText(
      _questionController.text,
      clearInput: true,
    );
  }

  Future<void> _ensureSpeechReady() async {
    if (_speechReady) {
      return;
    }
    final bool available = await _speechToText.initialize(
      onError: _handleSpeechError,
      onStatus: _handleSpeechStatus,
      debugLogging: false,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _speechReady = available;
      if (!available) {
        _speechError = "Speech recognition is unavailable on this device.";
      }
    });
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isListening = false;
      _speechError = error.errorMsg;
    });
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }
    if (status == "done" || status == "notListening") {
      setState(() => _isListening = false);
    }
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final String words = result.recognizedWords.trim();
    if (words.isEmpty) {
      return;
    }
    _questionController
      ..text = words
      ..selection = TextSelection.collapsed(offset: words.length);
    if (!result.finalResult) {
      return;
    }
    setState(() => _isListening = false);
    unawaited(_speechToText.stop());
    unawaited(_sendQuestionText(words, clearInput: true));
  }

  Future<void> _toggleListening() async {
    if (_loading) {
      return;
    }
    if (_isListening) {
      await _speechToText.stop();
      if (mounted) {
        setState(() => _isListening = false);
      }
      return;
    }

    await _ensureSpeechReady();
    if (!_speechReady) {
      return;
    }
    setState(() {
      _speechError = null;
      _isListening = true;
    });
    await _speechToText.listen(
      onResult: _handleSpeechResult,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            color: color.surfaceContainerHighest.withValues(alpha: 0.35),
            border: Border(
              bottom: BorderSide(
                color: color.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _QuickActionChip(
                label: "Last poo time",
                onTap: _loading
                    ? null
                    : () => _appendAssistantFromAction(
                          BabyAIApi.instance.quickLastPooTime,
                        ),
              ),
              _QuickActionChip(
                label: "Next feeding ETA",
                onTap: _loading
                    ? null
                    : () => _appendAssistantFromAction(
                          BabyAIApi.instance.quickNextFeedingEta,
                        ),
              ),
              _QuickActionChip(
                label: "Today summary",
                onTap: _loading
                    ? null
                    : () => _appendAssistantFromAction(
                          BabyAIApi.instance.quickTodaySummary,
                        ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            itemCount: _messages.length + (_loading ? 1 : 0),
            itemBuilder: (BuildContext context, int index) {
              if (_loading && index == _messages.length) {
                return const _TypingBubble();
              }
              final _ChatMessage message = _messages[index];
              return _MessageBubble(message: message);
            },
          ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: color.errorContainer,
            child: Text(
              _error!,
              style: TextStyle(color: color.onErrorContainer),
            ),
          ),
        if (_speechError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: color.tertiaryContainer,
            child: Text(
              _speechError!,
              style: TextStyle(color: color.onTertiaryContainer),
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: color.surface,
            border: Border(
              top: BorderSide(
                color: color.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _questionController,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendCustomQuestion(),
                  decoration: const InputDecoration(
                    hintText: "Ask anything about your baby's records...",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _loading ? null : _toggleListening,
                child: Icon(
                  _isListening
                      ? Icons.mic_off_outlined
                      : Icons.mic_none_outlined,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _loading ? null : _sendCustomQuestion,
                child: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _ChatRole { user, assistant }

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
  });

  final _ChatRole role;
  final String text;
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      avatar: const Icon(Icons.bolt, size: 16),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == _ChatRole.user;
    final ColorScheme color = Theme.of(context).colorScheme;
    final Color bubbleColor = isUser
        ? color.primaryContainer
        : color.surfaceContainerHighest.withValues(alpha: 0.45);
    final Color textColor = isUser ? color.onPrimaryContainer : color.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isUser) ...<Widget>[
            CircleAvatar(
              radius: 14,
              backgroundColor: color.secondaryContainer,
              child: Icon(
                Icons.smart_toy_outlined,
                size: 14,
                color: color.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                message.text,
                style: TextStyle(color: textColor, height: 1.3),
              ),
            ),
          ),
          if (isUser) ...<Widget>[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: color.primaryContainer,
              child: Icon(
                Icons.person_outline,
                size: 14,
                color: color.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 14,
            backgroundColor: color.secondaryContainer,
            child: Icon(
              Icons.smart_toy_outlined,
              size: 14,
              color: color.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      ),
    );
  }
}
