import "dart:convert";
import "dart:io";

class OfflineDataStore {
  OfflineDataStore._();

  static final OfflineDataStore instance = OfflineDataStore._();

  static const String _cacheRoot = "caches";
  static const String _mutationRoot = "mutations";

  bool _loaded = false;
  Map<String, dynamic> _state = <String, dynamic>{
    _cacheRoot: <String, dynamic>{},
    _mutationRoot: <dynamic>[],
  };

  File _storeFile() {
    final String home = Platform.environment["USERPROFILE"] ??
        Platform.environment["HOME"] ??
        "";
    if (home.trim().isEmpty) {
      return File(
        "${Directory.systemTemp.path}${Platform.pathSeparator}babyai_offline_store.json",
      );
    }
    return File("$home${Platform.pathSeparator}.babyai_offline_store.json");
  }

  String _cacheKey(String namespace, String babyId, String key) {
    return "${namespace.trim()}::${babyId.trim()}::${key.trim()}";
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    try {
      final File file = _storeFile();
      if (!await file.exists()) {
        return;
      }
      final String raw = await file.readAsString();
      final Object? parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) {
        return;
      }
      final Map<String, dynamic> merged = <String, dynamic>{
        _cacheRoot: <String, dynamic>{},
        _mutationRoot: <dynamic>[],
      };
      final Object? cacheObj = parsed[_cacheRoot];
      if (cacheObj is Map<String, dynamic>) {
        merged[_cacheRoot] = cacheObj;
      }
      final Object? mutationObj = parsed[_mutationRoot];
      if (mutationObj is List<dynamic>) {
        merged[_mutationRoot] = mutationObj;
      }
      _state = merged;
    } catch (_) {
      _state = <String, dynamic>{
        _cacheRoot: <String, dynamic>{},
        _mutationRoot: <dynamic>[],
      };
    }
  }

  Future<void> _persist() async {
    try {
      final File file = _storeFile();
      await file.writeAsString(jsonEncode(_state), flush: true);
    } catch (_) {
      // Ignore local persistence failure in dev/offline environments.
    }
  }

  Future<Map<String, dynamic>?> readCache({
    required String namespace,
    required String babyId,
    required String key,
  }) async {
    await _ensureLoaded();
    final Map<String, dynamic> caches =
        (_state[_cacheRoot] as Map<String, dynamic>? ?? <String, dynamic>{});
    final Object? entry = caches[_cacheKey(namespace, babyId, key)];
    if (entry is! Map<String, dynamic>) {
      return null;
    }
    final Object? data = entry["data"];
    if (data is! Map<String, dynamic>) {
      return null;
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> writeCache({
    required String namespace,
    required String babyId,
    required String key,
    required Map<String, dynamic> data,
  }) async {
    await _ensureLoaded();
    final Map<String, dynamic> caches =
        (_state[_cacheRoot] as Map<String, dynamic>? ?? <String, dynamic>{});
    caches[_cacheKey(namespace, babyId, key)] = <String, dynamic>{
      "saved_at": DateTime.now().toUtc().toIso8601String(),
      "data": data,
    };
    _state[_cacheRoot] = caches;
    await _persist();
  }

  Future<void> enqueueMutation({
    required String kind,
    required Map<String, dynamic> payload,
  }) async {
    await _ensureLoaded();
    final List<dynamic> queue =
        (_state[_mutationRoot] as List<dynamic>? ?? <dynamic>[]);
    queue.add(<String, dynamic>{
      "id": "m-${DateTime.now().toUtc().microsecondsSinceEpoch}",
      "kind": kind.trim(),
      "payload": payload,
      "queued_at": DateTime.now().toUtc().toIso8601String(),
    });
    _state[_mutationRoot] = queue;
    await _persist();
  }

  Future<List<Map<String, dynamic>>> listMutations() async {
    await _ensureLoaded();
    final List<dynamic> raw =
        (_state[_mutationRoot] as List<dynamic>? ?? <dynamic>[]);
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final dynamic item in raw) {
      if (item is Map<String, dynamic>) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
  }

  Future<void> removeMutation(String id) async {
    await _ensureLoaded();
    final String normalized = id.trim();
    if (normalized.isEmpty) {
      return;
    }
    final List<dynamic> raw =
        (_state[_mutationRoot] as List<dynamic>? ?? <dynamic>[]);
    raw.removeWhere((dynamic item) {
      if (item is! Map<String, dynamic>) {
        return false;
      }
      return (item["id"] ?? "").toString().trim() == normalized;
    });
    _state[_mutationRoot] = raw;
    await _persist();
  }
}
