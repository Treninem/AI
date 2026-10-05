package com.aurorafox.runtime

import java.io.File

internal data class FileTreeSnapshot(val files: List<File>, val truncated: Boolean)

/** Request budget comes from owner settings; exact fit is not an overflow. */
internal fun boundedDirectoryTree(root: File, requestedItems: Int): FileTreeSnapshot {
    val budget = requestedItems.coerceAtLeast(1)
    val iterator = root.walkTopDown().drop(1).iterator()
    val items = mutableListOf<File>()
    while (iterator.hasNext()) {
        val file = iterator.next()
        if (items.size >= budget) return FileTreeSnapshot(items, true)
        items.add(file)
    }
    return FileTreeSnapshot(items, false)
}
