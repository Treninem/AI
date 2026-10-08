package com.aurorafox.runtime

import java.io.File
import java.io.InputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.SeekableByteChannel
import java.nio.file.Files
import java.util.concurrent.CancellationException
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import org.apache.commons.compress.archivers.sevenz.SevenZMethod

/** Sequential, in-memory payload reading; entry names never become destinations. */
internal fun readSevenZText(file: File, limits: FileAnalysisLimits, extensions: Set<String>): ArchiveTextResult {
    fun checkCancelled() { if (Thread.currentThread().isInterrupted) throw CancellationException("7z read cancelled") }
    checkCancelled()
    require(file.length() <= limits.fileBytes) { "7z input exceeds owner file-byte budget" }
    // SevenZFile allocates the raw next-header buffer before checking metadata
    // estimates. Bound that buffer using actual signature-header offsets first.
    RandomAccessFile(file, "r").use { input ->
        val header = ByteArray(32); input.readFully(header)
        require(header.take(6).toByteArray().contentEquals(byteArrayOf(0x37,0x7A,0xBC.toByte(),0xAF.toByte(),0x27,0x1C))) { "Invalid 7z signature" }
        val raw = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
        val offset = raw.getLong(12); val size = raw.getLong(20)
        require(offset >= 0 && size >= 0 && offset <= file.length()-32 && size <= file.length()-32-offset) { "7z header outside file" }
        require(size <= minOf(limits.expandedBytes, Int.MAX_VALUE.toLong())) { "7z header exceeds owner metadata budget" }
        input.seek(32+offset)
        val next = ByteArray(size.toInt()); input.readFully(next)
        preflightSevenZEncodedHeader(next, limits.expandedBytes)
    }
    val memoryKiB = (limits.expandedBytes / 1024).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    require(memoryKiB > 0) { "7z metadata/decoder budget must represent at least one KiB" }
    val channel = Files.newByteChannel(file.toPath())
    val guarded = object : SeekableByteChannel {
        override fun read(dst: ByteBuffer): Int { checkCancelled(); return channel.read(dst) }
        override fun write(src: ByteBuffer): Int = throw UnsupportedOperationException("Read-only archive")
        override fun position(): Long { checkCancelled(); return channel.position() }
        override fun position(value: Long): SeekableByteChannel { checkCancelled(); channel.position(value); return this }
        override fun size(): Long { checkCancelled(); return channel.size() }
        override fun truncate(size: Long): SeekableByteChannel = throw UnsupportedOperationException("Read-only archive")
        override fun isOpen(): Boolean = channel.isOpen
        override fun close() = channel.close()
    }
    guarded.use { SevenZFile.builder().setSeekableByteChannel(it).setMaxMemoryLimitKb(memoryKiB).get().use { archive ->
        checkCancelled()
        val entries = mutableListOf<org.apache.commons.compress.archivers.sevenz.SevenZArchiveEntry>()
        var entryOverflow = false
        var expanded = 0L
        for (entry in archive.entries) {
            checkCancelled()
            if (entries.size >= limits.archiveEntries) { entryOverflow = true; break }
            require(entry.size >= 0) { "7z member has invalid size" }
            entries.add(entry)
            if (!entry.isDirectory) expanded = if (Long.MAX_VALUE-expanded < entry.size) Long.MAX_VALUE else expanded+entry.size
        }
        val blocked = expanded > limits.expandedBytes
        val warnings = mutableListOf<String>()
        if (entryOverflow) warnings.add("7z entry list is partial; raise owner entry budget")
        if (blocked) warnings.add("7z expanded-byte budget exceeded; extraction blocked")
        val listingBudget = minOf(limits.listingChars.toLong(), limits.outputChars.toLong()*limits.listingPercent/100).toInt()
        val listing = StringBuilder()
        var listingPartial = false
        if (listingBudget > 0) for (entry in entries) {
            val line = "${entry.name ?: "[unnamed]"} (${entry.size} B)\n"
            val left = listingBudget-listing.length
            listing.append(line.take(left.coerceAtLeast(0)))
            if (line.length > left) { listingPartial = true; break }
        }
        val out = StringBuilder()
        var bytesRead = 0L
        var extractedBytes = 0L
        var extracted = 0
        var unsafe = 0
        var contentPartial = false
        if (!blocked) for (expected in entries) {
            checkCancelled()
            val entry = archive.nextEntry ?: throw IllegalArgumentException("7z entry table ended unexpectedly")
            require(entry.name == expected.name && entry.size == expected.size) { "7z entry metadata changed" }
            // Other codecs lack the library's decoder-memory guard. Do not bypass it.
            require((entry.contentMethods ?: emptyList()).all { it.method in setOf(SevenZMethod.COPY, SevenZMethod.LZMA, SevenZMethod.LZMA2) }) {
                "7z codec requires a dedicated bounded decoder"
            }
            val name = entry.name
            val symlink = entry.hasWindowsAttributes && ((entry.windowsAttributes ushr 16) and 0xF000) == 0xA000
            if (name == null || isUnsafeArchivePath(name) || entry.isAntiItem || symlink) { unsafe++; continue }
            if (entry.isDirectory || File(name).extension.lowercase() !in extensions) continue
            val cap = minOf(limits.memberBytes, limits.totalTextBytes-bytesRead)
            if (cap <= 0) { contentPartial = true; break }
            if (entry.size > cap) { contentPartial = true; warnings.add("7z member exceeds owner text-byte budget"); continue }
            val input = object : InputStream() {
                override fun read(): Int { checkCancelled(); return archive.read() }
                override fun read(bytes: ByteArray, offset: Int, length: Int): Int { checkCancelled(); return archive.read(bytes, offset, length) }
            }
            val raw = readOwnerBounded(input, cap)
            bytesRead += raw.bytes.size
            require(!raw.truncated && raw.bytes.size.toLong() == entry.size) { "7z member size/integrity mismatch" }
            val text = decodeReadableArchiveText(raw.bytes) ?: continue
            if (text.isEmpty()) continue
            val header = "${if (out.isNotEmpty()) "\n\n" else ""}### Извлечённый файл: $name\n"
            val left = limits.outputChars-out.length-header.length
            if (left <= 0) { contentPartial = true; break }
            out.append(header).append(text.take(left)); extracted++; extractedBytes += raw.bytes.size
            if (text.length > left) { contentPartial = true; break }
        }
        val listBlock = if (listing.isEmpty()) "" else "### Состав архива\n$listing"
        val source = out.toString() + (if (out.isNotEmpty() && listBlock.isNotEmpty()) "\n\n" else "") + listBlock
        val partial = blocked || entryOverflow || listingPartial || contentPartial || source.length > limits.outputChars
        if (partial) warnings.add("7z extraction is partial; increase owner budgets and repeat reading")
        return ArchiveTextResult(source.take(limits.outputChars), mapOf("entries" to entries.size,
            "expanded_bytes" to expanded, "entries_truncated" to entryOverflow, "unsafe_entries" to unsafe,
            "text_entries_extracted" to extracted, "text_bytes_extracted" to extractedBytes,
            "text_bytes_read" to bytesRead, "extraction_blocked" to blocked, "listing_truncated" to listingPartial,
            "content_truncated" to contentPartial, "output_truncated" to partial,
            "untrusted_document" to true, "content_authority" to "data_only", "external_ai_required" to false), warnings, partial)
    } }
}

/** Bound the encoded header's declared expansion before the library allocates it. */
private fun preflightSevenZEncodedHeader(bytes: ByteArray, budget: Long) {
    val input = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
    fun byte(): Int { require(input.hasRemaining()) { "Truncated 7z header" }; return input.get().toInt() and 255 }
    fun number(): Long {
        val first = byte(); var mask = 128; var value = 0L
        for (i in 0..7) {
            if (first and mask == 0) return value or ((first and (mask-1)).toLong() shl (8*i))
            value = value or (byte().toLong() shl (8*i)); mask = mask ushr 1
        }
        require(value >= 0) { "7z integer exceeds signed representation" }; return value
    }
    fun skip(size: Long) { require(size >= 0 && size <= input.remaining()); input.position(input.position()+size.toInt()) }
    if (byte() != 0x17) return // Plain headers are already bounded above.
    require(byte() == 0x06) { "Unsupported encoded 7z header layout" }
    number() // packed offset is independently checked by SevenZFile against the input
    require(number() == 1L) { "Encoded 7z header requires one packed stream" }
    require(byte() == 0x09); number()
    var nid = byte()
    if (nid == 0x0A) { val all = byte(); val defined = if (all != 0) true else byte() and 128 != 0; if (defined) skip(4); nid = byte() }
    require(nid == 0 && byte() == 0x07 && byte() == 0x0B && number() == 1L && byte() == 0) {
        "Unsupported encoded 7z folder layout"
    }
    val count = number(); require(count > 0 && count <= input.remaining()/2) { "Invalid 7z header coder count" }
    for (i in 0 until count) {
        val flags = byte(); val idSize = flags and 15
        require(flags and 0xD0 == 0 && idSize in 1..8) { "Unsupported encoded 7z coder topology" }
        val id = ByteArray(idSize) { byte().toByte() }
        require(id.contentEquals(byteArrayOf(0)) || id.contentEquals(byteArrayOf(0x21)) || id.contentEquals(byteArrayOf(3,1,1))) {
            "Encoded 7z header codec has no bounded decoder"
        }
        if (flags and 0x20 != 0) skip(number())
    }
    for (i in 0 until count-1) { number(); number() } // simple coder bind pairs
    require(byte() == 0x0C) { "Missing encoded 7z unpack sizes" }
    for (i in 0 until count) require(number() <= minOf(budget, Int.MAX_VALUE.toLong())) {
        "Decoded 7z header exceeds owner metadata budget"
    }
}
