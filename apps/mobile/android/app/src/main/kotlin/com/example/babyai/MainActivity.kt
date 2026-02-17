package com.example.babyai

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "babyai/assistant_intent"
    }

    private var methodChannel: MethodChannel? = null
    private var lastPayload: HashMap<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialAction" -> {
                    if (lastPayload == null) {
                        lastPayload = extractIntentPayload(intent)
                    }
                    result.success(lastPayload)
                }

                else -> result.notImplemented()
            }
        }

        lastPayload = extractIntentPayload(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = extractIntentPayload(intent)
        if (payload != null) {
            lastPayload = payload
            methodChannel?.invokeMethod("onAssistantAction", payload)
        }
    }

    private fun extractIntentPayload(intent: Intent?): HashMap<String, Any?>? {
        if (intent == null) {
            return null
        }

        val extras = intent.extras
        val feature = firstNotBlank(
            findExtraString(extras, listOf("feature", "app_feature")),
            intent.data?.getQueryParameter("feature")
        )
        val actionRaw = intent.action
        val hasAssistantData = feature != null ||
            intent.data?.scheme == "babyai" ||
            intent.data?.host == "assistant"

        if (!hasAssistantData && actionRaw != Intent.ACTION_VIEW) {
            return null
        }

        val payload = hashMapOf<String, Any?>()
        if (feature != null) {
            payload["feature"] = feature.lowercase()
        }

        putIfNotBlank(payload, "query", firstNotBlank(
            findExtraString(extras, listOf("query", "utterance", "text", "prompt")),
            intent.data?.getQueryParameter("query")
        ))

        putIfNotBlank(payload, "memo", firstNotBlank(
            findExtraString(extras, listOf("memo", "note", "content")),
            intent.data?.getQueryParameter("memo")
        ))

        putIfNotBlank(payload, "diaper_type", firstNotBlank(
            findExtraString(extras, listOf("diaper_type", "diaperType")),
            intent.data?.getQueryParameter("diaper_type")
        ))

        putIfPositiveInt(payload, "amount_ml", firstNotBlank(
            findExtraString(extras, listOf("amount_ml", "amountMl", "amount")),
            intent.data?.getQueryParameter("amount_ml")
        ))

        putIfPositiveInt(payload, "duration_min", firstNotBlank(
            findExtraString(extras, listOf("duration_min", "durationMin", "duration")),
            intent.data?.getQueryParameter("duration_min")
        ))

        putIfPositiveInt(payload, "grams", firstNotBlank(
            findExtraString(extras, listOf("grams", "amount_g", "amountG")),
            intent.data?.getQueryParameter("grams")
        ))

        putIfPositiveInt(payload, "dose", firstNotBlank(
            findExtraString(extras, listOf("dose", "dose_mg", "doseMg")),
            intent.data?.getQueryParameter("dose")
        ))

        payload["source"] = "assistant"
        return payload
    }

    private fun findExtraString(extras: Bundle?, keys: List<String>): String? {
        if (extras == null) {
            return null
        }

        for (key in keys) {
            val value = extras.getString(key)
            if (!value.isNullOrBlank()) {
                return value
            }
        }

        for (rawKey in extras.keySet()) {
            val key = rawKey.lowercase()
            for (expected in keys) {
                if (key.endsWith(expected.lowercase())) {
                    val value = extras.get(rawKey)?.toString()
                    if (!value.isNullOrBlank()) {
                        return value
                    }
                }
            }
        }

        return null
    }

    private fun firstNotBlank(vararg values: String?): String? {
        for (value in values) {
            if (!value.isNullOrBlank()) {
                return value.trim()
            }
        }
        return null
    }

    private fun putIfNotBlank(map: HashMap<String, Any?>, key: String, value: String?) {
        if (!value.isNullOrBlank()) {
            map[key] = value.trim()
        }
    }

    private fun putIfPositiveInt(map: HashMap<String, Any?>, key: String, raw: String?) {
        val parsed = raw?.trim()?.toIntOrNull() ?: return
        if (parsed > 0) {
            map[key] = parsed
        }
    }
}
