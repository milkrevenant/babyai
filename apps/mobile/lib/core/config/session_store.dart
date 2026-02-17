import "dart:convert";
import "dart:io";

import "../network/babyai_api.dart";

class AppSessionStore {
  const AppSessionStore._();

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

      BabyAIApi.setRuntimeIds(
        babyId: (parsed["baby_id"] ?? "").toString(),
        householdId: (parsed["household_id"] ?? "").toString(),
        albumId: (parsed["album_id"] ?? "").toString(),
      );
      final String token = (parsed["token"] ?? "").toString().trim();
      if (token.isNotEmpty) {
        BabyAIApi.setBearerToken(token);
      }
    } catch (_) {
      // Keep runtime defaults when local session cannot be loaded.
    }
  }

  static Future<void> persistRuntimeState() async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        "baby_id": BabyAIApi.activeBabyId,
        "household_id": BabyAIApi.activeHouseholdId,
        "album_id": BabyAIApi.activeAlbumId,
        "token": BabyAIApi.currentBearerToken.trim(),
      };
      final File file = _sessionFile();
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {
      // Ignore persistence failure in local environments.
    }
  }
}
