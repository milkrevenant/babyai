import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_markdown/flutter_markdown.dart";
import "package:markdown/markdown.dart" as md;
import "package:speech_to_text/speech_recognition_error.dart";
import "package:speech_to_text/speech_recognition_result.dart";
import "package:speech_to_text/speech_to_text.dart" as stt;

import "../../core/network/babyai_api.dart";
import "../../core/widgets/app_svg_icon.dart";

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    this.onHistoryChanged,
  });

  final VoidCallback? onHistoryChanged;

  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speechToText = stt.SpeechToText();

  bool _loading = false;
  bool _loadingHistory = false;
  bool _speechReady = false;
  bool _isListening = false;
  String? _error;
  String? _speechError;
  int _activeThreadIndex = 0;
  Map<String, dynamic>? _lastCredit;
  Map<String, dynamic>? _lastUsage;

  final List<_ChatThread> _threads = <_ChatThread>[];

  bool get _hasActiveThread =>
      _threads.isNotEmpty &&
      _activeThreadIndex >= 0 &&
      _activeThreadIndex < _threads.length;

  _ChatThread? get _activeThreadOrNull =>
      _hasActiveThread ? _threads[_activeThreadIndex] : null;

  List<_ChatMessage> get _messages =>
      _activeThreadOrNull?.messages ?? const <_ChatMessage>[];

  String? get activeSessionId => _activeThreadOrNull?.sessionId;

  String get activeThreadTitle =>
      (_activeThreadOrNull?.title ?? "New conversation").trim();

  Future<void> applyLocalSessionTitle(String sessionId, String title) async {
    final String normalizedId = sessionId.trim();
    final String normalizedTitle = title.trim();
    if (normalizedId.isEmpty || normalizedTitle.isEmpty) {
      return;
    }
    final int idx = _findThreadIndexBySessionId(normalizedId);
    if (idx < 0 || !mounted) {
      return;
    }
    setState(() {
      _threads[idx].title = normalizedTitle;
    });
  }

  Future<void> hideSessionLocally(String sessionId) async {
    final String normalizedId = sessionId.trim();
    if (normalizedId.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _threads.removeWhere(
        (_ChatThread thread) => (thread.sessionId ?? "").trim() == normalizedId,
      );
      if (_threads.isEmpty) {
        _activeThreadIndex = 0;
      } else if (_activeThreadIndex >= _threads.length) {
        _activeThreadIndex = _threads.length - 1;
      }
    });
    if (_threads.isEmpty) {
      await _createNewThread();
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initializeChatState());
  }

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    _speechToText.cancel();
    super.dispose();
  }

  Future<void> _initializeChatState() async {
    await _createNewThread();
    if (!_hasActiveThread) {
      await _refreshThreadsFromServer(bootstrapActive: false);
    }
  }

  Future<void> refreshHistoryFromServer() async {
    await _refreshThreadsFromServer(bootstrapActive: false);
  }

  Future<void> openSessionById(String sessionId) async {
    final String normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return;
    }
    int index = _findThreadIndexBySessionId(normalized);
    if (index < 0) {
      await _refreshThreadsFromServer(
        preferredSessionId: normalized,
        bootstrapActive: false,
      );
      index = _findThreadIndexBySessionId(normalized);
    }
    if (index < 0) {
      return;
    }
    _openThread(index);
  }

  Future<void> createNewConversation() async {
    await _createNewThread();
  }

  Future<_ChatThread> _createThreadFromServer() async {
    final Map<String, dynamic> payload = await BabyAIApi.instance
        .createChatSession(childId: BabyAIApi.activeBabyId);
    final String sessionId = (payload["session_id"] ?? "").toString().trim();
    if (sessionId.isEmpty) {
      throw ApiFailure("Missing session_id from /chat/sessions");
    }
    final String titleRaw = (payload["title"] ?? "").toString().trim();
    return _ChatThread(
      title: titleRaw.isEmpty ? "New conversation" : titleRaw,
      preview: "Start by asking about today's routine",
      updatedAt: DateTime.now(),
      messages: <_ChatMessage>[],
      sessionId: sessionId,
    );
  }

  Future<void> _refreshThreadsFromServer({
    String? preferredSessionId,
    bool bootstrapActive = false,
  }) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingHistory = true;
      _error = null;
    });

    try {
      final String? currentSessionId = _activeThreadOrNull?.sessionId;
      final Map<String, _ChatThread> existingBySession = <String, _ChatThread>{
        for (final _ChatThread thread in _threads)
          if (thread.sessionId != null && thread.sessionId!.trim().isNotEmpty)
            thread.sessionId!.trim(): thread,
      };

      final Map<String, dynamic> payload = await BabyAIApi.instance
          .getChatSessions(childId: BabyAIApi.activeBabyId, limit: 50);
      final List<dynamic> rawSessions =
          (payload["sessions"] as List<dynamic>? ?? <dynamic>[]);

      final List<_ChatThread> parsed = <_ChatThread>[];
      for (final dynamic item in rawSessions) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final String sessionId = (item["session_id"] ?? "").toString().trim();
        if (sessionId.isEmpty) {
          continue;
        }
        final _ChatThread? existing = existingBySession[sessionId];
        final String title = (item["title"] ?? "").toString().trim();
        final String preview = (item["preview"] ?? "").toString().trim();
        final DateTime updatedAt = DateTime.tryParse(
              (item["updated_at"] ?? DateTime.now().toIso8601String())
                  .toString(),
            ) ??
            DateTime.now();
        parsed.add(
          _ChatThread(
            title: title.isEmpty ? "New conversation" : title,
            preview: preview.isEmpty ? "No messages yet" : preview,
            updatedAt: updatedAt,
            messages: existing?.messages ?? <_ChatMessage>[],
            sessionId: sessionId,
          ),
        );
      }

      if (parsed.isEmpty) {
        parsed.add(await _createThreadFromServer());
      }

      int nextIndex = 0;
      final String preferred = preferredSessionId?.trim() ?? "";
      if (preferred.isNotEmpty) {
        final int idx =
            parsed.indexWhere((_ChatThread t) => t.sessionId == preferred);
        if (idx >= 0) {
          nextIndex = idx;
        }
      } else if (currentSessionId != null &&
          currentSessionId.trim().isNotEmpty) {
        final int idx = parsed
            .indexWhere((_ChatThread t) => t.sessionId == currentSessionId);
        if (idx >= 0) {
          nextIndex = idx;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _threads
          ..clear()
          ..addAll(parsed);
        _activeThreadIndex = nextIndex;
      });

      if (bootstrapActive && _hasActiveThread) {
        await _loadThreadMessages(_activeThreadOrNull!);
      }
      widget.onHistoryChanged?.call();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingHistory = false);
      }
    }
  }

  int _findThreadIndexBySessionId(String sessionId) {
    return _threads.indexWhere(
      (_ChatThread thread) => (thread.sessionId ?? "").trim() == sessionId,
    );
  }

  Future<void> _loadThreadMessages(_ChatThread thread) async {
    final String sessionId = (thread.sessionId ?? "").trim();
    if (sessionId.isEmpty) {
      return;
    }

    final Map<String, dynamic> payload =
        await BabyAIApi.instance.getChatMessages(sessionId);
    final List<dynamic> rawMessages =
        (payload["messages"] as List<dynamic>? ?? <dynamic>[]);
    final List<_ChatMessage> parsed = <_ChatMessage>[];
    String? firstUserText;

    for (final dynamic item in rawMessages) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final String role = (item["role"] ?? "").toString().trim().toLowerCase();
      if (role != "user" && role != "assistant") {
        continue;
      }
      final String content = (item["content"] ?? "").toString();
      if (content.trim().isEmpty) {
        continue;
      }
      final DateTime createdAt = DateTime.tryParse(
            (item["created_at"] ?? DateTime.now().toIso8601String()).toString(),
          ) ??
          DateTime.now();
      if (firstUserText == null && role == "user") {
        firstUserText = content.trim();
      }
      parsed.add(
        _ChatMessage(
          role: role == "assistant" ? _ChatRole.assistant : _ChatRole.user,
          text: content,
          createdAt: createdAt,
        ),
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      if (parsed.isNotEmpty) {
        thread.messages
          ..clear()
          ..addAll(parsed);
        thread.preview = parsed.last.text.trim();
      }
      final String titleFromApi = (payload["title"] ?? "").toString().trim();
      if (titleFromApi.isNotEmpty) {
        thread.title = titleFromApi;
      } else if (firstUserText != null && firstUserText.isNotEmpty) {
        thread.title = _deriveTitleFromText(firstUserText);
      }
      thread.updatedAt = DateTime.now();
    });
    _scrollToBottom();
    widget.onHistoryChanged?.call();
  }

  String _deriveTitleFromText(String text) {
    final String normalized = text.replaceAll(RegExp(r"\s+"), " ").trim();
    if (normalized.isEmpty) {
      return "New conversation";
    }
    const int maxLen = 38;
    if (normalized.length <= maxLen) {
      return normalized;
    }
    return "${normalized.substring(0, maxLen)}...";
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

  Future<void> _sendQuestionText(
    String question, {
    bool clearInput = false,
  }) async {
    final String normalized = question.trim();
    if (normalized.isEmpty || _loading) {
      return;
    }
    if (!_hasActiveThread) {
      await _createNewThread();
      if (!_hasActiveThread) {
        return;
      }
    }

    if (clearInput) {
      _questionController.clear();
    }

    final _ChatThread thread = _activeThreadOrNull!;
    setState(() {
      thread.messages.add(
        _ChatMessage(
          role: _ChatRole.user,
          text: normalized,
          createdAt: DateTime.now(),
        ),
      );
      if (thread.title.trim().toLowerCase() == "new conversation") {
        thread.title = _deriveTitleFromText(normalized);
      }
      thread.preview = normalized;
      thread.updatedAt = DateTime.now();
      _error = null;
    });
    _scrollToBottom();

    setState(() => _loading = true);
    try {
      final String sessionId = (thread.sessionId ?? "").trim().isNotEmpty
          ? thread.sessionId!.trim()
          : (await _ensureThreadSession(thread));

      final Map<String, dynamic> result = await BabyAIApi.instance.chatQuery(
        sessionId: sessionId,
        query: normalized,
        tone: "neutral",
        usePersonalData: true,
        childId: BabyAIApi.activeBabyId,
      );

      final String answer = _extractAnswer(result);
      final Map<String, dynamic>? credit = result["credit"] is Map
          ? Map<String, dynamic>.from(result["credit"] as Map<dynamic, dynamic>)
          : null;
      final Map<String, dynamic>? usage = result["usage"] is Map
          ? Map<String, dynamic>.from(result["usage"] as Map<dynamic, dynamic>)
          : null;

      if (!mounted) {
        return;
      }
      setState(() {
        thread.messages.add(
          _ChatMessage(
            role: _ChatRole.assistant,
            text: answer,
            createdAt: DateTime.now(),
          ),
        );
        thread.preview = answer.trim().isEmpty ? "No response text" : answer;
        thread.updatedAt = DateTime.now();
        _lastCredit = credit;
        _lastUsage = usage;
      });
      _scrollToBottom();
      widget.onHistoryChanged?.call();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String> _ensureThreadSession(_ChatThread thread) async {
    final String existing = (thread.sessionId ?? "").trim();
    if (existing.isNotEmpty) {
      return existing;
    }
    final _ChatThread created = await _createThreadFromServer();
    thread.sessionId = created.sessionId;
    return (thread.sessionId ?? "").trim();
  }

  Future<void> _sendCustomQuestion() async {
    await _sendQuestionText(_questionController.text, clearInput: true);
  }

  void _openThread(int index) {
    if (index < 0 || index >= _threads.length) {
      return;
    }
    setState(() {
      _activeThreadIndex = index;
      _error = null;
      _speechError = null;
    });
    unawaited(_loadThreadMessages(_threads[index]));
    _scrollToBottom();
  }

  Future<void> _createNewThread() async {
    if (_loadingHistory) {
      return;
    }
    try {
      setState(() => _loadingHistory = true);
      final _ChatThread thread = await _createThreadFromServer();
      if (!mounted) {
        return;
      }
      setState(() {
        _threads.insert(0, thread);
        _activeThreadIndex = 0;
        _error = null;
        _speechError = null;
        _lastCredit = null;
        _lastUsage = null;
      });
      await _loadThreadMessages(thread);
      _scrollToBottom();
      widget.onHistoryChanged?.call();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loadingHistory = false);
      }
    }
  }

  int? _mapInt(Map<String, dynamic>? source, String key) {
    if (source == null) {
      return null;
    }
    final Object? value = source[key];
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

  String? _billingHint() {
    final int? charged = _mapInt(_lastCredit, "charged");
    final int? balance = _mapInt(_lastCredit, "balance_after");
    final String? mode = _lastCredit?["billing_mode"]?.toString();
    final int? totalTokens = _mapInt(_lastUsage, "total_tokens");
    if (charged == null && balance == null && totalTokens == null) {
      return null;
    }
    final List<String> parts = <String>[];
    if (charged != null) {
      parts.add("charged $charged cr");
    }
    if (balance != null) {
      parts.add("balance $balance cr");
    }
    if (mode != null && mode.trim().isNotEmpty) {
      parts.add(mode.trim());
    }
    if (totalTokens != null) {
      parts.add("$totalTokens tok");
    }
    return parts.join(" | ");
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

  Widget _buildQuickActionRow(ColorScheme color) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _QuickActionPill(
            label: "마지막 대변 시간",
            icon: Icons.water_drop_outlined,
            color: color,
            onTap: _loading ? null : () => _sendQuestionText("마지막 대변 시간 알려줘"),
          ),
          const SizedBox(width: 8),
          _QuickActionPill(
            label: "다음 수유 예측",
            icon: Icons.schedule_outlined,
            color: color,
            onTap: _loading ? null : () => _sendQuestionText("다음 수유 시간 예측해줘"),
          ),
          const SizedBox(width: 8),
          _QuickActionPill(
            label: "오늘 요약",
            icon: Icons.summarize_outlined,
            color: color,
            onTap: _loading ? null : () => _sendQuestionText("오늘 기록 요약해줘"),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPanel({
    required BuildContext context,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme color = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.surface.withValues(alpha: 0.98),
            color.surface.withValues(alpha: 0.92),
          ],
        ),
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: _hasActiveThread
                ? ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (BuildContext context, int index) {
                      if (_loading && index == _messages.length) {
                        return const _TypingBubble();
                      }
                      return _MessageBubble(message: _messages[index]);
                    },
                  )
                : Center(
                    child: Text(
                      _loadingHistory
                          ? "Loading conversations..."
                          : "No conversations yet. Start a new chat.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: color.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: color.onErrorContainer),
              ),
            ),
          if (_speechError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _speechError!,
                style: TextStyle(color: color.onTertiaryContainer),
              ),
            ),
          if (_billingHint() != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _billingHint()!,
                style: TextStyle(color: color.onPrimaryContainer),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: _buildQuickActionRow(color),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            decoration: BoxDecoration(
              color: color.surfaceContainerHigh.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: <Widget>[
                IconButton(
                  onPressed: _loading ? null : _toggleListening,
                  icon: Icon(
                    _isListening
                        ? Icons.mic_off_outlined
                        : Icons.mic_none_rounded,
                    size: 20,
                  ),
                  color: color.primary,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(34, 34),
                    maximumSize: const Size(34, 34),
                  ),
                  tooltip: "Voice input",
                ),
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendCustomQuestion(),
                    decoration: InputDecoration(
                      hintText: "Ask about your baby's routine...",
                      hintStyle: TextStyle(
                        color: color.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _loading ? null : _createNewThread,
                  icon: const Icon(Icons.add, size: 19),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(34, 34),
                    maximumSize: const Size(34, 34),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _loading ? null : _sendCustomQuestion,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(36, 36),
                    maximumSize: const Size(36, 36),
                  ),
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
    return _buildChatPanel(context: context);
  }
}

enum _ChatRole { user, assistant }

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final _ChatRole role;
  final String text;
  final DateTime createdAt;
}

class _ChatThread {
  _ChatThread({
    required this.title,
    required this.preview,
    required this.updatedAt,
    required this.messages,
    this.sessionId,
  });

  String title;
  String preview;
  DateTime updatedAt;
  final List<_ChatMessage> messages;
  String? sessionId;
}

class _QuickActionPill extends StatelessWidget {
  const _QuickActionPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final ColorScheme color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.surfaceContainerHighest.withValues(alpha: 0.52),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: color.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  static final RegExp _htmlBreakTagPattern = RegExp(
    r"<br\s*/?>",
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _tableAlignRowPattern = RegExp(
    r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$",
  );
  static final RegExp _longTokenPattern = RegExp(r"([^\s|]{14,})");
  static const String _softWrapHint = "\u200B";

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == _ChatRole.user;
    final ThemeData theme = Theme.of(context);
    final ColorScheme color = theme.colorScheme;
    final Color bubbleColor = isUser
        ? color.primary.withValues(alpha: 0.93)
        : color.surfaceContainerHighest.withValues(alpha: 0.52);
    final Color textColor = isUser ? color.onPrimary : color.onSurface;
    final String role = isUser ? "You" : "Parenting AI";
    final String markdownData = _normalizeMarkdownForChat(message.text);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              role,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (!isUser) ...<Widget>[
                CircleAvatar(
                  radius: 15,
                  backgroundColor: color.secondaryContainer,
                  child: AppSvgIcon(
                    AppSvgAsset.aiChatSparkles,
                    size: 15,
                    color: color.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(22),
                      topRight: const Radius.circular(22),
                      bottomLeft: Radius.circular(isUser ? 22 : 8),
                      bottomRight: Radius.circular(isUser ? 8 : 22),
                    ),
                  ),
                  child: _buildMarkdownMessage(
                    isUser: isUser,
                    theme: theme,
                    color: color,
                    textColor: textColor,
                    bubbleColor: bubbleColor,
                    data: markdownData,
                  ),
                ),
              ),
              if (isUser) ...<Widget>[
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 15,
                  backgroundColor: color.primaryContainer,
                  child: AppSvgIcon(
                    AppSvgAsset.profile,
                    size: 15,
                    color: color.onPrimaryContainer,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdownMessage({
    required bool isUser,
    required ThemeData theme,
    required ColorScheme color,
    required Color textColor,
    required Color bubbleColor,
    required String data,
  }) {
    final TextStyle baseTextStyle = (theme.textTheme.bodyLarge ??
            const TextStyle(fontSize: 16, height: 1.4))
        .copyWith(
      color: textColor,
      height: 1.46,
      fontFamily: "NotoSans",
      fontFamilyFallback: const <String>["IBMPlexSans"],
    );
    final TextStyle tableTextStyle = baseTextStyle.copyWith(
      fontSize: (baseTextStyle.fontSize ?? 16) - 0.8,
      height: 1.42,
      fontFamily: "NotoSans",
      fontFamilyFallback: const <String>["IBMPlexSans"],
    );

    return MarkdownBody(
      data: data,
      selectable: true,
      softLineBreak: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: baseTextStyle,
        pPadding: EdgeInsets.zero,
        strong: baseTextStyle.copyWith(
          fontWeight: FontWeight.w700,
          color: isUser ? textColor : color.primary,
        ),
        h1: theme.textTheme.titleLarge?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontFamily: "NotoSans",
          fontFamilyFallback: const <String>["IBMPlexSans"],
        ),
        h2: theme.textTheme.titleMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontFamily: "NotoSans",
          fontFamilyFallback: const <String>["IBMPlexSans"],
        ),
        h3: theme.textTheme.titleSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontFamily: "NotoSans",
          fontFamilyFallback: const <String>["IBMPlexSans"],
        ),
        listBullet: baseTextStyle,
        tableHead: tableTextStyle.copyWith(
          fontWeight: FontWeight.w700,
          fontFamily: "IBMPlexSans",
          fontFamilyFallback: const <String>["NotoSans"],
        ),
        tableBody: tableTextStyle,
        tableHeadAlign: TextAlign.left,
        tableColumnWidth: const FlexColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        tableVerticalAlignment: TableCellVerticalAlignment.top,
        tableBorder: TableBorder.all(
          color: textColor.withValues(alpha: 0.2),
          width: 0.7,
        ),
        tableCellsDecoration: BoxDecoration(
          color: isUser
              ? color.onPrimary.withValues(alpha: 0.08)
              : color.surface.withValues(alpha: 0.38),
        ),
        tablePadding: const EdgeInsets.only(bottom: 6),
        code: baseTextStyle.copyWith(
          fontFamily: "IBMPlexSans",
          fontFamilyFallback: const <String>["NotoSans"],
          fontSize: (baseTextStyle.fontSize ?? 16) * 0.9,
        ),
        codeblockPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        codeblockDecoration: BoxDecoration(
          color: bubbleColor.withValues(alpha: isUser ? 0.18 : 0.42),
          borderRadius: BorderRadius.circular(10),
        ),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        blockquoteDecoration: BoxDecoration(
          color: bubbleColor.withValues(alpha: isUser ? 0.12 : 0.24),
          border: Border(
            left: BorderSide(
              color: textColor.withValues(alpha: 0.28),
              width: 3,
            ),
          ),
        ),
      ),
    );
  }

  String _normalizeMarkdownForChat(String raw) {
    String normalized = raw.trim();
    if (normalized.isEmpty) {
      return "";
    }
    normalized = normalized
        .replaceAll("\r\n", "\n")
        .replaceAll("\r", "\n")
        .replaceAll(_htmlBreakTagPattern, "\n");
    return _injectTableSoftWrapHints(normalized);
  }

  String _injectTableSoftWrapHints(String markdown) {
    final List<String> lines = markdown.split("\n");
    final List<String> transformed = <String>[];
    bool inFence = false;

    for (final String line in lines) {
      final String trimmedLeft = line.trimLeft();
      if (trimmedLeft.startsWith("```")) {
        inFence = !inFence;
        transformed.add(line);
        continue;
      }
      if (inFence ||
          !_isLikelyTableRow(line) ||
          _tableAlignRowPattern.hasMatch(line)) {
        transformed.add(line);
        continue;
      }
      transformed.add(_softWrapTableRow(line));
    }

    return transformed.join("\n");
  }

  bool _isLikelyTableRow(String line) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.contains("|")) {
      return false;
    }
    final int pipeCount = "|".allMatches(trimmed).length;
    if (pipeCount < 2) {
      return false;
    }
    if (trimmed.startsWith("|") || trimmed.endsWith("|")) {
      return true;
    }
    return trimmed.contains(" | ");
  }

  String _softWrapTableRow(String line) {
    final int leftPaddingCount = line.length - line.trimLeft().length;
    final int rightPaddingCount = line.length - line.trimRight().length;
    final String leftPadding = line.substring(0, leftPaddingCount);
    final String rightPadding = rightPaddingCount > 0
        ? line.substring(line.length - rightPaddingCount)
        : "";

    String core = line.trim();
    final bool hasLeadingPipe = core.startsWith("|");
    final bool hasTrailingPipe = core.endsWith("|");

    if (hasLeadingPipe) {
      core = core.substring(1);
    }
    if (hasTrailingPipe && core.isNotEmpty) {
      core = core.substring(0, core.length - 1);
    }

    final List<String> cells = core.split("|");
    final List<String> processed = cells
        .map(
          (String cell) => _injectSoftWrapPoints(cell.trim()),
        )
        .toList(growable: false);

    String rebuilt = processed.join(" | ");
    if (hasLeadingPipe) {
      rebuilt = "| $rebuilt";
    }
    if (hasTrailingPipe) {
      rebuilt = "$rebuilt |";
    }
    return "$leftPadding$rebuilt$rightPadding";
  }

  String _injectSoftWrapPoints(String cellValue) {
    if (cellValue.isEmpty) {
      return cellValue;
    }

    String normalized = cellValue;
    const List<String> separators = <String>[
      "/",
      "-",
      "_",
      ".",
      ",",
      ":",
      ";",
      ")",
      "]",
      "}",
      ">",
      "=",
    ];
    for (final String separator in separators) {
      normalized = normalized.replaceAll(separator, "$separator$_softWrapHint");
    }
    normalized = normalized.replaceAllMapped(
      _longTokenPattern,
      (Match match) => _chunkTokenWithSoftWrap(match.group(1) ?? ""),
    );
    return normalized;
  }

  String _chunkTokenWithSoftWrap(String token) {
    if (token.isEmpty || token.length < 14) {
      return token;
    }
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < token.length; i++) {
      buffer.write(token[i]);
      final bool isLast = i == token.length - 1;
      if (!isLast && (i + 1) % 10 == 0) {
        buffer.write(_softWrapHint);
      }
    }
    return buffer.toString();
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          CircleAvatar(
            radius: 15,
            backgroundColor: color.secondaryContainer,
            child: AppSvgIcon(
              AppSvgAsset.aiChatSparkles,
              size: 15,
              color: color.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color.surfaceContainerHighest.withValues(alpha: 0.52),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomRight: Radius.circular(22),
                bottomLeft: Radius.circular(8),
              ),
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
