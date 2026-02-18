import "package:dio/dio.dart";

import "../config/app_env.dart";

class ApiFailure implements Exception {
  ApiFailure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : "$message (HTTP $statusCode)";
}

class BabyAIApi {
  BabyAIApi._()
      : _dio = Dio(
          BaseOptions(
            baseUrl: AppEnv.apiBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 10),
            responseType: ResponseType.json,
          ),
        );

  static final BabyAIApi instance = BabyAIApi._();
  static String _runtimeBearerToken = AppEnv.apiBearerToken;
  static String _runtimeBabyId = AppEnv.babyId;
  static String _runtimeHouseholdId = AppEnv.householdId;
  static String _runtimeAlbumId = AppEnv.albumId;
  final Dio _dio;

  bool get isConfigured =>
      _runtimeBearerToken.isNotEmpty && activeBabyId.isNotEmpty;

  static String get currentBearerToken => _runtimeBearerToken;
  static String get activeBabyId => _runtimeBabyId.trim();
  static String get activeHouseholdId => _runtimeHouseholdId.trim();
  static String get activeAlbumId => _runtimeAlbumId.trim();

  static void setBearerToken(String token) {
    _runtimeBearerToken = token.trim();
  }

  static void setRuntimeIds({
    String? babyId,
    String? householdId,
    String? albumId,
  }) {
    if (babyId != null) {
      _runtimeBabyId = babyId.trim();
    }
    if (householdId != null) {
      _runtimeHouseholdId = householdId.trim();
    }
    if (albumId != null) {
      _runtimeAlbumId = albumId.trim();
    }
  }

  void _requireToken() {
    if (_runtimeBearerToken.isEmpty) {
      throw ApiFailure("Set API_BEARER_TOKEN via --dart-define.");
    }
  }

  void _requireBabyId() {
    if (activeBabyId.isEmpty) {
      throw ApiFailure("Set BABY_ID via --dart-define.");
    }
  }

  void _requireHouseholdId() {
    if (activeHouseholdId.isEmpty) {
      throw ApiFailure("Set HOUSEHOLD_ID via --dart-define.");
    }
  }

  void _requireAlbumId() {
    if (activeAlbumId.isEmpty) {
      throw ApiFailure("Set ALBUM_ID via --dart-define.");
    }
  }

  Options _authOptions({
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) {
    _requireToken();
    return Options(
      headers: <String, String>{
        "Authorization": "Bearer $_runtimeBearerToken",
      },
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
    );
  }

  ApiFailure _toFailure(Object error) {
    if (error is ApiFailure) {
      return error;
    }
    if (error is DioException) {
      final String rawMessage = (error.message ?? "").toLowerCase();
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.unknown ||
          rawMessage.contains("connection refused") ||
          rawMessage.contains("failed host lookup") ||
          rawMessage.contains("connection error")) {
        return ApiFailure(
          "Cannot reach API server (${_dio.options.baseUrl}). "
          "Run backend server or set API_BASE_URL.",
        );
      }
      final int? code = error.response?.statusCode;
      final Object? data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final Object? detail =
            data["detail"] ?? data["error"] ?? data["message"];
        if (detail is String && detail.isNotEmpty) {
          return ApiFailure(detail, statusCode: code);
        }
      }
      return ApiFailure(
        error.message ?? "Request failed",
        statusCode: code,
      );
    }
    return ApiFailure(error.toString());
  }

  Map<String, dynamic> _requireMap(Response<dynamic> response) {
    final dynamic payload = response.data;
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    throw ApiFailure("Unexpected API response shape");
  }

  String _localTimezoneOffset() {
    final Duration offset = DateTime.now().timeZoneOffset;
    final int totalMinutes = offset.inMinutes;
    final String sign = totalMinutes >= 0 ? "+" : "-";
    final int absMinutes = totalMinutes.abs();
    final int hours = absMinutes ~/ 60;
    final int minutes = absMinutes % 60;
    return "$sign${hours.toString().padLeft(2, "0")}:${minutes.toString().padLeft(2, "0")}";
  }

  Future<Map<String, dynamic>> onboardingParent({
    required String provider,
    required String babyName,
    required String babyBirthDate,
    String? babySex,
    double? babyWeightKg,
    String? feedingMethod,
    String? formulaBrand,
    String? formulaProduct,
    String? formulaType,
    bool? formulaContainsStarch,
    List<String> requiredConsents = const <String>[
      "terms",
      "privacy",
      "data_processing",
    ],
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/onboarding/parent",
        data: <String, dynamic>{
          "provider": provider,
          "baby_name": babyName,
          "baby_birth_date": babyBirthDate,
          if (babySex != null && babySex.trim().isNotEmpty)
            "baby_sex": babySex.trim(),
          if (babyWeightKg != null) "baby_weight_kg": babyWeightKg,
          if (feedingMethod != null && feedingMethod.trim().isNotEmpty)
            "feeding_method": feedingMethod.trim(),
          if (formulaBrand != null && formulaBrand.trim().isNotEmpty)
            "formula_brand": formulaBrand.trim(),
          if (formulaProduct != null && formulaProduct.trim().isNotEmpty)
            "formula_product": formulaProduct.trim(),
          if (formulaType != null && formulaType.trim().isNotEmpty)
            "formula_type": formulaType.trim(),
          if (formulaContainsStarch != null)
            "formula_contains_starch": formulaContainsStarch,
          "required_consents": requiredConsents,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> issueLocalDevToken({
    String? sub,
    String? name,
    String provider = "google",
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/dev/local-token",
        queryParameters: <String, dynamic>{
          if (sub != null && sub.trim().isNotEmpty) "sub": sub.trim(),
          if (name != null && name.trim().isNotEmpty) "name": name.trim(),
          if (provider.trim().isNotEmpty) "provider": provider.trim(),
        },
      );
      final Map<String, dynamic> payload = _requireMap(response);
      final String token = (payload["token"] ?? "").toString().trim();
      if (token.isNotEmpty) {
        setBearerToken(token);
      }
      return payload;
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> getBabyProfile() async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/babies/profile",
        queryParameters: <String, dynamic>{"baby_id": activeBabyId},
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> upsertBabyProfile({
    String? babyName,
    String? babyBirthDate,
    String? babySex,
    double? babyWeightKg,
    String? feedingMethod,
    String? formulaBrand,
    String? formulaProduct,
    String? formulaType,
    bool? formulaContainsStarch,
  }) async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.patch<dynamic>(
        "/api/v1/babies/profile",
        data: <String, dynamic>{
          "baby_id": activeBabyId,
          if (babyName != null && babyName.trim().isNotEmpty)
            "baby_name": babyName.trim(),
          if (babyBirthDate != null && babyBirthDate.trim().isNotEmpty)
            "baby_birth_date": babyBirthDate.trim(),
          if (babySex != null && babySex.trim().isNotEmpty)
            "baby_sex": babySex.trim(),
          if (babyWeightKg != null) "baby_weight_kg": babyWeightKg,
          if (feedingMethod != null && feedingMethod.trim().isNotEmpty)
            "feeding_method": feedingMethod.trim(),
          if (formulaBrand != null && formulaBrand.trim().isNotEmpty)
            "formula_brand": formulaBrand.trim(),
          if (formulaProduct != null && formulaProduct.trim().isNotEmpty)
            "formula_product": formulaProduct.trim(),
          if (formulaType != null && formulaType.trim().isNotEmpty)
            "formula_type": formulaType.trim(),
          if (formulaContainsStarch != null)
            "formula_contains_starch": formulaContainsStarch,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> quickLastPooTime() async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/quick/last-poo-time",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          "tz_offset": _localTimezoneOffset(),
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> quickNextFeedingEta() async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/quick/next-feeding-eta",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          "tz_offset": _localTimezoneOffset(),
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> quickTodaySummary() async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/quick/today-summary",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          "tz_offset": _localTimezoneOffset(),
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> quickLastFeeding() async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/quick/last-feeding",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          "tz_offset": _localTimezoneOffset(),
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> quickRecentSleep() async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/quick/recent-sleep",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          "tz_offset": _localTimezoneOffset(),
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> quickLastDiaper() async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/quick/last-diaper",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          "tz_offset": _localTimezoneOffset(),
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> quickLastMedication() async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/quick/last-medication",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          "tz_offset": _localTimezoneOffset(),
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> getMySettings() async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/settings/me",
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> updateMySettings({
    String? themeMode,
    String? language,
    String? mainFont,
    String? highlightFont,
    String? accentTone,
    Map<String, bool>? bottomMenuEnabled,
    String? childCareProfile,
    Map<String, bool>? homeTiles,
    int? homeTileColumns,
    List<String>? homeTileOrder,
    bool? showSpecialMemo,
  }) async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        if (themeMode != null && themeMode.trim().isNotEmpty)
          "theme_mode": themeMode.trim(),
        if (language != null && language.trim().isNotEmpty)
          "language": language.trim(),
        if (mainFont != null && mainFont.trim().isNotEmpty)
          "main_font": mainFont.trim(),
        if (highlightFont != null && highlightFont.trim().isNotEmpty)
          "highlight_font": highlightFont.trim(),
        if (accentTone != null && accentTone.trim().isNotEmpty)
          "accent_tone": accentTone.trim(),
        if (bottomMenuEnabled != null) "bottom_menu_enabled": bottomMenuEnabled,
        if (childCareProfile != null && childCareProfile.trim().isNotEmpty)
          "child_care_profile": childCareProfile.trim(),
        if (homeTiles != null) "home_tiles": homeTiles,
        if (homeTileColumns != null) "home_tile_columns": homeTileColumns,
        if (homeTileOrder != null) "home_tile_order": homeTileOrder,
        if (showSpecialMemo != null) "show_special_memo": showSpecialMemo,
      };
      final Response<dynamic> response = await _dio.patch<dynamic>(
        "/api/v1/settings/me",
        data: payload,
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> quickLandingSnapshot({
    String range = "day",
  }) async {
    try {
      _requireBabyId();
      final String normalizedRange = range.trim().toLowerCase();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/quick/landing-snapshot",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          "range": normalizedRange.isEmpty ? "day" : normalizedRange,
          "tz_offset": _localTimezoneOffset(),
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> siriIntent(
    String intent, {
    String tone = "neutral",
  }) async {
    try {
      _requireBabyId();
      final String resolvedIntent =
          intent.trim().isEmpty ? "GetTodaySummary" : intent.trim();
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/assistants/siri/$resolvedIntent",
        data: <String, dynamic>{
          "baby_id": activeBabyId,
          "tone": tone,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> bixbyQuery(
    String action, {
    String tone = "neutral",
  }) async {
    try {
      _requireBabyId();
      final String resolvedAction =
          action.trim().isEmpty ? "GetTodaySummary" : action.trim();
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/assistants/bixby/query",
        data: <String, dynamic>{
          "capsule_action": resolvedAction,
          "baby_id": activeBabyId,
          "tone": tone,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> queryAi(String question) async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/ai/query",
        data: <String, dynamic>{
          "baby_id": activeBabyId,
          "question": question,
          "tone": "neutral",
          "use_personal_data": true,
        },
        options: _authOptions(
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> createChatSession({
    String? childId,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/chat/sessions",
        data: <String, dynamic>{
          if (childId != null && childId.trim().isNotEmpty)
            "child_id": childId.trim()
          else if (activeBabyId.isNotEmpty)
            "child_id": activeBabyId,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> getChatSessions({
    String? childId,
    int limit = 50,
  }) async {
    try {
      final Map<String, dynamic> params = <String, dynamic>{
        "limit": limit.clamp(1, 100),
      };
      if (childId != null && childId.trim().isNotEmpty) {
        params["child_id"] = childId.trim();
      } else if (activeBabyId.isNotEmpty) {
        params["child_id"] = activeBabyId;
      }
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/chat/sessions",
        queryParameters: params,
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> createChatMessage({
    required String sessionId,
    required String role,
    required String content,
    String? intent,
    Map<String, dynamic>? contextJson,
    String? childId,
  }) async {
    try {
      final String sid = sessionId.trim();
      if (sid.isEmpty) {
        throw ApiFailure("sessionId is required");
      }
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/chat/sessions/$sid/messages",
        data: <String, dynamic>{
          "role": role.trim(),
          "content": content,
          if (intent != null && intent.trim().isNotEmpty)
            "intent": intent.trim(),
          if (contextJson != null) "context_json": contextJson,
          if (childId != null && childId.trim().isNotEmpty)
            "child_id": childId.trim()
          else if (activeBabyId.isNotEmpty)
            "child_id": activeBabyId,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> getChatMessages(String sessionId) async {
    try {
      final String sid = sessionId.trim();
      if (sid.isEmpty) {
        throw ApiFailure("sessionId is required");
      }
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/chat/sessions/$sid/messages",
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> chatQuery({
    required String sessionId,
    required String query,
    String tone = "neutral",
    bool usePersonalData = true,
    String? childId,
  }) async {
    try {
      final String sid = sessionId.trim();
      if (sid.isEmpty) {
        throw ApiFailure("sessionId is required");
      }
      final String question = query.trim();
      if (question.isEmpty) {
        throw ApiFailure("query is required");
      }
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/chat/query",
        data: <String, dynamic>{
          "session_id": sid,
          "query": question,
          "tone": tone,
          "use_personal_data": usePersonalData,
          if (childId != null && childId.trim().isNotEmpty)
            "child_id": childId.trim()
          else if (activeBabyId.isNotEmpty)
            "child_id": activeBabyId,
        },
        options: _authOptions(
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> parseVoice(String? transcriptHint) async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/events/voice",
        data: <String, dynamic>{
          "baby_id": activeBabyId,
          if (transcriptHint != null && transcriptHint.trim().isNotEmpty)
            "transcript_hint": transcriptHint.trim(),
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> confirmVoiceEvents({
    required String clipId,
    required List<Map<String, dynamic>> events,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/events/confirm",
        data: <String, dynamic>{
          "clip_id": clipId,
          "events": events,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> createManualEvent({
    required String type,
    required DateTime startTime,
    DateTime? endTime,
    Map<String, dynamic> value = const <String, dynamic>{},
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/events/manual",
        data: <String, dynamic>{
          "baby_id": activeBabyId,
          "type": type.trim(),
          "start_time": startTime.toUtc().toIso8601String(),
          if (endTime != null) "end_time": endTime.toUtc().toIso8601String(),
          "value": value,
          if (metadata != null) "metadata": metadata,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> startManualEvent({
    required String type,
    required DateTime startTime,
    Map<String, dynamic> value = const <String, dynamic>{},
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/events/start",
        data: <String, dynamic>{
          "baby_id": activeBabyId,
          "type": type.trim(),
          "start_time": startTime.toUtc().toIso8601String(),
          "value": value,
          if (metadata != null) "metadata": metadata,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> completeManualEvent({
    required String eventId,
    DateTime? endTime,
    Map<String, dynamic>? value,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final String normalizedId = eventId.trim();
      if (normalizedId.isEmpty) {
        throw ApiFailure("event_id is required");
      }
      final Response<dynamic> response = await _dio.patch<dynamic>(
        "/api/v1/events/${Uri.encodeComponent(normalizedId)}/complete",
        data: <String, dynamic>{
          if (endTime != null) "end_time": endTime.toUtc().toIso8601String(),
          if (value != null) "value": value,
          if (metadata != null) "metadata": metadata,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> updateManualEvent({
    required String eventId,
    String? type,
    DateTime? startTime,
    DateTime? endTime,
    Map<String, dynamic>? value,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final String normalizedId = eventId.trim();
      if (normalizedId.isEmpty) {
        throw ApiFailure("event_id is required");
      }
      final Response<dynamic> response = await _dio.patch<dynamic>(
        "/api/v1/events/${Uri.encodeComponent(normalizedId)}",
        data: <String, dynamic>{
          if (type != null && type.trim().isNotEmpty) "type": type.trim(),
          if (startTime != null)
            "start_time": startTime.toUtc().toIso8601String(),
          if (endTime != null) "end_time": endTime.toUtc().toIso8601String(),
          if (value != null) "value": value,
          if (metadata != null) "metadata": metadata,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> cancelManualEvent({
    required String eventId,
    String? reason,
  }) async {
    try {
      final String normalizedId = eventId.trim();
      if (normalizedId.isEmpty) {
        throw ApiFailure("event_id is required");
      }
      final Response<dynamic> response = await _dio.patch<dynamic>(
        "/api/v1/events/${Uri.encodeComponent(normalizedId)}/cancel",
        data: <String, dynamic>{
          if (reason != null && reason.trim().isNotEmpty)
            "reason": reason.trim(),
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> listOpenEvents({
    String? type,
  }) async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/events/open",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          if (type != null && type.trim().isNotEmpty) "type": type.trim(),
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> dailyReport(DateTime targetDate) async {
    try {
      _requireBabyId();
      final String day = targetDate.toIso8601String().split("T").first;
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/reports/daily",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          "date": day,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> weeklyReport(DateTime weekStart) async {
    try {
      _requireBabyId();
      final String day = weekStart.toIso8601String().split("T").first;
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/reports/weekly",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          "week_start": day,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> createUploadUrl() async {
    try {
      _requireAlbumId();
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/photos/upload-url",
        queryParameters: <String, dynamic>{"album_id": activeAlbumId},
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> completeUpload({
    required String objectKey,
    required bool downloadable,
  }) async {
    try {
      _requireAlbumId();
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/photos/complete",
        data: <String, dynamic>{
          "album_id": activeAlbumId,
          "object_key": objectKey,
          "downloadable": downloadable,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> uploadPhotoFromDevice({
    required String filePath,
    bool downloadable = false,
  }) async {
    try {
      _requireBabyId();
      final String fileName = filePath.trim().split("/").last;
      final FormData payload = FormData.fromMap(<String, dynamic>{
        "baby_id": activeBabyId,
        if (activeAlbumId.isNotEmpty) "album_id": activeAlbumId,
        "downloadable": downloadable ? "true" : "false",
        "file": await MultipartFile.fromFile(
          filePath,
          filename: fileName.isEmpty ? "photo.jpg" : fileName,
        ),
      });
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/photos/upload",
        data: payload,
        options: _authOptions(),
      );
      final Map<String, dynamic> data = _requireMap(response);
      final String albumID = (data["album_id"] ?? "").toString().trim();
      if (albumID.isNotEmpty) {
        setRuntimeIds(albumId: albumID);
      }
      return data;
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> recentPhotos({int limit = 48}) async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/photos/recent",
        queryParameters: <String, dynamic>{
          "baby_id": activeBabyId,
          "limit": limit,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> subscriptionMe() async {
    try {
      _requireHouseholdId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/subscription/me",
        queryParameters: <String, dynamic>{"household_id": activeHouseholdId},
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }
}
