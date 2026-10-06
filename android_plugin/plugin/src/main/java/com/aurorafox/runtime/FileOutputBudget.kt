package com.aurorafox.runtime

/** Headers alone are not extracted knowledge; count only actual source payload. */
internal fun appendOwnerPage(out: StringBuilder, page: Int, text: String, budget: Int): Boolean {
    val header = "${if (out.isNotEmpty()) "\n\n" else ""}### Страница $page\n"
    val remaining = budget - out.length - header.length
    if (remaining <= 0) return false
    out.append(header).append(text.take(remaining))
    return text.length <= remaining
}

internal fun ownerPdfRenderScale(width: Double, height: Double, pixelBudget: Long): Double {
    require(width.isFinite() && height.isFinite() && width > 0 && height > 0 && pixelBudget > 0)
    // PDFBox receives Float page geometry and scale. Bound the rounded integer
    // allocation, not continuous area, before calling its bitmap renderer.
    val nativeWidth = width.toFloat()
    val nativeHeight = height.toFloat()
    require(nativeWidth.isFinite() && nativeHeight.isFinite() && nativeWidth > 0 && nativeHeight > 0) {
        "PDF page dimensions exceed native representation"
    }
    fun fits(scale: Float): Boolean {
        val w = kotlin.math.ceil((nativeWidth * scale).toDouble()).coerceAtLeast(1.0)
        val h = kotlin.math.ceil((nativeHeight * scale).toDouble()).coerceAtLeast(1.0)
        return w.isFinite() && h.isFinite() && w <= Int.MAX_VALUE && h <= Int.MAX_VALUE &&
            w.toLong() <= pixelBudget / h.toLong()
    }
    // Positive Float bit patterns are monotonic. Find the greatest representable
    // productive scale without a policy floor or an overflow-prone pixel product.
    var low = 1
    var high = (180f / 72f).toRawBits()
    var best = 0
    while (low <= high) {
        val mid = low + (high - low) / 2
        if (fits(Float.fromBits(mid))) { best = mid; low = mid + 1 }
        else high = mid - 1
    }
    require(best > 0) { "PDF render scale exceeds native representation" }
    return Float.fromBits(best).toDouble()
}
