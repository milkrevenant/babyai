import "package:flutter/foundation.dart";

class AppEnv {
  const AppEnv._();

  static String get apiBaseUrl {
    const String configured = String.fromEnvironment("API_BASE_URL");
    if (configured.isNotEmpty) {
      return configured;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return "http://10.0.2.2:8000";
    }
    return "http://127.0.0.1:8000";
  }

  static const String apiBearerToken = String.fromEnvironment(
    "API_BEARER_TOKEN",
    defaultValue: "",
  );
  static const String babyId = String.fromEnvironment(
    "BABY_ID",
    defaultValue: "",
  );
  static const String householdId = String.fromEnvironment(
    "HOUSEHOLD_ID",
    defaultValue: "",
  );
  static const String albumId = String.fromEnvironment(
    "ALBUM_ID",
    defaultValue: "",
  );
}
