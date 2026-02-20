import "dart:async";
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "assistant/assistant_intent_bridge.dart";
import "../features/chat/chat_page.dart";
import "../features/community/community_page.dart";
import "../features/market/market_page.dart";
import "../features/recording/recording_page.dart";
import "../features/report/report_page.dart";
import "../features/settings/child_profile_page.dart";
import "../features/settings/settings_page.dart";
import "config/session_store.dart";
import "i18n/app_i18n.dart";
import "network/babyai_api.dart";
import "theme/app_theme_controller.dart";
import "widgets/app_svg_icon.dart";

class BabyAIApp extends StatefulWidget {
  const BabyAIApp({super.key});

  @override
  State<BabyAIApp> createState() => _BabyAIAppState();
}

class _BabyAIAppState extends State<BabyAIApp> {
  final AppThemeController _themeController = AppThemeController();
  bool _appReady = false;
  bool _showLaunchSplash = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await AppSessionStore.load();
    await _themeController.load();
    if (mounted) {
      setState(() => _appReady = true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() => _showLaunchSplash = false);
    }
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  TextTheme _buildTextTheme(TextTheme base) {
    final String highlightFamily = _themeController.highlightFontFamily;

    TextStyle? highlight(TextStyle? style) {
      if (style == null) {
        return null;
      }
      return style.copyWith(
        fontFamily: highlightFamily,
        fontWeight: FontWeight.w700,
      );
    }

    return base.copyWith(
      displayLarge: highlight(base.displayLarge),
      displayMedium: highlight(base.displayMedium),
      displaySmall: highlight(base.displaySmall),
      headlineLarge: highlight(base.headlineLarge),
      headlineMedium: highlight(base.headlineMedium),
      headlineSmall: highlight(base.headlineSmall),
      titleLarge: highlight(base.titleLarge),
      titleMedium: highlight(base.titleMedium),
      labelLarge: highlight(base.labelLarge),
    );
  }

  ThemeData _buildTheme({required Brightness brightness}) {
    final String mainFontFamily = _themeController.mainFontFamily;
    final ColorScheme colorScheme = brightness == Brightness.light
        ? const ColorScheme(
            brightness: Brightness.light,
            primary: Color(0xFFE4B347),
            onPrimary: Color(0xFFFFFFFF),
            secondary: Color(0xFF8A7B66),
            onSecondary: Color(0xFFFFFFFF),
            error: Color(0xFFB3261E),
            onError: Color(0xFFFFFFFF),
            surface: Color(0xFFF7F4EF),
            onSurface: Color(0xFF2D2924),
            surfaceContainerHighest: Color(0xFFEFE8DE),
            onSurfaceVariant: Color(0xFF7F7467),
            outline: Color(0xFFD8CFC4),
          )
        : ColorScheme.fromSeed(
            seedColor: _themeController.seedColorFor(brightness),
            brightness: brightness,
          );
    final ThemeData base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: mainFontFamily.isEmpty ? null : mainFontFamily,
    );
    final TextTheme textTheme = _buildTextTheme(base.textTheme);
    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: brightness == Brightness.dark
            ? const Color(0xFF151922)
            : const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF090B10)
          : const Color(0xFFF1F1F1),
      navigationBarTheme: NavigationBarThemeData(
        height: 50,
        backgroundColor: brightness == Brightness.dark
            ? colorScheme.surface
            : const Color(0xFFF9F8F6),
        indicatorColor: colorScheme.primary.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (Set<WidgetState> states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Locale _localeFromLanguage(AppLanguage language) {
    switch (language) {
      case AppLanguage.ko:
        return const Locale("ko");
      case AppLanguage.en:
        return const Locale("en");
      case AppLanguage.es:
        return const Locale("es");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_appReady || _showLaunchSplash) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _LaunchSplashScreen(),
      );
    }

    return AppSettingsScope(
      controller: _themeController,
      child: AnimatedBuilder(
        animation: _themeController,
        builder: (BuildContext context, _) {
          return MaterialApp(
            title: "BabyAI",
            debugShowCheckedModeBanner: false,
            themeMode: _themeController.themeMode,
            locale: _localeFromLanguage(_themeController.language),
            theme: _buildTheme(brightness: Brightness.light),
            darkTheme: _buildTheme(brightness: Brightness.dark),
            home: _HomeShell(themeController: _themeController),
          );
        },
      ),
    );
  }
}

class _LaunchSplashScreen extends StatefulWidget {
  const _LaunchSplashScreen();

  @override
  State<_LaunchSplashScreen> createState() => _LaunchSplashScreenState();
}

class _LaunchSplashScreenState extends State<_LaunchSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ScaleTransition(
          scale: _scale,
          child: Image.asset(
            "assets/icons/app_logo.png",
            width: 148,
            height: 148,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell({required this.themeController});

  final AppThemeController themeController;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  static const int _homePage = 0;
  static const int _chatPage = 1;
  static const int _statisticsPage = 2;
  static const int _photosPage = 3;
  static const int _marketPage = 4;
  static const int _communityPage = 5;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<RecordingPageState> _recordPageKey =
      GlobalKey<RecordingPageState>();
  final GlobalKey<ChatPageState> _chatPageKey = GlobalKey<ChatPageState>();
  final GlobalKey<ReportPageState> _reportPageKey =
      GlobalKey<ReportPageState>();
  StreamSubscription<AssistantActionPayload>? _assistantSubscription;
  AssistantActionPayload? _pendingAssistantAction;

  int _index = 0;
  bool _isGoogleLoggedIn = false;
  bool _isBusinessAccount = false;
  String _accountName = "Google account";
  String _accountEmail = "Not connected";
  bool _chatHistoryLoading = false;
  String? _chatHistoryError;
  List<_ChatHistoryItem> _chatHistory = <_ChatHistoryItem>[];
  String? _selectedChatSessionId;
  String _homeBabyName = "우리 아기";
  String? _homeBabyPhotoUrl;
  final Set<String> _pinnedChatSessionIds = <String>{};
  final Set<String> _hiddenChatSessionIds = <String>{};
  final Map<String, String> _chatRenamedTitles = <String, String>{};

  ReportRange _reportRange = ReportRange.daily;
  DateTime _sharedScopeAnchorDateLocal = DateTime.now();
  MarketSection _marketSection = MarketSection.used;
  CommunitySection _communitySection = CommunitySection.free;

  @override
  void initState() {
    super.initState();
    _sharedScopeAnchorDateLocal =
        _normalizeScopeAnchorForRange(_reportRange, DateTime.now());
    _bootstrapAccountFromToken();
    _initializeAssistantBridge();
    if (BabyAIApi.activeBabyId.isNotEmpty) {
      unawaited(_loadChatHistory());
    }
  }

  @override
  void dispose() {
    _assistantSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeAssistantBridge() async {
    await AssistantIntentBridge.initialize();
    _assistantSubscription = AssistantIntentBridge.stream.listen(
      _handleAssistantAction,
    );
  }

  void _handleAssistantAction(AssistantActionPayload payload) {
    if (!mounted) {
      return;
    }
    if (BabyAIApi.activeBabyId.isEmpty) {
      _pendingAssistantAction = payload;
      return;
    }
    _processAssistantAction(payload);
  }

  void _flushPendingAssistantActionIfAny() {
    final AssistantActionPayload? payload = _pendingAssistantAction;
    if (payload == null || !mounted || BabyAIApi.activeBabyId.isEmpty) {
      return;
    }
    _pendingAssistantAction = null;
    _processAssistantAction(payload);
  }

  HomeTileType? _tileFromFeature(String? feature) {
    if (feature == null) {
      return null;
    }
    switch (feature.trim().toLowerCase()) {
      case "formula":
        return HomeTileType.formula;
      case "breastfeed":
      case "breastfeeding":
        return HomeTileType.breastfeed;
      case "weaning":
      case "solid":
        return HomeTileType.weaning;
      case "diaper":
      case "pee":
      case "poo":
        return HomeTileType.diaper;
      case "sleep":
        return HomeTileType.sleep;
      case "medication":
      case "medicine":
        return HomeTileType.medication;
      case "memo":
      case "note":
        return HomeTileType.memo;
      default:
        return null;
    }
  }

  HomeTileType? _tileFromQuery(String? query) {
    if (query == null) {
      return null;
    }
    final String text = query.toLowerCase();
    if (text.contains("formula") || text.contains("분유")) {
      return HomeTileType.formula;
    }
    if (text.contains("breast") || text.contains("모유")) {
      return HomeTileType.breastfeed;
    }
    if (text.contains("weaning") ||
        text.contains("solid") ||
        text.contains("이유식")) {
      return HomeTileType.weaning;
    }
    if (text.contains("diaper") ||
        text.contains("pee") ||
        text.contains("poo") ||
        text.contains("기저귀") ||
        text.contains("소변") ||
        text.contains("대변") ||
        text.contains("오줌") ||
        text.contains("응가") ||
        text.contains("똥")) {
      return HomeTileType.diaper;
    }
    if (text.contains("sleep") ||
        text.contains("잠") ||
        text.contains("수면") ||
        text.contains("기상")) {
      return HomeTileType.sleep;
    }
    if (text.contains("medication") ||
        text.contains("medicine") ||
        text.contains("투약") ||
        text.contains("약")) {
      return HomeTileType.medication;
    }
    if (text.contains("memo") || text.contains("note") || text.contains("메모")) {
      return HomeTileType.memo;
    }
    return null;
  }

  bool _containsAny(String text, List<String> keywords) {
    for (final String keyword in keywords) {
      if (text.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  bool _hasRecordIntent(String? query) {
    if (query == null) {
      return false;
    }
    final String text = query.toLowerCase();
    return _containsAny(text, <String>[
      "기록",
      "저장",
      "추가",
      "입력",
      "등록",
      "record",
      "log",
      "save",
      "add",
      "track",
    ]);
  }

  int? _extractAmountMlFromText(String? text) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    final RegExpMatch? match = RegExp(
      r"(\d{1,4})\s*(ml|mL|ML|cc|㎖|밀리)",
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
      r"(\d{1,2})\s*(시간|hour|hours|hr|hrs)",
      caseSensitive: false,
    );
    final RegExp minuteRegExp = RegExp(
      r"(\d{1,3})\s*(분|min|mins|minute|minutes)",
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

  _AssistantRecordAction _buildAssistantRecordAction(
    AssistantActionPayload payload,
  ) {
    final String normalizedFeature =
        (payload.feature ?? "").trim().toLowerCase();
    final String? normalizedQuery =
        payload.query?.trim().isEmpty ?? true ? null : payload.query!.trim();
    final String queryLower = normalizedQuery?.toLowerCase() ?? "";
    final Map<String, dynamic> prefill =
        Map<String, dynamic>.from(payload.asPrefillMap());

    if (normalizedFeature == "chat") {
      return _AssistantRecordAction(
        routeToChat: true,
        chatPrompt: normalizedQuery,
      );
    }

    final int? amountMl =
        payload.amountMl ?? _extractAmountMlFromText(normalizedQuery);
    if (amountMl != null && amountMl > 0) {
      prefill["amount_ml"] = amountMl;
    }

    HomeTileType? tile =
        _tileFromFeature(normalizedFeature) ?? _tileFromQuery(normalizedQuery);
    if (tile == null && amountMl != null && amountMl > 0) {
      tile = HomeTileType.formula;
    }
    if (tile == null) {
      final bool looksLikeRecordCommand = _hasRecordIntent(normalizedQuery) ||
          (normalizedQuery?.toLowerCase().contains("ml") ?? false);
      return _AssistantRecordAction(
        routeToChat: looksLikeRecordCommand ? false : normalizedQuery != null,
        chatPrompt: normalizedQuery,
      );
    }

    if (normalizedFeature == "pee") {
      prefill["diaper_type"] = "PEE";
    } else if (normalizedFeature == "poo") {
      prefill["diaper_type"] = "POO";
    }

    final int? durationMin =
        payload.durationMin ?? _extractDurationMinFromText(normalizedQuery);
    if (durationMin != null && durationMin > 0) {
      prefill["duration_min"] = durationMin;
    }

    if (tile == HomeTileType.diaper && !prefill.containsKey("diaper_type")) {
      if (_containsAny(
          queryLower, <String>["대변", "응가", "똥", "poo", "poop", "stool"])) {
        prefill["diaper_type"] = "POO";
      } else if (_containsAny(
          queryLower, <String>["소변", "오줌", "pee", "urine"])) {
        prefill["diaper_type"] = "PEE";
      }
    }

    if (tile == HomeTileType.sleep) {
      if (_containsAny(queryLower, <String>[
        "수면시작",
        "잠시작",
        "재우기 시작",
        "잠들",
        "sleep start",
        "start sleep",
      ])) {
        prefill["sleep_action"] = "start";
      } else if (_containsAny(queryLower, <String>[
        "수면종료",
        "잠종료",
        "기상",
        "깼",
        "wake",
        "woke",
        "sleep end",
        "stop sleep",
      ])) {
        prefill["sleep_action"] = "end";
      }
    }

    String medicationName =
        (prefill["medication_name"] ?? prefill["memo"] ?? normalizedQuery ?? "")
            .toString()
            .trim();
    if (tile == HomeTileType.medication && medicationName.isNotEmpty) {
      prefill["medication_name"] = medicationName;
    }

    bool autoSubmit =
        normalizedFeature.isNotEmpty || _hasRecordIntent(normalizedQuery);
    if (tile == HomeTileType.formula && !prefill.containsKey("amount_ml")) {
      autoSubmit = false;
    }
    if (tile == HomeTileType.diaper && !prefill.containsKey("diaper_type")) {
      autoSubmit = false;
    }
    if (tile == HomeTileType.sleep &&
        !prefill.containsKey("sleep_action") &&
        !prefill.containsKey("duration_min")) {
      autoSubmit = false;
    }
    if (tile == HomeTileType.medication) {
      medicationName = (prefill["medication_name"] ??
              prefill["memo"] ??
              normalizedQuery ??
              "")
          .toString()
          .trim();
      if (medicationName.isEmpty) {
        autoSubmit = false;
      } else {
        prefill["medication_name"] = medicationName;
      }
    }

    return _AssistantRecordAction(
      tile: tile,
      prefill: prefill,
      autoSubmit: autoSubmit,
    );
  }

  void _processAssistantAction(AssistantActionPayload payload) {
    final _AssistantRecordAction action = _buildAssistantRecordAction(payload);

    if (!action.routeToChat &&
        action.tile == null &&
        (_hasRecordIntent(action.chatPrompt) ||
            (action.chatPrompt?.toLowerCase().contains("ml") ?? false))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Record command was not parsed. Try: formula 120ml record.",
          ),
        ),
      );
      return;
    }

    if (action.routeToChat) {
      setState(() => _index = _chatPage);
      if (action.chatPrompt != null && action.chatPrompt!.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _chatPageKey.currentState?.sendAssistantPrompt(action.chatPrompt!);
        });
      }
      return;
    }

    final HomeTileType? tile = action.tile;
    if (tile == null) {
      return;
    }

    setState(() => _index = _homePage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recordPageKey.currentState?.openQuickEntryFromExternal(
        tile,
        prefill: action.prefill,
        autoSubmit: action.autoSubmit,
      );
    });
  }

  // ignore: unused_element
  String _labelForIndex(BuildContext context, int index) {
    switch (index) {
      case _homePage:
        return tr(context, ko: "홈", en: "Home", es: "Inicio");
      case _chatPage:
        return tr(context, ko: "AI 채팅", en: "AI Chat", es: "Chat IA");
      case _statisticsPage:
        return tr(context, ko: "통계", en: "Statistics", es: "Estadisticas");
      case _photosPage:
        return tr(context, ko: "사진", en: "Photos", es: "Fotos");
      case _marketPage:
        return tr(context, ko: "장터", en: "Market", es: "Mercado");
      case _communityPage:
        return tr(context, ko: "커뮤니티", en: "Community", es: "Comunidad");
      default:
        return "";
    }
  }

  // ignore: unused_element
  void _selectIndex(int next) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    _setIndex(next);
  }

  void _setIndex(int next) {
    setState(() => _index = next);
    if (next == _homePage) {
      unawaited(_recordPageKey.currentState?.refreshData());
    }
  }

  Future<void> _loadChatHistory() async {
    if (BabyAIApi.activeBabyId.isEmpty) {
      return;
    }
    if (mounted) {
      setState(() {
        _chatHistoryLoading = true;
        _chatHistoryError = null;
      });
    }

    try {
      final Map<String, dynamic> payload = await BabyAIApi.instance
          .getChatSessions(childId: BabyAIApi.activeBabyId, limit: 50);
      final List<dynamic> rawSessions =
          (payload["sessions"] as List<dynamic>? ?? <dynamic>[]);
      final List<_ChatHistoryItem> parsed = <_ChatHistoryItem>[];
      for (final dynamic item in rawSessions) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final String sessionId = (item["session_id"] ?? "").toString().trim();
        if (sessionId.isEmpty) {
          continue;
        }
        if (_hiddenChatSessionIds.contains(sessionId)) {
          continue;
        }
        final String title = (item["title"] ?? "").toString().trim();
        final String preview = (item["preview"] ?? "").toString().trim();
        final DateTime updatedAt = DateTime.tryParse(
              (item["updated_at"] ?? DateTime.now().toIso8601String())
                  .toString(),
            ) ??
            DateTime.now();
        parsed.add(
          _ChatHistoryItem(
            sessionId: sessionId,
            title: _chatRenamedTitles[sessionId]?.trim().isNotEmpty == true
                ? _chatRenamedTitles[sessionId]!
                : (title.isEmpty ? "New conversation" : title),
            preview: preview,
            updatedAt: updatedAt,
          ),
        );
      }
      parsed.sort((_ChatHistoryItem a, _ChatHistoryItem b) {
        final bool aPinned = _pinnedChatSessionIds.contains(a.sessionId);
        final bool bPinned = _pinnedChatSessionIds.contains(b.sessionId);
        if (aPinned != bPinned) {
          return aPinned ? -1 : 1;
        }
        return b.updatedAt.compareTo(a.updatedAt);
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _chatHistory = parsed;
        final String? selected = _selectedChatSessionId;
        if (selected != null &&
            _chatHistory
                .every((_ChatHistoryItem it) => it.sessionId != selected)) {
          _selectedChatSessionId = null;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _chatHistoryError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _chatHistoryLoading = false);
      }
    }
  }

  String _formatChatHistoryTime(DateTime value) {
    final DateTime local = value.toLocal();
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(local.year, local.month, local.day);
    final String minute = local.minute.toString().padLeft(2, "0");
    if (day == today) {
      return "${local.hour.toString().padLeft(2, "0")}:$minute";
    }
    return "${local.month}/${local.day}";
  }

  _ChatHistoryItem? _chatHistoryItemById(String sessionId) {
    for (final _ChatHistoryItem item in _chatHistory) {
      if (item.sessionId == sessionId) {
        return item;
      }
    }
    return null;
  }

  _ChatHistoryItem? _activeChatSessionItem() {
    final String activeId = (_chatPageKey.currentState?.activeSessionId ??
            _selectedChatSessionId ??
            "")
        .trim();
    if (activeId.isEmpty) {
      return null;
    }
    return _chatHistoryItemById(activeId) ??
        _ChatHistoryItem(
          sessionId: activeId,
          title: _chatPageKey.currentState?.activeThreadTitle ??
              "New conversation",
          preview: "",
          updatedAt: DateTime.now(),
        );
  }

  Future<void> _renameActiveChatFromTopBar() async {
    final String activeId = (_chatPageKey.currentState?.activeSessionId ??
            _selectedChatSessionId ??
            "")
        .trim();
    if (activeId.isEmpty) {
      return;
    }
    final _ChatHistoryItem item = _chatHistoryItemById(activeId) ??
        _ChatHistoryItem(
          sessionId: activeId,
          title: _chatPageKey.currentState?.activeThreadTitle ??
              "New conversation",
          preview: "",
          updatedAt: DateTime.now(),
        );
    await _renameChatSession(item);
  }

  List<PopupMenuEntry<String>> _chatSessionActionMenuItems(
    BuildContext context,
    _ChatHistoryItem item,
  ) {
    final bool pinned = _pinnedChatSessionIds.contains(item.sessionId);
    final ColorScheme color = Theme.of(context).colorScheme;
    return <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: "share",
        child: Row(
          children: <Widget>[
            const Icon(Icons.share_outlined, size: 18),
            const SizedBox(width: 10),
            Text(tr(context, ko: "공유", en: "Share", es: "Compartir")),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: "rename",
        child: Row(
          children: <Widget>[
            const Icon(Icons.drive_file_rename_outline, size: 18),
            const SizedBox(width: 10),
            Text(tr(context, ko: "이름 바꾸기", en: "Rename", es: "Renombrar")),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: "pin",
        child: Row(
          children: <Widget>[
            Icon(
              pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              pinned
                  ? tr(context, ko: "고정 해제", en: "Unpin", es: "Desfijar")
                  : tr(context, ko: "채팅 고정", en: "Pin chat", es: "Fijar chat"),
            ),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: "delete",
        child: Row(
          children: <Widget>[
            Icon(Icons.delete_outline, size: 18, color: color.error),
            const SizedBox(width: 10),
            Text(
              tr(context, ko: "삭제", en: "Delete", es: "Eliminar"),
              style: TextStyle(color: color.error, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _handleChatSessionAction(
    _ChatHistoryItem item,
    String action,
  ) async {
    if (action.isEmpty || !mounted) {
      return;
    }
    switch (action) {
      case "share":
        await Clipboard.setData(
          ClipboardData(text: "babyai://chat/${item.sessionId}"),
        );
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                ko: "채팅 링크를 클립보드에 복사했어요.",
                en: "Chat link copied to clipboard.",
                es: "Enlace copiado al portapapeles.",
              ),
            ),
          ),
        );
        return;
      case "rename":
        await _renameChatSession(item);
        return;
      case "pin":
        setState(() {
          if (_pinnedChatSessionIds.contains(item.sessionId)) {
            _pinnedChatSessionIds.remove(item.sessionId);
          } else {
            _pinnedChatSessionIds.add(item.sessionId);
          }
        });
        await _loadChatHistory();
        return;
      case "delete":
        setState(() {
          _hiddenChatSessionIds.add(item.sessionId);
          _pinnedChatSessionIds.remove(item.sessionId);
          _chatRenamedTitles.remove(item.sessionId);
          if (_selectedChatSessionId == item.sessionId) {
            _selectedChatSessionId = null;
          }
        });
        await _chatPageKey.currentState?.hideSessionLocally(item.sessionId);
        await _loadChatHistory();
        return;
      default:
        return;
    }
  }

  Widget _buildChatSessionPopupButton({
    required _ChatHistoryItem? item,
    required ColorScheme color,
    required double iconSize,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    bool compact = false,
  }) {
    if (item == null) {
      return Container(
        decoration: BoxDecoration(
          color: color.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
        ),
        padding: padding,
        child: Icon(
          Icons.more_vert,
          size: iconSize,
          color: color.onSurfaceVariant.withValues(alpha: 0.42),
        ),
      );
    }
    return PopupMenuButton<String>(
      tooltip: tr(context, ko: "채팅 옵션", en: "Chat options", es: "Opciones"),
      onSelected: (String action) =>
          unawaited(_handleChatSessionAction(item, action)),
      itemBuilder: (BuildContext context) =>
          _chatSessionActionMenuItems(context, item),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: color.surface,
      child: Container(
        decoration: BoxDecoration(
          color: color.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: compact
              ? Border.all(
                  color: color.outlineVariant.withValues(alpha: 0.2),
                )
              : null,
        ),
        padding: padding,
        child: Icon(
          Icons.more_vert,
          size: iconSize,
          color: color.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _renameChatSession(_ChatHistoryItem item) async {
    final TextEditingController controller =
        TextEditingController(text: item.title);
    final String? updated = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(tr(context,
              ko: "채팅 이름 바꾸기", en: "Rename chat", es: "Renombrar chat")),
          content: TextField(
            controller: controller,
            maxLength: 80,
            decoration: InputDecoration(
              hintText:
                  tr(context, ko: "새 이름", en: "New title", es: "Nuevo titulo"),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(context, ko: "취소", en: "Cancel", es: "Cancelar")),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(tr(context, ko: "저장", en: "Save", es: "Guardar")),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final String nextTitle = (updated ?? "").trim();
    if (nextTitle.isEmpty) {
      return;
    }
    setState(() {
      _chatRenamedTitles[item.sessionId] = nextTitle;
    });
    await _chatPageKey.currentState
        ?.applyLocalSessionTitle(item.sessionId, nextTitle);
    await _loadChatHistory();
  }

  void _openChatHistoryDrawer() {
    _scaffoldKey.currentState?.openDrawer();
    unawaited(_loadChatHistory());
  }

  Future<void> _openChatSessionFromDrawer(String sessionId) async {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    setState(() {
      _index = _chatPage;
      _selectedChatSessionId = sessionId;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final ChatPageState? chatState = _chatPageKey.currentState;
    if (chatState != null) {
      await chatState.openSessionById(sessionId);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await _chatPageKey.currentState?.openSessionById(sessionId);
  }

  Future<void> _createNewChatFromDrawer() async {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    setState(() {
      _index = _chatPage;
      _selectedChatSessionId = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final ChatPageState? chatState = _chatPageKey.currentState;
    if (chatState != null) {
      await chatState.createNewConversation();
      unawaited(_loadChatHistory());
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await _chatPageKey.currentState?.createNewConversation();
    unawaited(_loadChatHistory());
  }

  void _onChatHistoryChanged() {
    unawaited(_loadChatHistory());
  }

  List<_BottomMenuTab> _buildBottomTabs() {
    final List<_BottomMenuTab> tabs = <_BottomMenuTab>[
      const _BottomMenuTab(
        pageIndex: _homePage,
        iconData: Icons.home_outlined,
        selectedIconData: Icons.home_rounded,
        label: "home",
      ),
    ];
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.statistics)) {
      tabs.add(const _BottomMenuTab(
        pageIndex: _statisticsPage,
        iconAsset: AppSvgAsset.stats,
        label: "statistics",
      ));
    }
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.chat)) {
      tabs.add(const _BottomMenuTab(
        pageIndex: _chatPage,
        iconAsset: AppSvgAsset.aiChatSparkles,
        label: "chat",
      ));
    }
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.market)) {
      tabs.add(const _BottomMenuTab(
        pageIndex: _marketPage,
        iconAsset: AppSvgAsset.playCar,
        label: "market",
      ));
    }
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.community)) {
      tabs.add(const _BottomMenuTab(
        pageIndex: _communityPage,
        iconAsset: AppSvgAsset.profile,
        label: "community",
      ));
    }
    return tabs;
  }

  Widget _buildCurrentPage() {
    switch (_index) {
      case _homePage:
        return RecordingPage(
          key: _recordPageKey,
          range: RecordRange.day,
          onBabyNameChanged: _onHomeBabyNameChanged,
          onBabyPhotoChanged: _onHomeBabyPhotoChanged,
        );
      case _chatPage:
        return ChatPage(
          key: _chatPageKey,
          onHistoryChanged: _onChatHistoryChanged,
          initialDateMode: _chatModeFromReportRange(_reportRange),
          initialAnchorDateLocal: _sharedScopeAnchorDateLocal,
          onDateScopeChanged: _onChatDateScopeChanged,
        );
      case _statisticsPage:
        return ReportPage(
          key: _reportPageKey,
          initialRange: _reportRange,
          initialFocusDateLocal: _sharedScopeAnchorDateLocal,
        );
      case _photosPage:
        return SettingsPage(
          themeController: widget.themeController,
          isGoogleLoggedIn: _isGoogleLoggedIn,
          accountName: _accountName,
          accountEmail: _accountEmail,
          onGoogleLogin: _loginWithGoogleToken,
          onGoogleLogout: _logout,
          onManageChildProfile: _openChildProfileFromSettings,
        );
      case _marketPage:
        return MarketPage(section: _marketSection);
      case _communityPage:
        return CommunityPage(section: _communitySection);
      default:
        return RecordingPage(
          range: RecordRange.day,
          onBabyNameChanged: _onHomeBabyNameChanged,
          onBabyPhotoChanged: _onHomeBabyPhotoChanged,
        );
    }
  }

  // ignore: unused_element
  Future<void> _openSettings() async {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SettingsPage(
          themeController: widget.themeController,
          isGoogleLoggedIn: _isGoogleLoggedIn,
          accountName: _accountName,
          accountEmail: _accountEmail,
          onGoogleLogin: _loginWithGoogleToken,
          onGoogleLogout: _logout,
          onManageChildProfile: _openChildProfileFromSettings,
        ),
      ),
    );
  }

  Future<void> _openChildProfileFromSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChildProfilePage(
          initialOnboarding: false,
          onCompleted: _handleChildProfileSaved,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleChildProfileSaved(ChildProfileSaveResult result) async {
    BabyAIApi.setRuntimeIds(
      babyId: result.babyId,
      householdId: result.householdId,
    );
    await AppSessionStore.persistRuntimeState();
    _bootstrapAccountFromToken();
    unawaited(_loadChatHistory());
    _flushPendingAssistantActionIfAny();
  }

  Map<String, dynamic> _decodeJwtPayload(String token) {
    try {
      final List<String> parts = token.split(".");
      if (parts.length < 2) {
        return <String, dynamic>{};
      }
      final String normalized = base64Url.normalize(parts[1]);
      final String payload = utf8.decode(base64Url.decode(normalized));
      final Object? parsed = jsonDecode(payload);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  bool _resolveBusinessAccount(Map<String, dynamic> payload) {
    final dynamic raw = payload["account_type"] ??
        payload["plan_type"] ??
        payload["membership"] ??
        payload["workspace_type"] ??
        payload["tenant_type"] ??
        payload["organization_type"] ??
        payload["is_business"];
    if (raw is bool) {
      return raw;
    }

    final String normalized = raw?.toString().trim().toLowerCase() ?? "";
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized == "true") {
      return true;
    }
    if (normalized == "false") {
      return false;
    }
    if (normalized.contains("business") ||
        normalized.contains("enterprise") ||
        normalized.contains("team") ||
        normalized.contains("company") ||
        normalized.contains("organization") ||
        normalized.contains("org") ||
        normalized.contains("biz")) {
      return true;
    }
    return false;
  }

  String _accountTypeLabel(BuildContext context) {
    return _isBusinessAccount
        ? tr(context, ko: "비즈니스", en: "Business", es: "Empresa")
        : tr(context, ko: "개인", en: "Personal", es: "Personal");
  }

  String _accountInitials() {
    final String source = _accountName.trim().isNotEmpty
        ? _accountName.trim()
        : _accountEmail.trim();
    if (source.isEmpty) {
      return "AI";
    }
    final List<String> parts = source.split(RegExp(r"\s+"));
    if (parts.length == 1) {
      final String token = parts.first;
      return token.substring(0, token.length >= 2 ? 2 : 1).toUpperCase();
    }
    final String a = parts.first.isEmpty ? "A" : parts.first[0];
    final String b = parts[1].isEmpty ? "I" : parts[1][0];
    return (a + b).toUpperCase();
  }

  Widget _buildDrawerFooterAccount(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Material(
      color: color.surface,
      child: InkWell(
        onTap: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          _setIndex(_photosPage);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: color.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 20,
                backgroundColor: color.primary.withValues(alpha: 0.16),
                child: Text(
                  _accountInitials(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color.primary,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _accountName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _accountTypeLabel(context),
                      style: TextStyle(
                        fontSize: 14,
                        color: color.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: color.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _bootstrapAccountFromToken() {
    final String token = BabyAIApi.currentBearerToken;
    if (token.trim().isEmpty) {
      setState(() {
        _isGoogleLoggedIn = false;
        _isBusinessAccount = false;
        _accountName = "Google account";
        _accountEmail = "Not connected";
      });
      return;
    }
    final String? provider = BabyAIApi.currentTokenProvider;
    if (provider != "google") {
      setState(() {
        _isGoogleLoggedIn = false;
        _isBusinessAccount = false;
        _accountName = "Local user";
        _accountEmail = "Offline mode";
      });
      return;
    }
    final Map<String, dynamic> payload = _decodeJwtPayload(token);
    final String email =
        (payload["email"] ?? payload["upn"] ?? payload["sub"] ?? "").toString();
    final String name =
        (payload["name"] ?? payload["given_name"] ?? "Google User").toString();
    setState(() {
      _isGoogleLoggedIn = true;
      _isBusinessAccount = _resolveBusinessAccount(payload);
      _accountName = name.trim().isEmpty ? "Google User" : name.trim();
      _accountEmail = email.trim().isEmpty ? "Connected" : email.trim();
    });
  }

  void _clearLinkedProfileState() {
    BabyAIApi.setRuntimeIds(
      babyId: "",
      householdId: "",
      albumId: "",
    );
    _selectedChatSessionId = null;
    _chatHistory = <_ChatHistoryItem>[];
    _homeBabyName = "우리 아기";
    _pinnedChatSessionIds.clear();
    _hiddenChatSessionIds.clear();
    _chatRenamedTitles.clear();
  }

  double? _asNullableDouble(Object? raw) {
    if (raw is num) {
      return raw.toDouble();
    }
    if (raw == null) {
      return null;
    }
    return double.tryParse(raw.toString().trim().replaceAll(",", "."));
  }

  bool? _asNullableBool(Object? raw) {
    if (raw is bool) {
      return raw;
    }
    if (raw == null) {
      return null;
    }
    final String text = raw.toString().trim().toLowerCase();
    if (text == "true" || text == "1" || text == "yes") {
      return true;
    }
    if (text == "false" || text == "0" || text == "no") {
      return false;
    }
    return null;
  }

  Future<void> _promoteOfflineProfileAfterGoogleLogin() async {
    if (!BabyAIApi.isGoogleLinked) {
      return;
    }
    final String localBabyId = BabyAIApi.activeBabyId.trim();
    if (!localBabyId.toLowerCase().startsWith("offline_")) {
      return;
    }
    try {
      final Map<String, dynamic> profile =
          await BabyAIApi.instance.getBabyProfile();
      final String babyName =
          (profile["baby_name"] ?? "우리 아기").toString().trim();
      final String birthDateRaw =
          (profile["birth_date"] ?? "").toString().trim();
      final String birthDate = birthDateRaw.isEmpty
          ? DateTime.now().toIso8601String().split("T").first
          : birthDateRaw;
      final String babySex = (profile["sex"] ?? "unknown").toString().trim();
      final String feedingMethod =
          (profile["feeding_method"] ?? "mixed").toString().trim();
      final String formulaBrand =
          (profile["formula_brand"] ?? "").toString().trim();
      final String formulaProduct =
          (profile["formula_product"] ?? "").toString().trim();
      final String formulaType =
          (profile["formula_type"] ?? "standard").toString().trim();
      final double? weight = _asNullableDouble(profile["weight_kg"]);
      final bool formulaContainsStarch =
          _asNullableBool(profile["formula_contains_starch"]) ?? false;

      final Map<String, dynamic> remote =
          await BabyAIApi.instance.onboardingParent(
        provider: "google",
        babyName: babyName,
        babyBirthDate: birthDate,
        babySex: babySex,
        babyWeightKg: weight,
        feedingMethod: feedingMethod,
        formulaBrand: formulaBrand,
        formulaProduct: formulaProduct,
        formulaType: formulaType,
        formulaContainsStarch: formulaContainsStarch,
      );
      final String remoteBabyId = (remote["baby_id"] ?? "").toString().trim();
      final String remoteHouseholdId =
          (remote["household_id"] ?? "").toString().trim();
      if (remoteBabyId.isEmpty || remoteHouseholdId.isEmpty) {
        return;
      }
      BabyAIApi.setRuntimeIds(
        babyId: remoteBabyId,
        householdId: remoteHouseholdId,
      );
      await BabyAIApi.instance.upsertBabyProfile(
        babyName: babyName,
        babyBirthDate: birthDate,
        babySex: babySex,
        babyWeightKg: weight,
        feedingMethod: feedingMethod,
        formulaBrand: formulaBrand,
        formulaProduct: formulaProduct,
        formulaType: formulaType,
        formulaContainsStarch: formulaContainsStarch,
      );
    } catch (_) {
      // Keep local mode when online promotion fails.
    }
  }

  Future<void> _loginWithGoogleToken() async {
    final TextEditingController tokenController = TextEditingController();
    final TextEditingController emailController = TextEditingController();
    final TextEditingController nameController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(tr(context,
              ko: "구글 로그인", en: "Google Login", es: "Inicio de Google")),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: tokenController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: "JWT Token",
                    hintText: "Paste server-issued token",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: tr(context,
                        ko: "이름 (선택)",
                        en: "Name (optional)",
                        es: "Nombre (opcional)"),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: tr(context,
                        ko: "이메일 (선택)",
                        en: "Email (optional)",
                        es: "Correo (opcional)"),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(context, ko: "취소", en: "Cancel", es: "Cancelar")),
            ),
            FilledButton(
              onPressed: () async {
                final String token = tokenController.text.trim();
                final String previousToken =
                    BabyAIApi.currentBearerToken.trim();
                if (token.isNotEmpty) {
                  BabyAIApi.setBearerToken(token);
                  final bool changedToken = token != previousToken;
                  if (changedToken &&
                      BabyAIApi.activeBabyId.isNotEmpty &&
                      !BabyAIApi.activeBabyId
                          .toLowerCase()
                          .startsWith("offline_")) {
                    _clearLinkedProfileState();
                  }
                }
                await _promoteOfflineProfileAfterGoogleLogin();
                if (!mounted || !context.mounted) {
                  return;
                }
                final String name = nameController.text.trim();
                final String email = emailController.text.trim();
                final Map<String, dynamic> payload = _decodeJwtPayload(token);
                final bool isGoogle = BabyAIApi.isGoogleLinked;
                setState(() {
                  _isGoogleLoggedIn = isGoogle;
                  _isBusinessAccount = _resolveBusinessAccount(payload);
                  _accountName = name.isNotEmpty
                      ? name
                      : ((payload["name"] ??
                              payload["given_name"] ??
                              "Google User")
                          .toString());
                  _accountEmail = email.isNotEmpty
                      ? email
                      : ((payload["email"] ??
                              payload["upn"] ??
                              payload["sub"] ??
                              "Connected")
                          .toString());
                });
                unawaited(AppSessionStore.persistRuntimeState());
                Navigator.of(context).pop();
              },
              child: Text(tr(context, ko: "로그인", en: "Login", es: "Entrar")),
            ),
          ],
        );
      },
    );

    tokenController.dispose();
    emailController.dispose();
    nameController.dispose();
  }

  void _logout() {
    BabyAIApi.setBearerToken("");
    _clearLinkedProfileState();
    setState(() {
      _isGoogleLoggedIn = false;
      _isBusinessAccount = false;
      _accountName = "Google account";
      _accountEmail = "Not connected";
    });
    unawaited(AppSessionStore.persistRuntimeState());
  }

  DateTime _dateOnlyLocal(DateTime value) {
    final DateTime local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  DateTime _normalizeScopeAnchorForRange(ReportRange range, DateTime value) {
    final DateTime local = _dateOnlyLocal(value);
    switch (range) {
      case ReportRange.daily:
        return local;
      case ReportRange.weekly:
        return local.subtract(Duration(days: local.weekday - DateTime.monday));
      case ReportRange.monthly:
        return DateTime(local.year, local.month, 1);
    }
  }

  ChatDateMode _chatModeFromReportRange(ReportRange range) {
    switch (range) {
      case ReportRange.daily:
        return ChatDateMode.day;
      case ReportRange.weekly:
        return ChatDateMode.week;
      case ReportRange.monthly:
        return ChatDateMode.month;
    }
  }

  ReportRange _reportRangeFromChatMode(ChatDateMode mode) {
    switch (mode) {
      case ChatDateMode.day:
        return ReportRange.daily;
      case ChatDateMode.week:
        return ReportRange.weekly;
      case ChatDateMode.month:
        return ReportRange.monthly;
    }
  }

  String _scopeDateLabel(ReportRange range, DateTime anchorDateLocal) {
    String ymd(DateTime day) {
      return "${day.year.toString().padLeft(4, "0")}-"
          "${day.month.toString().padLeft(2, "0")}-"
          "${day.day.toString().padLeft(2, "0")}";
    }

    final DateTime anchor =
        _normalizeScopeAnchorForRange(range, anchorDateLocal);
    switch (range) {
      case ReportRange.daily:
        return ymd(anchor);
      case ReportRange.weekly:
        final DateTime end = anchor.add(const Duration(days: 6));
        return "${ymd(anchor)} ~ ${ymd(end)}";
      case ReportRange.monthly:
        return "${anchor.year.toString().padLeft(4, "0")}-"
            "${anchor.month.toString().padLeft(2, "0")}";
    }
  }

  Future<void> _syncReportStateWithSharedScope() async {
    final ReportPageState? reportState = _reportPageKey.currentState;
    if (reportState == null) {
      return;
    }
    reportState.setRange(_reportRange);
    switch (_reportRange) {
      case ReportRange.daily:
        await reportState.setFocusDate(_sharedScopeAnchorDateLocal);
      case ReportRange.weekly:
        await reportState.setFocusWeekStart(_sharedScopeAnchorDateLocal);
      case ReportRange.monthly:
        await reportState.setFocusMonthStart(_sharedScopeAnchorDateLocal);
    }
  }

  void _applySharedScope(
    ReportRange range,
    DateTime anchorDateLocal, {
    bool syncReportState = true,
    bool syncChatState = true,
  }) {
    final DateTime normalizedAnchor =
        _normalizeScopeAnchorForRange(range, anchorDateLocal);
    if (mounted) {
      setState(() {
        _reportRange = range;
        _sharedScopeAnchorDateLocal = normalizedAnchor;
      });
    }
    if (syncReportState) {
      unawaited(_syncReportStateWithSharedScope());
    }
    if (syncChatState) {
      unawaited(_chatPageKey.currentState?.applyDateScope(
        ChatDateScope(
          mode: _chatModeFromReportRange(range),
          anchorDateLocal: normalizedAnchor,
        ),
      ));
    }
  }

  void _onChatDateScopeChanged(ChatDateScope scope) {
    final ReportRange range = _reportRangeFromChatMode(scope.mode);
    _applySharedScope(range, scope.anchorDateLocal, syncChatState: false);
  }

  void _setReportRange(ReportRange next) {
    _applySharedScope(next, _sharedScopeAnchorDateLocal);
  }

  void _onHomeBabyNameChanged(String name) {
    final String normalized = name.trim();
    if (normalized.isEmpty || normalized == _homeBabyName) {
      return;
    }
    if (mounted) {
      setState(() => _homeBabyName = normalized);
    }
  }

  void _onHomeBabyPhotoChanged(String? photoUrl) {
    final String trimmed = (photoUrl ?? "").trim();
    final String? normalized = trimmed.isEmpty ? null : trimmed;
    if (normalized == _homeBabyPhotoUrl) {
      return;
    }
    if (mounted) {
      setState(() => _homeBabyPhotoUrl = normalized);
    }
  }

  Widget _buildHomeBabyAvatar(BuildContext context) {
    final String? photoUrl = _homeBabyPhotoUrl;
    if (photoUrl == null || photoUrl.isEmpty) {
      return const CircleAvatar(
        radius: 11,
        backgroundColor: Color(0xFFFFF2D9),
        child: AppSvgIcon(AppSvgAsset.profile, size: 12),
      );
    }
    return CircleAvatar(
      radius: 11,
      backgroundColor: const Color(0xFFFFF2D9),
      child: ClipOval(
        child: Image.network(
          photoUrl,
          width: 22,
          height: 22,
          fit: BoxFit.cover,
          errorBuilder: (BuildContext _, Object __, StackTrace? ___) {
            return const SizedBox(
              width: 22,
              height: 22,
              child: Center(
                child: AppSvgIcon(AppSvgAsset.profile, size: 12),
              ),
            );
          },
        ),
      ),
    );
  }

  String _todayYmdLabel() {
    final DateTime now = DateTime.now();
    final String y = now.year.toString().padLeft(4, "0");
    final String m = now.month.toString().padLeft(2, "0");
    final String d = now.day.toString().padLeft(2, "0");
    return "$y-$m-$d";
  }

  String _topBarDateLabel() {
    if (_index == _statisticsPage) {
      final String? reportLabel =
          _reportPageKey.currentState?.navigationDateLabel;
      if (reportLabel != null && reportLabel.trim().isNotEmpty) {
        return reportLabel.trim();
      }
      return _scopeDateLabel(_reportRange, _sharedScopeAnchorDateLocal);
    }
    if (_index == _chatPage) {
      return _scopeDateLabel(_reportRange, _sharedScopeAnchorDateLocal);
    }
    return _todayYmdLabel();
  }

  Future<void> _pickStatisticsDateFromTopBar() async {
    if (_index != _statisticsPage && _index != _chatPage) {
      return;
    }
    final ReportPageState? reportState = _reportPageKey.currentState;
    final ReportRange range = _reportRange;
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(now.year - 12, 1, 1);
    final DateTime lastDate = DateTime(now.year + 3, 12, 31);
    final DateTime rawInitial = _normalizeScopeAnchorForRange(
      range,
      reportState?.datePickerInitialDateLocal ?? _sharedScopeAnchorDateLocal,
    );
    final DateTime initialDate = rawInitial.isBefore(firstDate)
        ? firstDate
        : (rawInitial.isAfter(lastDate) ? lastDate : rawInitial);
    final bool Function(DateTime)? selectableDayPredicate;
    switch (range) {
      case ReportRange.daily:
        selectableDayPredicate = null;
      case ReportRange.weekly:
        selectableDayPredicate =
            (DateTime day) => day.weekday == DateTime.monday;
      case ReportRange.monthly:
        selectableDayPredicate = (DateTime day) => day.day == 1;
    }
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      selectableDayPredicate: selectableDayPredicate,
      helpText: tr(
        context,
        ko: range == ReportRange.weekly
            ? "주 선택 (월요일)"
            : range == ReportRange.monthly
                ? "월 선택 (1일)"
                : "날짜 선택",
        en: range == ReportRange.weekly
            ? "Choose week (Monday)"
            : range == ReportRange.monthly
                ? "Choose month (day 1)"
                : "Choose date",
        es: range == ReportRange.weekly
            ? "Elegir semana (lunes)"
            : range == ReportRange.monthly
                ? "Elegir mes (dia 1)"
                : "Elegir fecha",
      ),
    );
    if (!mounted || picked == null) {
      return;
    }
    _applySharedScope(range, picked);
  }

  Widget _buildHeaderControls(BuildContext context) {
    switch (_index) {
      case _homePage:
        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(
                  alpha: 0.45,
                ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildHomeBabyAvatar(context),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _homeBabyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      case _photosPage:
        return const _HeaderHint(label: "Settings");
      case _marketPage:
        return Wrap(
          spacing: 8,
          children: <Widget>[
            _HeaderChoice(
              selected: _marketSection == MarketSection.used,
              label: "Used",
              onTap: () => setState(() => _marketSection = MarketSection.used),
            ),
            _HeaderChoice(
              selected: _marketSection == MarketSection.newProduct,
              label: "New",
              onTap: () =>
                  setState(() => _marketSection = MarketSection.newProduct),
            ),
            _HeaderChoice(
              selected: _marketSection == MarketSection.promotion,
              label: "Promo",
              onTap: () =>
                  setState(() => _marketSection = MarketSection.promotion),
            ),
          ],
        );
      case _communityPage:
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              _HeaderChoice(
                selected: _communitySection == CommunitySection.free,
                label: "Free",
                onTap: () =>
                    setState(() => _communitySection = CommunitySection.free),
              ),
              const SizedBox(width: 8),
              _HeaderChoice(
                selected: _communitySection == CommunitySection.reviews,
                label: "Reviews",
                onTap: () => setState(
                    () => _communitySection = CommunitySection.reviews),
              ),
              const SizedBox(width: 8),
              _HeaderChoice(
                selected: _communitySection == CommunitySection.jobs,
                label: "Jobs",
                onTap: () =>
                    setState(() => _communitySection = CommunitySection.jobs),
              ),
              const SizedBox(width: 8),
              _HeaderChoice(
                selected: _communitySection == CommunitySection.servicePromo,
                label: "Service",
                onTap: () => setState(
                    () => _communitySection = CommunitySection.servicePromo),
              ),
              const SizedBox(width: 8),
              _HeaderChoice(
                selected: _communitySection == CommunitySection.suggestions,
                label: "Suggest",
                onTap: () => setState(
                    () => _communitySection = CommunitySection.suggestions),
              ),
            ],
          ),
        );
      case _statisticsPage:
        final ReportRange selectedRange =
            _reportPageKey.currentState?.selectedRange ?? _reportRange;
        return Wrap(
          spacing: 5,
          children: <Widget>[
            _HeaderChoice(
              selected: selectedRange == ReportRange.daily,
              label: tr(context, ko: "일", en: "Day", es: "Dia"),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              onTap: () => _setReportRange(ReportRange.daily),
            ),
            _HeaderChoice(
              selected: selectedRange == ReportRange.weekly,
              label: tr(context, ko: "주", en: "Week", es: "Semana"),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              onTap: () => _setReportRange(ReportRange.weekly),
            ),
            _HeaderChoice(
              selected: selectedRange == ReportRange.monthly,
              label: tr(context, ko: "월", en: "Month", es: "Mes"),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              onTap: () => _setReportRange(ReportRange.monthly),
            ),
          ],
        );
      case _chatPage:
      default:
        final String chatTitle =
            (_chatPageKey.currentState?.activeThreadTitle ?? "").trim();
        return _HeaderHint(
          label: chatTitle.isNotEmpty
              ? chatTitle
              : tr(context, ko: "대화", en: "Conversation", es: "Conversacion"),
          onTap: () => unawaited(_renameActiveChatFromTopBar()),
          showEditIcon: true,
        );
    }
  }

  PreferredSizeWidget _buildTopBar(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    final String ymd = _topBarDateLabel();
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 52,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              color.surface.withValues(alpha: 1.0),
              color.surface.withValues(alpha: 0.0),
            ],
            stops: const <double>[0, 1],
          ),
        ),
      ),
      titleSpacing: 12,
      title: Row(
        children: <Widget>[
          _RoundTopButton(icon: Icons.menu, onTap: _openChatHistoryDrawer),
          const SizedBox(width: 8),
          Expanded(child: _buildHeaderControls(context)),
          if (_index == _chatPage) ...<Widget>[
            const SizedBox(width: 6),
            _RoundTopButton(
              icon: Icons.edit_square,
              onTap: () => unawaited(_createNewChatFromDrawer()),
            ),
            const SizedBox(width: 4),
            _buildChatSessionPopupButton(
              item: _activeChatSessionItem(),
              color: color,
              iconSize: 20,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ],
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: (_index == _statisticsPage || _index == _chatPage)
                  ? () => unawaited(_pickStatisticsDateFromTopBar())
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      ymd,
                      style: TextStyle(
                        color: color.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_index == _statisticsPage ||
                        _index == _chatPage) ...<Widget>[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: color.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomTabIcon(
    _BottomMenuTab tab, {
    required Color color,
    required bool selected,
  }) {
    final String? iconAsset = tab.iconAsset;
    if (iconAsset != null) {
      return AppSvgIcon(
        iconAsset,
        size: 20,
        color: color,
      );
    }

    final IconData? fallbackIcon = tab.iconData;
    final IconData icon = selected
        ? (tab.selectedIconData ?? fallbackIcon ?? Icons.circle_outlined)
        : (fallbackIcon ?? Icons.circle_outlined);
    return Icon(icon, size: 20, color: color);
  }

  @override
  Widget build(BuildContext context) {
    if (BabyAIApi.activeBabyId.isEmpty) {
      return ChildProfilePage(
        initialOnboarding: true,
        onCompleted: (ChildProfileSaveResult result) async {
          await _handleChildProfileSaved(result);
          if (mounted) {
            setState(() {});
          }
        },
      );
    }

    final ColorScheme color = Theme.of(context).colorScheme;
    final List<_BottomMenuTab> bottomTabs = _buildBottomTabs();
    final int selectedBottomIndex = bottomTabs.indexWhere(
      (_BottomMenuTab tab) => tab.pageIndex == _index,
    );
    final bool showBottomNav = bottomTabs.isNotEmpty;
    final int selectedBottomIndexResolved =
        selectedBottomIndex >= 0 ? selectedBottomIndex : 0;

    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildTopBar(context),
      drawer: Drawer(
        backgroundColor: color.surface,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
                child: Row(
                  children: <Widget>[
                    const AppSvgIcon(AppSvgAsset.aiChatSparkles, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(context,
                            ko: "채팅 내역", en: "Chat history", es: "Historial"),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _chatHistoryLoading
                          ? null
                          : () => unawaited(_createNewChatFromDrawer()),
                      icon: const Icon(Icons.add_comment_outlined),
                      tooltip: "New conversation",
                    ),
                  ],
                ),
              ),
              if (_chatHistoryError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _chatHistoryError!,
                    style: TextStyle(
                      color: color.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Expanded(
                child: _chatHistoryLoading && _chatHistory.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _chatHistory.isEmpty
                        ? Center(
                            child: Text(
                              "No previous chats yet.",
                              style: TextStyle(
                                color: color.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                            itemCount: _chatHistory.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 2),
                            itemBuilder: (BuildContext context, int index) {
                              final _ChatHistoryItem item = _chatHistory[index];
                              final bool selected =
                                  item.sessionId == _selectedChatSessionId;
                              return ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                selected: selected,
                                selectedTileColor: color.primaryContainer
                                    .withValues(alpha: 0.35),
                                onTap: () => unawaited(
                                  _openChatSessionFromDrawer(item.sessionId),
                                ),
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor:
                                      color.surfaceContainerHighest,
                                  child: AppSvgIcon(
                                    AppSvgAsset.aiChatSparkles,
                                    size: 15,
                                    color: selected
                                        ? color.primary
                                        : color.onSurfaceVariant,
                                  ),
                                ),
                                title: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  item.preview.isEmpty
                                      ? "No preview"
                                      : item.preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    if (_pinnedChatSessionIds
                                        .contains(item.sessionId)) ...<Widget>[
                                      Icon(
                                        Icons.push_pin,
                                        size: 14,
                                        color: color.primary,
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      _formatChatHistoryTime(item.updatedAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: color.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    _buildChatSessionPopupButton(
                                      item: item,
                                      color: color,
                                      iconSize: 18,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 6,
                                      ),
                                      compact: true,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              _buildDrawerFooterAccount(context),
            ],
          ),
        ),
      ),
      body: SafeArea(top: false, child: _buildCurrentPage()),
      bottomNavigationBar: showBottomNav
          ? NavigationBar(
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              selectedIndex: selectedBottomIndexResolved,
              onDestinationSelected: (int i) {
                _setIndex(bottomTabs[i].pageIndex);
              },
              destinations: bottomTabs
                  .map(
                    (_BottomMenuTab tab) => NavigationDestination(
                      icon: _buildBottomTabIcon(
                        tab,
                        color: color.onSurfaceVariant,
                        selected: false,
                      ),
                      selectedIcon: _buildBottomTabIcon(
                        tab,
                        color: color.primary,
                        selected: true,
                      ),
                      label: tab.label,
                    ),
                  )
                  .toList(),
            )
          : null,
    );
  }
}

class _BottomMenuTab {
  const _BottomMenuTab({
    required this.pageIndex,
    required this.label,
    this.iconAsset,
    this.iconData,
    this.selectedIconData,
  }) : assert(iconAsset != null || iconData != null);

  final int pageIndex;
  final String? iconAsset;
  final IconData? iconData;
  final IconData? selectedIconData;
  final String label;
}

class _ChatHistoryItem {
  const _ChatHistoryItem({
    required this.sessionId,
    required this.title,
    required this.preview,
    required this.updatedAt,
  });

  final String sessionId;
  final String title;
  final String preview;
  final DateTime updatedAt;
}

class _AssistantRecordAction {
  const _AssistantRecordAction({
    this.tile,
    this.prefill = const <String, dynamic>{},
    this.autoSubmit = false,
    this.routeToChat = false,
    this.chatPrompt,
  });

  final HomeTileType? tile;
  final Map<String, dynamic> prefill;
  final bool autoSubmit;
  final bool routeToChat;
  final String? chatPrompt;
}

class _RoundTopButton extends StatelessWidget {
  const _RoundTopButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Material(
      color: color.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 17)),
      ),
    );
  }
}

class _HeaderChoice extends StatelessWidget {
  const _HeaderChoice({
    required this.selected,
    required this.label,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? color.primaryContainer.withValues(alpha: 0.92)
          : color.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Text(
            label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class _HeaderHint extends StatelessWidget {
  const _HeaderHint({
    required this.label,
    this.onTap,
    this.showEditIcon = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool showEditIcon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    final Widget content = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
          if (showEditIcon) ...<Widget>[
            const SizedBox(width: 6),
            Icon(
              Icons.edit_outlined,
              size: 14,
              color: color.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
