package com.aurorafox.runtime

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CancellationException

/** Bounds raw header allocations before junrar constructs its metadata objects. */
internal fun preflightRarHeaders(file: File, limits: FileAnalysisLimits) {
    require(file.length() <= limits.fileBytes) { "RAR input exceeds owner byte budget" }
    RandomAccessFile(file, "r").use { input ->
        val signature = ByteArray(7); input.readFully(signature)
        require(signature.take(6).toByteArray().contentEquals(byteArrayOf(0x52,0x61,0x72,0x21,0x1A,0x07))) { "Unsupported RAR signature/SFX" }
        val version = signature[6].toInt()
        require(version in 0..1) { "Unsupported RAR version" }
        if (version == 1) require(input.read() == 0) { "Invalid RAR5 signature" }
        var count = 0
        var headerBytes = 0L
        fun unsigned(): Long {
            var value = 0L
            for (i in 0..8) { val next = input.read(); require(next >= 0); value = value or ((next and 127).toLong() shl (7*i)); if (next and 128 == 0) return value }
            throw IllegalArgumentException("RAR integer exceeds signed representation")
        }
        while (input.filePointer < input.length()) {
            if (Thread.currentThread().isInterrupted) throw CancellationException("RAR header read cancelled")
            require(count++ < limits.archiveEntries) { "RAR metadata header count exceeds owner entry budget" }
            val start = input.filePointer
            var dataBytes: Long
            var end: Long
            if (version == 0) {
                val prefix = ByteArray(7); input.readFully(prefix)
                val data = ByteBuffer.wrap(prefix).order(ByteOrder.LITTLE_ENDIAN)
                val type = prefix[2].toInt() and 255
                val flags = data.getShort(3).toInt() and 65535
                val size = data.getShort(5).toInt() and 65535
                require(size >= 7 && size.toLong() <= minOf(limits.expandedBytes, input.length()-start)) { "RAR4 header outside owner/input budget" }
                require(type != 0x73 || flags and 0x81 == 0) { "Encrypted/multivolume RAR unsupported" }
                require(type !in setOf(0x74,0x7A) || flags and 7 == 0) { "Encrypted/split RAR member unsupported" }
                val header = ByteArray(size); prefix.copyInto(header); input.readFully(header,7,size-7)
                val raw = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
                dataBytes = if (type in setOf(0x74,0x7A) || flags and 0x8000 != 0) {
                    require(size >= 11); raw.getInt(7).toLong() and 0xFFFFFFFFL
                } else 0L
                if (type in setOf(0x74,0x7A) && flags and 0x100 != 0) {
                    require(size >= 40); val high = raw.getInt(32).toLong() and 0xFFFFFFFFL
                    require(high <= 0x7FFFFFFF); dataBytes = dataBytes or (high shl 32)
                }
                end = start+size
            } else {
                input.readInt() // CRC is validated by the library after bounded preflight.
                val size = unsigned(); val payloadStart = input.filePointer
                require(size <= minOf(limits.expandedBytes, input.length()-payloadStart, Int.MAX_VALUE.toLong())) { "RAR5 header outside owner/input budget" }
                end = payloadStart+size
                val type = unsigned(); val flags = unsigned()
                require(flags and 0x18 == 0L) { "Split RAR5 member unsupported" }
                if (flags and 1 != 0L) require(unsigned() <= size) { "RAR5 extra area outside header" }
                dataBytes = if (flags and 2 != 0L) unsigned() else 0L
                require(type != 4L) { "Encrypted RAR5 header unsupported" }
                if (type == 1L) require(unsigned() and 1 == 0L) { "Multivolume RAR5 unsupported" }
                require(input.filePointer <= end) { "RAR5 fields outside header" }
            }
            val consumed = end-start
            require(consumed > 0 && headerBytes <= limits.expandedBytes-consumed) { "RAR metadata exceeds owner byte budget" }
            headerBytes += consumed
            require(dataBytes >= 0 && end <= input.length() && dataBytes <= input.length()-end) { "RAR packed member outside input" }
            input.seek(end+dataBytes)
        }
    }
}
