package com.aurorafox.runtime

import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class FileTreeBudgetTest {
    @Test fun exactFitAndOverflowUseActualFiles() {
        val root = Files.createTempDirectory("aurora-tree-budget").toFile()
        try {
            repeat(3) { root.resolve("$it.txt").writeText("real content") }
            val exact = boundedDirectoryTree(root, 3)
            assertEquals(3, exact.files.size)
            assertFalse(exact.truncated)
            val clipped = boundedDirectoryTree(root, 2)
            assertEquals(2, clipped.files.size)
            assertTrue(clipped.truncated)
        } finally { root.deleteRecursively() }
    }

    @Test fun ownerCanRaiseBudgetAboveFiveThousand() {
        val root = Files.createTempDirectory("aurora-tree-raised").toFile()
        try {
            repeat(5001) { root.resolve("$it").createNewFile() }
            val raised = boundedDirectoryTree(root, 5001)
            assertEquals(5001, raised.files.size)
            assertFalse(raised.truncated)
            assertTrue(boundedDirectoryTree(root, 5000).truncated)
        } finally { root.deleteRecursively() }
    }

    @Test fun emptyDirectoryIsCompleteAndMinimumIsOne() {
        val root = Files.createTempDirectory("aurora-tree-empty").toFile()
        try {
            val empty = boundedDirectoryTree(root, 1)
            assertTrue(empty.files.isEmpty())
            assertFalse(empty.truncated)
            root.resolve("one").createNewFile()
            root.resolve("two").createNewFile()
            val minimum = boundedDirectoryTree(root, 0)
            assertEquals(1, minimum.files.size)
            assertTrue(minimum.truncated)
        } finally { root.deleteRecursively() }
    }
}
