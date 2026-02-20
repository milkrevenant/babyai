import "dart:async";
import "dart:convert";

import "package:dio/dio.dart";

import "../config/app_env.dart";
import "../storage/offline_data_store.dart";

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
  static bool _mutationFlushInProgress = false;
  static const String _cacheQuickLanding = "quick_landing_snapshot";
  static const String _cacheDailyReport = "daily_report";
  static const String _cacheWeeklyReport = "weekly_report";
  static const String _cacheBabyProfile = "baby_profile";
  final Dio _dio;

  bool get isConfigured =>
      _runtimeBearerToken.isNotEmpty && activeBabyId.isNotEmpty;

  static String get currentBearerToken => _runtimeBearerToken;
  static String get activeBabyId => _runtimeBabyId.trim();
  static String get activeHouseholdId => _runtimeHouseholdId.trim();
  static String get activeAlbumId => _runtimeAlbumId.trim();
  static String? get currentTokenProvider {
    final String token = _runtimeBearerToken.trim();
    if (token.isEmpty) {
      return null;
    }
    try {
      final List<String> parts = token.split(".");
      if (parts.length < 2) {
        return null;
      }
      final String payloadPart = base64Url.normalize(parts[1]);
      final Object? payload =
          jsonDecode(utf8.decode(base64Url.decode(payloadPart)));
      if (payload is! Map<String, dynamic>) {
        return null;
      }
      final String provider = (payload["provider"] ?? "").toString().trim();
      if (provider.isEmpty) {
        return null;
      }
      return provider.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  static bool get isGoogleLinked => currentTokenProvider == "google";

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

  bool get _isOnlineSyncEnabled => isGoogleLinked;
  bool get _hasServerLinkedProfile =>
      _isOnlineSyncEnabled &&
      activeBabyId.isNotEmpty &&
      !activeBabyId.toLowerCase().startsWith("offline_");

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

  bool _isConnectivityFailure(Object error) {
    if (error is ApiFailure) {
      return error.message.toLowerCase().contains("cannot reach api server");
    }
    if (error is DioException) {
      final String rawMessage = (error.message ?? "").toLowerCase();
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.unknown ||
          rawMessage.contains("connection refused") ||
          rawMessage.contains("failed host lookup") ||
          rawMessage.contains("connection error");
    }
    return false;
  }

  Map<String, dynamic> _withOfflineCacheFlag(Map<String, dynamic> data) {
    final Map<String, dynamic> copy = Map<String, dynamic>.from(data);
    copy["offline_cached"] = true;
    return copy;
  }

  Future<void> _enqueueEventMutation({
    required String kind,
    required Map<String, dynamic> payload,
  }) async {
    await OfflineDataStore.instance.enqueueMutation(
      kind: kind,
      payload: payload,
    );
  }

  Future<void> _dispatchQueuedMutation(Map<String, dynamic> item) async {
    final String kind = (item["kind"] ?? "").toString().trim();
    final Map<String, dynamic> payload = item["payload"] is Map
        ? Map<String, dynamic>.from(item["payload"] as Map<dynamic, dynamic>)
        : <String, dynamic>{};
    switch (kind) {
      case "event_create_closed":
        await _dio.post<dynamic>(
          "/api/v1/events/manual",
          data: payload,
          options: _authOptions(),
        );
        return;
      case "event_start":
        await _dio.post<dynamic>(
          "/api/v1/events/start",
          data: payload,
          options: _authOptions(),
        );
        return;
      case "event_complete":
        final String eventId = (payload["event_id"] ?? "").toString().trim();
        if (eventId.isEmpty) {
          return;
        }
        final Map<String, dynamic> body = Map<String, dynamic>.from(payload)
          ..remove("event_id");
        await _dio.patch<dynamic>(
          "/api/v1/events/${Uri.encodeComponent(eventId)}/complete",
          data: body,
          options: _authOptions(),
        );
        return;
      case "event_update":
        final String eventId = (payload["event_id"] ?? "").toString().trim();
        if (eventId.isEmpty) {
          return;
        }
        final Map<String, dynamic> body = Map<String, dynamic>.from(payload)
          ..remove("event_id");
        await _dio.patch<dynamic>(
          "/api/v1/events/${Uri.encodeComponent(eventId)}",
          data: body,
          options: _authOptions(),
        );
        return;
      case "event_cancel":
        final String eventId = (payload["event_id"] ?? "").toString().trim();
        if (eventId.isEmpty) {
          return;
        }
        final Map<String, dynamic> body = Map<String, dynamic>.from(payload)
          ..remove("event_id");
        await _dio.patch<dynamic>(
          "/api/v1/events/${Uri.encodeComponent(eventId)}/cancel",
          data: body,
          options: _authOptions(),
        );
        return;
      default:
        return;
    }
  }

  Future<void> flushOfflineMutations() async {
    if (!_hasServerLinkedProfile) {
      return;
    }
    if (_mutationFlushInProgress) {
      return;
    }
    _mutationFlushInProgress = true;
    try {
      final List<Map<String, dynamic>> queue =
          await OfflineDataStore.instance.listMutations();
      for (final Map<String, dynamic> item in queue) {
        final String id = (item["id"] ?? "").toString().trim();
        if (id.isEmpty) {
          continue;
        }
        try {
          await _dispatchQueuedMutation(item);
          await OfflineDataStore.instance.removeMutation(id);
        } catch (error) {
          // Keep queued mutations for later retry when auth/network state changes.
          if (_isConnectivityFailure(error)) {
            break;
          }
          break;
        }
      }
    } finally {
      _mutationFlushInProgress = false;
    }
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

  String _offlineId(String prefix) {
    final int micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return "offline_${prefix}_$micros";
  }

  int _daysInMonth(DateTime dateLocal) {
    return DateTime(dateLocal.year, dateLocal.month + 1, 0).day;
  }

  DateTime _toWeekStartLocal(DateTime dateLocal) {
    return dateLocal
        .subtract(Duration(days: dateLocal.weekday - DateTime.monday));
  }

  Future<void> _writeCachedBabyProfile({
    required String babyId,
    required Map<String, dynamic> profile,
  }) async {
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheBabyProfile,
      babyId: babyId,
      key: "profile",
      data: profile,
    );
  }

  Future<Map<String, dynamic>?> _readCachedBabyProfile({
    required String babyId,
  }) async {
    if (babyId.trim().isEmpty) {
      return null;
    }
    return OfflineDataStore.instance.readCache(
      namespace: _cacheBabyProfile,
      babyId: babyId,
      key: "profile",
    );
  }

  Map<String, dynamic> _buildOfflineProfile({
    required String babyId,
    required String babyName,
    required String babyBirthDate,
    required String babySex,
    double? babyWeightKg,
    required String feedingMethod,
    required String formulaBrand,
    required String formulaProduct,
    required String formulaType,
    required bool formulaContainsStarch,
  }) {
    final DateTime nowLocal = DateTime.now().toLocal();
    final DateTime birthLocal =
        DateTime.tryParse(babyBirthDate)?.toLocal() ?? nowLocal;
    final int ageDays = nowLocal
        .difference(DateTime(birthLocal.year, birthLocal.month, birthLocal.day))
        .inDays;
    final String formulaDisplay = <String>[
      formulaBrand.trim(),
      formulaProduct.trim(),
    ].where((String it) => it.isNotEmpty).join(" ");

    return <String, dynamic>{
      "baby_id": babyId,
      "baby_name": babyName.trim().isEmpty ? "우리 아기" : babyName.trim(),
      "birth_date": babyBirthDate.trim(),
      "age_days": ageDays < 0 ? 0 : ageDays,
      "sex": babySex.trim().isEmpty ? "unknown" : babySex.trim(),
      "weight_kg": babyWeightKg,
      "feeding_method":
          feedingMethod.trim().isEmpty ? "mixed" : feedingMethod.trim(),
      "formula_brand": formulaBrand.trim(),
      "formula_product": formulaProduct.trim(),
      "formula_type":
          formulaType.trim().isEmpty ? "standard" : formulaType.trim(),
      "formula_contains_starch": formulaContainsStarch,
      "formula_display_name": formulaDisplay.isEmpty ? "기본 분유" : formulaDisplay,
      "recommended_formula_daily_ml": null,
      "recommended_formula_per_feed_ml": null,
      "recommended_feed_interval_min": 180,
      "recommended_next_feeding_time": null,
      "recommended_next_feeding_in_min": null,
      "recommendation_reference_text": "",
      "recommendation_note": "",
      "formula_catalog": <dynamic>[],
      "offline_cached": true,
    };
  }

  Map<String, dynamic> _buildOfflineLandingSnapshot({
    required String babyId,
    required String babyName,
    required String range,
    required int rangeDayCount,
  }) {
    final DateTime nowLocal = DateTime.now().toLocal();
    final String date = nowLocal.toIso8601String().split("T").first;
    return <String, dynamic>{
      "baby_id": babyId,
      "baby_name": babyName,
      "baby_profile_photo_url": null,
      "date": date,
      "range": range,
      "range_day_count": rangeDayCount,
      "formula_total_ml": 0,
      "formula_daily_avg_ml": 0,
      "feedings_count": 0,
      "feedings_daily_avg_count": 0,
      "formula_count": 0,
      "breastfeed_count": 0,
      "breastfeed_daily_avg_count": 0,
      "sleep_avg_min": 0,
      "night_sleep_avg_min": 0,
      "nap_avg_min": 0,
      "pee_count": 0,
      "poo_count": 0,
      "medication_count": 0,
      "memo_count": 0,
      "weaning_count": 0,
      "last_formula_time": null,
      "last_breastfeed_time": null,
      "last_sleep_end_time": null,
      "recent_sleep_duration_min": 0,
      "recent_sleep_gap_min": 0,
      "last_pee_time": null,
      "last_poo_time": null,
      "last_medication_time": null,
      "last_medication_name": null,
      "last_weaning_time": null,
      "special_memo": "",
      "graph_labels": <dynamic>[],
      "graph_points": <dynamic>[],
      "open_formula_event_id": null,
      "open_formula_start_time": null,
      "open_formula_value": <String, dynamic>{},
      "open_breastfeed_event_id": null,
      "open_breastfeed_start_time": null,
      "open_breastfeed_value": <String, dynamic>{},
      "open_sleep_event_id": null,
      "open_sleep_start_time": null,
      "open_sleep_value": <String, dynamic>{},
      "open_diaper_event_id": null,
      "open_diaper_start_time": null,
      "open_diaper_value": <String, dynamic>{},
      "open_weaning_event_id": null,
      "open_weaning_start_time": null,
      "open_weaning_value": <String, dynamic>{},
      "open_medication_event_id": null,
      "open_medication_start_time": null,
      "open_medication_value": <String, dynamic>{},
      "offline_cached": true,
    };
  }

  Future<void> _seedOfflineSnapshotAndReports({
    required String babyId,
    required String babyName,
  }) async {
    final DateTime todayLocal = DateTime.now().toLocal();
    final DateTime weekStartLocal = _toWeekStartLocal(todayLocal);
    final DateTime monthStartLocal =
        DateTime(todayLocal.year, todayLocal.month, 1);
    final int monthDays = _daysInMonth(todayLocal);

    await OfflineDataStore.instance.writeCache(
      namespace: _cacheQuickLanding,
      babyId: babyId,
      key: "day",
      data: _buildOfflineLandingSnapshot(
        babyId: babyId,
        babyName: babyName,
        range: "day",
        rangeDayCount: 1,
      ),
    );
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheQuickLanding,
      babyId: babyId,
      key: "week",
      data: _buildOfflineLandingSnapshot(
        babyId: babyId,
        babyName: babyName,
        range: "week",
        rangeDayCount: 7,
      ),
    );
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheQuickLanding,
      babyId: babyId,
      key: "month",
      data: _buildOfflineLandingSnapshot(
        babyId: babyId,
        babyName: babyName,
        range: "month",
        rangeDayCount: monthDays,
      ),
    );

    final String todayKey = DateTime.utc(
      todayLocal.year,
      todayLocal.month,
      todayLocal.day,
    ).toIso8601String().split("T").first;
    final String weekKey = DateTime.utc(
      weekStartLocal.year,
      weekStartLocal.month,
      weekStartLocal.day,
    ).toIso8601String().split("T").first;

    await OfflineDataStore.instance.writeCache(
      namespace: _cacheDailyReport,
      babyId: babyId,
      key: todayKey,
      data: <String, dynamic>{
        "baby_id": babyId,
        "date": todayKey,
        "summary": <dynamic>[],
        "events": <dynamic>[],
        "labels": <dynamic>[],
        "offline_cached": true,
      },
    );
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheWeeklyReport,
      babyId: babyId,
      key: weekKey,
      data: <String, dynamic>{
        "baby_id": babyId,
        "week_start": weekKey,
        "trend": <String, dynamic>{},
        "suggestions": <dynamic>[],
        "labels": <dynamic>[],
        "offline_cached": true,
      },
    );
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheDailyReport,
      babyId: babyId,
      key: DateTime.utc(
        monthStartLocal.year,
        monthStartLocal.month,
        monthStartLocal.day,
      ).toIso8601String().split("T").first,
      data: <String, dynamic>{
        "baby_id": babyId,
        "date": DateTime.utc(
          monthStartLocal.year,
          monthStartLocal.month,
          monthStartLocal.day,
        ).toIso8601String().split("T").first,
        "summary": <dynamic>[],
        "events": <dynamic>[],
        "labels": <dynamic>[],
        "offline_cached": true,
      },
    );
  }

  Future<Map<String, dynamic>> createOfflineOnboarding({
    required String babyName,
    required String babyBirthDate,
    String? babySex,
    double? babyWeightKg,
    String? feedingMethod,
    String? formulaBrand,
    String? formulaProduct,
    String? formulaType,
    bool? formulaContainsStarch,
  }) async {
    final String babyId =
        activeBabyId.isNotEmpty ? activeBabyId : _offlineId("baby");
    final String householdId = activeHouseholdId.isNotEmpty
        ? activeHouseholdId
        : _offlineId("household");
    final String albumId =
        activeAlbumId.isNotEmpty ? activeAlbumId : _offlineId("album");
    final String resolvedBabyName =
        babyName.trim().isEmpty ? "우리 아기" : babyName.trim();
    final String resolvedBirthDate = babyBirthDate.trim().isEmpty
        ? DateTime.now().toIso8601String().split("T").first
        : babyBirthDate.trim();
    final Map<String, dynamic> profile = _buildOfflineProfile(
      babyId: babyId,
      babyName: resolvedBabyName,
      babyBirthDate: resolvedBirthDate,
      babySex: (babySex ?? "unknown").trim(),
      babyWeightKg: babyWeightKg,
      feedingMethod: (feedingMethod ?? "mixed").trim(),
      formulaBrand: (formulaBrand ?? "").trim(),
      formulaProduct: (formulaProduct ?? "").trim(),
      formulaType: (formulaType ?? "standard").trim(),
      formulaContainsStarch: formulaContainsStarch ?? false,
    );

    setRuntimeIds(babyId: babyId, householdId: householdId, albumId: albumId);
    await _writeCachedBabyProfile(babyId: babyId, profile: profile);
    await _seedOfflineSnapshotAndReports(
      babyId: babyId,
      babyName: resolvedBabyName,
    );

    return <String, dynamic>{
      "status": "offline_local",
      "baby_id": babyId,
      "household_id": householdId,
      "album_id": albumId,
      "offline_cached": true,
    };
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
    _requireBabyId();
    final Map<String, dynamic>? cached = await _readCachedBabyProfile(
      babyId: activeBabyId,
    );
    if (!_hasServerLinkedProfile) {
      if (cached != null) {
        return _withOfflineCacheFlag(cached);
      }
      throw ApiFailure("Local profile not found.");
    }
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/babies/profile",
        queryParameters: <String, dynamic>{"baby_id": activeBabyId},
        options: _authOptions(),
      );
      final Map<String, dynamic> payload = _requireMap(response);
      await _writeCachedBabyProfile(
        babyId: activeBabyId,
        profile: payload,
      );
      return payload;
    } catch (error) {
      if (cached != null) {
        return _withOfflineCacheFlag(cached);
      }
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
    Future<Map<String, dynamic>> writeOfflineProfile() async {
      final Map<String, dynamic> merged = <String, dynamic>{
        ...(await _readCachedBabyProfile(babyId: activeBabyId) ??
            <String, dynamic>{}),
        "baby_id": activeBabyId,
        if (babyName != null && babyName.trim().isNotEmpty)
          "baby_name": babyName.trim(),
        if (babyBirthDate != null && babyBirthDate.trim().isNotEmpty)
          "birth_date": babyBirthDate.trim(),
        if (babySex != null && babySex.trim().isNotEmpty) "sex": babySex.trim(),
        if (babyWeightKg != null) "weight_kg": babyWeightKg,
        if (feedingMethod != null && feedingMethod.trim().isNotEmpty)
          "feeding_method": feedingMethod.trim(),
        if (formulaBrand != null) "formula_brand": formulaBrand.trim(),
        if (formulaProduct != null) "formula_product": formulaProduct.trim(),
        if (formulaType != null && formulaType.trim().isNotEmpty)
          "formula_type": formulaType.trim(),
        if (formulaContainsStarch != null)
          "formula_contains_starch": formulaContainsStarch,
        "offline_cached": true,
      };
      if (merged["baby_name"] == null ||
          (merged["baby_name"] ?? "").toString().trim().isEmpty) {
        merged["baby_name"] = "우리 아기";
      }
      await _writeCachedBabyProfile(
        babyId: activeBabyId,
        profile: merged,
      );
      return _withOfflineCacheFlag(merged);
    }

    try {
      _requireBabyId();
      if (!_hasServerLinkedProfile) {
        return writeOfflineProfile();
      }
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
      final Map<String, dynamic> payload = _requireMap(response);
      await _writeCachedBabyProfile(
        babyId: activeBabyId,
        profile: payload,
      );
      return payload;
    } catch (error) {
      return writeOfflineProfile();
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
    String? reportColorTone,
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
        if (reportColorTone != null && reportColorTone.trim().isNotEmpty)
          "report_color_tone": reportColorTone.trim(),
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

  Future<String> exportDataCsv({String? babyId}) async {
    try {
      _requireBabyId();
      final String resolvedBabyId = (babyId ?? activeBabyId).trim();
      if (resolvedBabyId.isEmpty) {
        throw ApiFailure("baby_id is required");
      }
      final Options options = _authOptions().copyWith(
        responseType: ResponseType.plain,
      );
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/data/export.csv",
        queryParameters: <String, dynamic>{
          "baby_id": resolvedBabyId,
        },
        options: options,
      );
      final dynamic payload = response.data;
      if (payload is String) {
        return payload;
      }
      return payload?.toString() ?? "";
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> _fetchQuickLandingSnapshotRemote(
    String normalizedRange,
  ) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      "/api/v1/quick/landing-snapshot",
      queryParameters: <String, dynamic>{
        "baby_id": activeBabyId,
        "range": normalizedRange.isEmpty ? "day" : normalizedRange,
        "tz_offset": _localTimezoneOffset(),
      },
      options: _authOptions(),
    );
    final Map<String, dynamic> payload = _requireMap(response);
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheQuickLanding,
      babyId: activeBabyId,
      key: normalizedRange.isEmpty ? "day" : normalizedRange,
      data: payload,
    );
    return payload;
  }

  Future<void> _refreshQuickLandingSnapshotCache(String normalizedRange) async {
    if (!_hasServerLinkedProfile) {
      return;
    }
    try {
      await _fetchQuickLandingSnapshotRemote(normalizedRange);
    } catch (_) {
      // Ignore background refresh failures.
    }
  }

  Future<Map<String, dynamic>> quickLandingSnapshot({
    String range = "day",
    bool preferOffline = true,
  }) async {
    try {
      _requireBabyId();
      final String normalizedRange = range.trim().toLowerCase();
      final String cacheKey = normalizedRange.isEmpty ? "day" : normalizedRange;
      final Map<String, dynamic>? cached =
          await OfflineDataStore.instance.readCache(
        namespace: _cacheQuickLanding,
        babyId: activeBabyId,
        key: cacheKey,
      );
      if (preferOffline && cached != null) {
        if (_hasServerLinkedProfile) {
          unawaited(_refreshQuickLandingSnapshotCache(cacheKey));
        }
        return _withOfflineCacheFlag(cached);
      }
      if (!_hasServerLinkedProfile && cached != null) {
        return _withOfflineCacheFlag(cached);
      }
      await flushOfflineMutations();
      return await _fetchQuickLandingSnapshotRemote(cacheKey);
    } catch (error) {
      final Map<String, dynamic>? cached =
          await OfflineDataStore.instance.readCache(
        namespace: _cacheQuickLanding,
        babyId: activeBabyId,
        key: range.trim().toLowerCase().isEmpty
            ? "day"
            : range.trim().toLowerCase(),
      );
      if (cached != null) {
        return _withOfflineCacheFlag(cached);
      }
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
      await flushOfflineMutations();
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
    String dateMode = "day",
    DateTime? anchorDate,
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
      final DateTime anchor = (anchorDate ?? DateTime.now()).toLocal();
      final String normalizedMode = dateMode.trim().toLowerCase().isEmpty
          ? "day"
          : dateMode.trim().toLowerCase();
      final String anchorDateText = "${anchor.year.toString().padLeft(4, "0")}-"
          "${anchor.month.toString().padLeft(2, "0")}-"
          "${anchor.day.toString().padLeft(2, "0")}";
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/chat/query",
        data: <String, dynamic>{
          "session_id": sid,
          "query": question,
          "tone": tone,
          "use_personal_data": usePersonalData,
          "date_mode": normalizedMode,
          "anchor_date": anchorDateText,
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
    _requireBabyId();
    final Map<String, dynamic> offlinePayload = <String, dynamic>{
      "baby_id": activeBabyId,
      "type": type.trim(),
      "start_time": startTime.toUtc().toIso8601String(),
      if (endTime != null) "end_time": endTime.toUtc().toIso8601String(),
      "value": value,
      if (metadata != null) "metadata": metadata,
    };
    if (!_hasServerLinkedProfile) {
      await _enqueueEventMutation(
        kind: "event_create_closed",
        payload: offlinePayload,
      );
      return <String, dynamic>{
        "status": "queued_offline",
        "queued": true,
        "event_id": "local-${DateTime.now().millisecondsSinceEpoch}",
      };
    }
    try {
      await flushOfflineMutations();
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/events/manual",
        data: offlinePayload,
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      if (_isConnectivityFailure(error)) {
        await _enqueueEventMutation(
          kind: "event_create_closed",
          payload: offlinePayload,
        );
        return <String, dynamic>{
          "status": "queued_offline",
          "queued": true,
          "event_id": "local-${DateTime.now().millisecondsSinceEpoch}",
        };
      }
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> startManualEvent({
    required String type,
    required DateTime startTime,
    Map<String, dynamic> value = const <String, dynamic>{},
    Map<String, dynamic>? metadata,
  }) async {
    _requireBabyId();
    final Map<String, dynamic> offlinePayload = <String, dynamic>{
      "baby_id": activeBabyId,
      "type": type.trim(),
      "start_time": startTime.toUtc().toIso8601String(),
      "value": value,
      if (metadata != null) "metadata": metadata,
    };
    if (!_hasServerLinkedProfile) {
      await _enqueueEventMutation(
        kind: "event_start",
        payload: offlinePayload,
      );
      return <String, dynamic>{
        "status": "queued_offline",
        "queued": true,
        "event_id": "local-${DateTime.now().millisecondsSinceEpoch}",
      };
    }
    try {
      await flushOfflineMutations();
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/events/start",
        data: offlinePayload,
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      if (_isConnectivityFailure(error)) {
        await _enqueueEventMutation(
          kind: "event_start",
          payload: offlinePayload,
        );
        return <String, dynamic>{
          "status": "queued_offline",
          "queued": true,
          "event_id": "local-${DateTime.now().millisecondsSinceEpoch}",
        };
      }
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> completeManualEvent({
    required String eventId,
    DateTime? endTime,
    Map<String, dynamic>? value,
    Map<String, dynamic>? metadata,
  }) async {
    final String normalizedId = eventId.trim();
    if (normalizedId.isEmpty) {
      throw ApiFailure("event_id is required");
    }
    final Map<String, dynamic> offlinePayload = <String, dynamic>{
      "event_id": normalizedId,
      if (endTime != null) "end_time": endTime.toUtc().toIso8601String(),
      if (value != null) "value": value,
      if (metadata != null) "metadata": metadata,
    };
    if (!_hasServerLinkedProfile) {
      await _enqueueEventMutation(
        kind: "event_complete",
        payload: offlinePayload,
      );
      return <String, dynamic>{
        "status": "queued_offline",
        "queued": true,
        "event_id": normalizedId,
      };
    }
    try {
      await flushOfflineMutations();
      final Response<dynamic> response = await _dio.patch<dynamic>(
        "/api/v1/events/${Uri.encodeComponent(normalizedId)}/complete",
        data: Map<String, dynamic>.from(offlinePayload)..remove("event_id"),
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      if (_isConnectivityFailure(error)) {
        await _enqueueEventMutation(
          kind: "event_complete",
          payload: offlinePayload,
        );
        return <String, dynamic>{
          "status": "queued_offline",
          "queued": true,
          "event_id": normalizedId,
        };
      }
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
    final String normalizedId = eventId.trim();
    if (normalizedId.isEmpty) {
      throw ApiFailure("event_id is required");
    }
    final Map<String, dynamic> offlinePayload = <String, dynamic>{
      "event_id": normalizedId,
      if (type != null && type.trim().isNotEmpty) "type": type.trim(),
      if (startTime != null) "start_time": startTime.toUtc().toIso8601String(),
      if (endTime != null) "end_time": endTime.toUtc().toIso8601String(),
      if (value != null) "value": value,
      if (metadata != null) "metadata": metadata,
    };
    if (!_hasServerLinkedProfile) {
      await _enqueueEventMutation(
        kind: "event_update",
        payload: offlinePayload,
      );
      return <String, dynamic>{
        "status": "queued_offline",
        "queued": true,
        "event_id": normalizedId,
      };
    }
    try {
      await flushOfflineMutations();
      final Response<dynamic> response = await _dio.patch<dynamic>(
        "/api/v1/events/${Uri.encodeComponent(normalizedId)}",
        data: Map<String, dynamic>.from(offlinePayload)..remove("event_id"),
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      if (_isConnectivityFailure(error)) {
        await _enqueueEventMutation(
          kind: "event_update",
          payload: offlinePayload,
        );
        return <String, dynamic>{
          "status": "queued_offline",
          "queued": true,
          "event_id": normalizedId,
        };
      }
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> cancelManualEvent({
    required String eventId,
    String? reason,
  }) async {
    final String normalizedId = eventId.trim();
    if (normalizedId.isEmpty) {
      throw ApiFailure("event_id is required");
    }
    final Map<String, dynamic> offlinePayload = <String, dynamic>{
      "event_id": normalizedId,
      if (reason != null && reason.trim().isNotEmpty) "reason": reason.trim(),
    };
    if (!_hasServerLinkedProfile) {
      await _enqueueEventMutation(
        kind: "event_cancel",
        payload: offlinePayload,
      );
      return <String, dynamic>{
        "status": "queued_offline",
        "queued": true,
        "event_id": normalizedId,
      };
    }
    try {
      await flushOfflineMutations();
      final Response<dynamic> response = await _dio.patch<dynamic>(
        "/api/v1/events/${Uri.encodeComponent(normalizedId)}/cancel",
        data: Map<String, dynamic>.from(offlinePayload)..remove("event_id"),
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      if (_isConnectivityFailure(error)) {
        await _enqueueEventMutation(
          kind: "event_cancel",
          payload: offlinePayload,
        );
        return <String, dynamic>{
          "status": "queued_offline",
          "queued": true,
          "event_id": normalizedId,
        };
      }
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> listOpenEvents({
    String? type,
  }) async {
    if (!_hasServerLinkedProfile) {
      return <String, dynamic>{
        "items": <dynamic>[],
        "offline_cached": true,
      };
    }
    try {
      await flushOfflineMutations();
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

  Future<Map<String, dynamic>> _fetchDailyReportRemote(
      DateTime targetDate) async {
    final String day = targetDate.toIso8601String().split("T").first;
    final Response<dynamic> response = await _dio.get<dynamic>(
      "/api/v1/reports/daily",
      queryParameters: <String, dynamic>{
        "baby_id": activeBabyId,
        "date": day,
      },
      options: _authOptions(),
    );
    final Map<String, dynamic> payload = _requireMap(response);
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheDailyReport,
      babyId: activeBabyId,
      key: day,
      data: payload,
    );
    return payload;
  }

  Future<void> _refreshDailyReportCache(DateTime targetDate) async {
    if (!_hasServerLinkedProfile) {
      return;
    }
    try {
      await _fetchDailyReportRemote(targetDate);
    } catch (_) {
      // Ignore background refresh failures.
    }
  }

  Future<Map<String, dynamic>> dailyReport(
    DateTime targetDate, {
    bool preferOffline = true,
  }) async {
    _requireBabyId();
    final String day = targetDate.toIso8601String().split("T").first;
    final Map<String, dynamic>? cached =
        await OfflineDataStore.instance.readCache(
      namespace: _cacheDailyReport,
      babyId: activeBabyId,
      key: day,
    );
    if (preferOffline && cached != null) {
      if (_hasServerLinkedProfile) {
        unawaited(_refreshDailyReportCache(targetDate));
      }
      return _withOfflineCacheFlag(cached);
    }
    if (!_hasServerLinkedProfile && cached != null) {
      return _withOfflineCacheFlag(cached);
    }
    try {
      await flushOfflineMutations();
      return await _fetchDailyReportRemote(targetDate);
    } catch (error) {
      if (cached != null) {
        return _withOfflineCacheFlag(cached);
      }
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> _fetchWeeklyReportRemote(
      DateTime weekStart) async {
    final String day = weekStart.toIso8601String().split("T").first;
    final Response<dynamic> response = await _dio.get<dynamic>(
      "/api/v1/reports/weekly",
      queryParameters: <String, dynamic>{
        "baby_id": activeBabyId,
        "week_start": day,
      },
      options: _authOptions(),
    );
    final Map<String, dynamic> payload = _requireMap(response);
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheWeeklyReport,
      babyId: activeBabyId,
      key: day,
      data: payload,
    );
    return payload;
  }

  Future<void> _refreshWeeklyReportCache(DateTime weekStart) async {
    if (!_hasServerLinkedProfile) {
      return;
    }
    try {
      await _fetchWeeklyReportRemote(weekStart);
    } catch (_) {
      // Ignore background refresh failures.
    }
  }

  Future<Map<String, dynamic>> weeklyReport(
    DateTime weekStart, {
    bool preferOffline = true,
  }) async {
    _requireBabyId();
    final String day = weekStart.toIso8601String().split("T").first;
    final Map<String, dynamic>? cached =
        await OfflineDataStore.instance.readCache(
      namespace: _cacheWeeklyReport,
      babyId: activeBabyId,
      key: day,
    );
    if (preferOffline && cached != null) {
      if (_hasServerLinkedProfile) {
        unawaited(_refreshWeeklyReportCache(weekStart));
      }
      return _withOfflineCacheFlag(cached);
    }
    if (!_hasServerLinkedProfile && cached != null) {
      return _withOfflineCacheFlag(cached);
    }
    try {
      await flushOfflineMutations();
      return await _fetchWeeklyReportRemote(weekStart);
    } catch (error) {
      if (cached != null) {
        return _withOfflineCacheFlag(cached);
      }
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

  Future<Map<String, dynamic>> checkoutSubscription({
    required String plan,
  }) async {
    try {
      _requireHouseholdId();
      final String normalizedPlan = plan.trim().toUpperCase();
      if (normalizedPlan.isEmpty) {
        throw ApiFailure("plan is required");
      }
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/subscription/checkout",
        data: <String, dynamic>{
          "household_id": activeHouseholdId,
          "plan": normalizedPlan,
        },
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }
}
