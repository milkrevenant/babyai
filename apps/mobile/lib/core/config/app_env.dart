class AppEnv {
  const AppEnv._();

  static const String apiBaseUrl = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "http://127.0.0.1:8000",
  );
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
