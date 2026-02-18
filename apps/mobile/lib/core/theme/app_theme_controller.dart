import "dart:async";

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

enum AppLanguage {
  ko,
  en,
  es,
}

enum ChildCareProfile {
  breastfeeding,
  formula,
  weaning,
}

enum HomeTileType {
  formula,
  breastfeed,
  weaning,
  diaper,
  sleep,
  medication,
  memo,
}

class AppThemeController extends ChangeNotifier {
  static const Map<AppBottomMenu, bool> _defaultBottomMenuEnabled =
      <AppBottomMenu, bool>{
    AppBottomMenu.chat: true,
    AppBottomMenu.statistics: true,
    AppBottomMenu.photos: true,
    AppBottomMenu.market: false,
    AppBottomMenu.community: false,
  };

  static const Map<HomeTileType, bool> _defaultHomeTilesFormula =
      <HomeTileType, bool>{
    HomeTileType.formula: true,
    HomeTileType.breastfeed: false,
    HomeTileType.weaning: true,
    HomeTileType.diaper: true,
    HomeTileType.sleep: true,
    HomeTileType.medication: true,
    HomeTileType.memo: false,
  };

  static const Map<HomeTileType, bool> _defaultHomeTilesBreastfeeding =
      <HomeTileType, bool>{
    HomeTileType.formula: true,
    HomeTileType.breastfeed: false,
    HomeTileType.weaning: true,
    HomeTileType.diaper: true,
    HomeTileType.sleep: true,
    HomeTileType.medication: true,
    HomeTileType.memo: false,
  };

  static const Map<HomeTileType, bool> _defaultHomeTilesWeaning =
      <HomeTileType, bool>{
    HomeTileType.formula: true,
    HomeTileType.breastfeed: false,
    HomeTileType.weaning: true,
    HomeTileType.diaper: true,
    HomeTileType.sleep: true,
    HomeTileType.medication: true,
    HomeTileType.memo: false,
  };

  static const List<HomeTileType> _defaultHomeTileOrder = <HomeTileType>[
    HomeTileType.formula,
    HomeTileType.sleep,
    HomeTileType.diaper,
    HomeTileType.weaning,
    HomeTileType.medication,
  ];

  AppThemeMode _mode = AppThemeMode.system;
  AppMainFont _mainFont = AppMainFont.notoSans;
  AppHighlightFont _highlightFont = AppHighlightFont.ibmPlexSans;
  AppAccentTone _accentTone = AppAccentTone.gold;
  AppLanguage _language = AppLanguage.ko;
  ChildCareProfile _childCareProfile = ChildCareProfile.formula;
  int _homeTileColumns = 2;
  bool _showSpecialMemo = true;
  List<HomeTileType> _homeTileOrder =
      List<HomeTileType>.from(_defaultHomeTileOrder);

  final Map<AppBottomMenu, bool> _bottomMenuEnabled =
      Map<AppBottomMenu, bool>.from(_defaultBottomMenuEnabled);
  final Map<HomeTileType, bool> _homeTileEnabled =
      Map<HomeTileType, bool>.from(_defaultHomeTilesFormula);

  AppThemeMode get mode => _mode;
  AppMainFont get mainFont => _mainFont;
  AppHighlightFont get highlightFont => _highlightFont;
  AppAccentTone get accentTone => _accentTone;
  AppLanguage get language => _language;
  ChildCareProfile get childCareProfile => _childCareProfile;
  int get homeTileColumns => _homeTileColumns;
  bool get showSpecialMemo => _showSpecialMemo;
  List<HomeTileType> get homeTileOrder =>
      List<HomeTileType>.unmodifiable(_homeTileOrder);

  Map<AppBottomMenu, bool> get bottomMenuEnabled =>
      Map<AppBottomMenu, bool>.unmodifiable(_bottomMenuEnabled);
  Map<HomeTileType, bool> get homeTileEnabled =>
      Map<HomeTileType, bool>.unmodifiable(_homeTileEnabled);

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
      _mode = _enumByName<AppThemeMode>(
        AppThemeMode.values,
        (settings["theme_mode"] ?? "system").toString(),
        AppThemeMode.system,
      );
      _language = _enumByName<AppLanguage>(
        AppLanguage.values,
        (settings["language"] ?? "ko").toString(),
        AppLanguage.ko,
      );
      _mainFont = _enumByName<AppMainFont>(
        AppMainFont.values,
        (settings["main_font"] ?? AppMainFont.notoSans.name).toString(),
        AppMainFont.notoSans,
      );
      _highlightFont = _enumByName<AppHighlightFont>(
        AppHighlightFont.values,
        (settings["highlight_font"] ?? AppHighlightFont.ibmPlexSans.name)
            .toString(),
        AppHighlightFont.ibmPlexSans,
      );
      _accentTone = _enumByName<AppAccentTone>(
        AppAccentTone.values,
        (settings["accent_tone"] ?? AppAccentTone.gold.name).toString(),
        AppAccentTone.gold,
      );
      _childCareProfile = _enumByName<ChildCareProfile>(
        ChildCareProfile.values,
        (settings["child_care_profile"] ?? ChildCareProfile.formula.name)
            .toString(),
        ChildCareProfile.formula,
      );
      _homeTileColumns = _parseHomeTileColumns(settings["home_tile_columns"]);
      _showSpecialMemo = _asBool(settings["show_special_memo"]) ?? true;

      _applyBottomMenuFromPayload(settings["bottom_menu_enabled"]);
      _applyHomeTilesFromPayload(settings["home_tiles"]);
      _applyHomeTileOrderFromPayload(settings["home_tile_order"]);
    } catch (_) {
      // Keep defaults when server settings are unavailable.
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
    await _syncSettings();
  }

  void setMainFont(AppMainFont next) {
    if (_mainFont == next) {
      return;
    }
    _mainFont = next;
    notifyListeners();
    unawaited(_syncSettings());
  }

  void setHighlightFont(AppHighlightFont next) {
    if (_highlightFont == next) {
      return;
    }
    _highlightFont = next;
    notifyListeners();
    unawaited(_syncSettings());
  }

  void setAccentTone(AppAccentTone next) {
    if (_accentTone == next) {
      return;
    }
    _accentTone = next;
    notifyListeners();
    unawaited(_syncSettings());
  }

  void setLanguage(AppLanguage next) {
    if (_language == next) {
      return;
    }
    _language = next;
    notifyListeners();
    unawaited(_syncSettings());
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
    unawaited(_syncSettings());
  }

  bool isHomeTileEnabled(HomeTileType tile) {
    return _homeTileEnabled[tile] ?? false;
  }

  void setHomeTileEnabled(HomeTileType tile, bool enabled) {
    final bool current = _homeTileEnabled[tile] ?? false;
    if (current == enabled) {
      return;
    }
    _homeTileEnabled[tile] = enabled;
    notifyListeners();
    unawaited(_syncSettings());
  }

  Future<void> setChildCareProfile(
    ChildCareProfile next, {
    bool applyDefaultTiles = false,
  }) async {
    final bool changed = _childCareProfile != next;
    _childCareProfile = next;
    if (applyDefaultTiles) {
      _applyDefaultHomeTiles(next);
    }
    if (!changed && !applyDefaultTiles) {
      return;
    }
    notifyListeners();
    await _syncSettings();
  }

  Future<void> applyDefaultHomeTilesForProfile({
    ChildCareProfile? profile,
  }) async {
    _applyDefaultHomeTiles(profile ?? _childCareProfile);
    notifyListeners();
    await _syncSettings();
  }

  Future<void> setHomeTileColumns(int columns) async {
    if (columns < 1 || columns > 3 || _homeTileColumns == columns) {
      return;
    }
    _homeTileColumns = columns;
    notifyListeners();
    await _syncSettings();
  }

  Future<void> setShowSpecialMemo(bool enabled) async {
    if (_showSpecialMemo == enabled) {
      return;
    }
    _showSpecialMemo = enabled;
    notifyListeners();
    await _syncSettings();
  }

  Future<void> reorderHomeTile(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _homeTileOrder.length ||
        newIndex < 0 ||
        newIndex > _homeTileOrder.length) {
      return;
    }
    int targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    if (targetIndex == oldIndex) {
      return;
    }
    final HomeTileType moved = _homeTileOrder.removeAt(oldIndex);
    _homeTileOrder.insert(targetIndex, moved);
    notifyListeners();
    await _syncSettings();
  }

  void _applyDefaultHomeTiles(ChildCareProfile profile) {
    _homeTileEnabled.clear();
    switch (profile) {
      case ChildCareProfile.breastfeeding:
        _homeTileEnabled.addAll(_defaultHomeTilesBreastfeeding);
        break;
      case ChildCareProfile.weaning:
        _homeTileEnabled.addAll(_defaultHomeTilesWeaning);
        break;
      case ChildCareProfile.formula:
        _homeTileEnabled.addAll(_defaultHomeTilesFormula);
        break;
    }
  }

  T _enumByName<T extends Enum>(List<T> values, String raw, T fallback) {
    final String key = raw.trim();
    for (final T item in values) {
      if (item.name == key) {
        return item;
      }
    }
    return fallback;
  }

  bool? _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final String lowered = value.trim().toLowerCase();
      if (lowered == "true" || lowered == "1") {
        return true;
      }
      if (lowered == "false" || lowered == "0") {
        return false;
      }
    }
    return null;
  }

  void _applyBottomMenuFromPayload(Object? raw) {
    _bottomMenuEnabled
      ..clear()
      ..addAll(_defaultBottomMenuEnabled);
    if (raw is! Map<dynamic, dynamic>) {
      return;
    }
    for (final AppBottomMenu menu in AppBottomMenu.values) {
      final bool? parsed = _asBool(raw[menu.name]);
      if (parsed != null) {
        _bottomMenuEnabled[menu] = parsed;
      }
    }
  }

  void _applyHomeTilesFromPayload(Object? raw) {
    _applyDefaultHomeTiles(_childCareProfile);
    if (raw is! Map<dynamic, dynamic>) {
      return;
    }
    for (final HomeTileType tile in HomeTileType.values) {
      final bool? parsed = _asBool(raw[tile.name]);
      if (parsed != null) {
        _homeTileEnabled[tile] = parsed;
      }
    }
  }

  int _parseHomeTileColumns(Object? value) {
    if (value is int) {
      return (value >= 1 && value <= 3) ? value : 2;
    }
    if (value is double) {
      final int rounded = value.round();
      return (rounded >= 1 && rounded <= 3) ? rounded : 2;
    }
    if (value is String) {
      final int? parsed = int.tryParse(value.trim());
      if (parsed != null && parsed >= 1 && parsed <= 3) {
        return parsed;
      }
    }
    return 2;
  }

  void _applyHomeTileOrderFromPayload(Object? raw) {
    final List<HomeTileType> resolved =
        List<HomeTileType>.from(_defaultHomeTileOrder);
    if (raw is List<dynamic>) {
      final List<HomeTileType> parsed = <HomeTileType>[];
      for (final dynamic item in raw) {
        final String key = item.toString().trim().toLowerCase();
        final HomeTileType? tile = _tileFromOrderKey(key);
        if (tile != null && !parsed.contains(tile)) {
          parsed.add(tile);
        }
      }
      if (parsed.isNotEmpty) {
        for (final HomeTileType tile in _defaultHomeTileOrder) {
          if (!parsed.contains(tile)) {
            parsed.add(tile);
          }
        }
        _homeTileOrder = parsed;
        return;
      }
    }
    _homeTileOrder = resolved;
  }

  HomeTileType? _tileFromOrderKey(String key) {
    switch (key) {
      case "formula":
        return HomeTileType.formula;
      case "sleep":
        return HomeTileType.sleep;
      case "diaper":
        return HomeTileType.diaper;
      case "weaning":
        return HomeTileType.weaning;
      case "medication":
        return HomeTileType.medication;
      default:
        return null;
    }
  }

  Map<String, bool> _serializeBottomMenu() {
    return <String, bool>{
      for (final AppBottomMenu menu in AppBottomMenu.values)
        menu.name: _bottomMenuEnabled[menu] ?? false,
    };
  }

  Map<String, bool> _serializeHomeTiles() {
    return <String, bool>{
      for (final HomeTileType tile in HomeTileType.values)
        tile.name: _homeTileEnabled[tile] ?? false,
    };
  }

  List<String> _serializeHomeTileOrder() {
    final List<String> serialized = <String>[];
    for (final HomeTileType tile in _homeTileOrder) {
      final HomeTileType? normalized = _tileFromOrderKey(
        tile.name.toLowerCase(),
      );
      switch (normalized) {
        case HomeTileType.formula:
          serialized.add("formula");
          break;
        case HomeTileType.sleep:
          serialized.add("sleep");
          break;
        case HomeTileType.diaper:
          serialized.add("diaper");
          break;
        case HomeTileType.weaning:
          serialized.add("weaning");
          break;
        case HomeTileType.medication:
          serialized.add("medication");
          break;
        case HomeTileType.breastfeed:
        case HomeTileType.memo:
        case null:
          break;
      }
    }
    return serialized;
  }

  Future<void> _syncSettings() async {
    try {
      await BabyAIApi.instance.updateMySettings(
        themeMode: _mode.name,
        language: _language.name,
        mainFont: _mainFont.name,
        highlightFont: _highlightFont.name,
        accentTone: _accentTone.name,
        bottomMenuEnabled: _serializeBottomMenu(),
        childCareProfile: _childCareProfile.name,
        homeTiles: _serializeHomeTiles(),
        homeTileColumns: _homeTileColumns,
        homeTileOrder: _serializeHomeTileOrder(),
        showSpecialMemo: _showSpecialMemo,
      );
    } catch (_) {
      // Keep local state if sync fails.
    }
  }
}
