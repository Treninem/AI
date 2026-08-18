package com.aurorafox.runtime

import android.os.Build
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject
import java.io.File

class GodotAndroidPlugin(godot: Godot) : GodotPlugin(godot) {
    private val native = NativeRuntime()

    override fun getPluginName() = BuildConfig.GODOT_PLUGIN_NAME

    @UsedByGodot
    fun getPrivateRoot(): String = activity?.filesDir?.absolutePath ?: ""

    @UsedByGodot
    fun getCapabilities(): Map<String, Any> {
        val loaded = native.isLoaded()
        return mapOf(
            "embedded_runtime" to true,
            "android_app_sandbox" to true,
            "isolated_service" to true,
            "native_processes" to false,
            "container_runtime" to false,
            "llama_cpp" to (loaded && native.hasLlama()),
            "whisper_cpp" to (loaded && native.hasWhisper()),
            "wasm" to (loaded && native.hasWasm()),
            "architecture" to Build.SUPPORTED_ABIS.joinToString(",")
        )
    }

    @UsedByGodot
    fun chatLocal(modelPath: String, messagesJson: String, optionsJson: String): String {
        if (!native.isLoaded() || !native.hasLlama()) {
            return errorJson("llama.cpp runtime is not bundled in this build")
        }
        if (!isInsideAppStorage(modelPath)) {
            return errorJson("Model path must be inside AuroraFox app storage")
        }
        return native.chat(modelPath, messagesJson, optionsJson)
    }

    @UsedByGodot
    fun transcribeLocal(modelPath: String, audioPath: String, language: String): String {
        if (!native.isLoaded() || !native.hasWhisper()) {
            return errorJson("whisper.cpp runtime is not bundled in this build")
        }
        if (!isInsideAppStorage(modelPath) || !isInsideAppStorage(audioPath)) {
            return errorJson("Model and audio must be inside AuroraFox app storage")
        }
        return native.transcribe(modelPath, audioPath, language)
    }

    @UsedByGodot
    fun executeSandbox(requestJson: String): String {
        val root = activity?.filesDir ?: return errorJson("No Android activity")
        val request = try { JSONObject(requestJson) } catch (e: Exception) { return errorJson("Invalid request JSON") }
        val workspace = File(request.optString("workspace", ""))
        val rootCanonical = root.canonicalFile
        val workspaceCanonical = try { workspace.canonicalFile } catch (e: Exception) { return errorJson("Invalid workspace") }
        if (workspaceCanonical != rootCanonical && !workspaceCanonical.path.startsWith(rootCanonical.path + File.separator)) {
            return errorJson("Workspace escapes app sandbox")
        }

        val command = request.optJSONArray("command") ?: return errorJson("Missing command")
        if (command.length() == 0) return errorJson("Empty command")
        val executable = command.optString(0).lowercase()

        // Android build intentionally does not expose shell/native process execution.
        // Portable experiments run as WASM inside the native runtime.
        if (executable !in setOf("wasm", "wasmtime", "wasm3")) {
            return errorJson("Android sandbox accepts WASM execution only; compile source to WASM first")
        }
        if (!native.isLoaded() || !native.hasWasm()) {
            return errorJson("WASM runtime is not bundled in this build")
        }
        if (command.length() < 2) return errorJson("WASM module path is required")

        val module = File(workspaceCanonical, command.optString(1)).canonicalFile
        if (!module.path.startsWith(workspaceCanonical.path + File.separator) || !module.isFile) {
            return errorJson("WASM module is outside workspace or missing")
        }
        val args = mutableListOf<String>()
        for (i in 2 until command.length()) args += command.optString(i)
        return native.runWasm(module.absolutePath, workspaceCanonical.absolutePath, args.toTypedArray())
    }

    private fun isInsideAppStorage(path: String): Boolean {
        val root = activity?.filesDir?.canonicalFile ?: return false
        val target = try { File(path).canonicalFile } catch (e: Exception) { return false }
        return target == root || target.path.startsWith(root.path + File.separator)
    }

    private fun errorJson(message: String): String = JSONObject(mapOf("ok" to false, "error" to message)).toString()
}
