import "dart:async";

import "package:flutter/services.dart";

class AssistantActionPayload {
  const AssistantActionPayload({
    this.feature,
    this.query,
    this.memo,
    this.diaperType,
    this.amountMl,
    this.durationMin,
    this.grams,
    this.dose,
    this.source,
  });

  final String? feature;
  final String? query;
  final String? memo;
  final String? diaperType;
  final int? amountMl;
  final int? durationMin;
  final int? grams;
  final int? dose;
  final String? source;

  bool get isEmpty {
    return (feature ?? "").trim().isEmpty &&
        (query ?? "").trim().isEmpty &&
        (memo ?? "").trim().isEmpty &&
        amountMl == null &&
        durationMin == null &&
        grams == null &&
        dose == null;
  }

  factory AssistantActionPayload.fromMap(Map<dynamic, dynamic> raw) {
    int? parseInt(dynamic value) {
      if (value is int) {
        return value;
      }
      if (value is double) {
        return value.round();
      }
      if (value is String) {
        return int.tryParse(value.trim());
      }
      return null;
    }

    String? parseString(dynamic value) {
      if (value == null) {
        return null;
      }
      final String text = value.toString().trim();
      if (text.isEmpty) {
        return null;
      }
      return text;
    }

    return AssistantActionPayload(
      feature: parseString(raw["feature"])?.toLowerCase(),
      query: parseString(raw["query"]),
      memo: parseString(raw["memo"]),
      diaperType: parseString(raw["diaper_type"]),
      amountMl: parseInt(raw["amount_ml"]),
      durationMin: parseInt(raw["duration_min"]),
      grams: parseInt(raw["grams"]),
      dose: parseInt(raw["dose"]),
      source: parseString(raw["source"]),
    );
  }

  Map<String, dynamic> asPrefillMap() {
    return <String, dynamic>{
      if (query != null) "query": query,
      if (memo != null) "memo": memo,
      if (diaperType != null) "diaper_type": diaperType,
      if (amountMl != null) "amount_ml": amountMl,
      if (durationMin != null) "duration_min": durationMin,
      if (grams != null) "grams": grams,
      if (dose != null) "dose": dose,
    };
  }
}

class AssistantIntentBridge {
  AssistantIntentBridge._();

  static const MethodChannel _channel =
      MethodChannel("babyai/assistant_intent");
  static final StreamController<AssistantActionPayload> _controller =
      StreamController<AssistantActionPayload>.broadcast();

  static bool _initialized = false;

  static Stream<AssistantActionPayload> get stream => _controller.stream;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _channel.setMethodCallHandler(_onMethodCall);

    try {
      final Map<dynamic, dynamic>? initial =
          await _channel.invokeMethod<Map<dynamic, dynamic>>(
        "getInitialAction",
      );
      if (initial != null) {
        final AssistantActionPayload payload =
            AssistantActionPayload.fromMap(initial);
        if (!payload.isEmpty) {
          _controller.add(payload);
        }
      }
    } catch (_) {
      // Ignore bridge initialization failures.
    }
  }

  static Future<void> _onMethodCall(MethodCall call) async {
    if (call.method != "onAssistantAction") {
      return;
    }

    final dynamic args = call.arguments;
    if (args is Map<dynamic, dynamic>) {
      final AssistantActionPayload payload =
          AssistantActionPayload.fromMap(args);
      if (!payload.isEmpty) {
        _controller.add(payload);
      }
    }
  }
}
