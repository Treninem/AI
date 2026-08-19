package com.aurorafox.runtime

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class GodotAndroidPlugin(godot: Godot) : GodotPlugin(godot) {
    private val native = NativeRuntime()
    private val voice by lazy {
        val ctx = activity?.applicationContext ?: throw IllegalStateException("No Android context")
        AndroidVoiceRuntime(ctx)
    }
    private val files by lazy {
        val ctx = activity?.applicationContext ?: throw IllegalStateException("No Android context")
        AndroidFileRuntime(ctx, voice)
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
        val filesDir = activity?.filesDir
        val freeStorage = if (filesDir != null) StatFs(filesDir.absolutePath).availableBytes else 0L
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
                "file_intelligence" to true,
                "wasm" to (loaded && native.hasWasm()),
                "app_update_install" to true,
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
    fun analyzeLocalFile(path: String, question: String, visual: Boolean): String {
        if (!isInsideAppStorage(path)) return errorJson("File must be inside AuroraFox private storage")
        return try { files.analyze(path, question, visual) }
        catch (t: Throwable) { errorJson("Android File Intelligence unavailable: ${t.message ?: t.javaClass.simpleName}") }
    }

    @UsedByGodot
    fun clearFileCache(): String {
        return try { files.clearCache() } catch (t: Throwable) { errorJson(t.message ?: "Cannot clear file cache") }
    }

    @UsedByGodot
    fun treeLocal(path: String, maxItems: Int): String {
        if (!isInsideAppStorage(path)) return errorJson("Directory must be inside AuroraFox private storage")
        return try { files.tree(path, maxItems) }
        catch (t: Throwable) { errorJson("Cannot build Android file tree: ${t.message ?: t.javaClass.simpleName}") }
    }

    @UsedByGodot
    fun installUpdateApk(apkPath: String): String {
        val act = activity ?: return errorJson("No Android activity")
        val source = try { File(apkPath).canonicalFile } catch (_: Throwable) { return errorJson("Invalid APK path") }
        if (!source.isFile) return errorJson("Downloaded APK is missing")
        val roots = listOf(act.filesDir.canonicalFile, act.cacheDir.canonicalFile)
        if (roots.none { root -> source == root || source.path.startsWith(root.path + File.separator) }) {
            return errorJson("Update APK must be inside AuroraFox private storage")
        }

        return try {
            val updateDir = File(act.cacheDir, "aurora_updates").apply { mkdirs() }
            val target = File(updateDir, "AuroraFox-update.apk")
            if (source != target.canonicalFile) source.copyTo(target, overwrite = true)
            act.getSharedPreferences(AuroraUpdateProvider.PREFS, Context.MODE_PRIVATE)
                .edit().putString(AuroraUpdateProvider.KEY_APK_PATH, target.canonicalPath).apply()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !act.packageManager.canRequestPackageInstalls()) {
                val permissionIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${act.packageName}")
                )
                act.startActivity(permissionIntent)
                return JSONObject(
                    mapOf(
                        "ok" to false,
                        "requires_permission" to true,
                        "message" to "Разрешите установку обновлений для AuroraFox и повторите установку."
                    )
                ).toString()
            }

            val uri = Uri.parse("content://${act.packageName}.aurorafox.updates/update.apk")
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            act.startActivity(installIntent)
            JSONObject(mapOf("ok" to true, "installer_opened" to true)).toString()
        } catch (t: Throwable) {
            errorJson("Cannot open Android package installer: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    @UsedByGodot
    fun transcribeLocal(modelPath: String, audioPath: String, language: String): String {
        if (!isInsideAppStorage(audioPath)) return errorJson("Audio must be inside AuroraFox app storage")
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
        val act = activity ?: return false
        val target = try { File(path).canonicalFile } catch (_: Exception) { return false }
        val roots = listOf(act.filesDir.canonicalFile, act.cacheDir.canonicalFile)
        return roots.any { root -> target == root || target.path.startsWith(root.path + File.separator) }
    }

    private fun errorJson(message: String): String = JSONObject(mapOf("ok" to false, "error" to message)).toString()
}
