package com.aurorafox.runtime

import java.io.File
import java.net.URI
import java.util.zip.ZipFile
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Node
import org.w3c.dom.Element

/** OPF spine determines reading order. References are ZIP members, never URLs. */
internal fun readEpubText(file: File, limits: FileAnalysisLimits): ArchiveTextResult {
    ZipFile(file).use { zip ->
        var count = 0
        var expanded = 0L
        for (entry in zip.entries()) {
            if (Thread.currentThread().isInterrupted) throw java.util.concurrent.CancellationException("EPUB read cancelled")
            require(++count <= limits.archiveEntries) { "EPUB exceeds owner archive-entry budget" }
            val size = entry.size.coerceAtLeast(0)
            expanded = if (Long.MAX_VALUE-expanded < size) Long.MAX_VALUE else expanded+size
            require(expanded <= limits.expandedBytes) { "EPUB exceeds owner expanded-byte budget" }
        }
        var bytesRead = 0L
        fun xml(path: String): org.w3c.dom.Document {
            if (Thread.currentThread().isInterrupted) throw java.util.concurrent.CancellationException("EPUB read cancelled")
            require(path.isNotEmpty() && !isUnsafeArchivePath(path)) { "EPUB member path is unsafe" }
            val entry = zip.getEntry(path) ?: throw IllegalArgumentException("EPUB member missing: $path")
            val cap = minOf(limits.memberBytes, limits.totalTextBytes-bytesRead)
            require(cap > 0 && entry.size <= cap) { "EPUB XML exceeds owner member/total byte budget" }
            val raw = zip.getInputStream(entry).use { readOwnerBounded(it, cap) }
            require(!raw.truncated) { "EPUB XML exceeds actual owner byte budget" }
            bytesRead += raw.bytes.size
            rejectExternalXmlDeclarations(raw.bytes)
            val factory = DocumentBuilderFactory.newInstance().apply {
                isNamespaceAware = true
                isExpandEntityReferences = false
                isXIncludeAware = false
                try { setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) } catch (_: Exception) { }
                try { setFeature("http://xml.org/sax/features/external-general-entities", false) } catch (_: Exception) { }
                try { setFeature("http://xml.org/sax/features/external-parameter-entities", false) } catch (_: Exception) { }
            }
            return factory.newDocumentBuilder().parse(raw.bytes.inputStream())
        }
        fun elements(doc: org.w3c.dom.Document, name: String): List<Element> {
            val nodes = doc.getElementsByTagNameNS("*", name)
            return (0 until nodes.length).mapNotNull { nodes.item(it) as? Element }
        }
        val container = xml("META-INF/container.xml")
        val root = elements(container, "rootfile").firstOrNull() ?: throw IllegalArgumentException("EPUB rootfile missing")
        val opfPath = root.getAttribute("full-path")
        val opf = xml(opfPath)
        val manifest = elements(opf, "item").associateBy { it.getAttribute("id") }
        val spine = elements(opf, "itemref")
        require(spine.isNotEmpty()) { "EPUB reading spine missing" }
        val out = StringBuilder()
        val warnings = mutableListOf<String>()
        var truncated = false
        var chapters = 0
        for (reference in spine) {
            if (Thread.currentThread().isInterrupted) throw java.util.concurrent.CancellationException("EPUB read cancelled")
            val item = manifest[reference.getAttribute("idref")] ?: throw IllegalArgumentException("EPUB spine references missing manifest item")
            val href = URI(item.getAttribute("href"))
            require(href.scheme == null && href.authority == null && !href.path.isNullOrEmpty() && !href.path.startsWith('/')) { "EPUB external reference is not fetched" }
            val baseSegments = opfPath.split('/').dropLast(1).toMutableList()
            for (segment in href.path.split('/')) {
                when (segment) {
                    "", "." -> Unit
                    ".." -> { require(baseSegments.isNotEmpty()) { "EPUB reference escapes archive root" }; baseSegments.removeAt(baseSegments.lastIndex) }
                    else -> baseSegments.add(segment)
                }
            }
            val resolved = baseSegments.joinToString("/")
            require(!isUnsafeArchivePath(resolved)) { "EPUB reference escapes archive root" }
            val document = xml(resolved)
            val text = StringBuilder()
            val pending = java.util.ArrayDeque<Pair<Node, Boolean>>()
            pending.addLast(document.documentElement to false)
            while (pending.isNotEmpty()) {
                if (Thread.currentThread().isInterrupted) throw java.util.concurrent.CancellationException("EPUB read cancelled")
                val (node, exiting) = pending.removeLast()
                val name = (node.localName ?: node.nodeName).lowercase()
                if (exiting) { text.append('\n'); continue }
                if (name in setOf("head", "script", "style")) continue
                if (node.nodeType == Node.TEXT_NODE) text.append(node.nodeValue)
                else {
                    if (name in setOf("p", "div", "br", "h1", "h2", "li", "section")) pending.addLast(node to true)
                    val children = node.childNodes
                    for (i in children.length-1 downTo 0) pending.addLast(children.item(i) to false)
                }
            }
            val source = text.toString().trim()
            if (source.isEmpty()) continue
            val separator = if (out.isNotEmpty()) "\n\n" else ""
            val left = limits.outputChars-out.length-separator.length
            if (left <= 0) { truncated = true; break }
            out.append(separator).append(source.take(left))
            chapters++
            if (source.length > left) { truncated = true; break }
        }
        require(out.isNotEmpty()) { "EPUB contains no extracted readable text" }
        if (truncated) warnings.add("EPUB text is partial; raise owner output budget and repeat reading")
        return ArchiveTextResult(out.toString(), mapOf("format" to "epub", "title" to (elements(opf,"title").firstOrNull()?.textContent ?: ""),
            "authors" to elements(opf,"creator").map { it.textContent }, "language" to (elements(opf,"language").firstOrNull()?.textContent ?: ""),
            "spine_items" to spine.size, "chapters_read" to chapters, "text_bytes_read" to bytesRead,
            "output_truncated" to truncated, "untrusted_document" to true, "content_authority" to "data_only",
            "external_ai_required" to false), warnings, truncated)
    }
}
