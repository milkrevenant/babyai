import "dart:async";
import "dart:convert";
import "dart:ui" as ui;

import "package:flutter/material.dart";

import "assistant/assistant_intent_bridge.dart";
import "assistant/assistant_query_router.dart";
import "../features/chat/chat_page.dart";
import "../features/community/community_page.dart";
import "../features/market/market_page.dart";
import "../features/photos/photos_page.dart";
import "../features/recording/recording_page.dart";
import "../features/report/report_page.dart";
import "../features/settings/child_profile_page.dart";
import "../features/settings/settings_page.dart";
import "config/session_store.dart";
import "i18n/app_i18n.dart";
import "network/babyai_api.dart";
import "theme/app_theme_controller.dart";

class BabyAIApp extends StatefulWidget {
  const BabyAIApp({super.key});

  @override
  State<BabyAIApp> createState() => _BabyAIAppState();
}

class _BabyAIAppState extends State<BabyAIApp> {
  final AppThemeController _themeController = AppThemeController();
  bool _appReady = false;

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
    final ColorScheme colorScheme = ColorScheme.fromSeed(
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
            : colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF090B10)
          : colorScheme.surface,
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
    if (!_appReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(
              color: ThemeData(useMaterial3: true).colorScheme.primary,
            ),
          ),
        ),
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
  final GlobalKey<PhotosPageState> _photosPageKey =
      GlobalKey<PhotosPageState>();
  StreamSubscription<AssistantActionPayload>? _assistantSubscription;
  AssistantActionPayload? _pendingAssistantAction;
  String? _pendingChatPrompt;

  int _index = 0;
  bool _isGoogleLoggedIn = false;
  String _accountName = "Google account";
  String _accountEmail = "Not connected";

  RecordRange _recordRange = RecordRange.week;
  PhotosViewMode _photosViewMode = PhotosViewMode.tiles;
  MarketSection _marketSection = MarketSection.used;
  CommunitySection _communitySection = CommunitySection.free;

  @override
  void initState() {
    super.initState();
    _bootstrapAccountFromToken();
    _initializeAssistantBridge();
  }

  @override
  void dispose() {
    _assistantSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeAssistantBridge() async {
    _assistantSubscription = AssistantIntentBridge.stream.listen(
      _handleAssistantAction,
    );
    await AssistantIntentBridge.initialize();
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

  bool _looksLikeQuestion(String? query) {
    if (query == null) {
      return false;
    }
    final String text = query.trim().toLowerCase();
    if (text.isEmpty) {
      return false;
    }
    if (text.contains("?")) {
      return true;
    }
    return _containsAny(text, <String>[
      "when",
      "what",
      "how much",
      "how long",
      "tell me",
      "show me",
      "언제",
      "뭐",
      "무엇",
      "알려",
      "보여",
      "요약",
      "최근",
      "마지막",
    ]);
  }

  String? _queryForReadFeature(String feature) {
    switch (feature) {
      case "last_feeding":
      case "last-feeding":
        return "last feeding";
      case "recent_sleep":
      case "recent-sleep":
        return "recent sleep";
      case "last_diaper":
      case "last-diaper":
        return "last diaper";
      case "last_medication":
      case "last-medication":
        return "last medication";
      case "today_summary":
      case "today-summary":
        return "today summary";
      case "last_poo":
      case "last-poo":
      case "last_poo_time":
      case "last-poo-time":
        return "last poo time";
      case "next_feeding_eta":
      case "next-feeding-eta":
        return "next feeding eta";
      default:
        return null;
    }
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

    final String? readFeatureQuery = _queryForReadFeature(normalizedFeature);
    if (readFeatureQuery != null) {
      return _AssistantRecordAction(
        routeToChat: true,
        chatPrompt: normalizedQuery ?? readFeatureQuery,
      );
    }

    final AssistantQuickRoute quickRoute =
        AssistantQueryRouter.resolve(normalizedQuery ?? "");
    if (quickRoute != AssistantQuickRoute.none &&
        !_hasRecordIntent(normalizedQuery)) {
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
        routeToChat: looksLikeRecordCommand
            ? false
            : normalizedQuery != null || _looksLikeQuestion(normalizedQuery),
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
        _pendingChatPrompt = action.chatPrompt!.trim();
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _flushPendingChatPrompt(),
        );
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

  void _flushPendingChatPrompt({int attempt = 0}) {
    if (!mounted) {
      return;
    }
    final String? prompt = _pendingChatPrompt;
    if (prompt == null || prompt.isEmpty) {
      return;
    }

    final ChatPageState? chatState = _chatPageKey.currentState;
    if (chatState == null) {
      if (attempt >= 8) {
        return;
      }
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        _flushPendingChatPrompt(attempt: attempt + 1);
      });
      return;
    }

    _pendingChatPrompt = null;
    unawaited(chatState.sendAssistantPrompt(prompt));
  }

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

  void _selectIndex(int next) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    setState(() => _index = next);
  }

  List<_BottomMenuTab> _buildBottomTabs() {
    final List<_BottomMenuTab> tabs = <_BottomMenuTab>[
      const _BottomMenuTab(
          pageIndex: _homePage, icon: Icons.home_outlined, label: "home"),
    ];
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.chat)) {
      tabs.add(const _BottomMenuTab(
          pageIndex: _chatPage,
          icon: Icons.chat_bubble_outline,
          label: "chat"));
    }
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.statistics)) {
      tabs.add(const _BottomMenuTab(
          pageIndex: _statisticsPage,
          icon: Icons.insert_chart_outlined,
          label: "statistics"));
    }
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.photos)) {
      tabs.add(const _BottomMenuTab(
          pageIndex: _photosPage,
          icon: Icons.photo_library_outlined,
          label: "photos"));
    }
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.market)) {
      tabs.add(const _BottomMenuTab(
          pageIndex: _marketPage,
          icon: Icons.storefront_outlined,
          label: "market"));
    }
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.community)) {
      tabs.add(const _BottomMenuTab(
          pageIndex: _communityPage,
          icon: Icons.groups_outlined,
          label: "community"));
    }
    return tabs;
  }

  Widget _buildCurrentPage() {
    switch (_index) {
      case _homePage:
        return RecordingPage(key: _recordPageKey, range: _recordRange);
      case _chatPage:
        return ChatPage(key: _chatPageKey);
      case _statisticsPage:
        return ReportPage(key: _reportPageKey, range: _recordRange);
      case _photosPage:
        return PhotosPage(key: _photosPageKey, viewMode: _photosViewMode);
      case _marketPage:
        return MarketPage(section: _marketSection);
      case _communityPage:
        return CommunityPage(section: _communitySection);
      default:
        return RecordingPage(range: _recordRange);
    }
  }

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

  void _bootstrapAccountFromToken() {
    final String token = BabyAIApi.currentBearerToken;
    if (token.trim().isEmpty) {
      setState(() {
        _isGoogleLoggedIn = false;
        _accountName = "Google account";
        _accountEmail = "Not connected";
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
      _accountName = name.trim().isEmpty ? "Google User" : name.trim();
      _accountEmail = email.trim().isEmpty ? "Connected" : email.trim();
    });
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
              onPressed: () {
                final String token = tokenController.text.trim();
                if (token.isNotEmpty) {
                  BabyAIApi.setBearerToken(token);
                }
                final String name = nameController.text.trim();
                final String email = emailController.text.trim();
                final Map<String, dynamic> payload = _decodeJwtPayload(token);
                setState(() {
                  _isGoogleLoggedIn = token.isNotEmpty;
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
    setState(() {
      _isGoogleLoggedIn = false;
      _accountName = "Google account";
      _accountEmail = "Not connected";
    });
    unawaited(AppSessionStore.persistRuntimeState());
  }

  void _onTopRefreshPressed() {
    if (_index == _homePage) {
      _recordPageKey.currentState?.refreshData();
      return;
    }
    if (_index == _statisticsPage) {
      _reportPageKey.currentState?.refreshData();
    }
  }

  String _recordRangeLabel(BuildContext context, RecordRange range) {
    switch (range) {
      case RecordRange.day:
        return tr(context, ko: "일", en: "Day", es: "Dia");
      case RecordRange.week:
        return tr(context, ko: "주", en: "Week", es: "Semana");
      case RecordRange.month:
        return tr(context, ko: "월", en: "Month", es: "Mes");
    }
  }

  bool _showRangeTopActions() {
    return _index == _homePage || _index == _statisticsPage;
  }

  String _recordRangeDateLabel() {
    final DateTime now = DateTime.now();
    switch (_recordRange) {
      case RecordRange.day:
        return "${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}";
      case RecordRange.week:
        final DateTime monday = now.subtract(Duration(days: now.weekday - 1));
        final DateTime sunday = monday.add(const Duration(days: 6));
        return "${monday.month}/${monday.day}-${sunday.month}/${sunday.day}";
      case RecordRange.month:
        return "${now.year}-${now.month.toString().padLeft(2, "0")}";
    }
  }

  Widget _buildTopRangeDateChip(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.calendar_month_outlined, size: 16),
          const SizedBox(width: 6),
          Text(
            _recordRangeDateLabel(),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Future<void> _openRecordRangeMenu(BuildContext anchorContext) async {
    final List<RecordRange> candidates = RecordRange.values
        .where((RecordRange item) => item != _recordRange)
        .toList();
    if (candidates.isEmpty) {
      return;
    }

    final RenderBox button = anchorContext.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(anchorContext).context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final RecordRange? selected = await showMenu<RecordRange>(
      context: anchorContext,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: candidates
          .map(
            (RecordRange value) => PopupMenuItem<RecordRange>(
              value: value,
              child: Text(_recordRangeLabel(anchorContext, value)),
            ),
          )
          .toList(),
    );

    if (selected != null && mounted) {
      setState(() => _recordRange = selected);
    }
  }

  Widget _buildRecordRangeDropdown(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Builder(
      builder: (BuildContext anchorContext) {
        return Material(
          color: color.surfaceContainerHighest.withValues(alpha: 0.45),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => _openRecordRangeMenu(anchorContext),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _recordRangeLabel(context, _recordRange),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderControls(BuildContext context) {
    switch (_index) {
      case _homePage:
        return _buildRecordRangeDropdown(context);
      case _photosPage:
        return Wrap(
          spacing: 8,
          children: <Widget>[
            _HeaderChoice(
              selected: _photosViewMode == PhotosViewMode.tiles,
              label: tr(context, ko: "타일", en: "Tiles", es: "Mosaico"),
              onTap: () =>
                  setState(() => _photosViewMode = PhotosViewMode.tiles),
            ),
            _HeaderChoice(
              selected: _photosViewMode == PhotosViewMode.albums,
              label: tr(context, ko: "앨범", en: "Albums", es: "Albumes"),
              onTap: () =>
                  setState(() => _photosViewMode = PhotosViewMode.albums),
            ),
          ],
        );
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
        return _buildRecordRangeDropdown(context);
      case _chatPage:
      default:
        return _HeaderHint(
            label:
                tr(context, ko: "대화", en: "Conversation", es: "Conversacion"));
    }
  }

  PreferredSizeWidget _buildTopBar(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final double safeTopInset = MediaQuery.paddingOf(context).top;
    final double iosTitleOffset = isIOS
        ? (safeTopInset >= 54
            ? 6
            : safeTopInset >= 44
                ? 3
                : 0)
        : 0;
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: isIOS ? 58 + iosTitleOffset : 72,
      elevation: 0,
      scrolledUnderElevation: 0,
      forceMaterialTransparency: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(isIOS ? 16 : 24),
        ),
        side: BorderSide(color: color.outlineVariant.withValues(alpha: 0.28)),
      ),
      flexibleSpace: ClipRRect(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(isIOS ? 16 : 24),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  color.surface.withValues(alpha: isIOS ? 0.62 : 0.78),
                  color.surface.withValues(alpha: isIOS ? 0.42 : 0.58),
                ],
              ),
            ),
          ),
        ),
      ),
      titleSpacing: isIOS ? 12 : 12,
      title: Padding(
        padding: EdgeInsets.only(top: iosTitleOffset),
        child: Row(
          children: <Widget>[
            _RoundTopButton(
                icon: Icons.menu,
                onTap: () => _scaffoldKey.currentState?.openDrawer()),
            const SizedBox(width: 8),
            if (_index == _homePage || _index == _statisticsPage)
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildHeaderControls(context),
                ),
              )
            else
              Expanded(child: _buildHeaderControls(context)),
            if (_showRangeTopActions()) ...<Widget>[
              const SizedBox(width: 8),
              _buildTopRangeDateChip(context),
              const SizedBox(width: 8),
              _RoundTopButton(icon: Icons.refresh, onTap: _onTopRefreshPressed),
            ],
          ],
        ),
      ),
    );
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
    final bool showBottomNav = selectedBottomIndex >= 0;

    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildTopBar(context),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
                      child: Text("BabyAI",
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: Text(_labelForIndex(context, _homePage)),
                      selected: _index == _homePage,
                      onTap: () => _selectIndex(_homePage),
                    ),
                    ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(_labelForIndex(context, _chatPage)),
                      selected: _index == _chatPage,
                      onTap: () => _selectIndex(_chatPage),
                    ),
                    ListTile(
                      leading: const Icon(Icons.insert_chart_outlined),
                      title: Text(_labelForIndex(context, _statisticsPage)),
                      selected: _index == _statisticsPage,
                      onTap: () => _selectIndex(_statisticsPage),
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: Text(_labelForIndex(context, _photosPage)),
                      selected: _index == _photosPage,
                      onTap: () => _selectIndex(_photosPage),
                    ),
                    ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(_labelForIndex(context, _marketPage)),
                      selected: _index == _marketPage,
                      onTap: () => _selectIndex(_marketPage),
                    ),
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(_labelForIndex(context, _communityPage)),
                      selected: _index == _communityPage,
                      onTap: () => _selectIndex(_communityPage),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: Text(
                          tr(context, ko: "설정", en: "Settings", es: "Ajustes")),
                      onTap: _openSettings,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: color.surfaceContainerHighest.withValues(alpha: 0.45),
                  border: Border(
                      top: BorderSide(
                          color: color.outlineVariant.withValues(alpha: 0.5))),
                ),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: color.primaryContainer,
                          child: const Icon(Icons.account_circle_outlined),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(_accountName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text(_accountEmail,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _isGoogleLoggedIn
                                ? null
                                : _loginWithGoogleToken,
                            icon: const Icon(Icons.login),
                            label: Text(tr(context,
                                ko: "로그인", en: "Login", es: "Entrar")),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isGoogleLoggedIn ? _logout : null,
                            icon: const Icon(Icons.logout),
                            label: Text(tr(context,
                                ko: "로그아웃", en: "Logout", es: "Salir")),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _index == _photosPage
          ? FloatingActionButton.extended(
              onPressed: () {
                unawaited(
                    _photosPageKey.currentState?.pickAndUploadFromGallery());
              },
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                tr(context, ko: "사진 업로드", en: "Upload", es: "Subir"),
              ),
            )
          : null,
      body: SafeArea(child: _buildCurrentPage()),
      bottomNavigationBar: showBottomNav
          ? NavigationBar(
              height: 58,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              selectedIndex: selectedBottomIndex,
              onDestinationSelected: (int i) {
                setState(() => _index = bottomTabs[i].pageIndex);
              },
              destinations: bottomTabs
                  .map(
                    (_BottomMenuTab tab) => NavigationDestination(
                        icon: Icon(tab.icon), label: tab.label),
                  )
                  .toList(),
            )
          : null,
    );
  }
}

class _BottomMenuTab {
  const _BottomMenuTab(
      {required this.pageIndex, required this.icon, required this.label});

  final int pageIndex;
  final IconData icon;
  final String label;
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
        child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 20)),
      ),
    );
  }
}

class _HeaderChoice extends StatelessWidget {
  const _HeaderChoice(
      {required this.selected, required this.label, required this.onTap});

  final bool selected;
  final String label;
  final VoidCallback onTap;

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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
  const _HeaderHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}
