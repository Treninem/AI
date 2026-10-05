package com.aurorafox.runtime

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class FileAnalysisLimitsTest {
    @Test fun ownerSnapshotIsImmutableAndLowerRequestCeilingIsHonored() {
        val values = mutableMapOf("_request_max_chars" to 900000L, "request_max_text_chars" to 200001L,
            "spreadsheet_max_cells" to 60001L, "ocr_max_pdf_pages" to 2001L, "ocr_max_pages" to 701L,
            "archive_listing_max_chars" to 80001L, "analysis_timeout_seconds" to 1200L)
        val first = FileAnalysisLimits.from(values)
        values["spreadsheet_max_cells"] = 2
        val second = FileAnalysisLimits.from(values)
        assertEquals(60001, first.spreadsheetCells); assertEquals(2, second.spreadsheetCells)
        assertEquals(200001, first.outputChars); assertEquals(2001, first.pdfPages); assertEquals(701, first.ocrPages)
        assertEquals(80001, first.listingChars)
    }

    @Test fun commonDefaultsAndZeroListingAreExplicit() {
        val defaults = FileAnalysisLimits.from(emptyMap())
        assertEquals(256L*1024*1024, defaults.pdfBytes)
        assertEquals(1000, defaults.pdfPages); assertEquals(500, defaults.ocrPages)
        val limits = FileAnalysisLimits.from(mapOf("archive_listing_percent" to 0L, "archive_listing_max_chars" to 0L,
            "ocr_max_input_pixels" to 90000000L, "android_pending_file_jobs" to 16L))
        assertEquals(0, limits.listingPercent); assertEquals(0, limits.listingChars)
        assertEquals(90000000L, limits.inputPixels); assertEquals(16, limits.pendingJobs)
    }

    @Test fun byteReaderSeparatesExactFitAndRealOverflow() {
        val bytes = "Actual bytes".toByteArray()
        val exact = ByteArrayInputStream(bytes).use { readOwnerBounded(it, bytes.size.toLong()) }
        assertArrayEquals(bytes, exact.bytes); assertFalse(exact.truncated)
        val clipped = ByteArrayInputStream(bytes).use { readOwnerBounded(it, 3) }
        assertEquals(3, clipped.bytes.size); assertTrue(clipped.truncated)
        val zero = ByteArrayInputStream(bytes).use { readOwnerBounded(it, 0) }
        assertTrue(zero.bytes.isEmpty()); assertTrue(zero.truncated)
    }

    @Test fun byteReaderHonorsInterruptedJob() {
        Thread.currentThread().interrupt()
        try {
            try { readOwnerBounded(ByteArrayInputStream(byteArrayOf(1, 2)), 2); fail("Cancelled read proceeded") }
            catch (_: java.util.concurrent.CancellationException) { }
        } finally { Thread.interrupted() }
    }

    private fun archive(members: List<Pair<String, String>>): java.io.File {
        val file = Files.createTempFile("aurora-archive-real", ".zip").toFile()
        ZipOutputStream(file.outputStream()).use { zip ->
            for ((name, text) in members) { zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray()); zip.closeEntry() }
        }
        return file
    }

    @Test fun zipReadsRealTextWithoutExecutingOrWritingUnsafePaths() {
        val file = archive(listOf("lesson.txt" to "Genuine knowledge", "../escape.txt" to "Forbidden", "C:/escape.txt" to "Forbidden", "binary.txt" to "\u0000binary"))
        try {
            val result = readArchiveText(file, FileAnalysisLimits(listingChars=0), setOf("txt"))
            assertTrue(result.text.contains("Genuine knowledge")); assertFalse(result.text.contains("Forbidden"))
            assertEquals(1, result.metadata["text_entries_extracted"])
            assertEquals(2, result.metadata["unsafe_entries"])
            assertFalse(file.parentFile.resolve("escape.txt").exists())
        } finally { file.delete() }
    }

    @Test fun zipContentAboveOldTextCeilingAndTinyHeaderBudgetAreReal() {
        val file = archive(listOf("lesson.txt" to "x".repeat(180001)))
        try {
            val result = readArchiveText(file, FileAnalysisLimits(outputChars=200001, listingChars=0), setOf("txt"))
            assertTrue(result.text.length > 160000); assertFalse(result.metadata["content_truncated"] as Boolean)
            val tiny = readArchiveText(file, FileAnalysisLimits(outputChars=5, listingChars=0), setOf("txt"))
            assertTrue(tiny.text.isEmpty()); assertEquals(0, tiny.metadata["text_entries_extracted"])
            assertTrue(tiny.truncated)
        } finally { file.delete() }
    }

    @Test fun entryOverflowAndExpandedBudgetCannotPretendSuccessfulExtraction() {
        val file = archive(listOf("one.txt" to "one", "two.txt" to "two"))
        try {
            val exact = readArchiveText(file, FileAnalysisLimits(archiveEntries=2, listingChars=0), setOf("txt"))
            assertFalse(exact.metadata["entries_truncated"] as Boolean)
            val clipped = readArchiveText(file, FileAnalysisLimits(archiveEntries=1, listingChars=0), setOf("txt"))
            assertTrue(clipped.metadata["entries_truncated"] as Boolean)
            val blocked = readArchiveText(file, FileAnalysisLimits(expandedBytes=1), setOf("txt"))
            assertTrue(blocked.metadata["extraction_blocked"] as Boolean)
            assertEquals(0, blocked.metadata["text_entries_extracted"])
        } finally { file.delete() }
    }

    @Test fun pageHeaderCannotConsumeBudgetAndPretendToBeExtractedText() {
        val out = StringBuilder()
        assertFalse(appendOwnerPage(out, 1, "actual", 3)); assertTrue(out.isEmpty())
        val full = StringBuilder(); assertTrue(appendOwnerPage(full, 1, "actual", 1000))
        val exact = StringBuilder(); assertTrue(appendOwnerPage(exact, 1, "actual", full.length)); assertEquals(full.toString(), exact.toString())
        val clipped = StringBuilder(); assertFalse(appendOwnerPage(clipped, 1, "actual", full.length-1)); assertEquals(full.length-1, clipped.length)
    }

    @Test fun encodedXmlDeclarationsCannotEnableExternalAccess() {
        for (encoding in listOf(Charsets.UTF_8, Charsets.UTF_16LE, Charsets.UTF_16BE)) {
            val xml = "<!DOCTYPE foo [<!ENTITY x SYSTEM \"file:///private\">]><foo>&x;</foo>".toByteArray(encoding)
            try { rejectExternalXmlDeclarations(xml); fail("Unsafe XML accepted") } catch (_: IllegalArgumentException) { }
        }
        rejectExternalXmlDeclarations("<document>actual local text</document>".toByteArray())
    }

    @Test fun renderGeometryHonorsOwnerPixelsAndRejectsInvalidDimensions() {
        val scale = ownerPdfRenderScale(10000.0, 10000.0, 1000000)
        assertTrue(10000.0*10000.0*scale*scale <= 1000000.0*1.01)
        val raised = ownerPdfRenderScale(10000.0, 10000.0, 16000000)
        assertTrue(raised > scale)
        try { ownerPdfRenderScale(Double.NaN, 100.0, 1000000); fail("Invalid page accepted") } catch (_: IllegalArgumentException) { }
    }
}
