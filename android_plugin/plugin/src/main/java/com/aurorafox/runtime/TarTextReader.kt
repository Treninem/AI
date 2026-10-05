package com.aurorafox.runtime

import java.io.File
import java.util.zip.GZIPInputStream
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream

/** Streaming tar/tar.gz reader; never writes archive entries to any directory. */
internal fun readTarText(file: File, limits: FileAnalysisLimits, textExtensions: Set<String>): ArchiveTextResult {
    val base = file.inputStream().buffered()
    val stream = try { if (file.name.endsWith(".gz", true) || file.extension.equals("tgz", true)) GZIPInputStream(base) else base }
        catch (t: Throwable) { base.close(); throw t }
    val headerAllowance = limits.archiveEntries.toLong()*1024L + 10240L
    val streamBudget = if (Long.MAX_VALUE-limits.expandedBytes < headerAllowance) Long.MAX_VALUE else limits.expandedBytes+headerAllowance
    val bounded = object : java.io.FilterInputStream(stream) {
        var remaining = streamBudget
        override fun read(): Int {
            if (Thread.currentThread().isInterrupted) throw java.util.concurrent.CancellationException("Tar read cancelled")
            if (remaining <= 0) throw IllegalArgumentException("Tar stream exceeds owner expanded-byte/header budget")
            return `in`.read().also { if (it >= 0) remaining-- }
        }
        override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
            if (length == 0) return 0
            if (Thread.currentThread().isInterrupted) throw java.util.concurrent.CancellationException("Tar read cancelled")
            if (remaining <= 0) throw IllegalArgumentException("Tar stream exceeds owner expanded-byte/header budget")
            return `in`.read(bytes, offset, minOf(length.toLong(), remaining).toInt()).also { if (it > 0) remaining -= it }
        }
        override fun skip(count: Long): Long {
            val scratch = ByteArray(8192)
            var skipped = 0L
            while (skipped < count) {
                val read = read(scratch, 0, minOf(scratch.size.toLong(), count-skipped).toInt())
                if (read < 0) break
                skipped += read
            }
            return skipped
        }
    }
    TarArchiveInputStream(bounded).use { tar ->
        val listing = StringBuilder()
        val content = StringBuilder()
        val warnings = mutableListOf<String>()
        val listingBudget = minOf(limits.listingChars.toLong(), limits.outputChars.toLong()*limits.listingPercent/100).toInt()
        var entries = 0
        var unsafe = 0
        var expanded = 0L
        var bytesRead = 0L
        var retainedBytes = 0L
        var textEntries = 0
        var truncated = false
        var blocked = false
        while (true) {
            if (Thread.currentThread().isInterrupted) throw java.util.concurrent.CancellationException("Tar read cancelled")
            val entry = tar.nextTarEntry ?: break
            if (entries >= limits.archiveEntries) { truncated = true; break }
            entries++
            // Sparse reconstruction may expand independently of the stored member size.
            if (entry.isSparse) throw IllegalArgumentException("Sparse tar member requires a dedicated bounded reader")
            val bad = isUnsafeArchivePath(entry.name) || entry.isSymbolicLink || entry.isLink
            if (bad) unsafe++
            if (!entry.isDirectory) {
                val size = entry.size.coerceAtLeast(0)
                expanded = if (Long.MAX_VALUE-expanded < size) Long.MAX_VALUE else expanded+size
                if (expanded > limits.expandedBytes) { blocked = true; warnings.add("Tar exceeds owner expanded-byte budget; extraction blocked"); break }
            }
            val line = "${entry.name} (${entry.size} B)${if (bad) " [UNSAFE]" else ""}\n"
            val listLeft = listingBudget-listing.length
            listing.append(line.take(listLeft.coerceAtLeast(0)))
            if (line.length > listLeft) truncated = true
            if (!entry.isFile || bad || File(entry.name).extension.lowercase() !in textExtensions) continue
            val cap = minOf(limits.memberBytes, limits.totalTextBytes-bytesRead)
            if (cap <= 0) { truncated = true; break }
            if (entry.size > cap) { truncated = true; warnings.add("Tar member ${entry.name} exceeds owner text-byte budget"); continue }
            val raw = readOwnerBounded(tar, cap)
            bytesRead += raw.bytes.size
            if (raw.truncated) { truncated = true; continue }
            val text = decodeReadableArchiveText(raw.bytes) ?: continue
            if (text.isEmpty()) continue
            val header = "${if (content.isNotEmpty()) "\n\n" else ""}### Извлечённый файл: ${entry.name}\n"
            val left = limits.outputChars-content.length-header.length
            if (left <= 0) { truncated = true; break }
            content.append(header).append(text.take(left)); textEntries++; retainedBytes += raw.bytes.size
            if (text.length > left) truncated = true
        }
        val listBlock = if (listing.isNotEmpty()) "### Состав архива\n$listing" else ""
        val source = if (blocked) listBlock else if (content.isEmpty()) listBlock else content.toString() + (if (listBlock.isNotEmpty()) "\n\n$listBlock" else "")
        if (source.length > limits.outputChars) truncated = true
        if (truncated) warnings.add("Tar extraction is partial; increase owner budgets and repeat reading")
        return ArchiveTextResult(source.take(limits.outputChars), mapOf("entries" to entries, "expanded_bytes" to expanded,
            "unsafe_entries" to unsafe, "text_entries_extracted" to if (blocked) 0 else textEntries,
            "text_bytes_read" to bytesRead, "text_bytes_extracted" to if (blocked) 0L else retainedBytes,
            "extraction_blocked" to blocked, "output_truncated" to truncated,
            "untrusted_document" to true, "content_authority" to "data_only", "external_ai_required" to false), warnings, truncated)
    }
}
