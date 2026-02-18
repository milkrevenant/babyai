import "dart:convert";
import "dart:io";

import "app_env.dart";
import "../network/babyai_api.dart";

class AppSessionStore {
  const AppSessionStore._();

  static DateTime? _pendingSleepStart;
  static DateTime? _pendingFormulaStart;

  static File _sessionFile() {
    final String home = Platform.environment["USERPROFILE"] ??
        Platform.environment["HOME"] ??
        "";
    if (home.trim().isEmpty) {
      return File(
          "${Directory.systemTemp.path}${Platform.pathSeparator}babyai_session.json");
    }
    return File("$home${Platform.pathSeparator}.babyai_session.json");
  }

  static Future<void> load() async {
    try {
      final File file = _sessionFile();
      if (!await file.exists()) {
        return;
      }
      final String raw = await file.readAsString();
      final Object? parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) {
        return;
      }

      final bool hasDefineBabyId = AppEnv.babyId.trim().isNotEmpty;
      final bool hasDefineHouseholdId = AppEnv.householdId.trim().isNotEmpty;
      final bool hasDefineAlbumId = AppEnv.albumId.trim().isNotEmpty;
      final bool hasDefineToken = AppEnv.apiBearerToken.trim().isNotEmpty;

      BabyAIApi.setRuntimeIds(
        babyId: hasDefineBabyId ? null : (parsed["baby_id"] ?? "").toString(),
        householdId: hasDefineHouseholdId
            ? null
            : (parsed["household_id"] ?? "").toString(),
        albumId:
            hasDefineAlbumId ? null : (parsed["album_id"] ?? "").toString(),
      );

      final String token = (parsed["token"] ?? "").toString().trim();
      if (!hasDefineToken && token.isNotEmpty) {
        BabyAIApi.setBearerToken(token);
      }

      final String pendingSleepRaw =
          (parsed["pending_sleep_start"] ?? "").toString().trim();
      if (pendingSleepRaw.isNotEmpty) {
        try {
          _pendingSleepStart = DateTime.parse(pendingSleepRaw).toUtc();
        } catch (_) {
          _pendingSleepStart = null;
        }
      } else {
        _pendingSleepStart = null;
      }

      final String pendingFormulaRaw =
          (parsed["pending_formula_start"] ?? "").toString().trim();
      if (pendingFormulaRaw.isNotEmpty) {
        try {
          _pendingFormulaStart = DateTime.parse(pendingFormulaRaw).toUtc();
        } catch (_) {
          _pendingFormulaStart = null;
        }
      } else {
        _pendingFormulaStart = null;
      }
    } catch (_) {
      // Keep runtime defaults when local session cannot be loaded.
    }
  }

  static DateTime? get pendingSleepStart => _pendingSleepStart;
  static DateTime? get pendingFormulaStart => _pendingFormulaStart;

  static Future<void> setPendingSleepStart(DateTime? value) async {
    _pendingSleepStart = value?.toUtc();
    await persistRuntimeState();
  }

  static Future<void> setPendingFormulaStart(DateTime? value) async {
    _pendingFormulaStart = value?.toUtc();
    await persistRuntimeState();
  }

  static Future<void> persistRuntimeState() async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        "baby_id": BabyAIApi.activeBabyId,
        "household_id": BabyAIApi.activeHouseholdId,
        "album_id": BabyAIApi.activeAlbumId,
        "token": BabyAIApi.currentBearerToken.trim(),
        if (_pendingSleepStart != null)
          "pending_sleep_start": _pendingSleepStart!.toIso8601String(),
        if (_pendingFormulaStart != null)
          "pending_formula_start": _pendingFormulaStart!.toIso8601String(),
      };
      final File file = _sessionFile();
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {
      // Ignore persistence failure in local environments.
    }
  }
}
