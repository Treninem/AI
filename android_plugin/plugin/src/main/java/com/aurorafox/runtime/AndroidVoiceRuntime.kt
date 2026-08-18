package com.aurorafox.runtime

import android.content.Context
import android.content.res.AssetManager
import com.k2fsa.sherpa.onnx.GenerationConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig
import com.k2fsa.sherpa.onnx.OfflineWhisperModelConfig
import com.k2fsa.sherpa.onnx.WaveReader
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class AndroidVoiceRuntime(private val context: Context) {
    private val assets: AssetManager = context.assets
    private val cacheDir = File(context.filesDir, "voice_cache").apply { mkdirs() }
    private val ttsAssetRoot = "voice/vits-piper-ru_RU-denis-medium"
    private val sttAssetRoot = "voice/sherpa-onnx-whisper-tiny"

    @Volatile private var tts: OfflineTts? = null
    @Volatile private var recognizer: OfflineRecognizer? = null
    private val ttsLock = Any()
    private val sttLock = Any()

    fun isTtsAvailable(): Boolean = try {
        findAsset(ttsAssetRoot) { it.endsWith(".onnx") } != null &&
            findAsset(ttsAssetRoot) { it.endsWith("tokens.txt") } != null
    } catch (_: Throwable) { false }

    fun isSttAvailable(): Boolean = try {
        findAsset(sttAssetRoot) { it.contains("encoder") && it.endsWith(".onnx") } != null &&
            findAsset(sttAssetRoot) { it.contains("decoder") && it.endsWith(".onnx") } != null &&
            findAsset(sttAssetRoot) { it.contains("tokens") && it.endsWith(".txt") } != null
    } catch (_: Throwable) { false }

    fun synthesize(text: String, speed: Float, emotion: String, intensity: Float): String {
        if (text.isBlank()) return error("Empty speech text")
        if (!isTtsAvailable()) return error("Android Russian TTS assets are missing")
        return try {
            val engine = ensureTts()
            val safeSpeed = speed.coerceIn(0.82f, 1.20f)
            val key = sha256("$text|$safeSpeed|$emotion|$intensity|piper-denis-v1")
            val wav = File(cacheDir, "$key.wav")
            val meta = File(cacheDir, "$key.json")
            if (wav.isFile && meta.isFile) {
                wav.setLastModified(System.currentTimeMillis())
                return meta.readText()
            }

            val generation = GenerationConfig(
                silenceScale = when (emotion) {
                    "thinking", "serious", "sad" -> 0.28f
                    "excited", "success" -> 0.15f
                    else -> 0.20f
                },
                speed = safeSpeed,
                sid = 0,
            )
            val audio = synchronized(ttsLock) { engine.generateWithConfig(text, generation) }
            if (audio.samples.isEmpty()) return error("Android TTS returned empty audio")
            if (!audio.save(wav.absolutePath)) return error("Cannot save Android TTS WAV")

            val envelope = amplitudeEnvelope(audio.samples, 80)
            val payload = JSONObject().apply {
                put("ok", true)
                put("path", wav.absolutePath)
                put("engine", "sherpa-onnx-piper-denis")
                put("sample_rate", audio.sampleRate)
                put("duration", audio.samples.size.toDouble() / audio.sampleRate.toDouble())
                put("emotion", emotion)
                put("intensity", intensity.toDouble())
                put("cached", false)
                put("amplitude", JSONArray(envelope))
                put("spoken_text", text)
            }
            meta.writeText(payload.toString())
            trimCache(256L * 1024L * 1024L)
            payload.toString()
        } catch (t: Throwable) {
            error("Android TTS failed: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    fun transcribe(audioPath: String, language: String = "ru"): String {
        val audioFile = File(audioPath)
        if (!audioFile.isFile) return error("Audio file not found")
        if (!isSttAvailable()) return error("Android Whisper assets are missing")
        return try {
            val r = ensureRecognizer(language)
            val reader = WaveReader(audioFile.absolutePath)
            val stream = r.createStream()
            try {
                stream.acceptWaveform(reader.samples, reader.sampleRate)
                synchronized(sttLock) { r.decode(stream) }
                val result = r.getResult(stream)
                JSONObject().apply {
                    put("ok", true)
                    put("text", result.text.trim())
                    put("language", if (result.lang.isNullOrBlank()) language else result.lang)
                    put("engine", "sherpa-onnx-whisper-tiny")
                }.toString()
            } finally {
                stream.release()
            }
        } catch (t: Throwable) {
            error("Android STT failed: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    fun clearCache(): String {
        cacheDir.listFiles()?.forEach { if (it.isFile) it.delete() }
        return JSONObject(mapOf("ok" to true)).toString()
    }

    @Synchronized
    private fun ensureTts(): OfflineTts {
        tts?.let { return it }
        val model = findAsset(ttsAssetRoot) { it.endsWith(".onnx") && !it.contains("duration", true) }
            ?: throw IllegalStateException("Russian TTS model.onnx not found")
        val tokens = findAsset(ttsAssetRoot) { it.endsWith("tokens.txt") }
            ?: throw IllegalStateException("Russian TTS tokens.txt not found")
        val dataDir = findAssetDirectory(ttsAssetRoot, "espeak-ng-data") ?: "$ttsAssetRoot/espeak-ng-data"
        val lexicon = findAsset(ttsAssetRoot) { it.endsWith("lexicon.txt") } ?: ""
        val config = OfflineTtsConfig(
            model = OfflineTtsModelConfig(
                vits = OfflineTtsVitsModelConfig(
                    model = model,
                    tokens = tokens,
                    dataDir = dataDir,
                    lexicon = lexicon,
                    lengthScale = 1.0f,
                ),
                numThreads = min(4, max(2, Runtime.getRuntime().availableProcessors() - 1)),
                debug = false,
                provider = "cpu",
            ),
            maxNumSentences = 2,
            silenceScale = 0.2f,
        )
        return OfflineTts(assetManager = assets, config = config).also { tts = it }
    }

    @Synchronized
    private fun ensureRecognizer(language: String): OfflineRecognizer {
        recognizer?.let { return it }
        val encoder = findAsset(sttAssetRoot) { it.contains("encoder", true) && it.endsWith(".onnx") }
            ?: throw IllegalStateException("Whisper encoder not found")
        val decoder = findAsset(sttAssetRoot) { it.contains("decoder", true) && it.endsWith(".onnx") }
            ?: throw IllegalStateException("Whisper decoder not found")
        val tokens = findAsset(sttAssetRoot) { it.contains("tokens", true) && it.endsWith(".txt") }
            ?: throw IllegalStateException("Whisper tokens not found")
        val config = OfflineRecognizerConfig(
            modelConfig = OfflineModelConfig(
                whisper = OfflineWhisperModelConfig(
                    encoder = encoder,
                    decoder = decoder,
                    language = language,
                    task = "transcribe",
                ),
                numThreads = min(4, max(2, Runtime.getRuntime().availableProcessors() - 1)),
                debug = false,
                provider = "cpu",
                tokens = tokens,
                modelType = "whisper",
            ),
            decodingMethod = "greedy_search",
        )
        return OfflineRecognizer(assetManager = assets, config = config).also { recognizer = it }
    }

    private fun findAsset(root: String, predicate: (String) -> Boolean): String? {
        fun walk(path: String): String? {
            val children = assets.list(path) ?: emptyArray()
            if (children.isEmpty()) return if (predicate(path)) path else null
            for (child in children) {
                val full = if (path.isEmpty()) child else "$path/$child"
                val found = walk(full)
                if (found != null) return found
            }
            return null
        }
        return walk(root)
    }

    private fun findAssetDirectory(root: String, name: String): String? {
        fun walk(path: String): String? {
            if (path.substringAfterLast('/') == name && (assets.list(path)?.isNotEmpty() == true)) return path
            for (child in assets.list(path) ?: emptyArray()) {
                val full = "$path/$child"
                val found = walk(full)
                if (found != null) return found
            }
            return null
        }
        return walk(root)
    }

    private fun amplitudeEnvelope(samples: FloatArray, points: Int): List<Double> {
        if (samples.isEmpty()) return emptyList()
        val step = max(1, samples.size / points)
        val values = ArrayList<Double>()
        var i = 0
        while (i < samples.size && values.size < points) {
            val end = min(samples.size, i + step)
            var sum = 0.0
            var j = i
            while (j < end) {
                val v = samples[j].toDouble()
                sum += v * v
                j++
            }
            values += sqrt(sum / max(1, end - i).toDouble())
            i = end
        }
        val peak = values.maxOrNull()?.coerceAtLeast(1e-7) ?: 1.0
        return values.map { min(1.0, it / peak) }
    }

    private fun trimCache(limit: Long) {
        val files = cacheDir.listFiles()?.filter { it.isFile }?.sortedBy { it.lastModified() }?.toMutableList() ?: return
        var total = files.sumOf { it.length() }
        while (files.isNotEmpty() && total > limit) {
            val f = files.removeAt(0)
            total -= f.length()
            f.delete()
            if (f.extension == "wav") File(cacheDir, "${f.nameWithoutExtension}.json").delete()
        }
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    private fun error(message: String): String = JSONObject(mapOf("ok" to false, "error" to message)).toString()
}
