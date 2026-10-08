package com.aurorafox.runtime

import java.nio.file.Files
import java.util.concurrent.CancellationException
import org.apache.poi.hssf.usermodel.HSSFWorkbook
import org.apache.poi.poifs.filesystem.POIFSFileSystem
import org.junit.Assert.*
import org.junit.Test

class XlsTextReaderTest {
    private fun workbook(build: (HSSFWorkbook)->Unit): java.io.File {
        val file = Files.createTempFile("aurora-native-xls", ".xls").toFile()
        HSSFWorkbook().use { book -> build(book); file.outputStream().use { book.write(it) } }
        return file
    }
    @Test fun realUnicodeNumbersBooleansAndCachedFormulaAreReadWithoutEvaluation() {
        val file = workbook { book ->
            val row = book.createSheet("Знания").createRow(0)
            row.createCell(0).setCellValue("Реальные знания")
            row.createCell(1).setCellValue(12.5); row.createCell(2).setCellValue(true)
            val formula = row.createCell(3); formula.cellFormula="1+2"; formula.setCellValue(9.0)
            val text = row.createCell(4); text.cellFormula="\"computed\""; text.setCellValue("stale-cache")
        }
        try {
            val result = readXlsText(file,FileAnalysisLimits())
            for (text in listOf("Реальные знания","12.5","true","9.0","stale-cache","[Знания!R1C1]")) assertTrue(text,result.text.contains(text))
            assertFalse(result.text.contains("computed")); assertFalse(result.truncated); assertEquals(5,result.metadata["cells_read"])
        } finally { file.delete() }
    }
    @Test fun exactCellBudgetAndOverflowAcrossSheetsAreDifferent() {
        val file = workbook { book ->
            book.createSheet("First").createRow(0).createCell(0).setCellValue("One")
            book.createSheet("Second").createRow(0).createCell(0).setCellValue("Two")
        }
        try {
            assertFalse(readXlsText(file,FileAnalysisLimits(spreadsheetCells=2)).truncated)
            val partial = readXlsText(file,FileAnalysisLimits(spreadsheetCells=1))
            assertTrue(partial.truncated); assertTrue(partial.text.contains("One")); assertFalse(partial.text.contains("Two"))
            val tiny = readXlsText(file,FileAnalysisLimits(outputChars=2)); assertTrue(tiny.text.isEmpty()); assertEquals(0,tiny.metadata["cells_read"])
        } finally { file.delete() }
    }
    @Test fun sharedStringsAreBoundedBeforeParsingAndRealContinuationsWork() {
        val file = workbook { book -> val sheet = book.createSheet("Long"); repeat(6) { sheet.createRow(it).createCell(0).setCellValue("З".repeat(30000)+it) } }
        try {
            val full = readXlsText(file,FileAnalysisLimits(outputChars=200000)); assertTrue(full.text.length > 160000); assertFalse(full.truncated)
            try { readXlsText(file,FileAnalysisLimits(xlsSharedStrings=1)); fail("SST budget ignored") } catch (_: IllegalArgumentException) { }
            assertFalse(readXlsText(file,FileAnalysisLimits(xlsSharedStrings=10,outputChars=200000)).truncated)
        } finally { file.delete() }
    }
    @Test fun cellAndRowOwnerBudgetsCanExceedOldCeilings() {
        val file = workbook { book -> val sheet = book.createSheet("Large"); repeat(50001) { sheet.createRow(it).createCell(0).setCellValue(it.toDouble()) } }
        try {
            val full = readXlsText(file,FileAnalysisLimits(spreadsheetCells=50002,xlsRows=60000,outputChars=2000000)); assertEquals(50001,full.metadata["cells_read"]); assertFalse(full.truncated)
            val capped = readXlsText(file,FileAnalysisLimits(xlsRows=2)); assertEquals(2,capped.metadata["cells_read"]); assertTrue(capped.truncated)
        } finally { file.delete() }
    }
    @Test fun rawOleBudgetsAndCyclesRejectBeforePoifs() {
        val file = workbook { it.createSheet("One").createRow(0).createCell(0).setCellValue("Actual") }
        try {
            for (limits in listOf(FileAnalysisLimits(xlsFileBytes=1),FileAnalysisLimits(xlsDirectoryEntries=1))) {
                try { readXlsText(file,limits); fail("OLE budget ignored") } catch (_: IllegalArgumentException) { }
            }
            java.io.RandomAccessFile(file,"rw").use { input ->
                input.seek(48); val sector = Integer.reverseBytes(input.readInt())
                input.seek((sector.toLong()+1)*512+76); input.writeInt(0) // root child points to root
            }
            try { readXlsText(file,FileAnalysisLimits()); fail("OLE cycle accepted") } catch (_: IllegalArgumentException) { }
        } finally { file.delete() }
    }
    @Test fun raisedDirectoryDepthAcceptsActualDeepOleStructure() {
        val file = Files.createTempFile("aurora-deep-ole", ".xls").toFile()
        try {
            POIFSFileSystem().use { fs ->
                var directory = fs.root
                repeat(129) { directory = directory.createDirectory("D$it") as org.apache.poi.poifs.filesystem.DirectoryNode }
                file.outputStream().use { fs.writeFilesystem(it) }
            }
            try { preflightOleDirectory(file,FileAnalysisLimits()); fail("Depth budget ignored") } catch (_: IllegalArgumentException) { }
            preflightOleDirectory(file,FileAnalysisLimits(xlsDirectoryDepth=512))
        } finally { file.delete() }
    }
    @Test fun cancelledJobNeverConstructsPoifs() {
        val file = workbook { it.createSheet("One") }; Thread.currentThread().interrupt()
        try { try { readXlsText(file,FileAnalysisLimits()); fail("Cancelled XLS accepted") } catch (_: CancellationException) { } }
        finally { Thread.interrupted(); file.delete() }
    }
}
