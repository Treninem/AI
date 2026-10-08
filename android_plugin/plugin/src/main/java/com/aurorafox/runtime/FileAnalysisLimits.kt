package com.aurorafox.runtime

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.concurrent.CancellationException

/** Immutable owner settings captured before submitting a job, never global state. */
data class FileAnalysisLimits(
    val fileBytes: Long = 1024L * 1024 * 1024,
    val outputChars: Int = 160000,
    val spreadsheetCells: Int = 50000,
    val archiveEntries: Int = 5000,
    val expandedBytes: Long = 512L * 1024 * 1024,
    val memberBytes: Long = 8L * 1024 * 1024,
    val totalTextBytes: Long = 32L * 1024 * 1024,
    val listingChars: Int = 40000,
    val listingPercent: Int = 25,
    val pdfBytes: Long = 256L * 1024 * 1024,
    val pdfPages: Int = 1000,
    val ocrPages: Int = 500,
    val renderPixels: Long = 8000000,
    val inputPixels: Long = 64000000,
    val pendingJobs: Int = 8,
    val xlsFileBytes: Long = 32L*1024*1024,
    val xlsDirectoryEntries: Int = 4096,
    val xlsDirectoryDepth: Int = 64,
    val xlsSharedStrings: Int = 50000,
    val xlsSheets: Int = 256,
    val xlsRows: Int = 10000,
) {
    companion object {
        fun from(values: Map<String, Long>): FileAnalysisLimits {
            fun number(key: String, default: Long, minimum: Long = 1) = (values[key] ?: default).coerceAtLeast(minimum)
            // Int ceilings reflect JVM string/collection representation, not resource policy.
            fun count(key: String, default: Int, minimum: Int = 1) = number(key, default.toLong(), minimum.toLong()).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            fun nativeCount(key: String, default: Int): Int {
                val value = values[key] ?: default.toLong()
                require(value in 1..Int.MAX_VALUE.toLong()) { "Native XLS budget exceeds positive Int representation: $key" }
                return value.toInt()
            }
            val requestCeiling = count("request_max_text_chars", 500000)
            val output = count("_request_max_chars", count("max_text_chars", 160000)).coerceAtMost(requestCeiling)
            return FileAnalysisLimits(
                fileBytes = number("max_file_bytes", 1024L*1024*1024), outputChars = output,
                spreadsheetCells = count("spreadsheet_max_cells", 50000), archiveEntries = count("archive_max_entries", 5000),
                expandedBytes = number("archive_max_expanded", 512L*1024*1024), memberBytes = number("archive_text_member_max", 8L*1024*1024),
                totalTextBytes = number("archive_text_total_max", 32L*1024*1024), listingChars = count("archive_listing_max_chars", 40000, 0),
                listingPercent = count("archive_listing_percent", 25, 0).coerceAtMost(100), pdfBytes = number("ocr_max_pdf_bytes", 256L*1024*1024),
                pdfPages = count("ocr_max_pdf_pages", 1000), ocrPages = count("ocr_max_pages", 500),
                renderPixels = number("ocr_max_render_pixels", 8000000), inputPixels = number("ocr_max_input_pixels", 64000000),
                pendingJobs = count("android_pending_file_jobs", 8),
                xlsFileBytes = number("android_xls_file_bytes", 32L*1024*1024),
                xlsDirectoryEntries = nativeCount("android_xls_directory_entries", 4096),
                xlsDirectoryDepth = nativeCount("android_xls_directory_depth", 64),
                xlsSharedStrings = nativeCount("android_xls_shared_strings", 50000),
                xlsSheets = nativeCount("android_xls_sheets", 256), xlsRows = count("xls_max_rows", 10000),
            )
        }
    }
}

internal data class BoundedBytes(val bytes: ByteArray, val truncated: Boolean)

/** Streams at most the owner budget and probes one extra byte for real overflow. */
internal fun readOwnerBounded(input: InputStream, limit: Long): BoundedBytes {
    require(limit >= 0)
    val out = ByteArrayOutputStream()
    val buffer = ByteArray(32768)
    var left = limit
    while (left > 0) {
        if (Thread.currentThread().isInterrupted) throw CancellationException("File reading cancelled")
        val read = input.read(buffer, 0, minOf(left, buffer.size.toLong()).toInt())
        if (read < 0) return BoundedBytes(out.toByteArray(), false)
        if (read == 0) continue
        out.write(buffer, 0, read)
        left -= read
    }
    if (Thread.currentThread().isInterrupted) throw CancellationException("File reading cancelled")
    return BoundedBytes(out.toByteArray(), input.read() >= 0)
}

/** Reject DTD/entity declarations even on Android XML factories lacking feature flags. */
internal fun rejectExternalXmlDeclarations(bytes: ByteArray) {
    val ascii = bytes.filter { it != 0.toByte() }.toByteArray().toString(Charsets.ISO_8859_1).uppercase(java.util.Locale.ROOT)
    require(!ascii.contains("<!DOCTYPE") && !ascii.contains("<!ENTITY")) { "Untrusted XML DTD/entity declarations are not allowed" }
}
