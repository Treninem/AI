package com.aurorafox.runtime

import java.io.File
import java.nio.file.Files
import java.util.concurrent.CancellationException
import org.apache.commons.compress.archivers.sevenz.SevenZArchiveEntry
import org.apache.commons.compress.archivers.sevenz.SevenZMethod
import org.apache.commons.compress.archivers.sevenz.SevenZOutputFile
import org.junit.Assert.*
import org.junit.Test

class SevenZTextReaderTest {
    private fun archive(method: SevenZMethod = SevenZMethod.LZMA2,
        members: List<Pair<String, String>> = listOf("lesson.txt" to "Real local knowledge — знания", "../escape.txt" to "Forbidden", "binary.txt" to "\u0000binary")): File {
        val file = Files.createTempFile("aurora-native", ".7z").toFile()
        SevenZOutputFile(file).use { output ->
            output.setContentCompression(method)
            for ((name, text) in members) {
                val entry = SevenZArchiveEntry(); entry.name = name
                output.putArchiveEntry(entry); output.write(text.toByteArray()); output.closeArchiveEntry()
            }
        }
        return file
    }
    @Test fun copyAndLzma2ReadRealPayloadWithoutUnsafeOrBinaryKnowledge() {
        for (method in listOf(SevenZMethod.COPY, SevenZMethod.LZMA2)) {
            val file = archive(method)
            try {
                val result = readSevenZText(file, FileAnalysisLimits(listingChars=0), setOf("txt"))
                assertTrue(result.text.contains("знания")); assertFalse(result.text.contains("Forbidden"))
                assertFalse(result.truncated); assertEquals(1, result.metadata["text_entries_extracted"])
                assertEquals(1, result.metadata["unsafe_entries"])
                assertFalse(file.parentFile.resolve("escape.txt").exists())
            } finally { file.delete() }
        }
    }
    @Test fun ownerOutputAboveOldCeilingAndTinyHeaderAreReal() {
        val file = archive(members=listOf("lesson.txt" to "x".repeat(180001)))
        try {
            val full = readSevenZText(file, FileAnalysisLimits(outputChars=200001, listingChars=0), setOf("txt"))
            assertTrue(full.text.length > 160000); assertFalse(full.truncated)
            val tiny = readSevenZText(file, FileAnalysisLimits(outputChars=2, listingChars=0), setOf("txt"))
            assertTrue(tiny.text.isEmpty()); assertTrue(tiny.truncated); assertEquals(0, tiny.metadata["text_entries_extracted"])
        } finally { file.delete() }
    }
    @Test fun exactEntryBudgetAndActualOverflowAreDifferent() {
        val file = archive(members=listOf("one.txt" to "one", "two.txt" to "two"))
        try {
            val exact = readSevenZText(file, FileAnalysisLimits(archiveEntries=2, listingChars=0), setOf("txt"))
            assertFalse(exact.truncated); assertEquals(2, exact.metadata["text_entries_extracted"])
            val extra = readSevenZText(file, FileAnalysisLimits(archiveEntries=1, listingChars=0), setOf("txt"))
            assertTrue(extra.truncated); assertTrue(extra.metadata["entries_truncated"] as Boolean)
            val member = readSevenZText(file, FileAnalysisLimits(memberBytes=1, listingChars=0), setOf("txt"))
            assertTrue(member.truncated); assertEquals(0, member.metadata["text_entries_extracted"])
        } finally { file.delete() }
    }
    @Test fun headerDictionaryAndInputLimitsRejectBeforeUnboundedRead() {
        val file = archive()
        try {
            for (limits in listOf(FileAnalysisLimits(expandedBytes=1), FileAnalysisLimits(expandedBytes=1024), FileAnalysisLimits(fileBytes=1))) {
                try { readSevenZText(file, limits, setOf("txt")); fail("Too small owner budget accepted") }
                catch (_: Exception) { }
            }
        } finally { file.delete() }
    }
    @Test fun interruptionStopsBeforeArchiveOpen() {
        val file = archive()
        Thread.currentThread().interrupt()
        try {
            try { readSevenZText(file, FileAnalysisLimits(), setOf("txt")); fail("Cancelled job proceeded") }
            catch (_: CancellationException) { }
        } finally { Thread.interrupted(); file.delete() }
    }
    @Test fun declaredEncodedHeaderExpansionIsRejectedBeforeLibraryAllocation() {
        val file = Files.createTempFile("aurora-hostile-header", ".7z").toFile()
        try {
            // Encoded header, one COPY coder, declared header expansion65536.
            val next = byteArrayOf(0x17,0x06,0,1,0x09,0,0,0x07,0x0B,1,0,1,1,0,0x0C,0xC1.toByte(),0,0)
            val header = java.nio.ByteBuffer.allocate(32+next.size).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            header.put(byteArrayOf(0x37,0x7A,0xBC.toByte(),0xAF.toByte(),0x27,0x1C)); header.put(0); header.put(4)
            header.putInt(0); header.putLong(0); header.putLong(next.size.toLong()); header.putInt(0); header.put(next)
            file.writeBytes(header.array())
            try { readSevenZText(file,FileAnalysisLimits(expandedBytes=1024),setOf("txt")); fail("Decoded header budget ignored") }
            catch (expected: IllegalArgumentException) { assertTrue(expected.message!!.contains("Decoded 7z header")) }
        } finally { file.delete() }
    }

    @Test fun actualCopyEncodedHeaderAndItsOwnerExpansionBudgetAreValidated() {
        val file = archive(SevenZMethod.COPY,members=listOf("lesson.txt" to "Actual encoded-header knowledge"))
        try {
            val original = file.readBytes()
            val header = java.nio.ByteBuffer.wrap(original).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            val oldOffset = header.getLong(12); val oldSize = header.getLong(20)
            val encoded = java.io.ByteArrayOutputStream()
            fun number(value: Long) {
                for (i in 0..7) if (value < (1L shl (7*(i+1)))) {
                    val prefix = (255 shl (8-i)) and 255
                    encoded.write(prefix or (value ushr (8*i)).toInt())
                    repeat(i) { encoded.write((value ushr (8*it)).toInt() and 255) }; return
                }
                throw IllegalArgumentException("Fixture integer outside supported range")
            }
            encoded.write(0x17); encoded.write(6); number(oldOffset); number(1); encoded.write(9); number(oldSize)
            encoded.write(byteArrayOf(0,7,0x0B,1,0,1,1,0,0x0C)); number(oldSize); encoded.write(byteArrayOf(0,0))
            val bytes = encoded.toByteArray(); val rebuilt = original+bytes
            val updated = java.nio.ByteBuffer.wrap(rebuilt).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            updated.putLong(12,oldOffset+oldSize); updated.putLong(20,bytes.size.toLong())
            val crc = java.util.zip.CRC32(); crc.update(bytes); updated.putInt(28,crc.value.toInt())
            crc.reset(); crc.update(rebuilt,12,20); updated.putInt(8,crc.value.toInt())
            file.writeBytes(rebuilt)
            val result = readSevenZText(file,FileAnalysisLimits(listingChars=0),setOf("txt"))
            assertTrue(result.text.contains("Actual encoded-header knowledge")); assertFalse(result.truncated)
        } finally { file.delete() }
    }

}
