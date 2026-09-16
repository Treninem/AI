package com.aurorafox.corebenchmark

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Debug
import android.os.Process
import android.os.SystemClock
import android.util.Log
import com.aurorafox.runtime.NativeRuntime
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.Locale
import kotlin.concurrent.thread

class MainActivity : Activity() {
    companion object {
        private const val TAG = "AuroraFoxCoreBenchmark"
        private const val EXPECTED_BYTES = 1282439264L
        private const val EXPECTED_SHA = "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        thread(name = "aurorafox-core-benchmark") {
            val report = try {
                runBenchmark()
            } catch (t: Throwable) {
                JSONObject()
                    .put("schema_version", 1)
                    .put("suite", "aurorafox_core_android_backend_v1")
                    .put("status", "runner_failure")
                    .put("passed", false)
                    .put("error", t.stackTraceToString().take(12000))
            }
            val out = File(filesDir, "core-benchmark-android.json")
            out.writeText(report.toString(2), Charsets.UTF_8)
            Log.i(TAG, "AURORAFOX_ANDROID_CORE_BENCHMARK passed=${report.optBoolean("passed", false)} status=${report.optString("status")}")
            runOnUiThread { finishAndRemoveTask() }
        }
    }

    private fun runBenchmark(): JSONObject {
        val model = File(filesDir, "aurorafox-core.gguf")
        val modelSha = if (model.isFile) sha256(model) else ""
        val modelOk = model.isFile && model.length() == EXPECTED_BYTES && modelSha == EXPECTED_SHA
        val internetGranted = checkSelfPermission(Manifest.permission.INTERNET) == PackageManager.PERMISSION_GRANTED

        val native = NativeRuntime()
        val nativeOk = native.isLoaded() && native.hasLlama()
        val scenarios = JSONArray()

        val cold = sample(
            native,
            model,
            "cold_start_first_response",
            "Reply exactly ANDROID-LOCAL-READY and nothing else.",
            "ANDROID-LOCAL-READY"
        )
        scenarios.put(cold)
        val warm1 = sample(native, model, "basic_reasoning", "Compute 7 * 8. Reply only with 56.", "56")
        scenarios.put(warm1)
        val warm2 = sample(native, model, "russian_dialog", "Ответь только словом ЛОКАЛЬНО.", "ЛОКАЛЬНО")
        scenarios.put(warm2)

        val pssMb = currentPssMb()
        val coldMs = cold.optDouble("elapsed_ms", 0.0)
        val warmValues = listOf(warm1.optDouble("elapsed_ms", 0.0), warm2.optDouble("elapsed_ms", 0.0)).sorted()
        val warmMedian = if (warmValues.size == 2) (warmValues[0] + warmValues[1]) / 2.0 else 0.0
        val qualityPassed = (0 until scenarios.length()).all { scenarios.getJSONObject(it).optBoolean("passed", false) }
        val passed = modelOk && nativeOk && !internetGranted && qualityPassed && coldMs > 0.0 && warmMedian > 0.0 && pssMb > 0.0

        return JSONObject()
            .put("schema_version", 1)
            .put("suite", "aurorafox_core_android_backend_v1")
            .put("status", "completed")
            .put("passed", passed)
            .put("platform", "Android")
            .put("environment", JSONObject()
                .put("internet_permission_granted", internetGranted)
                .put("network_forbidden_by_manifest", !internetGranted)
                .put("remote_ai_allowed", false))
            .put("core", JSONObject()
                .put("runtime", "llama.cpp")
                .put("native_library_loaded", native.isLoaded())
                .put("llama_cpp", native.hasLlama())
                .put("model_path", model.absolutePath)
                .put("actual_bytes", if (model.isFile) model.length() else -1L)
                .put("prepared_sha256", modelSha)
                .put("expected_sha256", EXPECTED_SHA))
            .put("scenarios", scenarios)
            .put("performance", JSONObject()
                .put("cold_first_response_ms", coldMs)
                .put("warm_median_ms", warmMedian)
                .put("process_pss_mb", pssMb))
    }

    private fun sample(native: NativeRuntime, model: File, id: String, userPrompt: String, expected: String): JSONObject {
        if (!model.isFile || !native.isLoaded() || !native.hasLlama()) {
            return JSONObject()
                .put("id", id)
                .put("passed", false)
                .put("elapsed_ms", 0.0)
                .put("error", "model_or_native_runtime_unavailable")
        }
        val prompt = buildString {
            append("<|im_start|>system\n")
            append("You are AuroraFox Core. Follow the user's output format exactly.\n")
            append("<|im_end|>\n<|im_start|>user\n")
            append(userPrompt)
            append("<|im_end|>\n<|im_start|>assistant\n")
        }
        val options = JSONObject()
            .put("max_tokens", 48)
            .put("temperature", 0.0)
            .put("seed", 42)
            .toString()
        val started = SystemClock.elapsedRealtimeNanos()
        val raw = native.chat(model.absolutePath, prompt, options)
        val elapsedMs = (SystemClock.elapsedRealtimeNanos() - started) / 1_000_000.0
        val parsed = try { JSONObject(raw) } catch (_: Throwable) { JSONObject().put("ok", false).put("error", "invalid_json") }
        val content = finalText(parsed.optString("content", ""))
        val expectedNormalized = expected.trim().lowercase(Locale.ROOT)
        val passed = parsed.optBoolean("ok", false) &&
            parsed.optString("runtime", "") == "llama.cpp" &&
            content.lowercase(Locale.ROOT) == expectedNormalized
        return JSONObject()
            .put("id", id)
            .put("passed", passed)
            .put("elapsed_ms", elapsedMs)
            .put("runtime", parsed.optString("runtime", ""))
            .put("content_sha256", sha256(content.toByteArray(Charsets.UTF_8)))
            .put("content_excerpt", content.take(240))
            .put("error", parsed.optString("error", ""))
    }

    private fun finalText(text: String): String {
        var value = text.trim()
        value = Regex("(?s)<think>.*?</think>").replace(value, "").trim()
        value = value.removeSuffix("<|im_end|>").trim()
        return value
    }

    private fun currentPssMb(): Double {
        return try {
            val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            val info = manager.getProcessMemoryInfo(intArrayOf(Process.myPid())).firstOrNull()
            if (info != null) info.totalPss / 1024.0 else Debug.getPss() / 1024.0
        } catch (_: Throwable) {
            Debug.getPss() / 1024.0
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n <= 0) break
                digest.update(buffer, 0, n)
            }
        }
        return hex(digest.digest())
    }

    private fun sha256(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256")
        return hex(digest.digest(bytes))
    }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
}
