package com.aurorafox.runtime

import android.content.Context
import android.net.Uri
import com.github.luben.zstd.ZstdInputStream
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

internal class ProductionPackArchiveImport(private val context: Context) {
    companion object {
        private const val EXPECTED_ARCHIVE_SHA256 = "bc0f312448f70a650435af8f30e853ca0a81a58f69c61802de7095bed9e24614"
        private const val EXPECTED_SHARDS = 60
        private const val MAX_EXPANDED_BYTES = 2_100_000_000L
        private const val MAX_FILES = 256
    }

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "AuroraFoxProductionPackImport").apply { isDaemon = true }
    }
    @Volatile private var status = payload("idle")
    @Volatile private var busy = false

    fun prepareSelection(): String {
        if (busy) return errorPayload("Production pack import is already running")
        status = payload("selecting")
        return status
    }

    fun cancelSelection() {
        if (!busy) status = payload("cancelled")
    }

    fun failSelection(message: String) {
        if (!busy) status = errorPayload(message)
    }

    fun begin(uri: Uri) {
        if (busy) return
        busy = true
        status = payload("extracting", mapOf("progress_bytes" to 0L, "files" to 0))
        executor.submit {
            try {
                extract(uri)
            } catch (t: Throwable) {
                status = errorPayload(t.message ?: t.javaClass.simpleName)
            } finally {
                busy = false
            }
        }
    }

    fun poll(): String = status

    private fun extract(uri: Uri) {
        val archiveSha = computeArchiveSha(uri)
        check(archiveSha == EXPECTED_ARCHIVE_SHA256) { "Production archive SHA-256 mismatch: $archiveSha" }
        val root = File(context.filesDir, "app_userdata/AuroraFox")
        val incoming = File(root, "android-production-pack.incoming")
        val target = File(root, "android-production-pack")
        if (incoming.exists() && !incoming.deleteRecursively()) error("Cannot clear incomplete pack import")
        check(incoming.mkdirs()) { "Cannot create private pack directory" }

        var expanded = 0L
        var fileCount = 0
        try {
            val source = context.contentResolver.openInputStream(uri)
                ?: error("Selected archive cannot be opened")
            BufferedInputStream(source, 1024 * 1024).use { checked ->
                ZstdInputStream(checked).use { zstd ->
                    TarArchiveInputStream(BufferedInputStream(zstd, 1024 * 1024)).use { tar ->
                        val buffer = ByteArray(1024 * 1024)
                        while (true) {
                            val entry = tar.nextTarEntry ?: break
                            val relative = safeRelativePath(entry.name)
                            if (relative.isEmpty()) continue
                            val output = File(incoming, relative).canonicalFile
                            check(output.path.startsWith(incoming.canonicalPath + File.separator)) { "Archive path escapes destination" }
                            if (entry.isDirectory) {
                                check(output.mkdirs() || output.isDirectory) { "Cannot create archive directory" }
                                continue
                            }
                            check(entry.isFile) { "Archive contains unsupported entry: ${entry.name}" }
                            fileCount++
                            check(fileCount <= MAX_FILES) { "Archive contains too many files" }
                            output.parentFile?.let { check(it.mkdirs() || it.isDirectory) { "Cannot create archive parent" } }
                            BufferedOutputStream(FileOutputStream(output), 1024 * 1024).use { out ->
                                while (true) {
                                    val read = tar.read(buffer)
                                    if (read < 0) break
                                    if (read == 0) continue
                                    expanded += read
                                    check(expanded <= MAX_EXPANDED_BYTES) { "Archive exceeds production size bound" }
                                    out.write(buffer, 0, read)
                                    if (expanded % (16L * 1024L * 1024L) < read) {
                                        status = payload("extracting", mapOf("progress_bytes" to expanded, "files" to fileCount))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            check(File(incoming, "manifest.json").isFile) { "manifest.json is missing at archive root" }
            val shards = incoming.walkTopDown().count { it.isFile && it.extension.lowercase() == "jsonl" }
            check(shards == EXPECTED_SHARDS) { "Expected $EXPECTED_SHARDS shards, found $shards" }
            if (target.exists()) check(target.deleteRecursively()) { "Cannot replace previous production pack" }
            check(incoming.renameTo(target)) { "Cannot activate extracted production pack" }
            status = payload(
                "ready",
                mapOf(
                    "archive_sha256" to archiveSha,
                    "expanded_bytes" to expanded,
                    "files" to fileCount,
                    "shards" to shards,
                    "root" to target.absolutePath,
                ),
            )
        } catch (t: Throwable) {
            incoming.deleteRecursively()
            throw t
        }
    }

    private fun safeRelativePath(raw: String): String {
        val normalized = raw.replace('\\', '/').trim('/')
        if (normalized.isEmpty()) return ""
        val parts = normalized.split('/')
        check(parts.none { it.isEmpty() || it == "." || it == ".." }) { "Archive contains unsafe path" }
        return parts.joinToString(File.separator)
    }

    private fun computeArchiveSha(uri: Uri): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val source = context.contentResolver.openInputStream(uri)
            ?: error("Selected archive cannot be opened")
        BufferedInputStream(source, 1024 * 1024).use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                if (read > 0) digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun payload(stage: String, extra: Map<String, Any?> = emptyMap()): String = JSONObject().apply {
        put("ok", stage !in setOf("failed", "cancelled"))
        put("stage", stage)
        extra.forEach { (key, value) -> put(key, value) }
    }.toString()

    private fun errorPayload(message: String): String = JSONObject(
        mapOf("ok" to false, "stage" to "failed", "error" to message),
    ).toString()
}
