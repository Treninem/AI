package com.aurorafox.runtime

import java.io.File
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.util.concurrent.CancellationException
import com.github.junrar.Archive
import com.github.junrar.ArchiveOptions
import com.github.junrar.UnrarCallback
import com.github.junrar.volume.FileVolume
import com.github.junrar.volume.Volume
import com.github.junrar.volume.VolumeManager
import com.github.junrar.io.SeekableReadOnlyByteChannel

/** No adjacent volume lookup, no process/disk extraction, no executable authority. */
internal fun readRarText(file: File, limits: FileAnalysisLimits, extensions: Set<String>): ArchiveTextResult {
    fun checkCancelled() { if (Thread.currentThread().isInterrupted) throw CancellationException("RAR read cancelled") }
    checkCancelled(); preflightRarHeaders(file, limits)
    val callback = object : UnrarCallback {
        override fun isNextVolumeReady(next: Volume): Boolean = false
        override fun volumeProgressChanged(current: Long, total: Long) = checkCancelled()
    }
    val manager = object : VolumeManager {
        override fun nextVolume(archive: Archive, previous: Volume?): Volume? {
            checkCancelled(); if (previous != null) return null
            val original = FileVolume(archive, file)
            return object : Volume {
                override fun getArchive(): Archive = archive
                override fun getLength(): Long = file.length()
                override fun getChannel(): SeekableReadOnlyByteChannel {
                    val channel = original.channel
                    return object : SeekableReadOnlyByteChannel {
                        override fun getPosition(): Long { checkCancelled(); return channel.position }
                        override fun setPosition(value: Long) { checkCancelled(); channel.position = value }
                        override fun read(): Int { checkCancelled(); return channel.read() }
                        override fun read(buffer: ByteArray, offset: Int, count: Int): Int { checkCancelled(); return channel.read(buffer,offset,count) }
                        override fun readFully(buffer: ByteArray, count: Int): Int { checkCancelled(); return channel.readFully(buffer,count) }
                        override fun close() = channel.close()
                    }
                }
            }
        }
    }
    Archive(manager, ArchiveOptions.builder().maxDictionarySize(limits.expandedBytes).unrarCallback(callback).build()).use { archive ->
        checkCancelled(); require(!archive.isPasswordProtected) { "Encrypted RAR requires owner decryption outside this reader" }
        val entries = archive.fileHeaders
        require(entries.size <= limits.archiveEntries) { "RAR entries exceed owner budget" }
        var expanded = 0L
        for (entry in entries) {
            require(!entry.isSplitBefore && !entry.isSplitAfter && !entry.isUnpSizeUnknown && entry.fullUnpackSize >= 0) { "Unsupported split/unknown-size RAR member" }
            if (!entry.isDirectory) expanded = if (Long.MAX_VALUE-expanded < entry.fullUnpackSize) Long.MAX_VALUE else expanded+entry.fullUnpackSize
        }
        val blocked = expanded > limits.expandedBytes
        val warnings = mutableListOf<String>()
        var partial = blocked
        val out = StringBuilder(); val listing = StringBuilder()
        val listingBudget = minOf(limits.listingChars.toLong(), limits.outputChars.toLong()*limits.listingPercent/100).toInt()
        var bytesRead = 0L; var extractedBytes = 0L; var extracted = 0; var unsafe = 0
        for (entry in entries) {
            checkCancelled()
            val name = entry.fileName
            val bad = isUnsafeArchivePath(name) || entry.redirection != null || ((entry.fileAttr ushr 12) and 15) == 10
            if (bad) unsafe++
            if (listingBudget > 0) {
                val line = "$name (${entry.fullUnpackSize} B)${if (bad) " [UNSAFE]" else ""}\n"
                val left = listingBudget-listing.length; listing.append(line.take(left.coerceAtLeast(0)))
                if (line.length > left) partial = true
            }
            if (blocked || bad || entry.isDirectory || File(name).extension.lowercase() !in extensions) continue
            val cap = minOf(limits.memberBytes, limits.totalTextBytes-bytesRead)
            if (cap <= 0 || entry.fullUnpackSize > cap) { partial = true; continue }
            val bytes = ByteArrayOutputStream()
            val bounded = object : OutputStream() {
                override fun write(value: Int) { checkCancelled(); require(bytes.size().toLong() < cap) { "RAR actual member exceeds owner byte budget" }; bytes.write(value) }
                override fun write(buffer: ByteArray, offset: Int, count: Int) {
                    checkCancelled(); require(count.toLong() <= cap-bytes.size()) { "RAR actual member exceeds owner byte budget" }; bytes.write(buffer,offset,count)
                }
            }
            try { archive.extractFile(entry, bounded) } catch (failure: Exception) { checkCancelled(); throw failure }
            val raw = bytes.toByteArray(); bytesRead += raw.size
            require(raw.size.toLong() == entry.fullUnpackSize) { "RAR actual member size mismatch" }
            val text = decodeReadableArchiveText(raw) ?: continue
            if (text.isEmpty()) continue
            val header = "${if (out.isNotEmpty()) "\n\n" else ""}### Извлечённый файл: $name\n"
            val left = limits.outputChars-out.length-header.length
            if (left <= 0) { partial = true; break }
            out.append(header).append(text.take(left)); extracted++; extractedBytes += raw.size
            if (text.length > left) { partial = true; break }
        }
        val listBlock = if (listing.isEmpty()) "" else "### Состав архива\n$listing"
        val source = out.toString()+(if (out.isNotEmpty() && listBlock.isNotEmpty()) "\n\n" else "")+listBlock
        partial = partial || source.length > limits.outputChars
        if (partial) warnings.add("RAR extraction is partial/blocked; increase owner budgets and repeat reading")
        return ArchiveTextResult(source.take(limits.outputChars), mapOf("entries" to entries.size,
            "expanded_bytes" to expanded, "unsafe_entries" to unsafe, "text_entries_extracted" to extracted,
            "text_bytes_read" to bytesRead, "text_bytes_extracted" to extractedBytes, "extraction_blocked" to blocked,
            "output_truncated" to partial, "untrusted_document" to true, "content_authority" to "data_only",
            "external_ai_required" to false), warnings, partial)
    }
}
