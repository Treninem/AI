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
import java.util.concurrent.CancellationException

class AndroidOcrRuntime(private val context: Context) {
    companion object {
        private const val LANGUAGES = "rus+eng"
        private val MODEL_SHA = mapOf(
            "eng.traineddata" to "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2",
            "rus.traineddata" to "e16e5e036cce1d9ec2b00063cf8b54472625b9e14d893a169e2b0dedeb4df225",
        )
        @Volatile private var modelsVerified = false
    }

    private val dataRoot = File(context.filesDir, "ocr").apply { mkdirs() }
    private val tessdata = File(dataRoot, "tessdata").apply { mkdirs() }

    fun health(limits: FileAnalysisLimits = FileAnalysisLimits()): JSONObject = JSONObject().apply {
        var ready = false
        var healthError = ""
        var api: TessBaseAPI? = null
        try {
            api = newInitializedApi()
            ready = true
        } catch (t: Throwable) {
            healthError = t.message ?: t.javaClass.simpleName
        } finally {
            api?.recycle()
        }
        put("available", ready)
        put("engine", "tesseract4android")
        put("languages", JSONArray(listOf("rus", "eng")))
        put("network_required", false)
        put("external_ai_required", false)
        put("native_init_checked", true)
        if (healthError.isNotBlank()) put("error", healthError.take(500))
        put("max_pdf_bytes", limits.pdfBytes)
        put("max_pages", limits.pdfPages)
        put("max_ocr_pages", limits.ocrPages)
        put("max_output_chars", limits.outputChars)
        put("max_pixels", limits.renderPixels)
        put("max_input_pixels", limits.inputPixels)
    }

    fun extract(path: String, limits: FileAnalysisLimits = FileAnalysisLimits()): String {
        val file = try { File(path).canonicalFile } catch (_: Throwable) { return error("Invalid file path") }
        if (!file.isFile) return error("File not found")
        return try {
            when (file.extension.lowercase()) {
                "pdf" -> extractPdf(file, limits)
                "png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff" -> extractImage(file, limits)
                else -> error("Local OCR supports PDF and image files only")
            }
        } catch (_: CancellationException) {
            cancelled()
        } catch (t: Throwable) {
            error("Local Android OCR failed: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    private fun ensureModels() {
        if (modelsVerified) return
        synchronized(AndroidOcrRuntime::class.java) {
            if (modelsVerified) return
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
            modelsVerified = true
        }
    }

    private fun newInitializedApi(): TessBaseAPI {
        ensureModels()
        val api = TessBaseAPI()
        try {
            check(api.init(dataRoot.absolutePath, LANGUAGES)) { "Tesseract init failed" }
            api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            return api
        } catch (t: Throwable) {
            modelsVerified = false
            api.recycle()
            throw t
        }
    }

    private fun checkCancelled() {
        if (Thread.currentThread().isInterrupted) throw CancellationException("Local OCR cancelled")
    }

    private fun recognize(bitmap: Bitmap, limits: FileAnalysisLimits, sharedApi: TessBaseAPI? = null): String {
        checkCancelled()
        val prepared = limitBitmap(bitmap, limits)
        var ownedApi: TessBaseAPI? = null
        return try {
            val activeApi = sharedApi ?: newInitializedApi().also { ownedApi = it }
            checkCancelled()
            activeApi.setImage(prepared)
            val text = activeApi.getUTF8Text()?.replace("\u000c", "")?.trim().orEmpty()
            checkCancelled()
            text
        } finally {
            ownedApi?.recycle()
            if (prepared !== bitmap) prepared.recycle()
        }
    }

    private fun extractImage(file: File, limits: FileAnalysisLimits): String {
        checkCancelled()
        val bitmap = decodeBoundedBitmap(file, limits) ?: return error("Image cannot be decoded")
        return try {
            val raw = recognize(bitmap, limits)
            checkCancelled()
            val truncated = raw.length > limits.outputChars
            val text = raw.take(limits.outputChars)
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

    private fun extractPdf(file: File, limits: FileAnalysisLimits): String {
        checkCancelled()
        if (file.length() > limits.pdfBytes) return error("PDF exceeds owner byte limit ${limits.pdfBytes}")
        PDFBoxResourceLoader.init(context.applicationContext)
        PDDocument.load(file, MemoryUsageSetting.setupTempFileOnly()).use { document ->
            if (document.numberOfPages > limits.pdfPages) return error("PDF has ${document.numberOfPages} pages; Android OCR limit is ${limits.pdfPages}")
            val renderer = PDFRenderer(document)
            val out = StringBuilder(minOf(limits.outputChars, 32_768))
            val pageSources = JSONArray()
            val warnings = JSONArray()
            val ocrHealth = health(limits)
            var ocrReady = ocrHealth.optBoolean("available", false)
            var sharedApi: TessBaseAPI? = null
            if (ocrReady) {
                try {
                    sharedApi = newInitializedApi()
                } catch (t: Throwable) {
                    ocrReady = false
                    val message = t.message ?: t.javaClass.simpleName
                    ocrHealth.put("available", false)
                    ocrHealth.put("error", message.take(500))
                    warnings.put("Android local OCR could not initialize for this document; text-layer pages will still be imported safely.")
                }
            } else {
                warnings.put("Android local OCR is unavailable; usable PDF text layers will still be imported and scanned pages will be skipped safely.")
            }
            var ocrPages = 0
            var ocrFailedPages = 0
            var textPages = 0
            var emptyPages = 0
            var pagesProcessed = 0
            var outputTruncated = false
            var ocrLimitReached = false
            try {
                for (index in 0 until document.numberOfPages) {
                    checkCancelled()
                    if (out.length >= limits.outputChars) {
                        outputTruncated = true
                        break
                    }
                    val pageNo = index + 1
                    pagesProcessed = pageNo
                    val layer = try {
                        PDFTextStripper().apply { sortByPosition = true; startPage = pageNo; endPage = pageNo }.getText(document).trim()
                    } catch (_: Throwable) { "" }
                    checkCancelled()
                    if (usable(layer)) {
                        textPages++
                        val complete = appendPage(out, pageNo, layer, limits)
                        pageSources.put(JSONObject(mapOf("page" to pageNo, "source" to "text_layer", "chars" to layer.length)))
                        if (!complete) { outputTruncated = true; break }
                        continue
                    }
                    if (!ocrReady) {
                        if (layer.isBlank()) emptyPages++
                        val complete = if (layer.isNotBlank()) appendPage(out, pageNo, layer, limits) else true
                        pageSources.put(JSONObject(mapOf("page" to pageNo, "source" to "ocr_unavailable", "chars" to layer.length)))
                        if (!complete) { outputTruncated = true; break }
                        continue
                    }
                    if (ocrPages >= limits.ocrPages) {
                        ocrLimitReached = true
                        if (layer.isBlank()) emptyPages++
                        val complete = if (layer.isNotBlank()) appendPage(out, pageNo, layer, limits) else true
                        pageSources.put(JSONObject(mapOf("page" to pageNo, "source" to "ocr_limit", "chars" to layer.length)))
                        if (!complete) { outputTruncated = true; break }
                        continue
                    }
                    ocrPages++
                    try {
                        val bitmap = renderBoundedPdfPage(document, renderer, index, limits)
                        val recognized = try { recognize(bitmap, limits, sharedApi) } finally { bitmap.recycle() }
                        val chosen = if (recognized.isNotBlank()) recognized else layer
                        if (chosen.isBlank()) emptyPages++
                        val complete = if (chosen.isNotBlank()) appendPage(out, pageNo, chosen, limits) else true
                        pageSources.put(JSONObject(mapOf(
                            "page" to pageNo,
                            "source" to if (recognized.isNotBlank()) "ocr" else if (layer.isNotBlank()) "text_layer_sparse" else "empty",
                            "chars" to chosen.length,
                        )))
                        if (!complete) { outputTruncated = true; break }
                    } catch (t: Throwable) {
                        if (t is CancellationException) throw t
                        ocrFailedPages++
                        if (layer.isBlank()) emptyPages++
                        val complete = if (layer.isNotBlank()) appendPage(out, pageNo, layer, limits) else true
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
            } finally {
                sharedApi?.recycle()
            }
            if (outputTruncated) warnings.put("Local OCR output truncated at ${limits.outputChars} characters")
            if (ocrLimitReached) warnings.put("OCR page limit reached at ${limits.ocrPages} pages")
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
                    "output_limit_chars" to limits.outputChars,
                    "output_truncated" to (outputTruncated || ocrLimitReached || ocrFailedPages > 0),
                    "streaming_pages" to true,
                    "pdf_buffering" to "temp_file",
                    "ocr_engine_reused" to (ocrReady && sharedApi != null),
                    "cancellation_supported" to true,
                ),
                warnings,
                outputTruncated || ocrLimitReached || ocrFailedPages > 0,
            )
        }
    }

    private fun usable(text: String): Boolean {
        val compact = text.filterNot { it.isWhitespace() }
        return compact.length >= 12 && compact.count { it.isLetterOrDigit() } >= 4
    }

    private fun appendPage(out: StringBuilder, page: Int, text: String, limits: FileAnalysisLimits): Boolean =
        appendOwnerPage(out, page, text, limits.outputChars)

    private fun decodeBoundedBitmap(file: File, limits: FileAnalysisLimits): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        val width = bounds.outWidth
        val height = bounds.outHeight
        if (width <= 0 || height <= 0) return null
        val inputPixels = width.toLong() * height.toLong()
        require(inputPixels <= limits.inputPixels) { "Image exceeds local OCR input limit of ${limits.inputPixels} pixels" }
        var sample = 1
        while ((width / sample).toLong().coerceAtLeast(1L) * (height / sample).toLong().coerceAtLeast(1L) > limits.renderPixels) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return BitmapFactory.decodeFile(file.absolutePath, options)
    }

    private fun renderBoundedPdfPage(document: PDDocument, renderer: PDFRenderer, index: Int, limits: FileAnalysisLimits): Bitmap {
        val box = document.getPage(index).cropBox
        val width = box.width.toDouble()
        val height = box.height.toDouble()
        val scale = ownerPdfRenderScale(width, height, limits.renderPixels)
        return renderer.renderImage(index, scale.toFloat())
    }

    private fun limitBitmap(bitmap: Bitmap, limits: FileAnalysisLimits): Bitmap {
        val pixels = bitmap.width.toLong() * bitmap.height.toLong()
        if (pixels <= limits.renderPixels) return bitmap
        val scale = kotlin.math.sqrt(limits.renderPixels.toDouble() / pixels.toDouble())
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

    private fun cancelled(): String = JSONObject(
        mapOf(
            "ok" to false,
            "cancelled" to true,
            "error" to "Local OCR cancelled",
            "ocr_available" to true,
            "external_ai_required" to false,
        )
    ).toString()

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
