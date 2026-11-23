// Text for the home-screen widget, drawn with the app's own fonts. Launchers
// ignore custom font resources in widgets, so text is rendered to bitmaps:
// plain text as an alpha mask the ImageView tints (small), text with emoji in
// full color.
package com.arunvijey.subwayboard.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.text.TextPaint
import android.text.TextUtils
import android.util.LruCache
import android.widget.RemoteViews
import kotlin.math.ceil
import kotlin.math.max

/** A text style: the app's cond()/inter() helpers. [ls] is letter-spacing in em. */
class Style(val face: Typeface, val sp: Float, val ls: Float = 0f, val tnum: Boolean = false)

object Ink {
    private val faces = HashMap<String, Typeface>()

    /**
     * Drawn text, ticks and pills, kept between redraws. The widget redraws
     * every minute while something is live, but nearly all of it (titles,
     * times, headings) is the same as last time; this skips drawing it again.
     * Bitmaps here are never changed after they're made.
     */
    private val drawn = object : LruCache<String, Bitmap>(3 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }

    private inline fun cached(key: String, make: () -> Bitmap): Bitmap =
        drawn.get(key) ?: make().also { drawn.put(key, it) }

    /** What a [Style] draws like, for cache keys (fonts are cached, so identity is enough). */
    private fun styleKey(c: Context, st: Style): String {
        val m = c.resources
        return "${System.identityHashCode(st.face)}/${st.sp}/${st.ls}/${st.tnum}/${m.displayMetrics.density}/${m.configuration.fontScale}"
    }

    /** Barlow Condensed at 600 / 700 / 800, from the app's bundled assets. */
    fun cond(c: Context, weight: Int): Typeface = face(c, "cond$weight") {
        load(c, when (weight) {
            600 -> "BarlowCondensed-SemiBold.ttf"
            700 -> "BarlowCondensed-Bold.ttf"
            else -> "BarlowCondensed-ExtraBold.ttf"
        }, null)
    }

    /** Inter (variable font) at [weight]. */
    fun inter(c: Context, weight: Int): Typeface = face(c, "inter$weight") { load(c, "Inter.ttf", weight) }

    private fun face(c: Context, key: String, make: () -> Typeface) = synchronized(faces) { faces.getOrPut(key, make) }

    private fun load(c: Context, file: String, weight: Int?): Typeface {
        val path = "flutter_assets/assets/fonts/$file"
        return try {
            if (weight != null && Build.VERSION.SDK_INT >= 26) {
                Typeface.Builder(c.assets, path).setFontVariationSettings("'wght' $weight").build()
            } else {
                Typeface.createFromAsset(c.assets, path)
            }
        } catch (e: Exception) {
            Typeface.create("sans-serif-condensed", Typeface.BOLD)
        }
    }

    fun dp(c: Context, v: Float) = v * c.resources.displayMetrics.density

    fun paint(c: Context, st: Style) = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
        typeface = st.face
        textSize = st.sp * c.resources.displayMetrics.density * c.resources.configuration.fontScale
        letterSpacing = st.ls
        if (st.tnum) fontFeatureSettings = "tnum"
    }

    fun width(c: Context, text: String, st: Style) = ceil(paint(c, st).measureText(text)).toInt() + 2

    /**
     * Puts [text] into ImageView [id] in [color], ellipsized to [maxPx] (0 = no
     * limit). [seam] cuts the departure-board seam through the middle of the
     * digits, letting the row color show through. [strike] crosses it out (done).
     */
    fun text(rv: RemoteViews, id: Int, c: Context, text: String, st: Style, color: Int, maxPx: Int = 0, seam: Boolean = false, strike: Boolean = false) {
        val p = paint(c, st)
        val shown = if (maxPx > 0) TextUtils.ellipsize(text, p, maxPx.toFloat(), TextUtils.TruncateAt.END).toString() else text
        val emoji = shown.any { Character.isSurrogate(it) || it.code in 0x2190..0x2BFF }
        // Plain text is an alpha mask tinted below, so its color isn't part of the key.
        val key = "t|${styleKey(c, st)}|$seam|$strike|${if (emoji) color else 0}|$shown"
        rv.setImageViewBitmap(id, cached(key) { drawText(c, p, shown, emoji, color, seam, strike) })
        // Rows are recycled, so always reset the tint; transparent leaves color bitmaps untouched.
        rv.setInt(id, "setColorFilter", if (emoji) Color.TRANSPARENT else color)
    }

    private fun drawText(c: Context, p: TextPaint, shown: String, emoji: Boolean, color: Int, seam: Boolean, strike: Boolean): Bitmap {
        val fm = p.fontMetrics
        val w = max(1, ceil(p.measureText(shown)).toInt() + 2)
        val h = max(1, ceil(fm.descent - fm.ascent).toInt())
        val b = Bitmap.createBitmap(w, h, if (emoji) Bitmap.Config.ARGB_8888 else Bitmap.Config.ALPHA_8)
        val cv = Canvas(b)
        p.color = if (emoji) color else Color.BLACK
        cv.drawText(shown, 1f, -fm.ascent, p)
        if (strike) {
            val x = android.graphics.Rect().also { p.getTextBounds("x", 0, 1, it) }
            val y = -fm.ascent + x.exactCenterY()
            cv.drawRect(0f, y - dp(c, 1f), w.toFloat(), y + dp(c, 1f), Paint().apply { this.color = if (emoji) color else Color.BLACK })
        }
        if (seam) {
            val digit = android.graphics.Rect().also { p.getTextBounds("0", 0, 1, it) }
            val y = -fm.ascent + digit.exactCenterY()
            val t = dp(c, 1f)
            cv.drawRect(0f, y - t, w.toFloat(), y + t, Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR) })
        }
        return b
    }

    /**
     * The app's TaskCheck: a ring in the line color, filled with a tick when
     * done. [size] is the circle in dp; the bitmap has [pad] dp around it so the
     * tap target is bigger than the circle.
     */
    fun check(c: Context, done: Boolean, color: Int, size: Float = 24f, pad: Float = 9f): Bitmap =
        cached("c|$done|$color|$size|$pad|${c.resources.displayMetrics.density}") { drawCheck(c, done, color, size, pad) }

    private fun drawCheck(c: Context, done: Boolean, color: Int, size: Float, pad: Float): Bitmap {
        val px = ceil(dp(c, size + pad * 2)).toInt()
        val b = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val cv = Canvas(b)
        val r = dp(c, size) / 2
        val cx = px / 2f
        val stroke = dp(c, if (size > 22) 2.4f else 2f)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        if (done) {
            cv.drawCircle(cx, cx, r, p)
            val on = if (0.299 * Color.red(color) + 0.587 * Color.green(color) + 0.114 * Color.blue(color) > 140) BLACK else WHITE
            val k = dp(c, size) / 24f
            val path = android.graphics.Path().apply {
                moveTo(cx - 5.4f * k, cx + .4f * k)
                lineTo(cx - 1.6f * k, cx + 4.2f * k)
                lineTo(cx + 5.6f * k, cx - 3.6f * k)
            }
            cv.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = on
                style = Paint.Style.STROKE
                strokeWidth = dp(c, 2.6f) * size / 24f
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            })
        } else {
            p.style = Paint.Style.STROKE
            p.strokeWidth = stroke
            cv.drawCircle(cx, cx, r - stroke / 2, p)
        }
        return b
    }

    /** A rounded pill with centered text (TODAY button, LIVE tag). */
    fun pill(c: Context, text: String, st: Style, bg: Int, fg: Int, padH: Float, height: Float, radius: Float): Bitmap =
        cached("p|${styleKey(c, st)}|$bg|$fg|$padH|$height|$radius|$text") { drawPill(c, text, st, bg, fg, padH, height, radius) }

    private fun drawPill(c: Context, text: String, st: Style, bg: Int, fg: Int, padH: Float, height: Float, radius: Float): Bitmap {
        val p = paint(c, st).apply { color = fg }
        val tw = p.measureText(text)
        val w = ceil(tw + dp(c, padH) * 2).toInt()
        val h = ceil(dp(c, height)).toInt()
        val b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val cv = Canvas(b)
        cv.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), dp(c, radius), dp(c, radius), Paint(Paint.ANTI_ALIAS_FLAG).apply { color = bg })
        val fm = p.fontMetrics
        cv.drawText(text, (w - tw) / 2, h / 2f - (fm.ascent + fm.descent) / 2, p)
        return b
    }

    /**
     * The LIVE tag and its pulse halo, as two bitmaps of the same size: the
     * tag sits inside a margin the halo blooms into. The widget cross-fades
     * the halo over the tag, standing in for the app's pulsing ring.
     */
    fun liveTag(c: Context, st: Style, bg: Int, fg: Int, ring: Int, padH: Float, height: Float, radius: Float): Pair<Bitmap, Bitmap> {
        val k = "l|${styleKey(c, st)}|$bg|$fg|$ring|$padH|$height|$radius"
        val base0 = drawn.get("$k|base")
        val halo0 = drawn.get("$k|halo")
        if (base0 != null && halo0 != null) return base0 to halo0
        return drawLiveTag(c, st, bg, fg, ring, padH, height, radius).also {
            drawn.put("$k|base", it.first)
            drawn.put("$k|halo", it.second)
        }
    }

    private fun drawLiveTag(c: Context, st: Style, bg: Int, fg: Int, ring: Int, padH: Float, height: Float, radius: Float): Pair<Bitmap, Bitmap> {
        val tag = drawPill(c, "LIVE", st, bg, fg, padH, height, radius)
        val m = dp(c, 5f)
        val w = ceil(tag.width + m * 2).toInt()
        val h = ceil(tag.height + m * 2).toInt()
        val base = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        Canvas(base).drawBitmap(tag, m, m, null)
        val halo = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val cv = Canvas(halo)
        val r = dp(c, radius)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.color = ring
        p.alpha = 70
        cv.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), r + m, r + m, p)
        p.alpha = 140
        val m2 = m / 2
        cv.drawRoundRect(RectF(m2, m2, w - m2, h - m2), r + m2, r + m2, p)
        // Hollow where the tag is, so the tag underneath stays crisp.
        cv.drawRoundRect(RectF(m, m, w - m, h - m), r, r, Paint(Paint.ANTI_ALIAS_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR) })
        return base to halo
    }

    /** The board's DAY | WEEK segmented control: dark track, white thumb (motion.dart Segmented). */
    fun segmented(c: Context, labels: List<String>, selected: Int, segW: Float, height: Float): Bitmap =
        cached("s|${labels.joinToString(",")}|$selected|$segW|$height|${c.resources.displayMetrics.density}|${c.resources.configuration.fontScale}") {
            drawSegmented(c, labels, selected, segW, height)
        }

    private fun drawSegmented(c: Context, labels: List<String>, selected: Int, segW: Float, height: Float): Bitmap {
        val st = Style(cond(c, 800), 13f, .08f)
        val pad = dp(c, 3f)
        val sw = dp(c, segW)
        val w = ceil(sw * labels.size + pad * 2).toInt()
        val h = ceil(dp(c, height)).toInt()
        val b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val cv = Canvas(b)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG)
        fill.color = 0xFF1C1C20.toInt()
        cv.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), h / 2f, h / 2f, fill)
        val th = h - pad * 2
        fill.color = WHITE
        cv.drawRoundRect(RectF(pad + sw * selected, pad, pad + sw * (selected + 1), pad + th), th / 2, th / 2, fill)
        labels.forEachIndexed { i, label ->
            val p = paint(c, st).apply { color = if (i == selected) BLACK else 0xFFA1A1AA.toInt() }
            val fm = p.fontMetrics
            cv.drawText(label, pad + sw * i + (sw - p.measureText(label)) / 2, h / 2f - (fm.ascent + fm.descent) / 2, p)
        }
        return b
    }
}
