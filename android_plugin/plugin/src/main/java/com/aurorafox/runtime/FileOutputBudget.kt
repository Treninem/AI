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
    val defaultScale = 180.0 / 72.0
    val projected = width * height * defaultScale * defaultScale
    val scale = if (projected > pixelBudget.toDouble()) defaultScale * kotlin.math.sqrt(pixelBudget.toDouble() / projected) else defaultScale
    require(scale.isFinite() && scale >= 0.01) { "PDF page dimensions exceed representable render scale" }
    require(width * height * scale * scale <= pixelBudget.toDouble() * 1.01) { "PDF render exceeds owner pixel budget" }
    return scale
}
