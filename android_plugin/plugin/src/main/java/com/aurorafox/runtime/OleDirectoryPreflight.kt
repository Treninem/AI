package com.aurorafox.runtime

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CancellationException

/** CFB FAT/directory preflight before POIFS builds a recursive property graph. */
internal fun preflightOleDirectory(file: File, limits: FileAnalysisLimits) {
    require(file.length() <= minOf(limits.fileBytes, limits.xlsFileBytes)) { "XLS input exceeds owner byte budget" }
    RandomAccessFile(file, "r").use { input ->
        fun cancelled() { if (Thread.currentThread().isInterrupted) throw CancellationException("XLS directory read cancelled") }
        val header = ByteArray(512); input.readFully(header)
        require(header.take(8).toByteArray().contentEquals(byteArrayOf(0xD0.toByte(),0xCF.toByte(),0x11,0xE0.toByte(),0xA1.toByte(),0xB1.toByte(),0x1A,0xE1.toByte()))) { "Invalid OLE signature" }
        val h = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
        val version = h.getShort(26).toInt(); val shift = h.getShort(30).toInt()
        require(h.getShort(28).toInt() and 65535 == 65534 && h.getShort(32).toInt() == 6 && ((version == 3 && shift == 9) || (version == 4 && shift == 12))) { "Unsupported OLE sector format" }
        val sectorSize = 1 shl shift
        val sectors = file.length()/sectorSize-1
        require(sectors > 0 && sectors <= Int.MAX_VALUE && file.length()%sectorSize == 0L) { "Invalid OLE file sectors" }
        fun sector(id: Int): ByteBuffer {
            cancelled(); require(id >= 0 && id.toLong() < sectors) { "OLE sector outside file" }
            val bytes = ByteArray(sectorSize); input.seek((id.toLong()+1)*sectorSize); input.readFully(bytes)
            return ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        }
        val fatCount = h.getInt(44); val difatCount = h.getInt(72)
        require(fatCount > 0 && fatCount.toLong() <= sectors && difatCount >= 0 && difatCount.toLong() <= sectors) { "Invalid OLE FAT size" }
        val fatIds = mutableListOf<Int>(); val unique = mutableSetOf<Int>()
        fun add(id: Int) {
            if (id == -1) return
            require(id >= 0 && id.toLong() < sectors && fatIds.size < fatCount && unique.add(id)) { "Invalid/duplicate OLE FAT sector" }
            fatIds.add(id)
        }
        for (i in 0 until 109) add(h.getInt(76+i*4))
        var difat = h.getInt(68); val seenDifat = mutableSetOf<Int>()
        repeat(difatCount) {
            require(seenDifat.add(difat) && difat !in unique) { "OLE DIFAT cycle/overlap" }
            val data = sector(difat)
            for (i in 0 until sectorSize/4-1) add(data.getInt(i*4))
            difat = data.getInt(sectorSize-4)
        }
        require(fatIds.size == fatCount && (difatCount == 0 || difat == -2)) { "Incomplete OLE FAT" }
        // Keep only FAT sector IDs; random next-link lookup avoids a second full
        // FAT allocation. A single sector cache bounds temporary read memory.
        var cachedId = -1; var cached: ByteBuffer? = null
        fun next(id: Int): Int {
            require(id >= 0 && id.toLong() < sectors); val table = id/(sectorSize/4)
            require(table < fatIds.size) { "OLE FAT does not cover sector" }
            if (cachedId != table) { cached = sector(fatIds[table]); cachedId = table }
            return cached!!.getInt((id%(sectorSize/4))*4)
        }
        data class Property(val kind: Int, val left: Int, val right: Int, val child: Int)
        val properties = mutableListOf<Property>(); val seen = mutableSetOf<Int>()
        var directory = h.getInt(48)
        while (directory != -2) {
            require(seen.add(directory) && directory !in unique && directory !in seenDifat) { "OLE directory cycle/overlap" }
            val data = sector(directory)
            for (offset in 0 until sectorSize step 128) {
                require(properties.size < limits.xlsDirectoryEntries) { "XLS directory table exceeds owner budget" }
                val kind = data.get(offset+66).toInt() and 255
                require(kind in setOf(0,1,2,5)) { "Unsupported OLE property kind" }
                if (kind != 0) {
                    val nameBytes = data.getShort(offset+64).toInt() and 65535
                    require(nameBytes in 2..64 && nameBytes%2 == 0) { "Invalid OLE property name" }
                    val size = if (version == 3) data.getInt(offset+120).toLong() and 0xFFFFFFFFL else data.getLong(offset+120)
                    require(size >= 0 && size <= limits.xlsFileBytes) { "OLE stream exceeds owner XLS budget" }
                }
                properties.add(Property(kind,data.getInt(offset+68),data.getInt(offset+72),data.getInt(offset+76)))
            }
            directory = next(directory)
        }
        require(properties.isNotEmpty() && properties[0].kind == 5) { "OLE root missing" }
        val parents = IntArray(properties.size)
        for (p in properties) if (p.kind != 0) for (id in listOf(p.left,p.right,if (p.kind in setOf(1,5)) p.child else -1)) {
            require(id == -1 || id in properties.indices) { "OLE property link outside table" }
            if (id != -1) require(++parents[id] == 1 && properties[id].kind != 0) { "OLE shared/empty property link" }
        }
        data class Frame(val id: Int, val depth: Int, val exit: Boolean)
        val colors = ByteArray(properties.size)
        for (root in properties.indices) if (properties[root].kind != 0 && colors[root] == 0.toByte()) {
            val stack = java.util.ArrayDeque<Frame>(); stack.push(Frame(root,0,false))
            while (stack.isNotEmpty()) {
                cancelled(); val current = stack.pop()
                if (current.exit) { colors[current.id] = 2; continue }
                require(colors[current.id] != 1.toByte()) { "OLE property graph cycle" }
                if (colors[current.id] == 2.toByte()) continue
                require(current.depth <= limits.xlsDirectoryDepth) { "XLS directory depth exceeds owner budget" }
                colors[current.id] = 1; stack.push(Frame(current.id,current.depth,true))
                val p = properties[current.id]
                for (id in listOf(p.left,p.right)) if (id != -1) stack.push(Frame(id,current.depth,false))
                if (p.kind in setOf(1,5) && p.child != -1) stack.push(Frame(p.child,current.depth+1,false))
            }
        }
    }
}
