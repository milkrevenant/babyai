import "package:flutter/material.dart";

import "../network/babyai_api.dart";

enum AppThemeMode {
  system,
  dark,
  light,
}

enum AppMainFont {
  notoSans,
  systemSans,
}

enum AppHighlightFont {
  ibmPlexSans,
  notoSans,
}

enum AppAccentTone {
  gold,
  teal,
  coral,
  indigo,
}

enum AppBottomMenu {
  chat,
  statistics,
  photos,
  market,
  community,
}

class AppThemeController extends ChangeNotifier {
  AppThemeMode _mode = AppThemeMode.system;
  AppMainFont _mainFont = AppMainFont.notoSans;
  AppHighlightFont _highlightFont = AppHighlightFont.ibmPlexSans;
  AppAccentTone _accentTone = AppAccentTone.gold;
  final Map<AppBottomMenu, bool> _bottomMenuEnabled = <AppBottomMenu, bool>{
    AppBottomMenu.chat: true,
    AppBottomMenu.statistics: true,
    AppBottomMenu.photos: true,
    AppBottomMenu.market: false,
    AppBottomMenu.community: false,
  };

  AppThemeMode get mode => _mode;
  AppMainFont get mainFont => _mainFont;
  AppHighlightFont get highlightFont => _highlightFont;
  AppAccentTone get accentTone => _accentTone;
  Map<AppBottomMenu, bool> get bottomMenuEnabled =>
      Map<AppBottomMenu, bool>.unmodifiable(_bottomMenuEnabled);

  ThemeMode get themeMode {
    switch (_mode) {
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  String get mainFontFamily {
    switch (_mainFont) {
      case AppMainFont.notoSans:
        return "NotoSans";
      case AppMainFont.systemSans:
        return "";
    }
  }

  String get highlightFontFamily {
    switch (_highlightFont) {
      case AppHighlightFont.ibmPlexSans:
        return "IBMPlexSans";
      case AppHighlightFont.notoSans:
        return "NotoSans";
    }
  }

  Color seedColorFor(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    switch (_accentTone) {
      case AppAccentTone.gold:
        return dark ? const Color(0xFFE0B44C) : const Color(0xFFB9933F);
      case AppAccentTone.teal:
        return dark ? const Color(0xFF4FC3B8) : const Color(0xFF0E8F88);
      case AppAccentTone.coral:
        return dark ? const Color(0xFFE89B7D) : const Color(0xFFBE5F3D);
      case AppAccentTone.indigo:
        return dark ? const Color(0xFF9FA8F6) : const Color(0xFF5C66C5);
    }
  }

  Future<void> load() async {
    try {
      final Map<String, dynamic> settings =
          await BabyAIApi.instance.getMySettings();
      final String raw = (settings["theme_mode"] ?? "system").toString();
      _mode = AppThemeMode.values.firstWhere(
        (AppThemeMode item) => item.name == raw,
        orElse: () => AppThemeMode.system,
      );
    } catch (_) {
      // If server settings are unavailable (e.g. missing token), keep defaults.
    } finally {
      notifyListeners();
    }
  }

  Future<void> setMode(AppThemeMode next) async {
    if (_mode == next) {
      return;
    }
    _mode = next;
    notifyListeners();
    try {
      await BabyAIApi.instance.updateMySettings(themeMode: next.name);
    } catch (_) {
      // Keep local mode even if sync fails.
    }
  }

  void setMainFont(AppMainFont next) {
    if (_mainFont == next) {
      return;
    }
    _mainFont = next;
    notifyListeners();
  }

  void setHighlightFont(AppHighlightFont next) {
    if (_highlightFont == next) {
      return;
    }
    _highlightFont = next;
    notifyListeners();
  }

  void setAccentTone(AppAccentTone next) {
    if (_accentTone == next) {
      return;
    }
    _accentTone = next;
    notifyListeners();
  }

  bool isBottomMenuEnabled(AppBottomMenu menu) {
    return _bottomMenuEnabled[menu] ?? false;
  }

  void setBottomMenuEnabled(AppBottomMenu menu, bool enabled) {
    final bool current = _bottomMenuEnabled[menu] ?? false;
    if (current == enabled) {
      return;
    }
    _bottomMenuEnabled[menu] = enabled;
    notifyListeners();
  }
}
