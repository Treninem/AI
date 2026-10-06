package com.aurorafox.runtime

import java.io.File
import java.io.BufferedInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CancellationException
import org.apache.poi.poifs.filesystem.POIFSFileSystem
import org.apache.poi.hssf.record.*

/** BIFF8 cached cell values only: no full workbook, formula evaluator or macros. */
internal fun readXlsText(file: File, limits: FileAnalysisLimits): ArchiveTextResult {
    fun cancelled() { if (Thread.currentThread().isInterrupted) throw CancellationException("XLS read cancelled") }
    cancelled(); preflightOleDirectory(file, limits)
    POIFSFileSystem(file, true).use { fs ->
        val name = listOf("Workbook","Book").firstOrNull { fs.root.hasEntry(it) }
            ?: throw IllegalArgumentException("XLS workbook stream missing")
        val document = fs.root.getEntry(name) as? org.apache.poi.poifs.filesystem.DocumentEntry
            ?: throw IllegalArgumentException("XLS workbook is not a document")
        require(document.size.toLong() <= limits.xlsFileBytes) { "XLS workbook stream exceeds owner budget" }
        BufferedInputStream(fs.createDocumentInputStream(name)).use { input ->
            val records = RecordInputStream(input)
            val sheets = mutableListOf<String>(); var sheetMetadata = 0
            var sheet = -1; var inWorksheet = false; var strings: SSTRecord? = null
            var pendingString: Pair<Int,Int>? = null
            var cells = 0; val rows = mutableSetOf<Int>(); val out = StringBuilder()
            var partial = false
            fun emit(row: Int, column: Int, value: String): Boolean {
                if (!inWorksheet || value.isEmpty()) return true
                if (cells >= limits.spreadsheetCells || (row !in rows && rows.size >= limits.xlsRows)) { partial = true; return false }
                val prefix = "${if (out.isNotEmpty()) "\n" else ""}[${sheets.getOrElse(sheet) { "Sheet${sheet+1}" }}!R${row+1}C${column+1}] "
                val remaining = limits.outputChars-out.length-prefix.length
                if (remaining <= 0) { partial = true; return false }
                rows.add(row); cells++; out.append(prefix).append(value.take(remaining))
                if (value.length > remaining) { partial = true; return false }
                return true
            }
            fun peek(count: Int): ByteBuffer {
                require(records.remaining() >= count) { "Truncated XLS record" }
                input.mark(count); val bytes = ByteArray(count)
                var position = 0
                while (position < count) { val n = input.read(bytes,position,count-position); require(n > 0); position += n }
                input.reset(); return ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            }
            loop@ while (records.hasNextRecord()) {
                cancelled(); records.nextRecord()
                when (records.sid.toInt() and 65535) {
                    0x0809 -> {
                        require(pendingString == null) { "XLS formula string cache missing" }
                        val bof = BOFRecord(records); require(bof.version == 0x600) { "Only BIFF8 XLS is supported" }
                        inWorksheet = bof.type == 0x10
                        if (inWorksheet) { sheet++; rows.clear(); require(sheet < limits.xlsSheets) { "XLS sheet count exceeds owner budget" } }
                    }
                    0x002F -> throw IllegalArgumentException("Encrypted XLS requires owner decryption outside this reader")
                    0x0085 -> {
                        require(++sheetMetadata <= limits.xlsSheets) { "XLS sheet metadata exceeds owner budget" }
                        val raw = peek(6); val type = raw.get(5).toInt() and 255
                        val record = BoundSheetRecord(records)
                        if (type == 0) sheets.add(record.sheetname)
                    }
                    0x00FC -> {
                        val raw = peek(8); val total = raw.getInt(0); val unique = raw.getInt(4)
                        require(total >= 0 && unique >= 0 && unique <= total && unique <= limits.xlsSharedStrings) { "XLS shared strings exceed owner budget" }
                        strings = SSTRecord(records)
                    }
                    0x00FD -> {
                        require(pendingString == null); val r = LabelSSTRecord(records)
                        val table = strings ?: throw IllegalArgumentException("XLS shared strings missing")
                        require(r.sstIndex in 0 until table.numUniqueStrings) { "Invalid XLS string index" }
                        if (!emit(r.row,r.column.toInt(),table.getString(r.sstIndex).string)) break@loop
                    }
                    0x0204 -> { require(pendingString == null); val r = LabelRecord(records); if (!emit(r.row,r.column.toInt(),r.value)) break@loop }
                    0x0203 -> { require(pendingString == null); val r = NumberRecord(records); if (!emit(r.row,r.column.toInt(),r.value.toString())) break@loop }
                    0x027E -> { require(pendingString == null); val r = RKRecord(records); if (!emit(r.row,r.column.toInt(),r.rkNumber.toString())) break@loop }
                    0x00BD -> {
                        require(pendingString == null); val r = MulRKRecord(records)
                        for (i in 0 until r.numColumns) if (!emit(r.row,r.firstColumn.toInt()+i,r.getRKNumberAt(i).toString())) break@loop
                    }
                    0x0205 -> { require(pendingString == null); val r = BoolErrRecord(records); val value = if (r.isBoolean) r.booleanValue.toString() else "#ERROR(${r.errorValue.toInt() and 255})"; if (!emit(r.row,r.column.toInt(),value)) break@loop }
                    0x0006 -> {
                        require(pendingString == null); val raw = ByteBuffer.wrap(records.readRemainder()).order(ByteOrder.LITTLE_ENDIAN)
                        require(raw.limit() >= 20) { "Truncated XLS cached formula" }
                        val row = raw.getShort(0).toInt() and 65535; val column = raw.getShort(2).toInt() and 65535
                        if (raw.getShort(12).toInt() and 65535 == 65535) {
                            when (raw.get(6).toInt() and 255) {
                                0 -> pendingString = row to column
                                1 -> if (!emit(row,column,(raw.get(8).toInt() != 0).toString())) break@loop
                                2 -> if (!emit(row,column,"#ERROR(${raw.get(8).toInt() and 255})")) break@loop
                                3 -> { } // empty cached cell
                                else -> throw IllegalArgumentException("Invalid XLS cached formula type")
                            }
                        } else if (!emit(row,column,raw.getDouble(6).toString())) break@loop
                    }
                    0x0207 -> {
                        val r = StringRecord(records); val cell = pendingString ?: throw IllegalArgumentException("Unexpected XLS formula string")
                        pendingString = null; if (!emit(cell.first,cell.second,r.string)) break@loop
                    }
                    0x000A -> { require(pendingString == null) { "XLS formula string cache missing" }; inWorksheet = false }
                }
                if (records.remaining() > 0) records.readRemainder()
            }
            require(pendingString == null) { "XLS formula string cache missing" }
            val warnings = mutableListOf("XLS BIFF8 raw cached values; formulas/macros are not executed; date/style formatting is not applied")
            if (partial) warnings.add("XLS content is partial; raise owner row/cell/text budgets and repeat reading")
            return ArchiveTextResult(out.toString(),mapOf("sheets_read" to sheet+1,"cells_read" to cells,
                "output_truncated" to partial,"cached_formulas_only" to true,"untrusted_document" to true,
                "content_authority" to "data_only","external_ai_required" to false),warnings,partial)
        }
    }
}
