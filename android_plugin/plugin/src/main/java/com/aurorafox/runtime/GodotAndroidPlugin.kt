package com.aurorafox.runtime

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.StatFs
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class GodotAndroidPlugin(godot: Godot) : GodotPlugin(godot) {
    private val native = NativeRuntime()
    private val voice by lazy {
        val ctx = activity?.applicationContext ?: throw IllegalStateException("No Android context")
        AndroidVoiceRuntime(ctx)
    }

    override fun getPluginName() = BuildConfig.GODOT_PLUGIN_NAME

    @UsedByGodot
    fun getPrivateRoot(): String = activity?.filesDir?.absolutePath ?: ""

    @UsedByGodot
    fun getCapabilitiesJson(): String {
        val loaded = native.isLoaded()
        val memoryInfo = ActivityManager.MemoryInfo()
        val manager = activity?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        manager?.getMemoryInfo(memoryInfo)
        val files = activity?.filesDir
        val freeStorage = if (files != null) StatFs(files.absolutePath).availableBytes else 0L
        val tts = try { voice.isTtsAvailable() } catch (_: Throwable) { false }
        val sherpaStt = try { voice.isSttAvailable() } catch (_: Throwable) { false }
        return JSONObject(
            mapOf(
                "embedded_runtime" to true,
                "android_app_sandbox" to true,
                "isolated_service" to true,
                "native_processes" to false,
                "container_runtime" to false,
                "llama_cpp" to (loaded && native.hasLlama()),
                "whisper_cpp" to (loaded && native.hasWhisper()),
                "sherpa_stt" to sherpaStt,
                "local_tts" to tts,
                "wasm" to (loaded && native.hasWasm()),
                "architecture" to Build.SUPPORTED_ABIS.joinToString(","),
                "total_ram_mb" to (memoryInfo.totalMem / 1024L / 1024L),
                "free_storage_mb" to (freeStorage / 1024L / 1024L)
            )
        ).toString()
    }

    @UsedByGodot
    fun chatLocal(modelPath: String, messagesJson: String, optionsJson: String): String {
        if (!native.isLoaded() || !native.hasLlama()) return errorJson("llama.cpp runtime is not bundled in this build")
        if (!isInsideAppStorage(modelPath)) return errorJson("Model path must be inside AuroraFox app storage")
        val prompt = try { formatChatPrompt(JSONArray(messagesJson)) } catch (_: Exception) { return errorJson("Invalid messages JSON") }
        return native.chat(modelPath, prompt, optionsJson)
    }

    @UsedByGodot
    fun synthesizeSpeechLocal(text: String, speed: Float, emotion: String, intensity: Float): String {
        return try { voice.synthesize(text, speed, emotion, intensity) }
        catch (t: Throwable) { errorJson("Android TTS unavailable: ${t.message ?: t.javaClass.simpleName}") }
    }

    @UsedByGodot
    fun clearVoiceCache(): String {
        return try { voice.clearCache() } catch (t: Throwable) { errorJson(t.message ?: "Cannot clear voice cache") }
    }

    @UsedByGodot
    fun transcribeLocal(modelPath: String, audioPath: String, language: String): String {
        if (!isInsideAppStorage(audioPath)) return errorJson("Audio must be inside AuroraFox app storage")
        // Prefer sherpa-onnx Whisper assets shipped with AuroraFox. Keep the older whisper.cpp route as fallback.
        try {
            if (voice.isSttAvailable()) return voice.transcribe(audioPath, language)
        } catch (_: Throwable) { }
        if (!native.isLoaded() || !native.hasWhisper()) return errorJson("No local Android STT backend is available")
        if (!isInsideAppStorage(modelPath)) return errorJson("Whisper model path must be inside AuroraFox app storage")
        return native.transcribe(modelPath, audioPath, language)
    }

    @UsedByGodot
    fun executeSandbox(requestJson: String): String {
        val root = activity?.filesDir ?: return errorJson("No Android activity")
        val request = try { JSONObject(requestJson) } catch (_: Exception) { return errorJson("Invalid request JSON") }
        val workspace = File(request.optString("workspace", ""))
        val rootCanonical = root.canonicalFile
        val workspaceCanonical = try { workspace.canonicalFile } catch (_: Exception) { return errorJson("Invalid workspace") }
        if (workspaceCanonical != rootCanonical && !workspaceCanonical.path.startsWith(rootCanonical.path + File.separator)) return errorJson("Workspace escapes app sandbox")
        val command = request.optJSONArray("command") ?: return errorJson("Missing command")
        if (command.length() == 0) return errorJson("Empty command")
        val executable = command.optString(0).lowercase()
        if (executable !in setOf("wasm", "wasmtime", "wasm3")) return errorJson("Android sandbox accepts WASM execution only; compile source to WASM first")
        if (!native.isLoaded() || !native.hasWasm()) return errorJson("WASM runtime is not bundled in this build")
        if (command.length() < 2) return errorJson("WASM module path is required")
        val module = File(workspaceCanonical, command.optString(1)).canonicalFile
        if (!module.path.startsWith(workspaceCanonical.path + File.separator) || !module.isFile) return errorJson("WASM module is outside workspace or missing")
        val args = mutableListOf<String>()
        for (i in 2 until command.length()) args += command.optString(i)
        return native.runWasm(module.absolutePath, workspaceCanonical.absolutePath, args.toTypedArray())
    }

    private fun formatChatPrompt(messages: JSONArray): String {
        val out = StringBuilder()
        for (i in 0 until messages.length()) {
            val item = messages.optJSONObject(i) ?: continue
            val role = item.optString("role", "user").lowercase().let { if (it in setOf("system", "user", "assistant")) it else "user" }
            val content = item.optString("content", "")
            out.append("<|im_start|>").append(role).append('\n').append(content).append("<|im_end|>\n")
        }
        out.append("<|im_start|>assistant\n")
        return out.toString()
    }

    private fun isInsideAppStorage(path: String): Boolean {
        val root = activity?.filesDir?.canonicalFile ?: return false
        val target = try { File(path).canonicalFile } catch (_: Exception) { return false }
        return target == root || target.path.startsWith(root.path + File.separator)
    }

    private fun errorJson(message: String): String = JSONObject(mapOf("ok" to false, "error" to message)).toString()
}
