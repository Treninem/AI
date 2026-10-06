package com.aurorafox.runtime

import android.content.Context
import android.media.MediaMetadataRetriever
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
    private val ocr = AndroidOcrRuntime(context)
    private val textExt = setOf(
        "txt", "md", "json", "jsonl", "ndjson", "csv", "tsv", "gd", "py", "js", "ts", "tsx", "jsx", "html", "css",
        "xml", "yaml", "yml", "toml", "ini", "cfg", "log", "shader", "glsl", "cpp", "c", "h", "hpp",
        "cs", "java", "kt", "rs", "go", "php", "rb", "lua", "swift", "dart", "sql", "sh", "ps1", "r", "jl"
    )

    fun analyze(path: String, question: String = "", visual: Boolean = true, limits: FileAnalysisLimits = FileAnalysisLimits()): String {
        val file = try { File(path).canonicalFile } catch (_: Throwable) { return error("Invalid file path") }
        if (!file.isFile) return error("File not found")
        if (file.length() > limits.fileBytes) return error("File exceeds owner limit of ${limits.fileBytes} bytes")
        val ext = file.extension.lowercase()
        return try {
            val result = when {
                ext in textExt -> analyzeText(file, limits)
                ext == "docx" -> analyzeDocx(file, limits)
                ext == "xlsx" -> analyzeXlsx(file, limits)
                ext == "pptx" -> analyzePptx(file, limits)
                ext == "odt" || ext == "ods" -> analyzeOpenDocument(file, ext, limits)
                ext == "pdf" -> analyzeOcr(file, "pdf", visual, limits)
                ext in setOf("png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff") -> analyzeOcr(file, "image", visual, limits)
                ext == "gif" -> JSONObject(analyzeOcr(file, "image", visual, limits)).apply {
                    val warnings = optJSONArray("warnings") ?: JSONArray()
                    warnings.put("GIF: OCR выполнен для первого кадра; анимация целиком не разобрана.")
                    put("warnings", warnings)
                    put("truncated", true)
                    val metadata = optJSONObject("metadata") ?: JSONObject()
                    metadata.put("output_truncated", true)
                    metadata.put("gif_frame_scope", "first_frame")
                    put("metadata", metadata)
                }.toString()
                ext in setOf("wav", "mp3", "ogg", "flac", "m4a", "aac", "opus") -> analyzeAudio(file, limits)
                ext in setOf("mp4", "mkv", "webm", "mov", "avi", "m4v") -> analyzeVideo(file, visual)
                ext == "zip" -> analyzeZip(file, limits)
                ext == "epub" -> readEpubText(file, limits).let { payload("ebook", it.text, it.metadata, it.warnings, it.truncated) }
                ext in setOf("tar", "tgz") || file.name.endsWith(".tar.gz", true) -> readTarText(file, limits, textExt).let { payload("archive", it.text, it.metadata, it.warnings, it.truncated) }
                ext == "xls" -> readXlsText(file, limits).let { payload("spreadsheet", it.text, it.metadata, it.warnings, it.truncated) }
                ext == "7z" -> readSevenZText(file, limits, textExt).let { payload("archive", it.text, it.metadata, it.warnings, it.truncated) }
                ext == "rar" -> readRarText(file, limits, textExt).let { payload("archive", it.text, it.metadata, it.warnings, it.truncated) }
                else -> analyzeUnknown(file, limits)
            }
            val obj = JSONObject(result)
            val meta = obj.optJSONObject("metadata") ?: JSONObject()
            meta.put("owner_limits", JSONObject(mapOf(
                "android_xls_file_bytes" to limits.xlsFileBytes, "android_xls_directory_entries" to limits.xlsDirectoryEntries,
                "android_xls_directory_depth" to limits.xlsDirectoryDepth, "android_xls_shared_strings" to limits.xlsSharedStrings,
                "android_xls_sheets" to limits.xlsSheets, "xls_max_rows" to limits.xlsRows,
                "max_file_bytes" to limits.fileBytes, "output_chars" to limits.outputChars,
                "spreadsheet_max_cells" to limits.spreadsheetCells, "archive_max_entries" to limits.archiveEntries,
                "archive_max_expanded" to limits.expandedBytes, "archive_text_member_max" to limits.memberBytes,
                "archive_text_total_max" to limits.totalTextBytes, "archive_listing_max_chars" to limits.listingChars,
                "archive_listing_percent" to limits.listingPercent, "ocr_max_pdf_bytes" to limits.pdfBytes,
                "ocr_max_pdf_pages" to limits.pdfPages, "ocr_max_pages" to limits.ocrPages,
                "ocr_max_render_pixels" to limits.renderPixels, "ocr_max_input_pixels" to limits.inputPixels,
            )))
            if (question.isNotBlank()) meta.put("question", question.take(limits.outputChars))
            obj.put("metadata", meta)
            obj.toString()
        } catch (_: java.util.concurrent.CancellationException) {
            JSONObject(mapOf("ok" to false, "cancelled" to true, "error" to "Android file analysis cancelled")).toString()
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
        val snapshot = boundedDirectoryTree(root, maxItems)
        snapshot.files.forEach { file ->
            val relative = if (file.path.startsWith(rootPath)) file.path.removePrefix(rootPath).replace(File.separatorChar, '/') else file.name
            items.put(JSONObject(mapOf("path" to relative, "dir" to file.isDirectory, "size" to if (file.isFile) file.length() else 0L)))
        }
        return JSONObject(mapOf("ok" to true, "root" to root.path, "items" to items,
            "truncated" to snapshot.truncated, "item_budget" to maxItems.coerceAtLeast(1))).toString()
    }

    private fun analyzeText(file: File, limits: FileAnalysisLimits): String {
        val read = file.inputStream().use { readOwnerBounded(it, minOf(limits.fileBytes, limits.outputChars.toLong() * 4 + 4)) }
        val bytes = read.bytes
        val text = decodeText(bytes)
        return payload("text/code", text.take(limits.outputChars), mapOf("encoding_guess" to "utf8/cp1251", "size" to file.length()), truncated = read.truncated || text.length > limits.outputChars)
    }

    private fun analyzeDocx(file: File, limits: FileAnalysisLimits): String {
        ZipFile(file).use { zip ->
            val entry = zip.getEntry("word/document.xml") ?: return error("DOCX document.xml is missing")
            val xml = readXmlMember(zip, entry, limits)
            val text = extractXmlText(xml, setOf("t", "tab", "br"))
            return payload("document", text.take(limits.outputChars), mapOf("format" to "docx"), truncated = text.length > limits.outputChars)
        }
    }

    private fun analyzePptx(file: File, limits: FileAnalysisLimits): String {
        ZipFile(file).use { zip ->
            val slides = zip.entries().asSequence()
                .filter { !it.isDirectory && it.name.matches(Regex("ppt/slides/slide\\d+\\.xml")) }
                .sortedBy { slideIndex(it.name) }
                .toList()
            val out = StringBuilder()
            for ((index, entry) in slides.withIndex()) {
                val text = extractXmlText(readXmlMember(zip, entry, limits), setOf("t"))
                if (text.isNotBlank()) out.append("\n### Слайд ${index + 1}\n").append(text)
                if (out.length > limits.outputChars) break
            }
            return payload("presentation", out.toString().take(limits.outputChars), mapOf("slides" to slides.size), truncated = out.length > limits.outputChars)
        }
    }

    private fun analyzeXlsx(file: File, limits: FileAnalysisLimits): String {
        ZipFile(file).use { zip ->
            val shared = mutableListOf<String>()
            zip.getEntry("xl/sharedStrings.xml")?.let { entry ->
                val doc = parseXml(readXmlMember(zip, entry, limits))
                val nodes = doc.getElementsByTagNameNS("*", "si")
                for (i in 0 until nodes.length) shared += nodes.item(i).textContent.trim()
            }
            val sheets = zip.entries().asSequence()
                .filter { !it.isDirectory && it.name.matches(Regex("xl/worksheets/sheet\\d+\\.xml")) }
                .sortedBy { slideIndex(it.name) }
                .toList()
            val out = StringBuilder()
            var cellsRead = 0
            var cellsTruncated = false
            for ((sheetIndex, entry) in sheets.withIndex()) {
                out.append("\n### Лист ${sheetIndex + 1}\n")
                val doc = parseXml(readXmlMember(zip, entry, limits))
                val rows = doc.getElementsByTagNameNS("*", "row")
                for (r in 0 until rows.length) {
                    val row = rows.item(r) as? Element ?: continue
                    val cells = row.getElementsByTagNameNS("*", "c")
                    val values = mutableListOf<String>()
                    for (c in 0 until cells.length) {
                        val cell = cells.item(c) as? Element ?: continue
                        if (cellsRead >= limits.spreadsheetCells) { cellsTruncated = true; break }
                        val valueNodes = cell.getElementsByTagNameNS("*", "v")
                        val raw = if (valueNodes.length > 0) valueNodes.item(0).textContent else ""
                        val value = if (cell.getAttribute("t") == "s") raw.toIntOrNull()?.let { shared.getOrNull(it) } ?: raw else raw
                        values += value
                        cellsRead++
                    }
                    if (values.any { it.isNotBlank() }) out.append(values.joinToString("\t")).append('\n')
                    if (cellsTruncated || out.length > limits.outputChars) break
                }
                if (cellsTruncated || out.length > limits.outputChars) break
            }
            return payload("spreadsheet", out.toString().take(limits.outputChars), mapOf("sheets" to sheets.size, "cells_read" to cellsRead, "cell_budget" to limits.spreadsheetCells), truncated = out.length > limits.outputChars || cellsTruncated)
        }
    }

    private fun analyzeOpenDocument(file: File, ext: String, limits: FileAnalysisLimits): String {
        ZipFile(file).use { zip ->
            val entry = zip.getEntry("content.xml") ?: return error("OpenDocument content.xml is missing")
            val text = extractXmlText(readXmlMember(zip, entry, limits), setOf("p", "h", "table-cell"))
            return payload(if (ext == "ods") "spreadsheet" else "document", text.take(limits.outputChars), mapOf("format" to ext), truncated = text.length > limits.outputChars)
        }
    }

    private fun analyzeOcr(file: File, kind: String, visual: Boolean, limits: FileAnalysisLimits): String {
        val raw = ocr.extract(file.absolutePath, limits)
        val obj = try { JSONObject(raw) } catch (_: Throwable) { return error("Invalid local OCR response") }
        if (!obj.optBoolean("ok", false)) return raw
        obj.put("kind", kind)
        val meta = obj.optJSONObject("metadata") ?: JSONObject()
        meta.put("visual_requested", visual)
        meta.put("local_ocr", true)
        meta.put("untrusted_document", true)
        meta.put("content_authority", "data_only")
        meta.put("offline", true)
        meta.put("external_ai_required", false)
        obj.put("metadata", meta)
        obj.put("cached", false)
        return obj.toString()
    }

    private fun analyzeAudio(file: File, limits: FileAnalysisLimits): String {
        val transcribed = voice.transcribe(file.absolutePath, "ru")
        val obj = JSONObject(transcribed)
        if (obj.optBoolean("ok", false)) {
            val text = obj.optString("text", "")
            if (text.isBlank()) return error("Local audio transcription returned no text")
            return payload("audio", text.take(limits.outputChars), mapOf("engine" to obj.optString("engine", "android-local-stt")), truncated = text.length > limits.outputChars)
        }
        return error(obj.optString("error", "Локальная расшифровка не удалась"))
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

    private fun analyzeZip(file: File, limits: FileAnalysisLimits): String {
        val result = readArchiveText(file, limits, textExt)
        return payload("archive", result.text, result.metadata, result.warnings, result.truncated)
    }

    private fun analyzeUnknown(file: File, limits: FileAnalysisLimits): String {
        val read = file.inputStream().use { readOwnerBounded(it, minOf(limits.fileBytes, limits.outputChars.toLong() * 4 + 4)) }
        if (read.bytes.take(4096).any { it == 0.toByte() }) return unsupportedFormat(file.extension.lowercase())
        val decoded = decodeText(read.bytes)
        return payload("text", decoded.take(limits.outputChars), truncated = read.truncated || decoded.length > limits.outputChars)
    }

    private fun readXmlMember(zip: ZipFile, entry: java.util.zip.ZipEntry, limits: FileAnalysisLimits): ByteArray {
        require(entry.size <= limits.memberBytes || entry.size < 0) { "XML member exceeds owner byte budget" }
        val result = zip.getInputStream(entry).use { readOwnerBounded(it, limits.memberBytes) }
        require(!result.truncated) { "XML member exceeds owner byte budget; raise File Intelligence limits" }
        return result.bytes
    }

    private fun decodeText(bytes: ByteArray): String {
        return try {
            bytes.toString(Charsets.UTF_8)
        } catch (_: Throwable) {
            bytes.toString(Charset.forName("windows-1251"))
        }
    }

    private fun parseXml(bytes: ByteArray): org.w3c.dom.Document {
        rejectExternalXmlDeclarations(bytes)
        return DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
        try { setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) } catch (_: Throwable) {}
        try { setFeature("http://xml.org/sax/features/external-general-entities", false) } catch (_: Throwable) {}
        try { setFeature("http://xml.org/sax/features/external-parameter-entities", false) } catch (_: Throwable) {}
        isXIncludeAware = false
        isExpandEntityReferences = false
        }.newDocumentBuilder().parse(bytes.inputStream())
    }

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
        put("metadata", JSONObject(metadata).apply {
            put("output_truncated", truncated)
            put("untrusted_document", true)
            put("content_authority", "data_only")
        })
        put("warnings", JSONArray(warnings))
        put("truncated", truncated)
        put("cached", false)
    }.toString()

    private fun unsupportedFormat(extension: String): String = JSONObject(mapOf(
        "ok" to false,
        "error" to "Android local extractor for $extension is unavailable; provide a supported file or accessible text source",
        "error_code" to "unsupported_format",
        "extension" to extension,
        "requires_extractor" to true,
    )).toString()

    private fun error(message: String): String = JSONObject(mapOf("ok" to false, "error" to message)).toString()
}