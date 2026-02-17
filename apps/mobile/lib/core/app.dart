import "dart:async";
import "dart:convert";

import "package:flutter/material.dart";

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

    return AnimatedBuilder(
      animation: _themeController,
      builder: (BuildContext context, _) {
        return MaterialApp(
          title: "BabyAI",
          debugShowCheckedModeBanner: false,
          themeMode: _themeController.themeMode,
          locale: _localeFromLanguage(_themeController.language),
          theme: _buildTheme(brightness: Brightness.light),
          darkTheme: _buildTheme(brightness: Brightness.dark),
          home: AppSettingsScope(
            controller: _themeController,
            child: _HomeShell(themeController: _themeController),
          ),
        );
      },
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
  final GlobalKey<ReportPageState> _reportPageKey =
      GlobalKey<ReportPageState>();

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
        return RecordingPage(range: _recordRange);
      case _chatPage:
        return const ChatPage();
      case _statisticsPage:
        return ReportPage(key: _reportPageKey);
      case _photosPage:
        return PhotosPage(viewMode: _photosViewMode);
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
    if (_index == _statisticsPage) {
      _reportPageKey.currentState?.refreshData();
    }
  }

  Widget _buildHeaderControls(BuildContext context) {
    switch (_index) {
      case _homePage:
        return Wrap(
          spacing: 8,
          children: <Widget>[
            _HeaderChoice(
              selected: _recordRange == RecordRange.day,
              label: tr(context, ko: "일", en: "Day", es: "Dia"),
              onTap: () => setState(() => _recordRange = RecordRange.day),
            ),
            _HeaderChoice(
              selected: _recordRange == RecordRange.week,
              label: tr(context, ko: "주", en: "Week", es: "Semana"),
              onTap: () => setState(() => _recordRange = RecordRange.week),
            ),
            _HeaderChoice(
              selected: _recordRange == RecordRange.month,
              label: tr(context, ko: "월", en: "Month", es: "Mes"),
              onTap: () => setState(() => _recordRange = RecordRange.month),
            ),
          ],
        );
      case _photosPage:
        return Wrap(
          spacing: 8,
          children: <Widget>[
            _HeaderChoice(
              selected: _photosViewMode == PhotosViewMode.tiles,
              label: "Tiles",
              onTap: () =>
                  setState(() => _photosViewMode = PhotosViewMode.tiles),
            ),
            _HeaderChoice(
              selected: _photosViewMode == PhotosViewMode.albums,
              label: "Albums",
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
        return _HeaderHint(
            label: tr(context,
                ko: "일간 + 주간", en: "Daily + Weekly", es: "Diario + Semanal"));
      case _chatPage:
      default:
        return _HeaderHint(
            label:
                tr(context, ko: "대화", en: "Conversation", es: "Conversacion"));
    }
  }

  PreferredSizeWidget _buildTopBar(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 72,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        side: BorderSide(color: color.outlineVariant.withValues(alpha: 0.28)),
      ),
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              color.surface.withValues(alpha: 0.98),
              color.surface.withValues(alpha: 0.82),
            ],
          ),
        ),
      ),
      titleSpacing: 12,
      title: Row(
        children: <Widget>[
          _RoundTopButton(
              icon: Icons.menu,
              onTap: () => _scaffoldKey.currentState?.openDrawer()),
          const SizedBox(width: 8),
          Expanded(child: _buildHeaderControls(context)),
          if (_index == _statisticsPage) ...<Widget>[
            const SizedBox(width: 8),
            _RoundTopButton(icon: Icons.refresh, onTap: _onTopRefreshPressed),
          ],
        ],
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
      body: SafeArea(child: _buildCurrentPage()),
      bottomNavigationBar: showBottomNav
          ? NavigationBar(
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
