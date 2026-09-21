package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlin.math.max
import kotlin.math.min


/**
 * Document quadrilateral detector that runs entirely on a downscaled
 * luma buffer. Strategy:
 *
 * 1. Compute local luma; build a shadow-tolerant paper mask.
 * 2. Find the largest connected component in the mask.
 * 3. Walk the component's boundary, then approximate to a 4-point convex
 *    hull via Douglas-Peucker on the boundary polygon.
 *
 * Returns normalized `[0,1]` coordinates in `topLeft → topRight → bottomRight
 * → bottomLeft` order on the input buffer's frame (orientation handled by
 * caller).
 *
 * v0.1 deliberately avoids OpenCV and ML Kit (see docs/decisions.md).
 */
object QuadDetector {
    fun detect(luma: ByteArray, width: Int, height: Int): Quad? {
        if (width < 16 || height < 16) return null
        detectFromMask(buildMask(luma, width, height), width, height)?.let { return it }

        // 접힌 종이의 그림자·진한 표·약한 조명은 보통의 밝은 종이 마스크를
        // 여러 조각으로 나눈다. 기본 검출에 실패한 경우에만 임계값을 낮추고
        // 조금 넓게 닫은 마스크를 다시 시도한다. 따라서 일반적인 장면에서
        // 배경을 문서로 오인하는 회귀를 피한다.
        return detectFromMask(
            buildMask(
                luma = luma,
                w = width,
                h = height,
                globalOffset = 5,
                localOffset = -5,
                closeRadius = 2,
            ),
            width,
            height,
            includeDiagonal = true,
        )
    }

    private fun detectFromMask(
        mask: BooleanArray?,
        width: Int,
        height: Int,
        includeDiagonal: Boolean = false,
    ): Quad? {
        if (mask == null) return null
        val component = bestDocumentComponent(mask, width, height, includeDiagonal) ?: return null
        if (component.size < (width * height) / 50) return null
        val boundary = traceBoundary(component, width, height) ?: return null
        val hull = convexHull(boundary)
        if (hull.size < 4) return null
        val quad = approximateQuad(hull) ?: return null
        return normalizeAndOrder(quad, width.toFloat(), height.toFloat())
    }

    /**
     * Detect on a captured upright bitmap. The returned quad stays normalized,
     * so callers can safely scale it into the original capture dimensions.
     */
    fun detectInBitmap(bitmap: Bitmap, target: Int): Quad? {
        val w = bitmap.width
        val h = bitmap.height
        if (w < 16 || h < 16) return null
        val scale = min(1.0, target.toDouble() / max(w, h))
        val dw = max(16, (w * scale).toInt())
        val dh = max(16, (h * scale).toInt())
        val small = if (dw == w && dh == h) bitmap
        else Bitmap.createScaledBitmap(bitmap, dw, dh, true)
        return try {
            detect(lumaOf(small, dw, dh), dw, dh)
        } finally {
            if (small !== bitmap) small.recycle()
        }
    }

    /**
     * Run [detect] on a still image already on disk (e.g. one imported from
     * the gallery). Decodes the file, bakes in any EXIF orientation, then
     * detects on a downscaled luma copy — the normalized quad is
     * resolution-independent, so the downscale only affects speed.
     *
     * Returns a map of `{ "quad": <normalized quad map> | null, "imageSize":
     * [width, height] }` in the EXIF-upright pixel space (the same space the
     * warp operates in). Throws [ScannerException.CaptureFailed] when the file
     * cannot be decoded.
     */
    fun detectInFile(path: String): Map<String, Any?> {
        val raw = BitmapFactory.decodeFile(path)
            ?: throw ScannerException.CaptureFailed("Decode failed: $path")
        val upright = ExifRotator.rotated(raw, path)
        try {
            val w = upright.width
            val h = upright.height
            // The detector emits normalized [0,1] coordinates, so the
            // downscale is only a speed/memory optimisation.
            // Corner adjustment needs pins as close as possible to the paper
            // boundary. Use the same high-resolution analysis target as a
            // freshly captured still instead of the lower gallery preview.
            val target = 960
            val quad = detectInBitmap(upright, target)
            return mapOf(
                "quad" to quad?.toMap(),
                "imageSize" to listOf(w.toDouble(), h.toDouble()),
            )
        } finally {
            if (upright !== raw) upright.recycle()
            raw.recycle()
        }
    }

    private fun lumaOf(bitmap: Bitmap, width: Int, height: Int): ByteArray {
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        return ByteArray(pixels.size) { index ->
            val p = pixels[index]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            (((r * 77 + g * 150 + b * 29) shr 8) and 0xFF).toByte()
        }
    }

    private fun buildMask(
        luma: ByteArray,
        w: Int,
        h: Int,
        globalOffset: Int = 20,
        localOffset: Int = 7,
        closeRadius: Int = 1,
    ): BooleanArray? {
        var sum = 0L
        for (b in luma) sum += b.toInt() and 0xFF
        val mean = (sum / luma.size).toInt()
        // 전역 밝기만 쓰면 문서 한쪽 그림자가 배경으로 빠진다. 적분 영상으로
        // 주변 조도를 구해 더 낮은 쪽 임계값을 쓰되, 너무 어두운 배경은 전역
        // 기준으로 계속 제외한다.
        val stride = w + 1
        val integral = IntArray(stride * (h + 1))
        for (y in 1..h) {
            var rowSum = 0
            for (x in 1..w) {
                rowSum += luma[(y - 1) * w + (x - 1)].toInt() and 0xFF
                integral[y * stride + x] = integral[(y - 1) * stride + x] + rowSum
            }
        }
        val radius = (min(w, h) / 10).coerceAtLeast(12)
        val globalThreshold = (mean + globalOffset).coerceIn(50, 220)
        val mask = BooleanArray(luma.size)
        for (y in 0 until h) {
            val top = (y - radius).coerceAtLeast(0)
            val bottom = (y + radius + 1).coerceAtMost(h)
            for (x in 0 until w) {
                val left = (x - radius).coerceAtLeast(0)
                val right = (x + radius + 1).coerceAtMost(w)
                val localSum = integral[bottom * stride + right] -
                    integral[top * stride + right] -
                    integral[bottom * stride + left] + integral[top * stride + left]
                val localMean = localSum / ((bottom - top) * (right - left))
                val threshold = min(globalThreshold, (localMean + localOffset).coerceIn(45, 220))
                val index = y * w + x
                mask[index] = (luma[index].toInt() and 0xFF) > threshold
            }
        }
        return closeMask(mask, w, h, closeRadius)
    }

    /** Close small shadow/text gaps so a paper region remains connected. */
    private fun closeMask(mask: BooleanArray, w: Int, h: Int, radius: Int): BooleanArray {
        val dilated = BooleanArray(mask.size)
        for (y in 0 until h) for (x in 0 until w) {
            var any = false
            for (dy in -radius..radius) for (dx in -radius..radius) {
                val px = x + dx
                val py = y + dy
                if (px in 0 until w && py in 0 until h && mask[py * w + px]) any = true
            }
            dilated[y * w + x] = any
        }
        val closed = BooleanArray(mask.size)
        for (y in 0 until h) for (x in 0 until w) {
            var all = true
            for (dy in -radius..radius) for (dx in -radius..radius) {
                val px = x + dx
                val py = y + dy
                if (px !in 0 until w || py !in 0 until h || !dilated[py * w + px]) all = false
            }
            closed[y * w + x] = all
        }
        return closed
    }

    private fun bestDocumentComponent(
        mask: BooleanArray,
        w: Int,
        h: Int,
        includeDiagonal: Boolean,
    ): IntArray? {
        val labels = IntArray(mask.size) { -1 }
        var best: IntArray? = null
        var bestScore = Double.NEGATIVE_INFINITY
        var closeDocumentFallback: IntArray? = null
        var closeDocumentFallbackScore = Double.NEGATIVE_INFINITY
        val stack = IntArray(mask.size)
        for (start in mask.indices) {
            if (!mask[start] || labels[start] != -1) continue
            // BFS / flood fill iterative.
            var top = 0
            stack[top++] = start
            labels[start] = start
            val collected = IntArray(mask.size)
            var collectedSize = 0
            while (top > 0) {
                val idx = stack[--top]
                collected[collectedSize++] = idx
                val x = idx % w
                val y = idx / w
                val neighbors = if (includeDiagonal) intArrayOf(
                    if (x > 0) idx - 1 else -1,
                    if (x < w - 1) idx + 1 else -1,
                    if (y > 0) idx - w else -1,
                    if (y < h - 1) idx + w else -1,
                    if (x > 0 && y > 0) idx - w - 1 else -1,
                    if (x < w - 1 && y > 0) idx - w + 1 else -1,
                    if (x > 0 && y < h - 1) idx + w - 1 else -1,
                    if (x < w - 1 && y < h - 1) idx + w + 1 else -1,
                ) else intArrayOf(
                    if (x > 0) idx - 1 else -1,
                    if (x < w - 1) idx + 1 else -1,
                    if (y > 0) idx - w else -1,
                    if (y < h - 1) idx + w else -1,
                )
                for (n in neighbors) {
                    if (n >= 0 && mask[n] && labels[n] == -1) {
                        labels[n] = start
                        stack[top++] = n
                    }
                }
            }
            if (collectedSize < (w * h) / 80) continue
            var minX = w; var maxX = 0; var minY = h; var maxY = 0
            for (i in 0 until collectedSize) {
                val x = collected[i] % w; val y = collected[i] / w
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
            val boxArea = max(1, (maxX - minX + 1) * (maxY - minY + 1))
            val fill = collectedSize.toDouble() / boxArea
            val area = collectedSize.toDouble() / (w * h)
            val touchesFrame = (if (minX == 0) 1 else 0) + (if (maxX == w - 1) 1 else 0) +
                (if (minY == 0) 1 else 0) + (if (maxY == h - 1) 1 else 0)
            // 전체 프레임이 하나의 밝은 덩어리인 경우는 흰 배경이지 문서
            // 외곽이 아니다. 보조 검출에서도 이를 사각형으로 확정하지 않는다.
            if (touchesFrame == 4 && area > 0.92) continue
            // 바닥처럼 넓게 퍼진 반사보다, 화면 중앙을 적당히 채우는 밀도 높은
            // 종이 후보를 우선한다. 다만 가까이 든 종이는 세 변에 닿을 수 있으므로
            // 이를 바로 버리면 "윤곽 없음"이 된다. 일반 후보가 없을 때만 쓰는
            // fallback으로 보존하면 Flutter가 "조금 더 멀리" 안내를 줄 수 있다.
            val preferredArea = 0.45
            val areaFit = 1.0 - kotlin.math.abs(area - preferredArea)
            val score = fill * areaFit * if (touchesFrame >= 2) 0.12 else 1.0
            val isCloseDocument = touchesFrame >= 3 || (area > 0.82 && fill < 0.92)
            if (isCloseDocument) {
                if (fill >= 0.55 && score > closeDocumentFallbackScore) {
                    closeDocumentFallbackScore = score
                    closeDocumentFallback = collected.copyOf(collectedSize)
                }
                continue
            }
            if (score > bestScore) {
                bestScore = score
                best = collected.copyOf(collectedSize)
            }
        }
        return best ?: closeDocumentFallback
    }

    private fun traceBoundary(component: IntArray, w: Int, h: Int): List<PointF>? {
        // A pixel is a boundary if any of its 4-neighbors is NOT in the component.
        val inComp = BooleanArray(w * h)
        for (idx in component) inComp[idx] = true
        val result = ArrayList<PointF>(component.size / 4 + 8)
        for (idx in component) {
            val x = idx % w
            val y = idx / w
            val isBoundary =
                x == 0 || y == 0 || x == w - 1 || y == h - 1 ||
                !inComp[idx - 1] || !inComp[idx + 1] ||
                !inComp[idx - w] || !inComp[idx + w]
            if (isBoundary) result.add(PointF(x.toFloat(), y.toFloat()))
        }
        return if (result.size < 4) null else result
    }

    private fun convexHull(points: List<PointF>): List<PointF> {
        if (points.size < 3) return points
        val sorted = points.sortedWith(compareBy({ it.x }, { it.y }))
        val lower = ArrayList<PointF>()
        for (p in sorted) {
            while (lower.size >= 2 && cross(lower[lower.size - 2], lower[lower.size - 1], p) <= 0)
                lower.removeAt(lower.size - 1)
            lower.add(p)
        }
        val upper = ArrayList<PointF>()
        for (p in sorted.reversed()) {
            while (upper.size >= 2 && cross(upper[upper.size - 2], upper[upper.size - 1], p) <= 0)
                upper.removeAt(upper.size - 1)
            upper.add(p)
        }
        if (lower.isNotEmpty()) lower.removeAt(lower.size - 1)
        if (upper.isNotEmpty()) upper.removeAt(upper.size - 1)
        return lower + upper
    }

    private fun cross(O: PointF, A: PointF, B: PointF): Float =
        (A.x - O.x) * (B.y - O.y) - (A.y - O.y) * (B.x - O.x)

    /**
     * Reduce a convex hull to its 4 dominant corners by picking the hull
     * points that extremize (x+y), (x-y), -(x+y), -(x-y) — these are the
     * TL, TR, BR, BL extents for any near-rectangular hull, robust to
     * orientation jitter.
     */
    private fun approximateQuad(hull: List<PointF>): List<PointF>? {
        if (hull.size < 4) return null
        var tl = hull[0]; var tr = hull[0]; var br = hull[0]; var bl = hull[0]
        var tlScore = Float.POSITIVE_INFINITY
        var brScore = Float.NEGATIVE_INFINITY
        var trScore = Float.NEGATIVE_INFINITY
        var blScore = Float.POSITIVE_INFINITY
        for (p in hull) {
            val sum = p.x + p.y
            val diff = p.x - p.y
            if (sum < tlScore) { tlScore = sum; tl = p }
            if (sum > brScore) { brScore = sum; br = p }
            if (diff > trScore) { trScore = diff; tr = p }
            if (diff < blScore) { blScore = diff; bl = p }
        }
        // Ensure non-degenerate (no two corners coincide).
        val set = setOf(tl, tr, br, bl)
        if (set.size < 4) return null
        return listOf(tl, tr, br, bl)
    }

    private fun normalizeAndOrder(pts: List<PointF>, w: Float, h: Float): Quad {
        val normalized = pts.map { PointF(it.x / w, it.y / h) }
        return QuadOrdering.reorderClockwise(normalized)
    }
}

object QuadOrdering {
    /** Orders 4 points into TL/TR/BR/BL based on sum and difference heuristics. */
    fun reorderClockwise(pts: List<PointF>): Quad {
        require(pts.size == 4)
        val sumSorted = pts.sortedBy { it.x + it.y }
        val tl = sumSorted.first()
        val br = sumSorted.last()
        val remaining = pts - tl - br
        val (tr, bl) = if (remaining[0].x > remaining[1].x) remaining[0] to remaining[1]
                       else remaining[1] to remaining[0]
        return Quad(tl, tr, br, bl)
    }
}
