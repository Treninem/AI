package com.aurorafox.runtime

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.pdf.PdfRenderer
import android.media.MediaMetadataRetriever
import android.os.ParcelFileDescriptor
import org.json.JSONArray
import org.json.JSONObject
import org.w3c.dom.Element
import java.io.File
import java.nio.charset.Charset
import java.util.zip.ZipFile
import javax.xml.parsers.DocumentBuilderFactory

class AndroidFileRuntime(
    private val context: Context,
    private val voice: AndroidVoiceRuntime,
) {
    private val cacheDir = File(context.filesDir, "file_cache").apply { mkdirs() }
    private val textExt = setOf(
        "txt", "md", "json", "csv", "tsv", "gd", "py", "js", "ts", "tsx", "jsx", "html", "css",
        "xml", "yaml", "yml", "toml", "ini", "cfg", "log", "shader", "glsl", "cpp", "c", "h", "hpp",
        "cs", "java", "kt", "rs", "go", "php", "rb", "lua", "swift", "dart", "sql", "sh", "ps1", "r", "jl"
    )

    fun analyze(path: String, question: String = "", visual: Boolean = true): String {
        val file = try { File(path).canonicalFile } catch (_: Throwable) { return error("Invalid file path") }
        if (!file.isFile) return error("File not found")
        if (file.length() > 1024L * 1024L * 1024L) return error("File is larger than 1 GB")
        val ext = file.extension.lowercase()
        return try {
            val result = when {
                ext in textExt -> analyzeText(file)
                ext == "docx" -> analyzeDocx(file)
                ext == "xlsx" -> analyzeXlsx(file)
                ext == "pptx" -> analyzePptx(file)
                ext == "odt" || ext == "ods" -> analyzeOpenDocument(file, ext)
                ext == "pdf" -> analyzePdf(file)
                ext in setOf("png", "jpg", "jpeg", "webp", "bmp", "gif") -> analyzeImage(file, visual)
                ext in setOf("wav", "mp3", "ogg", "flac", "m4a", "aac", "opus") -> analyzeAudio(file)
                ext in setOf("mp4", "mkv", "webm", "mov", "avi", "m4v") -> analyzeVideo(file, visual)
                ext == "zip" -> analyzeZip(file)
                ext == "xls" -> payload("spreadsheet", "Старый бинарный XLS требует отдельного локального XLS backend.", warnings = listOf("Android native parser поддерживает XLSX; XLS пока не разобран."))
                ext in setOf("7z", "rar") -> payload("archive", "Архив $ext принят.", warnings = listOf("Для этого формата на Android пока не подключён безопасный native распаковщик."))
                else -> analyzeUnknown(file)
            }
            if (question.isNotBlank()) {
                val obj = JSONObject(result)
                val meta = obj.optJSONObject("metadata") ?: JSONObject()
                meta.put("question", question.take(2000))
                obj.put("metadata", meta)
                obj.toString()
            } else result
        } catch (t: Throwable) {
            error("Android file analysis failed: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    fun clearCache(): String {
        cacheDir.listFiles()?.forEach { if (it.isFile) it.delete() }
        return JSONObject(mapOf("ok" to true)).toString()
    }

    fun tree(path: String, maxItems: Int): String {
        val root = try { File(path).canonicalFile } catch (_: Throwable) { return error("Invalid directory path") }
        if (!root.isDirectory) return error("Directory not found")
        val items = JSONArray()
        val rootPath = root.path + File.separator
        root.walkTopDown().drop(1).take(maxItems.coerceIn(1, 5000)).forEach { file ->
            val relative = if (file.path.startsWith(rootPath)) file.path.removePrefix(rootPath).replace(File.separatorChar, '/') else file.name
            items.put(JSONObject(mapOf("path" to relative, "dir" to file.isDirectory, "size" to if (file.isFile) file.length() else 0L)))
        }
        return JSONObject(mapOf("ok" to true, "root" to root.path, "items" to items)).toString()
    }

    private fun analyzeText(file: File): String {
        val bytes = file.readBytes()
        val text = decodeText(bytes)
        return payload("text/code", text.take(160_000), mapOf("encoding_guess" to "utf8/cp1251", "size" to file.length()), truncated = text.length > 160_000)
    }

    private fun analyzeDocx(file: File): String {
        ZipFile(file).use { zip ->
            val entry = zip.getEntry("word/document.xml") ?: return error("DOCX document.xml is missing")
            val xml = zip.getInputStream(entry).readBytes()
            val text = extractXmlText(xml, setOf("t", "tab", "br"))
            return payload("document", text.take(160_000), mapOf("format" to "docx"), truncated = text.length > 160_000)
        }
    }

    private fun analyzePptx(file: File): String {
        ZipFile(file).use { zip ->
            val slides = zip.entries().asSequence()
                .filter { !it.isDirectory && it.name.matches(Regex("ppt/slides/slide\\d+\\.xml")) }
                .sortedBy { slideIndex(it.name) }
                .toList()
            val out = StringBuilder()
            for ((index, entry) in slides.withIndex()) {
                val text = extractXmlText(zip.getInputStream(entry).readBytes(), setOf("t"))
                if (text.isNotBlank()) out.append("\n### Слайд ${index + 1}\n").append(text)
                if (out.length > 170_000) break
            }
            return payload("presentation", out.toString().take(160_000), mapOf("slides" to slides.size), truncated = out.length > 160_000)
        }
    }

    private fun analyzeXlsx(file: File): String {
        ZipFile(file).use { zip ->
            val shared = mutableListOf<String>()
            zip.getEntry("xl/sharedStrings.xml")?.let { entry ->
                val doc = parseXml(zip.getInputStream(entry).readBytes())
                val nodes = doc.getElementsByTagNameNS("*", "si")
                for (i in 0 until nodes.length) shared += nodes.item(i).textContent.trim()
            }
            val sheets = zip.entries().asSequence()
                .filter { !it.isDirectory && it.name.matches(Regex("xl/worksheets/sheet\\d+\\.xml")) }
                .sortedBy { slideIndex(it.name) }
                .toList()
            val out = StringBuilder()
            var cellsRead = 0
            for ((sheetIndex, entry) in sheets.withIndex()) {
                out.append("\n### Лист ${sheetIndex + 1}\n")
                val doc = parseXml(zip.getInputStream(entry).readBytes())
                val rows = doc.getElementsByTagNameNS("*", "row")
                for (r in 0 until rows.length) {
                    val row = rows.item(r) as? Element ?: continue
                    val cells = row.getElementsByTagNameNS("*", "c")
                    val values = mutableListOf<String>()
                    for (c in 0 until cells.length) {
                        val cell = cells.item(c) as? Element ?: continue
                        val valueNodes = cell.getElementsByTagNameNS("*", "v")
                        val raw = if (valueNodes.length > 0) valueNodes.item(0).textContent else ""
                        val value = if (cell.getAttribute("t") == "s") raw.toIntOrNull()?.let { shared.getOrNull(it) } ?: raw else raw
                        values += value
                        cellsRead++
                        if (cellsRead >= 50_000) break
                    }
                    if (values.any { it.isNotBlank() }) out.append(values.joinToString("\t")).append('\n')
                    if (cellsRead >= 50_000 || out.length > 170_000) break
                }
                if (cellsRead >= 50_000 || out.length > 170_000) break
            }
            return payload("spreadsheet", out.toString().take(160_000), mapOf("sheets" to sheets.size, "cells_read" to cellsRead), truncated = out.length > 160_000 || cellsRead >= 50_000)
        }
    }

    private fun analyzeOpenDocument(file: File, ext: String): String {
        ZipFile(file).use { zip ->
            val entry = zip.getEntry("content.xml") ?: return error("OpenDocument content.xml is missing")
            val text = extractXmlText(zip.getInputStream(entry).readBytes(), setOf("p", "h", "table-cell"))
            return payload(if (ext == "ods") "spreadsheet" else "document", text.take(160_000), mapOf("format" to ext), truncated = text.length > 160_000)
        }
    }

    private fun analyzePdf(file: File): String {
        val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        PdfRenderer(descriptor).use { renderer ->
            val pages = renderer.pageCount
            val pageInfo = JSONArray()
            val sample = minOf(pages, 8)
            for (i in 0 until sample) {
                renderer.openPage(i).use { page ->
                    pageInfo.put(JSONObject(mapOf("page" to (i + 1), "width" to page.width, "height" to page.height)))
                }
            }
            return payload(
                "pdf",
                "PDF: $pages стр. Android native runtime подтвердил структуру документа. Текстовый слой PDF на мобильном backend пока не извлекается; для полного разбора используйте Windows File Intelligence или будущий локальный mobile OCR/vision backend.",
                mapOf("pages" to pages, "sample_pages" to pageInfo),
                warnings = listOf("На Android PdfRenderer рендерит страницы, но текущий AuroraFox runtime ещё не выполняет локальный OCR PDF.")
            )
        }
    }

    private fun analyzeImage(file: File, visual: Boolean): String {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, opts)
        val meta = mapOf("width" to opts.outWidth, "height" to opts.outHeight, "mime" to (opts.outMimeType ?: ""))
        return payload(
            "image",
            "Изображение ${opts.outWidth}×${opts.outHeight}${if (opts.outMimeType != null) ", ${opts.outMimeType}" else ""}.",
            meta,
            warnings = if (visual) listOf("Локальный Android vision/OCR backend для содержимого изображения пока не подключён.") else emptyList()
        )
    }

    private fun analyzeAudio(file: File): String {
        val transcribed = voice.transcribe(file.absolutePath, "ru")
        val obj = JSONObject(transcribed)
        if (obj.optBoolean("ok", false)) {
            return payload("audio", obj.optString("text", ""), mapOf("engine" to obj.optString("engine", "android-local-stt")))
        }
        return payload("audio", "Аудиофайл принят.", warnings = listOf(obj.optString("error", "Локальная расшифровка не удалась")))
    }

    private fun analyzeVideo(file: File, visual: Boolean): String {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            payload(
                "video",
                "Видео ${width}×${height}, длительность %.1f сек.".format(duration / 1000.0),
                mapOf("duration_ms" to duration, "width" to width, "height" to height),
                warnings = if (visual) listOf("Глубокий анализ кадров Android vision backend пока не подключён.") else emptyList()
            )
        } finally {
            retriever.release()
        }
    }

    private fun analyzeZip(file: File): String {
        ZipFile(file).use { zip ->
            val entries = JSONArray()
            var count = 0
            var total = 0L
            var unsafe = 0
            val iterator = zip.entries()
            while (iterator.hasMoreElements() && count < 5000) {
                val e = iterator.nextElement()
                val normalized = e.name.replace('\\', '/')
                val bad = normalized.startsWith('/') || normalized.split('/').any { it == ".." }
                if (bad) unsafe++
                if (!e.isDirectory) total += maxOf(0L, e.size)
                entries.put(JSONObject(mapOf("path" to normalized, "size" to e.size, "dir" to e.isDirectory, "unsafe" to bad)))
                count++
            }
            val lines = buildString {
                for (i in 0 until entries.length()) {
                    val e = entries.getJSONObject(i)
                    append(if (e.optBoolean("dir")) "[DIR] " else "")
                    append(e.optString("path")).append(" (").append(e.optLong("size")).append(" B)")
                    if (e.optBoolean("unsafe")) append(" [UNSAFE]")
                    append('\n')
                }
            }
            val warnings = mutableListOf<String>()
            if (unsafe > 0) warnings += "Обнаружено небезопасных путей: $unsafe; автоматическая распаковка таких записей запрещена."
            if (total > 512L * 1024L * 1024L) warnings += "Заявленный распакованный размер превышает 512 МБ."
            return payload("archive", lines.take(160_000), mapOf("entries" to count, "expanded_bytes" to total, "unsafe_entries" to unsafe), warnings, lines.length > 160_000)
        }
    }

    private fun analyzeUnknown(file: File): String {
        val bytes = file.inputStream().use { input -> ByteArray(minOf(file.length(), 256_000L).toInt()).also { input.read(it) } }
        if (bytes.take(4096).any { it == 0.toByte() }) return payload("binary", "Бинарный файл: автоматическое преобразование в текст не выполнено.")
        return payload("text", decodeText(bytes).take(160_000))
    }

    private fun decodeText(bytes: ByteArray): String {
        return try {
            bytes.toString(Charsets.UTF_8)
        } catch (_: Throwable) {
            bytes.toString(Charset.forName("windows-1251"))
        }
    }

    private fun parseXml(bytes: ByteArray) = DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
        try { setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) } catch (_: Throwable) {}
        try { setFeature("http://xml.org/sax/features/external-general-entities", false) } catch (_: Throwable) {}
        try { setFeature("http://xml.org/sax/features/external-parameter-entities", false) } catch (_: Throwable) {}
        isXIncludeAware = false
        isExpandEntityReferences = false
    }.newDocumentBuilder().parse(bytes.inputStream())

    private fun extractXmlText(bytes: ByteArray, localNames: Set<String>): String {
        val doc = parseXml(bytes)
        val out = StringBuilder()
        fun walk(node: org.w3c.dom.Node) {
            if (node.nodeType == org.w3c.dom.Node.ELEMENT_NODE && node.localName in localNames) {
                val text = node.textContent?.trim().orEmpty()
                if (text.isNotBlank()) out.append(text).append('\n')
                return
            }
            val children = node.childNodes
            for (i in 0 until children.length) walk(children.item(i))
        }
        walk(doc.documentElement)
        return out.toString()
    }

    private fun slideIndex(name: String): Int = Regex("(\\d+)").findAll(name).lastOrNull()?.value?.toIntOrNull() ?: Int.MAX_VALUE

    private fun payload(
        kind: String,
        content: String,
        metadata: Map<String, Any?> = emptyMap(),
        warnings: List<String> = emptyList(),
        truncated: Boolean = false,
    ): String = JSONObject().apply {
        put("ok", true)
        put("kind", kind)
        put("content", content)
        put("metadata", JSONObject(metadata))
        put("warnings", JSONArray(warnings))
        put("truncated", truncated)
        put("cached", false)
    }.toString()

    private fun error(message: String): String = JSONObject(mapOf("ok" to false, "error" to message)).toString()
}
