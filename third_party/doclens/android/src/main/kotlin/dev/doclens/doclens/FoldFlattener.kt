package dev.doclens.doclens

import android.graphics.Bitmap
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Conservative one-fold page flattener for a perspective-corrected document.
 *
 * A single photo cannot recover arbitrary 3D paper geometry. This processor
 * therefore only acts when it finds a broad, dark fold valley near the centre
 * of the page. It expands samples around that valley with a smooth mesh; when
 * confidence is low it returns the input unchanged rather than distorting text
 * or tables.
 */
object FoldFlattener {
    private const val MIN_VALLEY_CONTRAST = 10f
    private const val MAX_STRENGTH = 0.14f

    private enum class Axis { vertical, horizontal }

    private data class Fold(
        val axis: Axis,
        val position: Int,
        val strength: Float,
        val confidence: Float,
    )

    fun flatten(source: Bitmap): Bitmap {
        val fold = findFold(source) ?: return source
        val output = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        when (fold.axis) {
            Axis.vertical -> remapVertical(source, output, fold)
            Axis.horizontal -> remapHorizontal(source, output, fold)
        }
        return output
    }

    private fun findFold(bitmap: Bitmap): Fold? {
        val vertical = findValley(bitmap, Axis.vertical)
        val horizontal = findValley(bitmap, Axis.horizontal)
        return listOfNotNull(vertical, horizontal).maxByOrNull { it.confidence }
    }

    private fun findValley(bitmap: Bitmap, axis: Axis): Fold? {
        val length = if (axis == Axis.vertical) bitmap.width else bitmap.height
        val crossLength = if (axis == Axis.vertical) bitmap.height else bitmap.width
        if (length < 120 || crossLength < 120) return null

        val sampleStep = max(2, length / 220)
        val crossStep = max(4, crossLength / 180)
        val profile = ArrayList<Float>()
        val positions = ArrayList<Int>()
        val pixel = IntArray(1)
        for (position in 0 until length step sampleStep) {
            var sum = 0L
            var count = 0
            for (cross in crossStep until crossLength - crossStep step crossStep) {
                val x = if (axis == Axis.vertical) position else cross
                val y = if (axis == Axis.vertical) cross else position
                bitmap.getPixels(pixel, 0, 1, x, y, 1, 1)
                val value = pixel[0]
                val r = (value shr 16) and 0xFF
                val g = (value shr 8) and 0xFF
                val b = value and 0xFF
                sum += (r * 77 + g * 150 + b * 29) shr 8
                count++
            }
            if (count > 0) {
                positions += position
                profile += sum.toFloat() / count
            }
        }
        if (profile.size < 20) return null

        val neighborRadius = max(3, profile.size / 24)
        var best: Fold? = null
        val first = (profile.size * 0.18).toInt()
        val last = (profile.size * 0.82).toInt()
        for (index in first..last) {
            val centerStart = max(0, index - 1)
            val centerEnd = min(profile.lastIndex, index + 1)
            var centerSum = 0f
            for (i in centerStart..centerEnd) centerSum += profile[i]
            val center = centerSum / (centerEnd - centerStart + 1)

            val leftStart = max(0, index - neighborRadius)
            val leftEnd = max(0, index - 2)
            val rightStart = min(profile.lastIndex, index + 2)
            val rightEnd = min(profile.lastIndex, index + neighborRadius)
            if (leftEnd < leftStart || rightEnd < rightStart) continue
            var surroundingSum = 0f
            var surroundingCount = 0
            for (i in leftStart..leftEnd) { surroundingSum += profile[i]; surroundingCount++ }
            for (i in rightStart..rightEnd) { surroundingSum += profile[i]; surroundingCount++ }
            val valley = surroundingSum / surroundingCount - center
            if (valley < MIN_VALLEY_CONTRAST) continue

            val confidence = valley * (1f - abs(index - profile.size / 2).toFloat() / profile.size)
            val strength = (valley / 255f * 2.4f).coerceIn(0.045f, MAX_STRENGTH)
            val candidate = Fold(axis, positions[index], strength, confidence)
            if (best == null || candidate.confidence > best.confidence) best = candidate
        }
        return best
    }

    private fun remapVertical(source: Bitmap, output: Bitmap, fold: Fold) {
        val width = source.width
        val sourceRow = IntArray(width)
        val outputRow = IntArray(width)
        for (y in 0 until source.height) {
            source.getPixels(sourceRow, 0, width, 0, y, width, 1)
            for (x in 0 until width) outputRow[x] = sourceRow[mapCoordinate(x, width, fold)]
            output.setPixels(outputRow, 0, width, 0, y, width, 1)
        }
    }

    private fun remapHorizontal(source: Bitmap, output: Bitmap, fold: Fold) {
        val width = source.width
        val sourceRow = IntArray(width)
        val outputRow = IntArray(width)
        for (y in 0 until source.height) {
            val sourceY = mapCoordinate(y, source.height, fold)
            source.getPixels(sourceRow, 0, width, 0, sourceY, width, 1)
            sourceRow.copyInto(outputRow)
            output.setPixels(outputRow, 0, width, 0, y, width, 1)
        }
    }

    private fun mapCoordinate(destination: Int, length: Int, fold: Fold): Int {
        val offset = destination - fold.position
        val sideLength = if (offset < 0) fold.position else length - 1 - fold.position
        if (sideLength <= 0) return destination.coerceIn(0, length - 1)
        val normalized = abs(offset).toFloat() / sideLength
        val scale = 1f - fold.strength * (1f - normalized) * (1f - normalized)
        return (fold.position + offset * scale).toInt().coerceIn(0, length - 1)
    }
}
