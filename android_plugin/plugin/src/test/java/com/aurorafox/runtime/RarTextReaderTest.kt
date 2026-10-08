package com.aurorafox.runtime

import java.nio.file.Files
import java.util.Base64
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Test

class RarTextReaderTest {
    private fun fixture(name: String): java.io.File {
        val encoded = javaClass.getResourceAsStream("/native_archive/$name.b64")!!.bufferedReader().use { it.readText() }.trim()
        return Files.createTempFile("aurora-native-rar", ".rar").toFile().apply { writeBytes(Base64.getDecoder().decode(encoded)) }
    }
    @Test fun rar4AndRar5SolidProduceActualPayload() {
        for (name in listOf("test.rar", "solid-rar5-solid.rar")) {
            val file = fixture(name)
            try {
                val result = readRarText(file, FileAnalysisLimits(listingChars=0), setOf("txt"))
                assertTrue(result.text.isNotBlank()); assertTrue((result.metadata["text_entries_extracted"] as Int) > 0)
                assertFalse(result.truncated); assertEquals("data_only",result.metadata["content_authority"])
            } finally { file.delete() }
        }
    }
    @Test fun hostileLinksAndParentPathsAreNotImported() {
        for (name in listOf("links-rar5-links-hostile.rar", "parent-dir.rar")) {
            val file = fixture(name)
            try {
                val result = readRarText(file, FileAnalysisLimits(listingChars=0), setOf("txt"))
                assertTrue((result.metadata["unsafe_entries"] as Int) > 0)
                assertEquals(if (name.startsWith("links")) 2 else 0, result.metadata["text_entries_extracted"])
            } finally { file.delete() }
        }
    }
    @Test fun encryptedAndMetadataInputBudgetsFailHonestly() {
        val encrypted = fixture("password-rar4-encrypted-junrar.rar")
        try {
            try { readRarText(encrypted,FileAnalysisLimits(),setOf("txt")); fail("Encrypted RAR accepted") }
            catch (_: Exception) { }
        } finally { encrypted.delete() }
        val file = fixture("test.rar")
        try {
            for (limits in listOf(FileAnalysisLimits(fileBytes=1),FileAnalysisLimits(archiveEntries=1),FileAnalysisLimits(expandedBytes=1))) {
                try { readRarText(file,limits,setOf("txt")); fail("Owner limit ignored") }
                catch (_: Exception) { }
            }
            val tiny = readRarText(file,FileAnalysisLimits(outputChars=2,listingChars=0),setOf("txt"))
            assertTrue(tiny.text.isEmpty()); assertEquals(0,tiny.metadata["text_entries_extracted"]); assertTrue(tiny.truncated)
        } finally { file.delete() }
    }
    @Test fun rar5DecoderDictionaryBudgetIsApplied() {
        val file = fixture("solid-rar5-solid.rar")
        try {
            try { readRarText(file,FileAnalysisLimits(expandedBytes=1024,listingChars=0),setOf("txt")); fail("Dictionary budget ignored") }
            catch (expected: Exception) { assertTrue(expected.toString().contains("Dictionary",true) || expected.toString().contains("memory",true)) }
        } finally { file.delete() }
    }
    @Test fun cancelledJobNeverOpensArchive() {
        val file = fixture("test.rar"); Thread.currentThread().interrupt()
        try {
            try { readRarText(file,FileAnalysisLimits(),setOf("txt")); fail("Cancelled RAR accepted") }
            catch (_: CancellationException) { }
        } finally { Thread.interrupted(); file.delete() }
    }
}
