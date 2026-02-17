import "dart:convert";

import "package:flutter/material.dart";

import "../features/chat/chat_page.dart";
import "../features/community/community_page.dart";
import "../features/market/market_page.dart";
import "../features/photos/photos_page.dart";
import "../features/recording/recording_page.dart";
import "../features/report/report_page.dart";
import "../features/settings/settings_page.dart";
import "network/babyai_api.dart";
import "theme/app_theme_controller.dart";

class BabyAIApp extends StatefulWidget {
  const BabyAIApp({super.key});

  @override
  State<BabyAIApp> createState() => _BabyAIAppState();
}

class _BabyAIAppState extends State<BabyAIApp> {
  final AppThemeController _themeController = AppThemeController();

  @override
  void initState() {
    super.initState();
    _themeController.load();
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (BuildContext context, _) {
        return MaterialApp(
          title: "BabyAI",
          debugShowCheckedModeBanner: false,
          themeMode: _themeController.themeMode,
          theme: _buildTheme(brightness: Brightness.light),
          darkTheme: _buildTheme(brightness: Brightness.dark),
          home: _HomeShell(themeController: _themeController),
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

  int _index = 0;
  bool _isGoogleLoggedIn = false;
  String _accountName = "Google account";
  String _accountEmail = "Not connected";

  final List<String> _titles = const <String>[
    "Home",
    "AI Chat",
    "Statistics",
    "Photos",
    "Market",
    "Community",
  ];

  final List<Widget> _pages = const <Widget>[
    RecordingPage(),
    ChatPage(),
    ReportPage(),
    PhotosPage(),
    MarketPage(),
    CommunityPage(),
  ];

  @override
  void initState() {
    super.initState();
    _bootstrapAccountFromToken();
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
        pageIndex: _homePage,
        icon: Icons.home_outlined,
        label: "Home",
      ),
    ];
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.chat)) {
      tabs.add(const _BottomMenuTab(
        pageIndex: _chatPage,
        icon: Icons.chat_bubble_outline,
        label: "AI",
      ));
    }
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.statistics)) {
      tabs.add(const _BottomMenuTab(
        pageIndex: _statisticsPage,
        icon: Icons.insert_chart_outlined,
        label: "Statistics",
      ));
    }
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.photos)) {
      tabs.add(const _BottomMenuTab(
        pageIndex: _photosPage,
        icon: Icons.photo_library_outlined,
        label: "Photos",
      ));
    }
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.market)) {
      tabs.add(const _BottomMenuTab(
        pageIndex: _marketPage,
        icon: Icons.storefront_outlined,
        label: "Market",
      ));
    }
    if (widget.themeController.isBottomMenuEnabled(AppBottomMenu.community)) {
      tabs.add(const _BottomMenuTab(
        pageIndex: _communityPage,
        icon: Icons.groups_outlined,
        label: "Community",
      ));
    }
    return tabs;
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
        ),
      ),
    );
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
          title: const Text("Google Login"),
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
                  decoration: const InputDecoration(
                    labelText: "Name (optional)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: "Email (optional)",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
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
                Navigator.of(context).pop();
              },
              child: const Text("Login"),
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
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    final List<_BottomMenuTab> bottomTabs = _buildBottomTabs();
    final int selectedBottomIndex = bottomTabs.indexWhere(
      (_BottomMenuTab tab) => tab.pageIndex == _index,
    );
    final bool showBottomNav = selectedBottomIndex >= 0;

    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        "BabyAI",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: const Text("Home"),
                      subtitle: const Text("Today snapshot + record input"),
                      selected: _index == _homePage,
                      onTap: () => _selectIndex(_homePage),
                    ),
                    ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: const Text("AI Chat"),
                      selected: _index == _chatPage,
                      onTap: () => _selectIndex(_chatPage),
                    ),
                    ListTile(
                      leading: const Icon(Icons.insert_chart_outlined),
                      title: const Text("Statistics"),
                      selected: _index == _statisticsPage,
                      onTap: () => _selectIndex(_statisticsPage),
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text("Photos"),
                      selected: _index == _photosPage,
                      onTap: () => _selectIndex(_photosPage),
                    ),
                    ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: const Text("Market"),
                      subtitle: const Text("Used / New / Promotion"),
                      selected: _index == _marketPage,
                      onTap: () => _selectIndex(_marketPage),
                    ),
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: const Text("Community"),
                      subtitle: const Text("Boards and suggestions"),
                      selected: _index == _communityPage,
                      onTap: () => _selectIndex(_communityPage),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text("Settings"),
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
                      color: color.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
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
                              Text(
                                _accountName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _accountEmail,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                            label: const Text("Login"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isGoogleLoggedIn ? _logout : null,
                            icon: const Icon(Icons.logout),
                            label: const Text("Logout"),
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
      body: SafeArea(child: _pages[_index]),
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
                      icon: Icon(tab.icon),
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
    required this.icon,
    required this.label,
  });

  final int pageIndex;
  final IconData icon;
  final String label;
}
