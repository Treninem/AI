package com.aurorafox.runtime

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.rendering.PDFRenderer
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.googlecode.tesseract.android.TessBaseAPI
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

class AndroidOcrRuntime(private val context: Context) {
    companion object {
        private const val MAX_PDF_BYTES = 128L * 1024L * 1024L
        private const val MAX_PAGES = 200
        private const val MAX_OCR_PAGES = 150
        private const val MAX_OUTPUT_CHARS = 160_000
        private const val MAX_PIXELS = 8_000_000L
        private const val MAX_INPUT_PIXELS = 64_000_000L
        private const val LANGUAGES = "rus+eng"
        private val MODEL_SHA = mapOf(
            "eng.traineddata" to "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2",
            "rus.traineddata" to "e16e5e036cce1d9ec2b00063cf8b54472625b9e14d893a169e2b0dedeb4df225",
        )
    }

    private val dataRoot = File(context.filesDir, "ocr").apply { mkdirs() }
    private val tessdata = File(dataRoot, "tessdata").apply { mkdirs() }

    fun health(): JSONObject = JSONObject().apply {
        var ready = false
        var healthError = ""
        try {
            ensureModels()
            val api = TessBaseAPI()
            try {
                ready = api.init(dataRoot.absolutePath, LANGUAGES)
                if (!ready) healthError = "Tesseract native init failed"
            } finally {
                api.recycle()
            }
        } catch (t: Throwable) {
            healthError = t.message ?: t.javaClass.simpleName
        }
        put("available", ready)
        put("engine", "tesseract4android")
        put("languages", JSONArray(listOf("rus", "eng")))
        put("network_required", false)
        put("external_ai_required", false)
        put("native_init_checked", true)
        if (healthError.isNotBlank()) put("error", healthError.take(500))
        put("max_pdf_bytes", MAX_PDF_BYTES)
        put("max_pages", MAX_PAGES)
        put("max_ocr_pages", MAX_OCR_PAGES)
        put("max_output_chars", MAX_OUTPUT_CHARS)
        put("max_pixels", MAX_PIXELS)
        put("max_input_pixels", MAX_INPUT_PIXELS)
    }

    fun extract(path: String): String {
        val file = try { File(path).canonicalFile } catch (_: Throwable) { return error("Invalid file path") }
        if (!file.isFile) return error("File not found")
        return try {
            when (file.extension.lowercase()) {
                "pdf" -> extractPdf(file)
                "png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff" -> extractImage(file)
                else -> error("Local OCR supports PDF and image files only")
            }
        } catch (t: Throwable) {
            error("Local Android OCR failed: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    private fun ensureModels() {
        MODEL_SHA.forEach { (name, expected) ->
            val target = File(tessdata, name)
            if (!target.isFile || sha256(target) != expected) {
                val tmp = File(tessdata, "$name.tmp")
                context.assets.open("tessdata/$name").use { input -> tmp.outputStream().use { input.copyTo(it) } }
                val actual = sha256(tmp)
                require(actual == expected) { "Bundled OCR model hash mismatch for $name" }
                if (target.exists()) target.delete()
                if (!tmp.renameTo(target)) { tmp.copyTo(target, overwrite = true); tmp.delete() }
            }
        }
    }

    private fun recognize(bitmap: Bitmap): String {
        ensureModels()
        val prepared = limitBitmap(bitmap)
        val api = TessBaseAPI()
        return try {
            check(api.init(dataRoot.absolutePath, LANGUAGES)) { "Tesseract init failed" }
            api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            api.setImage(prepared)
            api.getUTF8Text()?.replace("\u000c", "")?.trim().orEmpty()
        } finally {
            api.recycle()
            if (prepared !== bitmap) prepared.recycle()
        }
    }

    private fun extractImage(file: File): String {
        val bitmap = decodeBoundedBitmap(file) ?: return error("Image cannot be decoded")
        return try {
            val raw = recognize(bitmap)
            val truncated = raw.length > MAX_OUTPUT_CHARS
            val text = raw.take(MAX_OUTPUT_CHARS)
            payload(
                text,
                mapOf(
                    "engine" to "tesseract4android",
                    "ocr" to true,
                    "pages" to 1,
                    "pages_processed" to 1,
                    "output_truncated" to truncated,
                    "page_sources" to JSONArray().put(JSONObject(mapOf("page" to 1, "source" to "ocr", "chars" to raw.length, "stored_chars" to text.length))),
                ),
                truncated = truncated,
            )
        } finally { bitmap.recycle() }
    }

    private fun extractPdf(file: File): String {
        if (file.length() > MAX_PDF_BYTES) return error("PDF is larger than the 128 MB Android OCR limit")
        PDFBoxResourceLoader.init(context.applicationContext)
        PDDocument.load(file, MemoryUsageSetting.setupTempFileOnly()).use { document ->
            if (document.numberOfPages > MAX_PAGES) return error("PDF has ${document.numberOfPages} pages; Android OCR limit is $MAX_PAGES")
            val renderer = PDFRenderer(document)
            val out = StringBuilder(minOf(MAX_OUTPUT_CHARS, 32_768))
            val pageSources = JSONArray()
            val warnings = JSONArray()
            val ocrHealth = health()
            val ocrReady = ocrHealth.optBoolean("available", false)
            if (!ocrReady) {
                warnings.put("Android local OCR is unavailable; usable PDF text layers will still be imported and scanned pages will be skipped safely.")
            }
            var ocrPages = 0
            var ocrFailedPages = 0
            var textPages = 0
            var emptyPages = 0
            var pagesProcessed = 0
            var outputTruncated = false
            for (index in 0 until document.numberOfPages) {
                if (out.length >= MAX_OUTPUT_CHARS) {
                    outputTruncated = true
                    break
                }
                val pageNo = index + 1
                pagesProcessed = pageNo
                val layer = try {
                    PDFTextStripper().apply { sortByPosition = true; startPage = pageNo; endPage = pageNo }.getText(document).trim()
                } catch (_: Throwable) { "" }
                if (usable(layer)) {
                    textPages++
                    val complete = appendPage(out, pageNo, layer)
                    pageSources.put(JSONObject(mapOf("page" to pageNo, "source" to "text_layer", "chars" to layer.length)))
                    if (!complete) { outputTruncated = true; break }
                    continue
                }
                if (!ocrReady) {
                    if (layer.isBlank()) emptyPages++
                    val complete = if (layer.isNotBlank()) appendPage(out, pageNo, layer) else true
                    pageSources.put(JSONObject(mapOf("page" to pageNo, "source" to "ocr_unavailable", "chars" to layer.length)))
                    if (!complete) { outputTruncated = true; break }
                    continue
                }
                if (ocrPages >= MAX_OCR_PAGES) {
                    if (layer.isBlank()) emptyPages++
                    val complete = if (layer.isNotBlank()) appendPage(out, pageNo, layer) else true
                    pageSources.put(JSONObject(mapOf("page" to pageNo, "source" to "ocr_limit", "chars" to layer.length)))
                    if (!complete) { outputTruncated = true; break }
                    continue
                }
                ocrPages++
                try {
                    val bitmap = renderBoundedPdfPage(document, renderer, index)
                    val recognized = try { recognize(bitmap) } finally { bitmap.recycle() }
                    val chosen = if (recognized.isNotBlank()) recognized else layer
                    if (chosen.isBlank()) emptyPages++
                    val complete = if (chosen.isNotBlank()) appendPage(out, pageNo, chosen) else true
                    pageSources.put(JSONObject(mapOf(
                        "page" to pageNo,
                        "source" to if (recognized.isNotBlank()) "ocr" else if (layer.isNotBlank()) "text_layer_sparse" else "empty",
                        "chars" to chosen.length,
                    )))
                    if (!complete) { outputTruncated = true; break }
                } catch (t: Throwable) {
                    ocrFailedPages++
                    if (layer.isBlank()) emptyPages++
                    val complete = if (layer.isNotBlank()) appendPage(out, pageNo, layer) else true
                    pageSources.put(JSONObject(mapOf(
                        "page" to pageNo,
                        "source" to "ocr_error",
                        "chars" to layer.length,
                        "error" to (t.message ?: t.javaClass.simpleName).take(500),
                    )))
                    warnings.put("Page $pageNo local OCR failed; continuing safely with the remaining document.")
                    if (!complete) { outputTruncated = true; break }
                }
            }
            if (outputTruncated) warnings.put("Local OCR output truncated at $MAX_OUTPUT_CHARS characters")
            if (ocrPages >= MAX_OCR_PAGES && pagesProcessed < document.numberOfPages) warnings.put("OCR page limit reached at $MAX_OCR_PAGES pages")
            return payload(
                out.toString(),
                mapOf(
                    "engine" to "pdfbox+tesseract4android",
                    "pages" to document.numberOfPages,
                    "pages_processed" to pagesProcessed,
                    "text_pages" to textPages,
                    "ocr_pages" to ocrPages,
                    "ocr_failed_pages" to ocrFailedPages,
                    "empty_pages" to emptyPages,
                    "ocr_available" to ocrReady,
                    "ocr" to ocrHealth,
                    "page_sources" to pageSources,
                    "output_limit_chars" to MAX_OUTPUT_CHARS,
                    "output_truncated" to outputTruncated,
                    "streaming_pages" to true,
                    "pdf_buffering" to "temp_file",
                ),
                warnings,
                outputTruncated,
            )
        }
    }

    private fun usable(text: String): Boolean {
        val compact = text.filterNot { it.isWhitespace() }
        return compact.length >= 12 && compact.count { it.isLetterOrDigit() } >= 4
    }

    private fun appendPage(out: StringBuilder, page: Int, text: String): Boolean {
        val prefix = if (out.isNotEmpty()) "\n\n" else ""
        val block = "$prefix### Страница $page\n$text"
        val remaining = MAX_OUTPUT_CHARS - out.length
        if (remaining <= 0) return false
        if (block.length <= remaining) {
            out.append(block)
            return true
        }
        out.append(block, 0, remaining)
        return false
    }

    private fun decodeBoundedBitmap(file: File): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        val width = bounds.outWidth
        val height = bounds.outHeight
        if (width <= 0 || height <= 0) return null
        val inputPixels = width.toLong() * height.toLong()
        require(inputPixels <= MAX_INPUT_PIXELS) { "Image exceeds local OCR input limit of $MAX_INPUT_PIXELS pixels" }
        var sample = 1
        while ((width / sample).toLong().coerceAtLeast(1L) * (height / sample).toLong().coerceAtLeast(1L) > MAX_PIXELS) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return BitmapFactory.decodeFile(file.absolutePath, options)
    }

    private fun renderBoundedPdfPage(document: PDDocument, renderer: PDFRenderer, index: Int): Bitmap {
        val box = document.getPage(index).cropBox
        val defaultScale = 180.0 / 72.0
        val projected = maxOf(1.0, box.width.toDouble() * box.height.toDouble() * defaultScale * defaultScale)
        val scale = if (projected > MAX_PIXELS.toDouble()) {
            defaultScale * kotlin.math.sqrt(MAX_PIXELS.toDouble() / projected)
        } else defaultScale
        return renderer.renderImage(index, scale.coerceAtLeast(0.1).toFloat())
    }

    private fun limitBitmap(bitmap: Bitmap): Bitmap {
        val pixels = bitmap.width.toLong() * bitmap.height.toLong()
        if (pixels <= MAX_PIXELS) return bitmap
        val scale = kotlin.math.sqrt(MAX_PIXELS.toDouble() / pixels.toDouble())
        return Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt().coerceAtLeast(1), (bitmap.height * scale).toInt().coerceAtLeast(1), true)
    }

    private fun payload(
        content: String,
        metadata: Map<String, Any?>,
        warnings: JSONArray = JSONArray(),
        truncated: Boolean = false,
    ): String = JSONObject().apply {
        put("ok", true)
        put("mode", "text")
        put("content", content)
        put("text", content)
        put("metadata", JSONObject(metadata).apply {
            put("untrusted_document", true)
            put("content_authority", "data_only")
            put("offline", true)
            put("external_ai_required", false)
        })
        put("warnings", warnings)
        put("truncated", truncated)
        put("extractor", "aurora_android_local_ocr")
    }.toString()

    private fun error(message: String): String = JSONObject(mapOf("ok" to false, "error" to message, "ocr_available" to false, "external_ai_required" to false)).toString()

    private fun sha256(file: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) { val n = input.read(buf); if (n <= 0) break; md.update(buf, 0, n) }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }
}
