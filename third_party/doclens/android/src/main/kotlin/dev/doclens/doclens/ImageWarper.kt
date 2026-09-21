package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import java.io.File
import java.io.FileOutputStream
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Applies a 4-corner perspective warp using Android's `Matrix.setPolyToPoly`.
 * The output bitmap's size is determined by the average of the quad's edge
 * lengths to preserve resolution without excessive memory use.
 */
object ImageWarper {
    fun warp(
        bitmap: Bitmap,
        quad: Quad,
        jpegQuality: Int,
        enhancement: String = "none",
        autoOrientation: String = "none",
        flattenFold: Boolean = false,
    ): String {
        validateQuad(bitmap, quad)
        val widthTop = hypot((quad.topRight.x - quad.topLeft.x).toDouble(),
                             (quad.topRight.y - quad.topLeft.y).toDouble())
        val widthBottom = hypot((quad.bottomRight.x - quad.bottomLeft.x).toDouble(),
                                (quad.bottomRight.y - quad.bottomLeft.y).toDouble())
        val heightLeft = hypot((quad.bottomLeft.x - quad.topLeft.x).toDouble(),
                               (quad.bottomLeft.y - quad.topLeft.y).toDouble())
        val heightRight = hypot((quad.bottomRight.x - quad.topRight.x).toDouble(),
                                (quad.bottomRight.y - quad.topRight.y).toDouble())
        val outW = max(widthTop, widthBottom).roundToInt().coerceAtLeast(8)
        val outH = max(heightLeft, heightRight).roundToInt().coerceAtLeast(8)

        val src = floatArrayOf(
            quad.topLeft.x, quad.topLeft.y,
            quad.topRight.x, quad.topRight.y,
            quad.bottomRight.x, quad.bottomRight.y,
            quad.bottomLeft.x, quad.bottomLeft.y,
        )
        val dst = floatArrayOf(
            0f, 0f,
            outW.toFloat(), 0f,
            outW.toFloat(), outH.toFloat(),
            0f, outH.toFloat(),
        )

        val matrix = Matrix()
        if (!matrix.setPolyToPoly(src, 0, dst, 0, 4)) {
            throw ScannerException.CaptureFailed("setPolyToPoly failed")
        }
        val out = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
        canvas.drawBitmap(bitmap, matrix, paint)

        var processed = out
        if (flattenFold) {
            val flattened = FoldFlattener.flatten(out)
            if (flattened !== out) {
                out.recycle()
                processed = flattened
            }
        }
        // Optional post-warp enhancement (shadow-aware). Operates on the
        // cropped pixels in place; `none` is a no-op.
        enhanceInPlace(processed, enhancement)
        // 해상도 상한을 올리지 않고도 글자 경계를 복원한다. 원본을 과장하지 않는
        // 약한 unsharp mask라 JPEG 노이즈 증폭을 제한한다.
        sharpenInPlace(processed)

        // Optional upright-orientation correction. Detect the dominant text
        // direction on the dewarped crop and rotate it so it reads upright;
        // `0` turns (or no confident text) leaves it untouched.
        var finalBmp = processed
        if (autoOrientation == "auto") {
            val turns = TextOrientationDetector.bestClockwiseTurns(processed)
            if (turns != 0) {
                val rot = rotateBitmap(processed, turns)
                if (rot !== processed) {
                    processed.recycle()
                    finalBmp = rot
                }
            }
        }

        val tmp = File.createTempFile("fnds_cropped_", ".jpg")
        FileOutputStream(tmp).use { stream ->
            finalBmp.compress(Bitmap.CompressFormat.JPEG, jpegQuality.coerceIn(1, 100), stream)
        }
        finalBmp.recycle()
        return tmp.absolutePath
    }

    private fun validateQuad(bitmap: Bitmap, quad: Quad) {
        val points = listOf(quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft)
        if (points.any { it.x < 0f || it.y < 0f || it.x > bitmap.width || it.y > bitmap.height }) {
            throw ScannerException.CaptureFailed("Document corners are outside the image")
        }
        var signedArea = 0f
        for (index in points.indices) {
            val current = points[index]
            val next = points[(index + 1) % points.size]
            signedArea += current.x * next.y - next.x * current.y
        }
        if (kotlin.math.abs(signedArea) < 128f) {
            throw ScannerException.CaptureFailed("Document corners are too close together")
        }
        var direction = 0f
        for (index in points.indices) {
            val a = points[index]
            val b = points[(index + 1) % points.size]
            val c = points[(index + 2) % points.size]
            val cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if (kotlin.math.abs(cross) < 0.01f) {
                throw ScannerException.CaptureFailed("Document corners must form a convex quadrilateral")
            }
            if (direction == 0f) direction = cross
            else if (direction * cross < 0f) {
                throw ScannerException.CaptureFailed("Document corners must not cross")
            }
        }
    }

    fun warpFile(
        rawPath: String,
        quad: Quad,
        jpegQuality: Int,
        enhancement: String = "none",
        autoOrientation: String = "none",
        flattenFold: Boolean = false,
    ): String {
        val raw = BitmapFactory.decodeFile(rawPath)
            ?: throw ScannerException.CaptureFailed("Decode failed: $rawPath")
        val rotated = ExifRotator.rotated(raw, rawPath)
        try {
            return warp(rotated, quad, jpegQuality, enhancement, autoOrientation, flattenFold)
        } finally {
            if (rotated !== raw) rotated.recycle()
            raw.recycle()
        }
    }

    /**
     * Rotate the JPEG at [rawPath] by [quarterTurns] clockwise 90° steps and
     * write a new file, returning its path. EXIF orientation is baked in
     * first so the rotation is applied to the visually-upright pixels.
     * [quarterTurns] is normalized modulo 4.
     */
    fun rotateFile(rawPath: String, quarterTurns: Int, jpegQuality: Int): String {
        val raw = BitmapFactory.decodeFile(rawPath)
            ?: throw ScannerException.CaptureFailed("Decode failed: $rawPath")
        val rotated = ExifRotator.rotated(raw, rawPath)
        val out = rotateBitmap(rotated, quarterTurns)
        val tmp = File.createTempFile("fnds_rotated_", ".jpg")
        FileOutputStream(tmp).use { stream ->
            out.compress(Bitmap.CompressFormat.JPEG, jpegQuality.coerceIn(1, 100), stream)
        }
        // `out`, `rotated` and `raw` may alias each other (no rotation / no
        // EXIF). Recycle each distinct bitmap exactly once.
        listOf(out, rotated, raw).distinct().forEach { it.recycle() }
        return tmp.absolutePath
    }

    /**
     * Return a new bitmap rotated [clockwiseQuarterTurns] 90° steps clockwise,
     * or the input itself when the normalized turn count is 0. `Matrix.postRotate`
     * with positive degrees rotates clockwise (matching `ExifRotator`).
     */
    fun rotateBitmap(src: Bitmap, clockwiseQuarterTurns: Int): Bitmap {
        val t = ((clockwiseQuarterTurns % 4) + 4) % 4
        if (t == 0) return src
        val matrix = Matrix()
        matrix.postRotate(90f * t)
        return Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
    }

    /**
     * Applies a shadow-aware enhancement to the cropped bitmap, in place.
     *
     * `enhanced` and `blackAndWhite` first estimate the per-pixel background
     * illumination — a heavily downscaled, smoothed copy of the image — and
     * divide it out. This is the classic Retinex/"flatten" correction: under
     * the multiplicative model `image = reflectance × illumination`, dividing
     * by a smooth illumination estimate cancels uneven lighting and soft
     * shadows. `enhanced` keeps colour and whitens the background; the
     * background estimate is a tiny downscaled copy, bilinearly sampled per
     * pixel — a cheap stand-in for a very large blur kernel.
     *
     * `blackAndWhite` adaptively thresholds luma against the local background
     * (white where `luma >= background_luma × ratio`, else black) — this is
     * the no-OpenCV equivalent of OpenCV's `ADAPTIVE_THRESH_MEAN_C`, which
     * tolerates shadows where a single global (Otsu) threshold fails.
     *
     * `grayscale` is a plain global desaturate (no shadow handling). `none`
     * is a no-op.
     *
     * iOS performs the equivalent step with `CIDocumentEnhancer` /
     * `CIColorThresholdOtsu`; see `ImageWarper.swift`.
     */
    private fun enhanceInPlace(bmp: Bitmap, mode: String) {
        if (mode == "none" || mode.isEmpty()) return
        val w = bmp.width
        val h = bmp.height
        if (w <= 0 || h <= 0) return

        if (mode == "grayscale") {
            val row = IntArray(w)
            for (y in 0 until h) {
                bmp.getPixels(row, 0, w, 0, y, w, 1)
                for (x in 0 until w) {
                    val p = row[x]
                    val l = luma((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)
                    row[x] = (0xFF shl 24) or (l shl 16) or (l shl 8) or l
                }
                bmp.setPixels(row, 0, w, 0, y, w, 1)
            }
            return
        }
        if (mode != "enhanced" && mode != "blackAndWhite") return

        // Smooth background illumination estimate: downscale away the text
        // (keeping only the lighting gradient) into a tiny bitmap, then read
        // its pixels once. `factor` is clamped to >= 2 so the downscale always
        // produces a strictly smaller bitmap — `createScaledBitmap` returns
        // the *same* instance when the size is unchanged, which would later
        // recycle our output bitmap out from under us. We bilinearly sample
        // this small map per pixel (cheap, and avoids a full-size background
        // bitmap — keeping peak memory flat on large captures).
        val targetMax = 80
        val factor = max(2, max(w, h) / targetMax)
        val sw = max(1, w / factor)
        val sh = max(1, h / factor)
        val small = Bitmap.createScaledBitmap(bmp, sw, sh, true)
        val bg = IntArray(sw * sh)
        small.getPixels(bg, 0, sw, 0, 0, sw, sh)
        small.recycle()

        val blackAndWhite = mode == "blackAndWhite"
        // ~0.85 keeps faint strokes while clearing background speckle;
        // equivalent to a positive C offset in adaptive-mean thresholding.
        val bwRatio = 0.85f
        // One width-sized scratch row; the background map stays tiny.
        val row = IntArray(w)
        for (y in 0 until h) {
            bmp.getPixels(row, 0, w, 0, y, w, 1)
            // Bilinear sample coordinates into the small map (pixel-centre
            // aligned), with the row factors hoisted out of the inner loop.
            val gy = (y + 0.5f) * sh / h - 0.5f
            val fy = floor(gy).toInt()
            val ty = (gy - fy).coerceIn(0f, 1f)
            val y0 = fy.coerceIn(0, sh - 1)
            val y1 = (fy + 1).coerceIn(0, sh - 1)
            for (x in 0 until w) {
                val gx = (x + 0.5f) * sw / w - 0.5f
                val fx = floor(gx).toInt()
                val tx = (gx - fx).coerceIn(0f, 1f)
                val x0 = fx.coerceIn(0, sw - 1)
                val x1 = (fx + 1).coerceIn(0, sw - 1)
                val c00 = bg[y0 * sw + x0]
                val c10 = bg[y0 * sw + x1]
                val c01 = bg[y1 * sw + x0]
                val c11 = bg[y1 * sw + x1]
                val br = bilerp((c00 shr 16) and 0xFF, (c10 shr 16) and 0xFF,
                                (c01 shr 16) and 0xFF, (c11 shr 16) and 0xFF, tx, ty)
                val bgc = bilerp((c00 shr 8) and 0xFF, (c10 shr 8) and 0xFF,
                                 (c01 shr 8) and 0xFF, (c11 shr 8) and 0xFF, tx, ty)
                val bb = bilerp(c00 and 0xFF, c10 and 0xFF,
                                c01 and 0xFF, c11 and 0xFF, tx, ty)

                val d = row[x]
                val sr = (d shr 16) and 0xFF
                val sg = (d shr 8) and 0xFF
                val sb = d and 0xFF
                if (blackAndWhite) {
                    val sl = luma(sr, sg, sb)
                    val bl = luma(br, bgc, bb)
                    val ratio = if (bl > 0) sl.toFloat() / bl else 1f
                    val o = if (ratio >= bwRatio) 0xFF else 0x00
                    row[x] = (0xFF shl 24) or (o shl 16) or (o shl 8) or o
                } else {
                    val rr = if (br > 0) (sr * 255 / br).coerceAtMost(255) else 255
                    val rg = if (bgc > 0) (sg * 255 / bgc).coerceAtMost(255) else 255
                    val rb = if (bb > 0) (sb * 255 / bb).coerceAtMost(255) else 255
                    row[x] = (0xFF shl 24) or (rr shl 16) or (rg shl 8) or rb
                }
            }
            bmp.setPixels(row, 0, w, 0, y, w, 1)
        }
    }

    /** 3×3 unsharp mask. Per-row 버퍼만 사용해 큰 스캔에서 추가 전체 비트맵을 만들지 않는다. */
    private fun sharpenInPlace(bmp: Bitmap) {
        val width = bmp.width
        val height = bmp.height
        if (width < 3 || height < 3) return

        var previous = IntArray(width)
        var current = IntArray(width)
        var next = IntArray(width)
        val output = IntArray(width)
        bmp.getPixels(current, 0, width, 0, 0, width, 1)
        bmp.getPixels(next, 0, width, 0, 1, width, 1)

        for (y in 0 until height) {
            val top = if (y == 0) current else previous
            val bottom = if (y == height - 1) current else next
            for (x in 0 until width) {
                val left = (x - 1).coerceAtLeast(0)
                val right = (x + 1).coerceAtMost(width - 1)
                val center = current[x]
                val neighbours = intArrayOf(top[x], bottom[x], current[left], current[right])
                fun channel(shift: Int): Int {
                    val source = (center shr shift) and 0xFF
                    val blur = (neighbours.sumOf { (it shr shift) and 0xFF } + source * 4) / 8
                    return (source + (source - blur) * 0.65f).roundToInt().coerceIn(0, 255)
                }
                output[x] = (0xFF shl 24) or (channel(16) shl 16) or
                    (channel(8) shl 8) or channel(0)
            }
            bmp.setPixels(output, 0, width, 0, y, width, 1)
            if (y + 1 >= height) continue
            val recycled = previous
            previous = current
            current = next
            next = recycled
            if (y + 2 < height) bmp.getPixels(next, 0, width, 0, y + 2, width, 1)
        }
    }

    /** Bilinear interpolation of four corner samples; result clamped to [0,255]. */
    private fun bilerp(c00: Int, c10: Int, c01: Int, c11: Int, tx: Float, ty: Float): Int {
        val top = c00 + (c10 - c00) * tx
        val bot = c01 + (c11 - c01) * tx
        return (top + (bot - top) * ty).toInt().coerceIn(0, 255)
    }

    /** Rec.601 luma in [0, 255] using integer weights (77/150/29 ≈ /256). */
    private fun luma(r: Int, g: Int, b: Int): Int =
        ((r * 77 + g * 150 + b * 29) shr 8).coerceIn(0, 255)
}
