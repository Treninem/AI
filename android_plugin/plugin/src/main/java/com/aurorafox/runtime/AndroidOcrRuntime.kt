package com.aurorafox.runtime

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
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
        private const val LANGUAGES = "rus+eng"
        private val MODEL_SHA = mapOf(
            "eng.traineddata" to "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2",
            "rus.traineddata" to "e16e5e036cce1d9ec2b00063cf8b54472625b9e14d893a169e2b0dedeb4df225",
        )
    }

    private val dataRoot = File(context.filesDir, "ocr").apply { mkdirs() }
    private val tessdata = File(dataRoot, "tessdata").apply { mkdirs() }

    fun health(): JSONObject = JSONObject().apply {
        val ready = try { ensureModels(); true } catch (_: Throwable) { false }
        put("available", ready)
        put("engine", "tesseract4android")
        put("languages", JSONArray(listOf("rus", "eng")))
        put("network_required", false)
        put("external_ai_required", false)
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
            api.pageSegMode = TessBaseAPI.PageSegMode.PSM_AUTO
            api.setImage(prepared)
            api.utF8Text?.replace("\u000c", "")?.trim().orEmpty()
        } finally {
            api.recycle()
            if (prepared !== bitmap) prepared.recycle()
        }
    }

    private fun extractImage(file: File): String {
        val bitmap = BitmapFactory.decodeFile(file.absolutePath) ?: return error("Image cannot be decoded")
        return try {
            val text = recognize(bitmap)
            payload(text, mapOf("engine" to "tesseract4android", "ocr" to true, "pages" to 1, "page_sources" to JSONArray().put(JSONObject(mapOf("page" to 1, "source" to "ocr", "chars" to text.length)))))
        } finally { bitmap.recycle() }
    }

    private fun extractPdf(file: File): String {
        if (file.length() > MAX_PDF_BYTES) return error("PDF is larger than the 128 MB Android OCR limit")
        PDFBoxResourceLoader.init(context.applicationContext)
        PDDocument.load(file).use { document ->
            if (document.numberOfPages > MAX_PAGES) return error("PDF has ${document.numberOfPages} pages; Android OCR limit is $MAX_PAGES")
            val renderer = PDFRenderer(document)
            val out = StringBuilder()
            val pageSources = JSONArray()
            val warnings = JSONArray()
            var ocrPages = 0
            var textPages = 0
            for (index in 0 until document.numberOfPages) {
                val pageNo = index + 1
                val layer = try {
                    PDFTextStripper().apply { sortByPosition = true; startPage = pageNo; endPage = pageNo }.getText(document).trim()
                } catch (_: Throwable) { "" }
                if (usable(layer)) {
                    textPages++
                    appendPage(out, pageNo, layer)
                    pageSources.put(JSONObject(mapOf("page" to pageNo, "source" to "text_layer", "chars" to layer.length)))
                    continue
                }
                if (ocrPages >= MAX_OCR_PAGES) {
                    if (layer.isNotBlank()) appendPage(out, pageNo, layer)
                    pageSources.put(JSONObject(mapOf("page" to pageNo, "source" to "ocr_limit", "chars" to layer.length)))
                    continue
                }
                val bitmap = renderer.renderImageWithDPI(index, 180f)
                val recognized = try { recognize(bitmap) } finally { bitmap.recycle() }
                ocrPages++
                val chosen = if (recognized.isNotBlank()) recognized else layer
                if (chosen.isNotBlank()) appendPage(out, pageNo, chosen)
                pageSources.put(JSONObject(mapOf("page" to pageNo, "source" to if (recognized.isNotBlank()) "ocr" else if (layer.isNotBlank()) "text_layer_sparse" else "empty", "chars" to chosen.length)))
                if (out.length >= MAX_OUTPUT_CHARS) { warnings.put("OCR output truncated at $MAX_OUTPUT_CHARS characters"); break }
            }
            return payload(out.toString().take(MAX_OUTPUT_CHARS), mapOf("engine" to "pdfbox+tesseract4android", "pages" to document.numberOfPages, "text_pages" to textPages, "ocr_pages" to ocrPages, "page_sources" to pageSources), warnings)
        }
    }

    private fun usable(text: String): Boolean {
        val compact = text.filterNot { it.isWhitespace() }
        return compact.length >= 12 && compact.count { it.isLetterOrDigit() } >= 4
    }

    private fun appendPage(out: StringBuilder, page: Int, text: String) {
        if (out.isNotEmpty()) out.append("\n\n")
        out.append("### Страница ").append(page).append('\n').append(text)
    }

    private fun limitBitmap(bitmap: Bitmap): Bitmap {
        val pixels = bitmap.width.toLong() * bitmap.height.toLong()
        if (pixels <= MAX_PIXELS) return bitmap
        val scale = kotlin.math.sqrt(MAX_PIXELS.toDouble() / pixels.toDouble())
        return Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt().coerceAtLeast(1), (bitmap.height * scale).toInt().coerceAtLeast(1), true)
    }

    private fun payload(content: String, metadata: Map<String, Any?>, warnings: JSONArray = JSONArray()): String = JSONObject().apply {
        put("ok", true); put("mode", "text"); put("content", content); put("text", content)
        put("metadata", JSONObject(metadata).apply { put("untrusted_document", true); put("content_authority", "data_only"); put("offline", true); put("external_ai_required", false) })
        put("warnings", warnings); put("truncated", content.length >= MAX_OUTPUT_CHARS); put("extractor", "aurora_android_local_ocr")
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
