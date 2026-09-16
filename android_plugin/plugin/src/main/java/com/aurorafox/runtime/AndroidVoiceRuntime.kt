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
            val spokenText = prepareSpeechText(text)
            if (spokenText.isBlank()) return error("Speech text is empty after normalization")

            val safeSpeed = speed.coerceIn(0.92f, 1.08f)
            val power = intensity.coerceIn(0.0f, 1.0f)
            val targetSilence = when (emotion) {
                "thinking", "serious", "sad" -> 0.24f
                "excited", "success" -> 0.18f
                "warning", "error" -> 0.19f
                else -> 0.20f
            }
            val silenceScale = 0.20f + (targetSilence - 0.20f) * power
            val key = sha256("$spokenText|$safeSpeed|$emotion|$power|piper-denis-v4")
            val wav = File(cacheDir, "$key.wav")
            val meta = File(cacheDir, "$key.json")
            if (wav.isFile && meta.isFile) {
                wav.setLastModified(System.currentTimeMillis())
                return meta.readText()
            }

            val generation = GenerationConfig(
                silenceScale = silenceScale,
                speed = safeSpeed,
                sid = 0,
            )
            val audio = synchronized(ttsLock) { engine.generateWithConfig(spokenText, generation) }
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
                put("intensity", power.toDouble())
                put("speed", safeSpeed.toDouble())
                put("cached", false)
                put("amplitude", JSONArray(envelope))
                put("source_text", text)
                put("spoken_text", spokenText)
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
            val reader = WaveReader.readWave(audioFile.absolutePath)
            val stream = r.createStream()
            try {
                stream.acceptWaveform(reader.samples, reader.sampleRate)
                synchronized(sttLock) { r.decode(stream) }
                val result = r.getResult(stream)
                JSONObject().apply {
                    put("ok", true)
                    put("text", result.text.trim())
                    put("language", if (result.lang.isBlank()) language else result.lang)
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

    private fun prepareSpeechText(source: String): String {
        var text = source.replace("\r\n", "\n").replace('\r', '\n')
        text = Regex("```[\\s\\S]*?```").replace(text, " Код я показала в сообщении. ")
        text = Regex("`([^`]{1,80})`").replace(text) { it.groupValues[1] }
        text = Regex("\\[([^]]+)]\\([^)]+\\)").replace(text) { it.groupValues[1] }
        text = Regex("https?://\\S+").replace(text, "ссылка в сообщении")

        text = Regex("(?<![\\p{L}\\d])-?\\d+(?:\\.\\d+){2,}(?![\\p{L}\\d])").replace(text) {
            val negative = it.value.startsWith('-')
            val body = if (negative) it.value.substring(1) else it.value
            val spoken = body.split('.').joinToString(" точка ") { part -> integerToRussian(part.toLongOrNull() ?: 0L) }
            (if (negative) "минус " else "") + spoken
        }
        text = Regex("(?<![\\p{L}\\d])(-?\\d+(?:[,.]\\d+)?)\\s*°\\s*[CcСс](?![\\p{L}])").replace(text) {
            val token = it.groupValues[1]
            speakNumberToken(token) + " " + unitForm(
                token,
                "градус Цельсия",
                "градуса Цельсия",
                "градусов Цельсия",
                "градуса Цельсия",
            )
        }
        text = Regex("(?<![\\p{L}\\d])(-?\\d+(?:[,.]\\d+)?)\\s*%(?![\\p{L}\\d])").replace(text) {
            val token = it.groupValues[1]
            speakNumberToken(token) + " " + unitForm(token, "процент", "процента", "процентов", "процента")
        }
        text = Regex("(?<![\\p{L}\\d])-?\\d+[,.]\\d+(?![\\p{L}\\d])").replace(text) {
            speakNumberToken(it.value)
        }
        text = Regex("(?<![\\p{L}\\d])-?\\d+(?![\\p{L}\\d])").replace(text) {
            speakNumberToken(it.value)
        }

        text = text.replace("**", "").replace("__", "").replace("~~", "")
        text = text.replace('|', ',')
        text = Regex("\\n{2,}").replace(text, ". ")
        text = Regex("\\n").replace(text, ", ")
        text = Regex("\\s+").replace(text, " ").trim(' ', ',')
        return text
    }

    private fun unitForm(token: String, one: String, few: String, many: String, decimal: String): String {
        val body = token.removePrefix("-").replace(',', '.')
        if (body.contains('.')) {
            val fractional = body.substringAfter('.').trimEnd('0')
            if (fractional.isNotEmpty()) return decimal
        }
        val value = body.substringBefore('.').toLongOrNull() ?: 0L
        return pluralForm(value, one, few, many)
    }

    private fun pluralForm(value: Long, one: String, few: String, many: String): String {
        val positive = if (value < 0L) -value else value
        val mod100 = positive % 100L
        if (mod100 in 11L..14L) return many
        return when (positive % 10L) {
            1L -> one
            2L, 3L, 4L -> few
            else -> many
        }
    }

    private fun speakNumberToken(token: String): String {
        val negative = token.startsWith('-')
        val body = if (negative) token.substring(1) else token
        val parts = body.replace(',', '.').split('.', limit = 2)
        val prefix = if (negative) "минус " else ""
        if (parts.size == 1) return prefix + integerToRussian(parts[0].toLongOrNull() ?: 0L)

        val fractionalDigits = parts[1].trimEnd('0')
        if (fractionalDigits.isEmpty()) {
            return prefix + integerToRussian(parts[0].toLongOrNull() ?: 0L)
        }
        if (fractionalDigits.length > 3) {
            val integer = integerToRussian(parts[0].toLongOrNull() ?: 0L)
            val digits = fractionalDigits.map { digitToRussian(it) }.joinToString(" ")
            return "$prefix$integer запятая $digits"
        }

        val integerValue = parts[0].toLongOrNull() ?: 0L
        val fractionalValue = fractionalDigits.toLongOrNull() ?: 0L
        val wholeNoun = if (usesSingularForm(integerValue)) "целая" else "целых"
        val denominator = when (fractionalDigits.length) {
            1 -> if (usesSingularForm(fractionalValue)) "десятая" else "десятых"
            2 -> if (usesSingularForm(fractionalValue)) "сотая" else "сотых"
            else -> if (usesSingularForm(fractionalValue)) "тысячная" else "тысячных"
        }
        return buildString {
            append(prefix)
            append(integerToRussian(integerValue, feminine = true))
            append(' ')
            append(wholeNoun)
            append(' ')
            append(integerToRussian(fractionalValue, feminine = true))
            append(' ')
            append(denominator)
        }
    }

    private fun usesSingularForm(value: Long): Boolean {
        val positive = if (value < 0L) -value else value
        return positive % 10L == 1L && positive % 100L != 11L
    }

    private fun digitToRussian(ch: Char): String = when (ch) {
        '0' -> "ноль"
        '1' -> "один"
        '2' -> "два"
        '3' -> "три"
        '4' -> "четыре"
        '5' -> "пять"
        '6' -> "шесть"
        '7' -> "семь"
        '8' -> "восемь"
        '9' -> "девять"
        else -> ""
    }

    private fun integerToRussian(value: Long, feminine: Boolean = false): String {
        if (value == 0L) return "ноль"
        if (value < 0L) return "минус " + integerToRussian(-value, feminine)
        if (value > 999_999_999L) return value.toString().map { digitToRussian(it) }.joinToString(" ")

        val ones = arrayOf("", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять")
        val teens = arrayOf("десять", "одиннадцать", "двенадцать", "тринадцать", "четырнадцать", "пятнадцать", "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать")
        val tens = arrayOf("", "", "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят", "семьдесят", "восемьдесят", "девяносто")
        val hundreds = arrayOf("", "сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот", "семьсот", "восемьсот", "девятьсот")

        fun underThousand(n: Int, feminineUnits: Boolean = false): List<String> {
            if (n == 0) return emptyList()
            val out = ArrayList<String>()
            out += hundreds[n / 100]
            val tail = n % 100
            if (tail in 10..19) {
                out += teens[tail - 10]
            } else {
                out += tens[tail / 10]
                val unit = tail % 10
                if (feminineUnits && unit == 1) out += "одна"
                else if (feminineUnits && unit == 2) out += "две"
                else out += ones[unit]
            }
            return out.filter { it.isNotBlank() }
        }

        fun form(n: Int, one: String, few: String, many: String): String {
            val mod100 = n % 100
            if (mod100 in 11..14) return many
            return when (n % 10) {
                1 -> one
                2, 3, 4 -> few
                else -> many
            }
        }

        var remaining = value
        val words = ArrayList<String>()
        val millions = (remaining / 1_000_000L).toInt()
        if (millions > 0) {
            words += underThousand(millions)
            words += form(millions, "миллион", "миллиона", "миллионов")
            remaining %= 1_000_000L
        }
        val thousands = (remaining / 1_000L).toInt()
        if (thousands > 0) {
            words += underThousand(thousands, feminineUnits = true)
            words += form(thousands, "тысяча", "тысячи", "тысяч")
            remaining %= 1_000L
        }
        words += underThousand(remaining.toInt(), feminineUnits = feminine)
        return words.joinToString(" ").trim()
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
