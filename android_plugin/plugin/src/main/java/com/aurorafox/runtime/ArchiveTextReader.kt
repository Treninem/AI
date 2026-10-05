package com.aurorafox.runtime

import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.zip.ZipFile

internal data class ArchiveTextResult(val text: String, val metadata: Map<String, Any>, val warnings: List<String>, val truncated: Boolean)

/** Reads data in memory only: archive paths never become filesystem destinations. */
internal fun readArchiveText(file: File, limits: FileAnalysisLimits, textExtensions: Set<String>): ArchiveTextResult {
    ZipFile(file).use { zip ->
        val iterator = zip.entries()
        val entries = mutableListOf<java.util.zip.ZipEntry>()
        var entryOverflow = false
        var expanded = 0L
        while (iterator.hasMoreElements()) {
            val entry = iterator.nextElement()
            if (entries.size >= limits.archiveEntries) { entryOverflow = true; break }
            entries.add(entry)
            if (!entry.isDirectory) {
                val size = entry.size.coerceAtLeast(0)
                expanded = if (Long.MAX_VALUE - expanded < size) Long.MAX_VALUE else expanded + size
            }
        }
        val warnings = mutableListOf<String>()
        val blocked = expanded > limits.expandedBytes
        if (blocked) warnings.add("Archive exceeds owner expanded-byte budget; extraction blocked")
        if (entryOverflow) warnings.add("Archive entry list is partial; raise owner entry budget")
        val listingBudget = minOf(limits.listingChars.toLong(), limits.outputChars.toLong() * limits.listingPercent / 100).toInt()
        val listing = StringBuilder()
        var listingTruncated = entryOverflow
        for (entry in entries) {
            val line = "${if (entry.isDirectory) "[DIR] " else ""}${entry.name} (${entry.size} B)${if (isUnsafeArchivePath(entry.name)) " [UNSAFE]" else ""}\n"
            val left = listingBudget - listing.length
            if (line.length > left) { if (left > 0) listing.append(line, 0, left); listingTruncated = true; break }
            listing.append(line)
        }
        val out = StringBuilder()
        if (listing.isNotEmpty()) out.append(("### Состав архива\n" + listing).take(limits.outputChars))
        var contentTruncated = false
        var bytesRead = 0L
        var textEntries = 0
        var extractedBytes = 0L
        if (!blocked) for (entry in entries) {
            if (Thread.currentThread().isInterrupted) throw java.util.concurrent.CancellationException("Archive read cancelled")
            if (entry.isDirectory || isUnsafeArchivePath(entry.name) || File(entry.name).extension.lowercase() !in textExtensions) continue
            val remainingBytes = limits.totalTextBytes - bytesRead
            if (remainingBytes <= 0) { contentTruncated = true; break }
            val cap = minOf(limits.memberBytes, remainingBytes)
            if (entry.size > cap) { contentTruncated = true; warnings.add("Member ${entry.name} exceeds owner text-byte budget"); continue }
            val raw = zip.getInputStream(entry).use { readOwnerBounded(it, cap) }
            if (raw.truncated) { contentTruncated = true; warnings.add("Member ${entry.name} exceeds actual byte budget"); continue }
            bytesRead += raw.bytes.size
            val text = decodeReadableArchiveText(raw.bytes)
            if (text == null) { warnings.add("Member ${entry.name} is binary; not imported"); continue }
            if (text.isEmpty()) continue
            val header = "${if (out.isNotEmpty()) "\n\n" else ""}### Извлечённый файл: ${entry.name}\n"
            val left = limits.outputChars - out.length - header.length
            if (left <= 0) { contentTruncated = true; break }
            out.append(header).append(text.take(left))
            textEntries++
            extractedBytes += raw.bytes.size
            if (text.length > left) contentTruncated = true
        }
        if (contentTruncated) warnings.add("Archive text is partial; increase owner budgets and repeat reading")
        val metadata = mapOf<String, Any>("entries" to entries.size, "entries_truncated" to entryOverflow,
            "expanded_bytes" to expanded, "unsafe_entries" to entries.count { isUnsafeArchivePath(it.name) },
            "text_entries_extracted" to textEntries, "text_bytes_extracted" to extractedBytes, "text_bytes_read" to bytesRead, "extraction_blocked" to blocked,
            "listing_budget" to listingBudget, "listing_truncated" to listingTruncated, "content_truncated" to contentTruncated,
            "output_truncated" to (entryOverflow || listingTruncated || contentTruncated),
            "untrusted_document" to true, "content_authority" to "data_only", "external_ai_required" to false)
        return ArchiveTextResult(out.toString(), metadata, warnings, entryOverflow || listingTruncated || contentTruncated)
    }
}

internal fun isUnsafeArchivePath(name: String): Boolean {
    val path = name.replace('\\', '/')
    return path.startsWith('/') || (path.length >= 2 && path[1] == ':') || path.split('/').any { it == ".." }
}

internal fun decodeReadableArchiveText(bytes: ByteArray): String? {
    val decoded = try {
        Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
    } catch (_: java.nio.charset.CharacterCodingException) { String(bytes, charset("windows-1251")) }
    val text = decoded.trim()
    if (text.isEmpty()) return ""
    if (text.contains('\u0000') || text.count { it.isISOControl() && it !in "\n\r\t" }.toDouble() / text.length > 0.15) return null
    return text
}
