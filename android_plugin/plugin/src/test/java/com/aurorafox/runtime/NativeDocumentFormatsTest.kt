package com.aurorafox.runtime

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import java.util.zip.GZIPOutputStream
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveOutputStream

class NativeDocumentFormatsTest {
    private fun epub(href: String = "second.xhtml"): File {
        val file = Files.createTempFile("aurora-epub", ".epub").toFile()
        val members = linkedMapOf(
            "META-INF/container.xml" to "<container xmlns='urn:oasis:names:tc:opendocument:xmlns:container'><rootfiles><rootfile full-path='OPS/book.opf'/></rootfiles></container>",
            "OPS/book.opf" to "<package xmlns='http://www.idpf.org/2007/opf'><metadata xmlns:dc='http://purl.org/dc/elements/1.1/'><dc:title>Real Book</dc:title><dc:creator>Author</dc:creator></metadata><manifest><item id='one' href='first.xhtml'/><item id='two' href='$href'/></manifest><spine><itemref idref='two'/><itemref idref='one'/></spine></package>",
            "OPS/first.xhtml" to "<html xmlns='http://www.w3.org/1999/xhtml'><head><title>Hidden</title></head><body><p>First chapter</p><script>Forbidden</script></body></html>",
            "OPS/second.xhtml" to "<html xmlns='http://www.w3.org/1999/xhtml'><body><p>Second chapter — знания</p></body></html>"
        )
        ZipOutputStream(file.outputStream()).use { zip ->
            members.forEach { (name, text) -> zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray()); zip.closeEntry() }
        }
        return file
    }
    private fun rejects(action: () -> Unit) {
        try { action(); fail("Unsafe or incomplete document was accepted") } catch (_: IllegalArgumentException) { }
    }
    @Test fun epubReadsRealSpineOrderAndMetadataWithoutActiveContent() {
        val file = epub()
        try {
            val result = readEpubText(file, FileAnalysisLimits())
            assertTrue(result.text.indexOf("Second chapter") < result.text.indexOf("First chapter"))
            assertTrue(result.text.contains("знания")); assertFalse(result.text.contains("Forbidden")); assertFalse(result.text.contains("Hidden"))
            assertEquals("Real Book", result.metadata["title"]); assertEquals(2, result.metadata["chapters_read"])
            assertFalse(result.truncated)
        } finally { file.delete() }
    }
    @Test fun epubRejectsExternalRootEscapingAndEmptySpineReferences() {
        for (href in listOf("https://example.com/book.xhtml", "../../outside.xhtml", "", "%2Foutside.xhtml")) {
            val file = epub(href)
            try { rejects { readEpubText(file, FileAnalysisLimits()) } } finally { file.delete() }
        }
    }
    @Test fun epubHonorsOutputEntryAndMemberBudgets() {
        val file = epub()
        try {
            val clipped = readEpubText(file, FileAnalysisLimits(outputChars=6))
            assertEquals("Second", clipped.text); assertTrue(clipped.truncated)
            rejects { readEpubText(file, FileAnalysisLimits(archiveEntries=3)) }
            rejects { readEpubText(file, FileAnalysisLimits(memberBytes=3)) }
        } finally { file.delete() }
    }
    private fun tar(gzip: Boolean = false, members: List<Pair<String, String>> = listOf("lesson.txt" to "Actual knowledge", "../escape.txt" to "Forbidden")): File {
        val file = Files.createTempFile("aurora-tar", if (gzip) ".tar.gz" else ".tar").toFile()
        val stream = file.outputStream().let { if (gzip) GZIPOutputStream(it) else it }
        TarArchiveOutputStream(stream).use { tar ->
            members.forEach { (name, text) ->
                val bytes = text.toByteArray(); val entry = TarArchiveEntry(name); entry.size = bytes.size.toLong()
                tar.putArchiveEntry(entry); tar.write(bytes); tar.closeArchiveEntry()
            }
        }
        return file
    }
    @Test fun tarAndGzipExtractPayloadAndSkipUnsafeMembersWithoutFilesystemWrites() {
        for (gzip in listOf(false, true)) {
            val file = tar(gzip)
            try {
                val result = readTarText(file, FileAnalysisLimits(listingChars=0), setOf("txt"))
                assertTrue(result.text.contains("Actual knowledge")); assertFalse(result.text.contains("Forbidden"))
                assertEquals(1, result.metadata["unsafe_entries"]); assertEquals(1, result.metadata["text_entries_extracted"])
                assertFalse(result.truncated)
                assertFalse(file.parentFile.resolve("escape.txt").exists())
            } finally { file.delete() }
        }
    }
    @Test fun tarExactEntryBudgetDoesNotLosePayloadAndOverflowIsExplicit() {
        val file = tar(members=listOf("one.txt" to "one", "two.txt" to "two"))
        try {
            val full = readTarText(file, FileAnalysisLimits(archiveEntries=2, listingChars=0), setOf("txt"))
            assertEquals(2, full.metadata["text_entries_extracted"])
            assertFalse(full.truncated)
            val partial = readTarText(file, FileAnalysisLimits(archiveEntries=1, listingChars=0), setOf("txt"))
            assertEquals(1, partial.metadata["text_entries_extracted"]); assertTrue(partial.truncated)
            val blocked = readTarText(file, FileAnalysisLimits(expandedBytes=1), setOf("txt"))
            assertEquals(0, blocked.metadata["text_entries_extracted"]); assertTrue(blocked.metadata["extraction_blocked"] as Boolean)
        } finally { file.delete() }
    }
    @Test fun tarHeaderCannotPretendToBeContentAndMemberByteBudgetIsHonored() {
        val file = tar(members=listOf("one.txt" to "Actual knowledge"))
        try {
            val tiny = readTarText(file, FileAnalysisLimits(outputChars=2, listingChars=0), setOf("txt"))
            assertTrue(tiny.text.isEmpty()); assertEquals(0, tiny.metadata["text_entries_extracted"])
            val capped = readTarText(file, FileAnalysisLimits(memberBytes=1, listingChars=0), setOf("txt"))
            assertEquals(0, capped.metadata["text_entries_extracted"]); assertTrue(capped.truncated)
        } finally { file.delete() }
    }

    @Test fun tarHiddenListingPercentIsCompleteButPositiveOverflowIsPartial() {
        val file = tar(members=listOf("lesson.txt" to "Actual knowledge"))
        try {
            val hidden = readTarText(file, FileAnalysisLimits(listingPercent=0), setOf("txt"))
            assertFalse(hidden.truncated); assertTrue(hidden.text.contains("Actual knowledge"))
            val partial = readTarText(file, FileAnalysisLimits(listingChars=1), setOf("txt"))
            assertTrue(partial.truncated)
        } finally { file.delete() }
    }
}
