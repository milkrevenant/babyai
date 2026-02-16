import "package:dio/dio.dart";

import "../config/app_env.dart";

class ApiFailure implements Exception {
  ApiFailure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null ? message : "$message (HTTP $statusCode)";
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
  final Dio _dio;

  bool get isConfigured =>
      AppEnv.apiBearerToken.isNotEmpty && AppEnv.babyId.isNotEmpty;

  void _requireToken() {
    if (AppEnv.apiBearerToken.isEmpty) {
      throw ApiFailure("Set API_BEARER_TOKEN via --dart-define.");
    }
  }

  void _requireBabyId() {
    if (AppEnv.babyId.isEmpty) {
      throw ApiFailure("Set BABY_ID via --dart-define.");
    }
  }

  void _requireHouseholdId() {
    if (AppEnv.householdId.isEmpty) {
      throw ApiFailure("Set HOUSEHOLD_ID via --dart-define.");
    }
  }

  void _requireAlbumId() {
    if (AppEnv.albumId.isEmpty) {
      throw ApiFailure("Set ALBUM_ID via --dart-define.");
    }
  }

  Options _authOptions() {
    _requireToken();
    return Options(
      headers: <String, String>{
        "Authorization": "Bearer ${AppEnv.apiBearerToken}",
      },
    );
  }

  ApiFailure _toFailure(Object error) {
    if (error is ApiFailure) {
      return error;
    }
    if (error is DioException) {
      final int? code = error.response?.statusCode;
      final Object? data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final Object? detail = data["detail"] ?? data["error"] ?? data["message"];
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

  Future<Map<String, dynamic>> quickLastPooTime() async {
    try {
      _requireBabyId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/quick/last-poo-time",
        queryParameters: <String, dynamic>{"baby_id": AppEnv.babyId},
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
        queryParameters: <String, dynamic>{"baby_id": AppEnv.babyId},
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
        queryParameters: <String, dynamic>{"baby_id": AppEnv.babyId},
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
          "baby_id": AppEnv.babyId,
          "question": question,
          "tone": "neutral",
          "use_personal_data": true,
        },
        options: _authOptions(),
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
          "baby_id": AppEnv.babyId,
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

  Future<Map<String, dynamic>> dailyReport(DateTime targetDate) async {
    try {
      _requireBabyId();
      final String day = targetDate.toIso8601String().split("T").first;
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/reports/daily",
        queryParameters: <String, dynamic>{
          "baby_id": AppEnv.babyId,
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
          "baby_id": AppEnv.babyId,
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
        queryParameters: <String, dynamic>{"album_id": AppEnv.albumId},
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
          "album_id": AppEnv.albumId,
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

  Future<Map<String, dynamic>> subscriptionMe() async {
    try {
      _requireHouseholdId();
      final Response<dynamic> response = await _dio.get<dynamic>(
        "/api/v1/subscription/me",
        queryParameters: <String, dynamic>{"household_id": AppEnv.householdId},
        options: _authOptions(),
      );
      return _requireMap(response);
    } catch (error) {
      throw _toFailure(error);
    }
  }
}
