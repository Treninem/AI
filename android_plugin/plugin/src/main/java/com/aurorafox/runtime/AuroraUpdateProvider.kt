package com.aurorafox.runtime

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File

class AuroraUpdateProvider : ContentProvider() {
    companion object {
        const val PREFS = "aurorafox_update"
        const val KEY_APK_PATH = "apk_path"
    }

    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = "application/vnd.android.package-archive"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("AuroraFox update provider is read-only")
        val file = pendingApk() ?: throw java.io.FileNotFoundException("No pending AuroraFox update")
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val file = pendingApk() ?: throw java.io.FileNotFoundException("No pending AuroraFox update")
        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(cols)
        val row = cursor.newRow()
        for (column in cols) {
            when (column) {
                OpenableColumns.DISPLAY_NAME -> row.add(file.name)
                OpenableColumns.SIZE -> row.add(file.length())
                else -> row.add(null)
            }
        }
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw SecurityException("Read-only provider")
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

    private fun pendingApk(): File? {
        val ctx = context ?: return null
        val path = ctx.getSharedPreferences(PREFS, 0).getString(KEY_APK_PATH, null) ?: return null
        val file = try { File(path).canonicalFile } catch (_: Throwable) { return null }
        if (!file.isFile) return null
        val allowed = listOf(ctx.filesDir.canonicalFile, ctx.cacheDir.canonicalFile)
        if (allowed.none { root -> file == root || file.path.startsWith(root.path + File.separator) }) return null
        return file
    }
}
