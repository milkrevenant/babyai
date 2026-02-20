import "dart:async";
import "dart:convert";

import "package:dio/dio.dart";
import "package:flutter/foundation.dart";

import "../config/app_env.dart";
import "../storage/offline_data_store.dart";

enum _LocalEventStatus { open, closed, canceled }

class _LocalEventRecord {
  _LocalEventRecord({
    required this.id,
    required this.type,
    required this.startTime,
    required this.status,
    this.endTime,
    Map<String, dynamic>? value,
    Map<String, dynamic>? metadata,
  })  : value = value ?? <String, dynamic>{},
        metadata = metadata ?? <String, dynamic>{};

  final String id;
  String type;
  DateTime startTime;
  DateTime? endTime;
  _LocalEventStatus status;
  Map<String, dynamic> value;
  Map<String, dynamic> metadata;

  _LocalEventRecord copyWith({
    String? id,
    String? type,
    DateTime? startTime,
    DateTime? endTime,
    _LocalEventStatus? status,
    Map<String, dynamic>? value,
    Map<String, dynamic>? metadata,
  }) {
    return _LocalEventRecord(
      id: id ?? this.id,
      type: type ?? this.type,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      value: value ?? this.value,
      metadata: metadata ?? this.metadata,
    );
  }
}

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
  static const String _cacheSyncEventIds = "sync_event_ids";
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

  Future<void> _ensureLocalDevTokenIfMissing() async {
    if (kReleaseMode) {
      return;
    }
    if (_runtimeBearerToken.trim().isNotEmpty) {
      return;
    }
    try {
      final Map<String, dynamic> issued = await issueLocalDevToken(
        sub: AppEnv.localDevDefaultSub,
        name: "Local Dev User",
        provider: "google",
      );
      final String issuedBabyId = (issued["baby_id"] ?? "").toString().trim();
      final String issuedHouseholdId =
          (issued["household_id"] ?? "").toString().trim();
      if (issuedBabyId.isNotEmpty || issuedHouseholdId.isNotEmpty) {
        setRuntimeIds(
          babyId: issuedBabyId.isNotEmpty ? issuedBabyId : null,
          householdId: issuedHouseholdId.isNotEmpty ? issuedHouseholdId : null,
        );
      }
    } catch (_) {
      // Keep existing behavior when local backend is unavailable.
    }
  }

  void _requireToken() {
    if (_runtimeBearerToken.isEmpty) {
      throw ApiFailure(
        "로그인이 필요합니다. 설정에서 Google 로그인 후 다시 시도해 주세요.",
      );
    }
  }

  void _requireBabyId() {
    if (activeBabyId.isEmpty) {
      throw ApiFailure("아이 프로필이 없습니다. 아이 등록 후 다시 시도해 주세요.");
    }
  }

  void _requireHouseholdId() {
    if (activeHouseholdId.isEmpty) {
      throw ApiFailure("가정 정보가 없습니다. 다시 로그인하거나 아이를 등록해 주세요.");
    }
  }

  void _requireAlbumId() {
    if (activeAlbumId.isEmpty) {
      throw ApiFailure("앨범 정보가 없습니다. 잠시 후 다시 시도해 주세요.");
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

  bool _isBabyNotFoundFailure(ApiFailure failure) {
    final String message = failure.message.toLowerCase();
    final bool statusMatched =
        failure.statusCode == 404 || failure.statusCode == 400;
    if (!statusMatched) {
      return false;
    }
    return message.contains("baby not found") ||
        message.contains("child not found") ||
        message.contains("baby profile not found");
  }

  Future<bool> _recoverLocalDevIdentityForMissingBaby() async {
    if (kReleaseMode) {
      return false;
    }
    try {
      final Map<String, dynamic> issued = await issueLocalDevToken(
        sub: AppEnv.localDevDefaultSub,
        name: "Local Dev User",
        provider: "google",
      );
      final String recoveredBabyId =
          (issued["baby_id"] ?? "").toString().trim();
      final String recoveredHouseholdId =
          (issued["household_id"] ?? "").toString().trim();
      if (recoveredBabyId.isEmpty || recoveredHouseholdId.isEmpty) {
        return false;
      }
      setRuntimeIds(
        babyId: recoveredBabyId,
        householdId: recoveredHouseholdId,
      );
      return true;
    } catch (_) {
      return false;
    }
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

  Map<String, dynamic> _asStringKeyedMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final MapEntry<dynamic, dynamic> entry in value.entries)
          entry.key.toString(): entry.value,
      };
    }
    return <String, dynamic>{};
  }

  DateTime? _parseIsoDateTime(dynamic raw) {
    if (raw == null) {
      return null;
    }
    final String text = raw.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(text).toLocal();
    } catch (_) {
      return null;
    }
  }

  int _extractCount(Map<String, dynamic> value) {
    final List<String> keys = <String>["count", "times", "value", "qty"];
    for (final String key in keys) {
      final Object? raw = value[key];
      if (raw is int) {
        return raw <= 0 ? 1 : raw;
      }
      if (raw is double) {
        final int parsed = raw.round();
        return parsed <= 0 ? 1 : parsed;
      }
      if (raw is String) {
        final int? parsed = int.tryParse(raw.trim());
        if (parsed != null) {
          return parsed <= 0 ? 1 : parsed;
        }
      }
    }
    return 1;
  }

  int _extractMl(Map<String, dynamic> value) {
    const List<String> keys = <String>[
      "amount_ml",
      "amountMl",
      "ml",
      "volume_ml",
      "volumeMl",
      "formula_ml",
    ];
    for (final String key in keys) {
      final Object? raw = value[key];
      if (raw is int) {
        return raw;
      }
      if (raw is double) {
        return raw.round();
      }
      if (raw is String) {
        final int? parsed = int.tryParse(raw.trim());
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return 0;
  }

  String _eventIdFromPayload(
    Map<String, dynamic> payload,
    String fallbackId,
  ) {
    final String explicit = (payload["event_id"] ?? "").toString().trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final String localExplicit =
        (payload["local_event_id"] ?? "").toString().trim();
    if (localExplicit.isNotEmpty) {
      return localExplicit;
    }
    return "local-$fallbackId";
  }

  Future<Map<String, String>> _readSyncEventIdMap() async {
    if (activeBabyId.isEmpty) {
      return <String, String>{};
    }
    final Map<String, dynamic>? cached =
        await OfflineDataStore.instance.readCache(
      namespace: _cacheSyncEventIds,
      babyId: activeBabyId,
      key: "map",
    );
    if (cached == null) {
      return <String, String>{};
    }
    final Map<String, String> out = <String, String>{};
    for (final MapEntry<String, dynamic> entry in cached.entries) {
      final String key = entry.key.trim();
      final String value = entry.value.toString().trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      out[key] = value;
    }
    return out;
  }

  Future<void> _writeSyncEventIdMap(Map<String, String> map) async {
    if (activeBabyId.isEmpty) {
      return;
    }
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheSyncEventIds,
      babyId: activeBabyId,
      key: "map",
      data: <String, dynamic>{
        for (final MapEntry<String, String> e in map.entries) e.key: e.value
      },
    );
  }

  Future<List<_LocalEventRecord>> _localEventRecordsForBaby(
      String babyId) async {
    final List<Map<String, dynamic>> queue =
        await OfflineDataStore.instance.listMutations();
    final Map<String, _LocalEventRecord> records =
        <String, _LocalEventRecord>{};

    for (final Map<String, dynamic> item in queue) {
      final String kind = (item["kind"] ?? "").toString().trim();
      if (kind.isEmpty) {
        continue;
      }
      final Map<String, dynamic> payload = _asStringKeyedMap(item["payload"]);
      final String itemId = (item["id"] ?? "").toString().trim();
      final String payloadBabyId = (payload["baby_id"] ?? "").toString().trim();
      if (payloadBabyId.isNotEmpty &&
          payloadBabyId != babyId &&
          !payloadBabyId.toLowerCase().startsWith("offline_")) {
        continue;
      }

      switch (kind) {
        case "event_create_closed":
          {
            final DateTime? start = _parseIsoDateTime(payload["start_time"]);
            if (start == null) {
              break;
            }
            final String id = _eventIdFromPayload(payload, itemId);
            final String type =
                (payload["type"] ?? "").toString().trim().toUpperCase();
            if (type.isEmpty) {
              break;
            }
            records[id] = _LocalEventRecord(
              id: id,
              type: type,
              startTime: start,
              endTime: _parseIsoDateTime(payload["end_time"]),
              status: _LocalEventStatus.closed,
              value: _asStringKeyedMap(payload["value"]),
              metadata: _asStringKeyedMap(payload["metadata"]),
            );
            break;
          }
        case "event_start":
          {
            final DateTime? start = _parseIsoDateTime(payload["start_time"]);
            if (start == null) {
              break;
            }
            final String id = _eventIdFromPayload(payload, itemId);
            final String type =
                (payload["type"] ?? "").toString().trim().toUpperCase();
            if (type.isEmpty) {
              break;
            }
            records[id] = _LocalEventRecord(
              id: id,
              type: type,
              startTime: start,
              status: _LocalEventStatus.open,
              value: _asStringKeyedMap(payload["value"]),
              metadata: _asStringKeyedMap(payload["metadata"]),
            );
            break;
          }
        case "event_complete":
          {
            final String id = (payload["event_id"] ?? "").toString().trim();
            if (id.isEmpty) {
              break;
            }
            final _LocalEventRecord? existing = records[id];
            final DateTime? end = _parseIsoDateTime(payload["end_time"]);
            final DateTime start =
                existing?.startTime ?? end ?? DateTime.now().toLocal();
            records[id] = (existing ??
                    _LocalEventRecord(
                      id: id,
                      type: "SLEEP",
                      startTime: start,
                      status: _LocalEventStatus.open,
                    ))
                .copyWith(
              endTime: end ?? existing?.endTime,
              status: _LocalEventStatus.closed,
              value: payload.containsKey("value")
                  ? _asStringKeyedMap(payload["value"])
                  : existing?.value,
              metadata: payload.containsKey("metadata")
                  ? _asStringKeyedMap(payload["metadata"])
                  : existing?.metadata,
            );
            break;
          }
        case "event_update":
          {
            final String id = (payload["event_id"] ?? "").toString().trim();
            if (id.isEmpty) {
              break;
            }
            final _LocalEventRecord? existing = records[id];
            if (existing == null) {
              break;
            }
            final String updatedType = (payload["type"] ?? existing.type)
                .toString()
                .trim()
                .toUpperCase();
            records[id] = existing.copyWith(
              type: updatedType.isEmpty ? existing.type : updatedType,
              startTime: _parseIsoDateTime(payload["start_time"]) ??
                  existing.startTime,
              endTime: payload.containsKey("end_time")
                  ? _parseIsoDateTime(payload["end_time"])
                  : existing.endTime,
              value: payload.containsKey("value")
                  ? _asStringKeyedMap(payload["value"])
                  : existing.value,
              metadata: payload.containsKey("metadata")
                  ? _asStringKeyedMap(payload["metadata"])
                  : existing.metadata,
            );
            break;
          }
        case "event_cancel":
          {
            final String id = (payload["event_id"] ?? "").toString().trim();
            if (id.isEmpty) {
              break;
            }
            final _LocalEventRecord? existing = records[id];
            if (existing == null) {
              break;
            }
            records[id] = existing.copyWith(status: _LocalEventStatus.canceled);
            break;
          }
        default:
          break;
      }
    }

    final List<_LocalEventRecord> out = records.values
        .where((_LocalEventRecord e) => e.status != _LocalEventStatus.canceled)
        .toList(growable: false)
      ..sort(
        (_LocalEventRecord a, _LocalEventRecord b) =>
            a.startTime.compareTo(b.startTime),
      );
    return out;
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

  Map<String, dynamic> _payloadForActiveBaby(Map<String, dynamic> payload) {
    final Map<String, dynamic> copy = Map<String, dynamic>.from(payload);
    if (activeBabyId.isNotEmpty) {
      copy["baby_id"] = activeBabyId;
    }
    return copy;
  }

  bool _isMappingPendingError(Object error) {
    return error.toString().toLowerCase().contains("mapping pending");
  }

  Future<void> _dispatchQueuedMutation(
    Map<String, dynamic> item,
    Map<String, String> eventIdMap,
  ) async {
    final String kind = (item["kind"] ?? "").toString().trim();
    final Map<String, dynamic> payload = item["payload"] is Map
        ? Map<String, dynamic>.from(item["payload"] as Map<dynamic, dynamic>)
        : <String, dynamic>{};
    switch (kind) {
      case "event_create_closed":
        final String localEventId =
            (payload["local_event_id"] ?? payload["event_id"] ?? "")
                .toString()
                .trim();
        final Map<String, dynamic> body = _payloadForActiveBaby(payload)
          ..remove("event_id")
          ..remove("local_event_id");
        final Map<String, dynamic> response =
            _requireMap(await _dio.post<dynamic>(
          "/api/v1/events/manual",
          data: body,
          options: _authOptions(),
        ));
        final String remoteEventId =
            (response["event_id"] ?? response["id"] ?? "").toString().trim();
        if (localEventId.isNotEmpty && remoteEventId.isNotEmpty) {
          eventIdMap[localEventId] = remoteEventId;
        }
        return;
      case "event_start":
        final String localEventId =
            (payload["local_event_id"] ?? payload["event_id"] ?? "")
                .toString()
                .trim();
        final Map<String, dynamic> body = _payloadForActiveBaby(payload)
          ..remove("event_id")
          ..remove("local_event_id");
        final Map<String, dynamic> response =
            _requireMap(await _dio.post<dynamic>(
          "/api/v1/events/start",
          data: body,
          options: _authOptions(),
        ));
        final String remoteEventId =
            (response["event_id"] ?? response["id"] ?? "").toString().trim();
        if (localEventId.isNotEmpty && remoteEventId.isNotEmpty) {
          eventIdMap[localEventId] = remoteEventId;
        }
        return;
      case "event_complete":
        final String originEventId =
            (payload["event_id"] ?? "").toString().trim();
        if (originEventId.isEmpty) {
          return;
        }
        final String eventId = eventIdMap[originEventId] ?? originEventId;
        if (eventId.toLowerCase().startsWith("local-") ||
            eventId.toLowerCase().startsWith("offline_")) {
          throw ApiFailure("event mapping pending");
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
        final String originEventId =
            (payload["event_id"] ?? "").toString().trim();
        if (originEventId.isEmpty) {
          return;
        }
        final String eventId = eventIdMap[originEventId] ?? originEventId;
        if (eventId.toLowerCase().startsWith("local-") ||
            eventId.toLowerCase().startsWith("offline_")) {
          throw ApiFailure("event mapping pending");
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
        final String originEventId =
            (payload["event_id"] ?? "").toString().trim();
        if (originEventId.isEmpty) {
          return;
        }
        final String eventId = eventIdMap[originEventId] ?? originEventId;
        if (eventId.toLowerCase().startsWith("local-") ||
            eventId.toLowerCase().startsWith("offline_")) {
          throw ApiFailure("event mapping pending");
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
      final Map<String, String> eventIdMap = await _readSyncEventIdMap();
      bool eventIdMapChanged = false;
      final List<Map<String, dynamic>> queue =
          await OfflineDataStore.instance.listMutations();
      for (final Map<String, dynamic> item in queue) {
        final String id = (item["id"] ?? "").toString().trim();
        if (id.isEmpty) {
          continue;
        }
        try {
          final int beforeCount = eventIdMap.length;
          await _dispatchQueuedMutation(item, eventIdMap);
          if (eventIdMap.length != beforeCount) {
            eventIdMapChanged = true;
            await _writeSyncEventIdMap(eventIdMap);
          }
          await OfflineDataStore.instance.removeMutation(id);
        } catch (error) {
          // Keep queued mutations for later retry when auth/network state changes.
          if (_isConnectivityFailure(error) || _isMappingPendingError(error)) {
            break;
          }
          break;
        }
      }
      if (eventIdMapChanged) {
        await _writeSyncEventIdMap(eventIdMap);
      }
    } finally {
      _mutationFlushInProgress = false;
    }
  }

  Future<void> syncAllLocalDataToServer() async {
    if (!_hasServerLinkedProfile) {
      return;
    }
    await flushOfflineMutations();
    try {
      await _fetchQuickLandingSnapshotRemote("day");
      await _fetchQuickLandingSnapshotRemote("week");
      await _fetchQuickLandingSnapshotRemote("month");
    } catch (_) {
      // Ignore cache refresh failures after mutation flush.
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

  bool _sameLocalDay(DateTime a, DateTime b) {
    final DateTime la = a.toLocal();
    final DateTime lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  String _ymdLocal(DateTime value) {
    final DateTime local = value.toLocal();
    final String y = local.year.toString().padLeft(4, "0");
    final String m = local.month.toString().padLeft(2, "0");
    final String d = local.day.toString().padLeft(2, "0");
    return "$y-$m-$d";
  }

  bool _isNightSleep(DateTime localStart) {
    final int h = localStart.hour;
    return h >= 21 || h < 6;
  }

  String? _lastMedicationName(List<_LocalEventRecord> events) {
    for (int i = events.length - 1; i >= 0; i--) {
      final _LocalEventRecord e = events[i];
      if (e.type != "MEDICATION") {
        continue;
      }
      final Map<String, dynamic> value = e.value;
      final String name = (value["name"] ??
              value["medicine_name"] ??
              value["medication_name"] ??
              value["drug"])
          .toString()
          .trim();
      if (name.isNotEmpty) {
        return name;
      }
    }
    return null;
  }

  String? _latestMemoText(List<_LocalEventRecord> events) {
    for (int i = events.length - 1; i >= 0; i--) {
      final _LocalEventRecord e = events[i];
      if (e.type != "MEMO") {
        continue;
      }
      final String text =
          (e.value["note"] ?? e.value["memo"] ?? e.value["text"] ?? "")
              .toString()
              .trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  Map<String, dynamic> _localSnapshotFromEvents({
    required List<_LocalEventRecord> events,
    required String range,
    required String babyId,
    required String babyName,
  }) {
    final DateTime now = DateTime.now().toLocal();
    final String normalizedRange =
        range.trim().toLowerCase().isEmpty ? "day" : range.trim().toLowerCase();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);
    final DateTime rangeStart = switch (normalizedRange) {
      "week" => _toWeekStartLocal(todayStart),
      "month" => DateTime(todayStart.year, todayStart.month, 1),
      _ => todayStart,
    };
    final DateTime rangeEnd = switch (normalizedRange) {
      "week" => rangeStart.add(const Duration(days: 7)),
      "month" => DateTime(rangeStart.year, rangeStart.month + 1, 1),
      _ => rangeStart.add(const Duration(days: 1)),
    };
    final int rangeDayCount = switch (normalizedRange) {
      "week" => 7,
      "month" => _daysInMonth(rangeStart),
      _ => 1,
    };

    final List<_LocalEventRecord> closedInRange = events
        .where(
          (_LocalEventRecord e) =>
              e.status == _LocalEventStatus.closed &&
              !e.startTime.isBefore(rangeStart) &&
              e.startTime.isBefore(rangeEnd),
        )
        .toList(growable: false);
    final List<_LocalEventRecord> openEvents = events
        .where((_LocalEventRecord e) => e.status == _LocalEventStatus.open)
        .toList(growable: false);

    final List<_LocalEventRecord> formulaEvents = closedInRange
        .where((_LocalEventRecord e) => e.type == "FORMULA")
        .toList(growable: false);
    final List<_LocalEventRecord> breastfeedEvents = closedInRange
        .where((_LocalEventRecord e) => e.type == "BREASTFEED")
        .toList(growable: false);
    final List<_LocalEventRecord> sleepEvents = closedInRange
        .where((_LocalEventRecord e) => e.type == "SLEEP" && e.endTime != null)
        .toList(growable: false);
    final List<_LocalEventRecord> peeEvents = closedInRange
        .where((_LocalEventRecord e) => e.type == "PEE")
        .toList(growable: false);
    final List<_LocalEventRecord> pooEvents = closedInRange
        .where((_LocalEventRecord e) => e.type == "POO")
        .toList(growable: false);
    final List<_LocalEventRecord> medicationEvents = closedInRange
        .where((_LocalEventRecord e) => e.type == "MEDICATION")
        .toList(growable: false);
    final List<_LocalEventRecord> memoEvents = closedInRange
        .where((_LocalEventRecord e) => e.type == "MEMO")
        .toList(growable: false);
    final List<_LocalEventRecord> weaningEvents = closedInRange
        .where(
          (_LocalEventRecord e) =>
              e.type == "WEANING" ||
              (e.value["category"] ?? "").toString().toLowerCase() == "weaning",
        )
        .toList(growable: false);

    final int formulaTotalMl = formulaEvents.fold<int>(
        0, (int s, _LocalEventRecord e) => s + _extractMl(e.value));
    final int formulaCount = formulaEvents.length;
    final int breastfeedCount = breastfeedEvents.length;
    final int feedingsCount = formulaCount + breastfeedCount;

    final int peeCount = peeEvents.fold<int>(
        0, (int s, _LocalEventRecord e) => s + _extractCount(e.value));
    final int pooCount = pooEvents.fold<int>(
        0, (int s, _LocalEventRecord e) => s + _extractCount(e.value));
    final int medicationCount = medicationEvents.length;
    final int memoCount = memoEvents.length;
    final int weaningCount = weaningEvents.length;

    int sleepTotalMin = 0;
    int napTotalMin = 0;
    int nightTotalMin = 0;
    for (final _LocalEventRecord event in sleepEvents) {
      final DateTime end = event.endTime ?? event.startTime;
      final int duration = end.difference(event.startTime).inMinutes;
      if (duration <= 0) {
        continue;
      }
      sleepTotalMin += duration;
      if (_isNightSleep(event.startTime)) {
        nightTotalMin += duration;
      } else {
        napTotalMin += duration;
      }
    }

    _LocalEventRecord? latestClosedOf(String type) {
      for (int i = closedInRange.length - 1; i >= 0; i--) {
        final _LocalEventRecord e = closedInRange[i];
        if (e.type == type) {
          return e;
        }
      }
      return null;
    }

    _LocalEventRecord? latestOpenOf(String type) {
      for (int i = openEvents.length - 1; i >= 0; i--) {
        final _LocalEventRecord e = openEvents[i];
        if (e.type == type) {
          return e;
        }
      }
      return null;
    }

    final _LocalEventRecord? lastFormula = latestClosedOf("FORMULA");
    final _LocalEventRecord? lastBreastfeed = latestClosedOf("BREASTFEED");
    final _LocalEventRecord? lastSleep =
        sleepEvents.isEmpty ? null : sleepEvents.last;
    final _LocalEventRecord? lastPee =
        peeEvents.isEmpty ? null : peeEvents.last;
    final _LocalEventRecord? lastPoo =
        pooEvents.isEmpty ? null : pooEvents.last;
    final _LocalEventRecord? lastMedication =
        medicationEvents.isEmpty ? null : medicationEvents.last;
    final _LocalEventRecord? lastDiaper = (() {
      if (lastPee == null) {
        return lastPoo;
      }
      if (lastPoo == null) {
        return lastPee;
      }
      return lastPee.startTime.isAfter(lastPoo.startTime) ? lastPee : lastPoo;
    })();

    final DateTime? lastSleepEnd = lastSleep?.endTime;
    final int? minutesSinceLastSleep =
        lastSleepEnd == null ? null : now.difference(lastSleepEnd).inMinutes;
    final int? recentSleepDuration = (lastSleep?.endTime == null)
        ? null
        : lastSleep!.endTime!.difference(lastSleep.startTime).inMinutes;

    final _LocalEventRecord? openFormula = latestOpenOf("FORMULA");
    final _LocalEventRecord? openBreastfeed = latestOpenOf("BREASTFEED");
    final _LocalEventRecord? openSleep = latestOpenOf("SLEEP");
    final _LocalEventRecord? openDiaper = (() {
      final _LocalEventRecord? openPee = latestOpenOf("PEE");
      final _LocalEventRecord? openPoo = latestOpenOf("POO");
      if (openPee == null) {
        return openPoo;
      }
      if (openPoo == null) {
        return openPee;
      }
      return openPee.startTime.isAfter(openPoo.startTime) ? openPee : openPoo;
    })();
    final _LocalEventRecord? openWeaning = latestOpenOf("WEANING");
    final _LocalEventRecord? openMedication = latestOpenOf("MEDICATION");
    final String openDiaperType =
        openDiaper == null ? "" : (openDiaper.type == "POO" ? "POO" : "PEE");

    final List<String> graphLabels = <String>[];
    final List<int> graphPoints = <int>[];
    if (normalizedRange == "day") {
      for (final _LocalEventRecord event in formulaEvents) {
        graphLabels.add(
            "${event.startTime.hour.toString().padLeft(2, "0")}:${event.startTime.minute.toString().padLeft(2, "0")}");
        graphPoints.add(_extractMl(event.value));
      }
    } else {
      final int dayCount = normalizedRange == "week" ? 7 : rangeDayCount;
      for (int i = 0; i < dayCount; i++) {
        final DateTime day = rangeStart.add(Duration(days: i));
        graphLabels.add("${day.month}/${day.day}");
        final int total = formulaEvents
            .where((_LocalEventRecord e) => _sameLocalDay(e.startTime, day))
            .fold<int>(
                0, (int s, _LocalEventRecord e) => s + _extractMl(e.value));
        graphPoints.add(total);
      }
    }

    return <String, dynamic>{
      "baby_id": babyId,
      "baby_name": babyName,
      "date": _ymdLocal(now),
      "range": normalizedRange,
      "range_day_count": rangeDayCount,
      "formula_total_ml": formulaTotalMl,
      "formula_daily_avg_ml": (formulaTotalMl / rangeDayCount).round(),
      "formula_count": formulaCount,
      "breastfeed_count": breastfeedCount,
      "feedings_count": feedingsCount,
      "avg_formula_ml_per_day": formulaTotalMl / rangeDayCount,
      "avg_feedings_per_day": feedingsCount / rangeDayCount,
      "avg_sleep_minutes_per_day": sleepTotalMin / rangeDayCount,
      "avg_nap_minutes_per_day": napTotalMin / rangeDayCount,
      "avg_night_sleep_minutes_per_day": nightTotalMin / rangeDayCount,
      "diaper_pee_count": peeCount,
      "diaper_poo_count": pooCount,
      "avg_diaper_pee_per_day": peeCount / rangeDayCount,
      "avg_diaper_poo_per_day": pooCount / rangeDayCount,
      "medication_count": medicationCount,
      "memo_count": memoCount,
      "weaning_count": weaningCount,
      "sleep_avg_min": (sleepTotalMin / rangeDayCount).round(),
      "night_sleep_avg_min": (nightTotalMin / rangeDayCount).round(),
      "nap_avg_min": (napTotalMin / rangeDayCount).round(),
      "last_formula_time": lastFormula?.startTime.toUtc().toIso8601String(),
      "last_breastfeed_time":
          lastBreastfeed?.startTime.toUtc().toIso8601String(),
      "recent_sleep_time": lastSleep?.startTime.toUtc().toIso8601String(),
      "recent_sleep_duration_min": recentSleepDuration ?? 0,
      "last_sleep_end_time": lastSleepEnd?.toUtc().toIso8601String(),
      "minutes_since_last_sleep":
          (minutesSinceLastSleep == null || minutesSinceLastSleep < 0)
              ? null
              : minutesSinceLastSleep,
      "last_diaper_time": lastDiaper?.startTime.toUtc().toIso8601String(),
      "last_pee_time": lastPee?.startTime.toUtc().toIso8601String(),
      "last_poo_time": lastPoo?.startTime.toUtc().toIso8601String(),
      "last_medication_time":
          lastMedication?.startTime.toUtc().toIso8601String(),
      "last_medication_name": _lastMedicationName(medicationEvents),
      "last_weaning_time": (weaningEvents.isEmpty
          ? null
          : weaningEvents.last.startTime.toUtc().toIso8601String()),
      "special_memo": _latestMemoText(memoEvents) ?? "",
      "graph_labels": graphLabels,
      "graph_points": graphPoints,
      "open_formula_event_id": openFormula?.id,
      "open_formula_start_time":
          openFormula?.startTime.toUtc().toIso8601String(),
      "open_formula_value": openFormula?.value ?? <String, dynamic>{},
      "open_breastfeed_event_id": openBreastfeed?.id,
      "open_breastfeed_start_time":
          openBreastfeed?.startTime.toUtc().toIso8601String(),
      "open_breastfeed_value": openBreastfeed?.value ?? <String, dynamic>{},
      "open_sleep_event_id": openSleep?.id,
      "open_sleep_start_time": openSleep?.startTime.toUtc().toIso8601String(),
      "open_sleep_value": openSleep?.value ?? <String, dynamic>{},
      "open_diaper_event_id": openDiaper?.id,
      "open_diaper_start_time": openDiaper?.startTime.toUtc().toIso8601String(),
      "open_diaper_type": openDiaperType,
      "open_diaper_value": openDiaper?.value ?? <String, dynamic>{},
      "open_weaning_event_id": openWeaning?.id,
      "open_weaning_start_time":
          openWeaning?.startTime.toUtc().toIso8601String(),
      "open_weaning_value": openWeaning?.value ?? <String, dynamic>{},
      "open_medication_event_id": openMedication?.id,
      "open_medication_start_time":
          openMedication?.startTime.toUtc().toIso8601String(),
      "open_medication_value": openMedication?.value ?? <String, dynamic>{},
      "offline_cached": true,
    };
  }

  Future<Map<String, dynamic>> _buildLocalLandingSnapshot({
    required String normalizedRange,
  }) async {
    _requireBabyId();
    final Map<String, dynamic>? profile =
        await _readCachedBabyProfile(babyId: activeBabyId);
    final String babyName =
        (profile?["baby_name"] ?? profile?["name"] ?? "우리 아기").toString();
    final List<_LocalEventRecord> events =
        await _localEventRecordsForBaby(activeBabyId);
    final Map<String, dynamic> snapshot = _localSnapshotFromEvents(
      events: events,
      range: normalizedRange,
      babyId: activeBabyId,
      babyName: babyName,
    );
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheQuickLanding,
      babyId: activeBabyId,
      key: normalizedRange,
      data: snapshot,
    );
    return snapshot;
  }

  Future<Map<String, dynamic>> _buildFallbackOfflineLandingSnapshot({
    required String normalizedRange,
  }) async {
    _requireBabyId();
    final Map<String, dynamic>? profile =
        await _readCachedBabyProfile(babyId: activeBabyId);
    final String babyName =
        (profile?["baby_name"] ?? profile?["name"] ?? "우리 아기").toString();
    final int rangeDayCount = switch (normalizedRange) {
      "week" => 7,
      "month" => _daysInMonth(DateTime.now().toLocal()),
      _ => 1,
    };
    final Map<String, dynamic> payload = _buildOfflineLandingSnapshot(
      babyId: activeBabyId,
      babyName: babyName,
      range: normalizedRange,
      rangeDayCount: rangeDayCount,
    );
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheQuickLanding,
      babyId: activeBabyId,
      key: normalizedRange,
      data: payload,
    );
    return payload;
  }

  Future<Map<String, dynamic>> _buildLocalDailyReport(
      DateTime targetDate) async {
    _requireBabyId();
    final DateTime localDate = targetDate.toLocal();
    final DateTime dayStart =
        DateTime(localDate.year, localDate.month, localDate.day);
    final DateTime dayEnd = dayStart.add(const Duration(days: 1));
    final List<_LocalEventRecord> all =
        await _localEventRecordsForBaby(activeBabyId);
    final List<_LocalEventRecord> closed = all
        .where(
          (_LocalEventRecord e) =>
              e.status == _LocalEventStatus.closed &&
              !e.startTime.isBefore(dayStart) &&
              e.startTime.isBefore(dayEnd),
        )
        .toList(growable: false)
      ..sort(
        (_LocalEventRecord a, _LocalEventRecord b) =>
            a.startTime.compareTo(b.startTime),
      );

    final int sleepTotal = closed
        .where((_LocalEventRecord e) => e.type == "SLEEP" && e.endTime != null)
        .fold<int>(
            0,
            (int s, _LocalEventRecord e) =>
                s +
                (e.endTime!
                    .difference(e.startTime)
                    .inMinutes
                    .clamp(0, 24 * 60)));
    final int feedings = closed
        .where((_LocalEventRecord e) =>
            e.type == "FORMULA" || e.type == "BREASTFEED")
        .length;
    final int formulaTotal = closed
        .where((_LocalEventRecord e) => e.type == "FORMULA")
        .fold<int>(0, (int s, _LocalEventRecord e) => s + _extractMl(e.value));
    final int pee = closed
        .where((_LocalEventRecord e) => e.type == "PEE")
        .fold<int>(
            0, (int s, _LocalEventRecord e) => s + _extractCount(e.value));
    final int poo = closed
        .where((_LocalEventRecord e) => e.type == "POO")
        .fold<int>(
            0, (int s, _LocalEventRecord e) => s + _extractCount(e.value));

    final List<Map<String, dynamic>> eventRows = closed
        .map(
          (_LocalEventRecord e) => <String, dynamic>{
            "type": e.type,
            "start_time": e.startTime.toUtc().toIso8601String(),
            if (e.endTime != null)
              "end_time": e.endTime!.toUtc().toIso8601String(),
            "value": e.value,
          },
        )
        .toList(growable: false);

    final Map<String, dynamic> payload = <String, dynamic>{
      "baby_id": activeBabyId,
      "date": _ymdLocal(dayStart.toUtc()),
      "summary": <String>[
        "Sleep total: $sleepTotal min",
        "Feeding events: $feedings",
        "Formula total: $formulaTotal ml",
        "Diaper pee: $pee",
        "Diaper poo: $poo",
      ],
      "events": eventRows,
      "labels": <dynamic>[],
      "offline_cached": true,
    };
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheDailyReport,
      babyId: activeBabyId,
      key: targetDate.toIso8601String().split("T").first,
      data: payload,
    );
    return payload;
  }

  Future<Map<String, dynamic>> _buildLocalWeeklyReport(
      DateTime weekStart) async {
    _requireBabyId();
    final DateTime localWeekStart = weekStart.toLocal();
    final DateTime weekEnd = localWeekStart.add(const Duration(days: 7));
    final List<_LocalEventRecord> all =
        await _localEventRecordsForBaby(activeBabyId);
    final List<_LocalEventRecord> closed = all
        .where(
          (_LocalEventRecord e) =>
              e.status == _LocalEventStatus.closed &&
              !e.startTime.isBefore(localWeekStart) &&
              e.startTime.isBefore(weekEnd),
        )
        .toList(growable: false);

    final int formulaTotal = closed
        .where((_LocalEventRecord e) => e.type == "FORMULA")
        .fold<int>(0, (int s, _LocalEventRecord e) => s + _extractMl(e.value));
    final int sleepTotal = closed
        .where((_LocalEventRecord e) => e.type == "SLEEP" && e.endTime != null)
        .fold<int>(
            0,
            (int s, _LocalEventRecord e) =>
                s + e.endTime!.difference(e.startTime).inMinutes);
    final int diaperTotal = closed
        .where((_LocalEventRecord e) => e.type == "PEE" || e.type == "POO")
        .fold<int>(
            0, (int s, _LocalEventRecord e) => s + _extractCount(e.value));

    final Map<String, dynamic> payload = <String, dynamic>{
      "baby_id": activeBabyId,
      "week_start": weekStart.toIso8601String().split("T").first,
      "trend": <String, dynamic>{
        "feeding_total_ml": formulaTotal,
        "sleep_total_min": sleepTotal,
        "diaper_total_count": diaperTotal,
      },
      "suggestions": <String>[
        "로컬 기록 기반 주간 요약입니다.",
      ],
      "labels": <dynamic>[],
      "offline_cached": true,
    };
    await OfflineDataStore.instance.writeCache(
      namespace: _cacheWeeklyReport,
      babyId: activeBabyId,
      key: weekStart.toIso8601String().split("T").first,
      data: payload,
    );
    return payload;
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
      final String issuedBabyId = (payload["baby_id"] ?? "").toString().trim();
      final String issuedHouseholdId =
          (payload["household_id"] ?? "").toString().trim();
      if (issuedBabyId.isNotEmpty || issuedHouseholdId.isNotEmpty) {
        setRuntimeIds(
          babyId: issuedBabyId.isNotEmpty ? issuedBabyId : null,
          householdId: issuedHouseholdId.isNotEmpty ? issuedHouseholdId : null,
        );
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
    final String normalizedRange = range.trim().toLowerCase();
    final String cacheKey = normalizedRange.isEmpty ? "day" : normalizedRange;
    try {
      _requireBabyId();
      final Map<String, dynamic>? cached =
          await OfflineDataStore.instance.readCache(
        namespace: _cacheQuickLanding,
        babyId: activeBabyId,
        key: cacheKey,
      );
      if (preferOffline || !_hasServerLinkedProfile) {
        try {
          final Map<String, dynamic> local =
              await _buildLocalLandingSnapshot(normalizedRange: cacheKey);
          if (_hasServerLinkedProfile) {
            unawaited(_refreshQuickLandingSnapshotCache(cacheKey));
          }
          return _withOfflineCacheFlag(local);
        } catch (_) {
          if (cached != null) {
            return _withOfflineCacheFlag(cached);
          }
          return await _buildFallbackOfflineLandingSnapshot(
            normalizedRange: cacheKey,
          );
        }
      }
      await flushOfflineMutations();
      return await _fetchQuickLandingSnapshotRemote(cacheKey);
    } catch (error) {
      try {
        return await _buildLocalLandingSnapshot(normalizedRange: cacheKey);
      } catch (_) {
        final Map<String, dynamic>? cached =
            await OfflineDataStore.instance.readCache(
          namespace: _cacheQuickLanding,
          babyId: activeBabyId,
          key: cacheKey,
        );
        if (cached != null) {
          return _withOfflineCacheFlag(cached);
        }
        try {
          return await _buildFallbackOfflineLandingSnapshot(
            normalizedRange: cacheKey,
          );
        } catch (_) {
          throw _toFailure(error);
        }
      }
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
      await _ensureLocalDevTokenIfMissing();
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
      await _ensureLocalDevTokenIfMissing();
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
      final ApiFailure failure = _toFailure(error);
      if (_isBabyNotFoundFailure(failure) &&
          await _recoverLocalDevIdentityForMissingBaby()) {
        final Response<dynamic> retry = await _dio.post<dynamic>(
          "/api/v1/chat/sessions",
          data: <String, dynamic>{
            if (activeBabyId.isNotEmpty) "child_id": activeBabyId,
          },
          options: _authOptions(),
        );
        return _requireMap(retry);
      }
      throw failure;
    }
  }

  Future<Map<String, dynamic>> getChatSessions({
    String? childId,
    int limit = 50,
  }) async {
    try {
      await _ensureLocalDevTokenIfMissing();
      if (!_hasServerLinkedProfile) {
        return <String, dynamic>{
          "sessions": <dynamic>[],
          "offline_cached": true,
        };
      }
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
      final ApiFailure failure = _toFailure(error);
      if (_isBabyNotFoundFailure(failure) &&
          await _recoverLocalDevIdentityForMissingBaby()) {
        try {
          final Response<dynamic> retry = await _dio.get<dynamic>(
            "/api/v1/chat/sessions",
            queryParameters: <String, dynamic>{
              "limit": limit.clamp(1, 100),
              if (activeBabyId.isNotEmpty) "child_id": activeBabyId,
            },
            options: _authOptions(),
          );
          return _requireMap(retry);
        } catch (_) {
          // Fall through to offline empty payload.
        }
      }
      return <String, dynamic>{
        "sessions": <dynamic>[],
        "offline_cached": true,
      };
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
      await _ensureLocalDevTokenIfMissing();
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
      final ApiFailure failure = _toFailure(error);
      if (_isBabyNotFoundFailure(failure) &&
          await _recoverLocalDevIdentityForMissingBaby()) {
        final String sid = sessionId.trim();
        final Response<dynamic> retry = await _dio.post<dynamic>(
          "/api/v1/chat/sessions/$sid/messages",
          data: <String, dynamic>{
            "role": role.trim(),
            "content": content,
            if (intent != null && intent.trim().isNotEmpty)
              "intent": intent.trim(),
            if (contextJson != null) "context_json": contextJson,
            if (activeBabyId.isNotEmpty) "child_id": activeBabyId,
          },
          options: _authOptions(),
        );
        return _requireMap(retry);
      }
      throw failure;
    }
  }

  Future<Map<String, dynamic>> getChatMessages(String sessionId) async {
    try {
      await _ensureLocalDevTokenIfMissing();
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
      await _ensureLocalDevTokenIfMissing();
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
      final ApiFailure failure = _toFailure(error);
      if (_isBabyNotFoundFailure(failure) &&
          await _recoverLocalDevIdentityForMissingBaby()) {
        final String sid = sessionId.trim();
        final String question = query.trim();
        final DateTime anchor = (anchorDate ?? DateTime.now()).toLocal();
        final String normalizedMode = dateMode.trim().toLowerCase().isEmpty
            ? "day"
            : dateMode.trim().toLowerCase();
        final String anchorDateText =
            "${anchor.year.toString().padLeft(4, "0")}-"
            "${anchor.month.toString().padLeft(2, "0")}-"
            "${anchor.day.toString().padLeft(2, "0")}";
        final Response<dynamic> retry = await _dio.post<dynamic>(
          "/api/v1/chat/query",
          data: <String, dynamic>{
            "session_id": sid,
            "query": question,
            "tone": tone,
            "use_personal_data": usePersonalData,
            "date_mode": normalizedMode,
            "anchor_date": anchorDateText,
            if (activeBabyId.isNotEmpty) "child_id": activeBabyId,
          },
          options: _authOptions(
            connectTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 90),
          ),
        );
        return _requireMap(retry);
      }
      throw failure;
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
    final String localEventId =
        "local-${DateTime.now().toUtc().microsecondsSinceEpoch}";
    final Map<String, dynamic> offlinePayload = <String, dynamic>{
      "event_id": localEventId,
      "local_event_id": localEventId,
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
        "event_id": localEventId,
      };
    }
    try {
      await flushOfflineMutations();
      final Map<String, dynamic> remoteBody = Map<String, dynamic>.from(
        offlinePayload,
      )
        ..remove("event_id")
        ..remove("local_event_id");
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/events/manual",
        data: remoteBody,
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
          "event_id": localEventId,
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
    final String localEventId =
        "local-${DateTime.now().toUtc().microsecondsSinceEpoch}";
    final Map<String, dynamic> offlinePayload = <String, dynamic>{
      "event_id": localEventId,
      "local_event_id": localEventId,
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
        "event_id": localEventId,
      };
    }
    try {
      await flushOfflineMutations();
      final Map<String, dynamic> remoteBody = Map<String, dynamic>.from(
        offlinePayload,
      )
        ..remove("event_id")
        ..remove("local_event_id");
      final Response<dynamic> response = await _dio.post<dynamic>(
        "/api/v1/events/start",
        data: remoteBody,
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
          "event_id": localEventId,
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
      final String normalizedType = (type ?? "").trim().toUpperCase();
      final List<_LocalEventRecord> all =
          await _localEventRecordsForBaby(activeBabyId);
      final List<Map<String, dynamic>> items = all
          .where((_LocalEventRecord e) => e.status == _LocalEventStatus.open)
          .where(
            (_LocalEventRecord e) =>
                normalizedType.isEmpty || e.type == normalizedType,
          )
          .map(
            (_LocalEventRecord e) => <String, dynamic>{
              "event_id": e.id,
              "type": e.type,
              "start_time": e.startTime.toUtc().toIso8601String(),
              "value": e.value,
            },
          )
          .toList(growable: false);
      return <String, dynamic>{
        "items": items,
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
    if (preferOffline || !_hasServerLinkedProfile) {
      try {
        final Map<String, dynamic> local =
            await _buildLocalDailyReport(targetDate);
        if (_hasServerLinkedProfile) {
          unawaited(_refreshDailyReportCache(targetDate));
        }
        return _withOfflineCacheFlag(local);
      } catch (_) {
        if (cached != null) {
          return _withOfflineCacheFlag(cached);
        }
        return <String, dynamic>{
          "baby_id": activeBabyId,
          "date": day,
          "summary": <String>[],
          "events": <dynamic>[],
          "labels": <dynamic>[],
          "offline_cached": true,
        };
      }
    }
    try {
      await flushOfflineMutations();
      return await _fetchDailyReportRemote(targetDate);
    } catch (_) {
      if (cached != null) {
        return _withOfflineCacheFlag(cached);
      }
      return await _buildLocalDailyReport(targetDate);
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
    if (preferOffline || !_hasServerLinkedProfile) {
      try {
        final Map<String, dynamic> local =
            await _buildLocalWeeklyReport(weekStart);
        if (_hasServerLinkedProfile) {
          unawaited(_refreshWeeklyReportCache(weekStart));
        }
        return _withOfflineCacheFlag(local);
      } catch (_) {
        if (cached != null) {
          return _withOfflineCacheFlag(cached);
        }
        return <String, dynamic>{
          "baby_id": activeBabyId,
          "week_start": day,
          "trend": <String, dynamic>{},
          "suggestions": <String>[],
          "labels": <dynamic>[],
          "offline_cached": true,
        };
      }
    }
    try {
      await flushOfflineMutations();
      return await _fetchWeeklyReportRemote(weekStart);
    } catch (_) {
      if (cached != null) {
        return _withOfflineCacheFlag(cached);
      }
      return await _buildLocalWeeklyReport(weekStart);
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
