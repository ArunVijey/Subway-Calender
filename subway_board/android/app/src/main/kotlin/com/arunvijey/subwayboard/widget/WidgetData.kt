// Data the home-screen widget draws from: the snapshot the app pushes (events,
// tasks, money logged), the widget's own state (selected day, DAY/WEEK), and
// the board's colors.
package com.arunvijey.subwayboard.widget

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Date
import java.util.Locale

const val YELLOW = 0xFFF7C400.toInt()
const val BLACK = 0xFF000000.toInt()
const val WHITE = 0xFFFFFFFF.toInt()

/** A line (category): badge text, name and color. */
class WLine(val id: String, val label: String, val color: Int, val name: String = "") {
    /** Same threshold as the app's darkTextOn. */
    val darkText = 0.299 * Color.red(color) + 0.587 * Color.green(color) + 0.114 * Color.blue(color) > 165
}

/** One event, or one occurrence of a repeating event (the app expands repeats). */
class WEvent(
    val id: String,
    val title: String,
    val loc: String,
    val start: Long,
    val end: Long,
    val allDay: Boolean,
    val cat: String,
    val repeating: Boolean,
    /** Made with this task (quick add's "Also"): the row carries its tick. */
    val task: String? = null,
    /** The task counts as done on this occurrence's day. */
    val done: Boolean = false,
    /** A repeating task: its past days can't be un-ticked. */
    val taskRepeats: Boolean = false,
    /** Bill amount, formatted ("₹3,700"). */
    val amt: String? = null,
) {
    /** Same overlap rule as the app's occurrences(). */
    fun overlaps(d0: Long, d1: Long) = start < d1 && (end > d0 || start >= d0)
}

/** A task: open ones due in the window (or overdue), and ones ticked off in it. */
class WTask(
    val id: String,
    val title: String,
    val cat: String,
    /** YYYY-MM-DD */
    val due: String,
    /** Minutes after midnight, or null for any time. */
    val time: Int?,
    val star: Boolean,
    /** The day it was ticked off; null while open. */
    val doneDay: String?,
    val repeating: Boolean,
    /** A done copy of a repeating task: un-ticking it would make a duplicate. */
    val noUndo: Boolean,
    val amt: String?,
    val created: Long,
) {
    val done get() = doneDay != null
}

/** Money logged: a spend, refund or income (moves between accounts are left out). */
class WTxn(val id: String, val title: String, val emoji: String, val cat: String, val at: Long, val amt: String, val plus: Boolean)

/** What the app last pushed: events overlapping [from, to), tasks, money, lines, theme setting. */
class Snapshot(
    val theme: String,
    val from: Long,
    val to: Long,
    val lines: List<WLine>,
    val events: List<WEvent>,
    val tasks: List<WTask> = emptyList(),
    val txns: List<WTxn> = emptyList(),
    /** Per day (YYYY-MM-DD): spent, and income ("+₹5,000"), formatted. */
    val days: Map<String, Pair<String?, String?>> = emptyMap(),
) {
    private val byId = lines.associateBy { it.id }
    fun line(id: String) = byId[id] ?: lines.firstOrNull() ?: WLine("A", "A", Color.GRAY)
    fun covers(d0: Long, d1: Long) = d0 >= from && d1 <= to

    companion object {
        fun parse(raw: String): Snapshot {
            val o = JSONObject(raw)
            val ls = o.getJSONArray("lines")
            val es = o.getJSONArray("events")
            val ts = o.optJSONArray("tasks")
            val xs = o.optJSONArray("txns")
            val ds = o.optJSONObject("days")
            return Snapshot(
                theme = o.optString("theme", "system"),
                from = o.getLong("from"),
                to = o.getLong("to"),
                lines = (0 until ls.length()).map {
                    val l = ls.getJSONObject(it)
                    WLine(l.getString("id"), l.optString("label", l.getString("id")), parseColor(l.optString("color")), l.optString("name"))
                },
                events = (0 until es.length()).map {
                    val e = es.getJSONObject(it)
                    WEvent(
                        e.getString("id"), e.optString("title"), e.optString("loc"), e.getLong("start"), e.getLong("end"),
                        e.optBoolean("allDay"), e.optString("cat"), e.optBoolean("rep"),
                        task = e.optString("task").ifEmpty { null },
                        done = e.optBoolean("done"),
                        taskRepeats = e.optBoolean("trep"),
                        amt = e.optString("amt").ifEmpty { null },
                    )
                },
                tasks = if (ts == null) emptyList() else (0 until ts.length()).map {
                    val t = ts.getJSONObject(it)
                    WTask(
                        t.getString("id"), t.optString("title"), t.optString("cat"), t.optString("due"),
                        if (t.has("time")) t.optInt("time") else null,
                        t.optBoolean("star"), t.optString("doneDay").ifEmpty { null }, t.optBoolean("rep"), t.optBoolean("noUndo"),
                        t.optString("amt").ifEmpty { null }, t.optLong("created"),
                    )
                },
                txns = if (xs == null) emptyList() else (0 until xs.length()).map {
                    val x = xs.getJSONObject(it)
                    WTxn(x.getString("id"), x.optString("title"), x.optString("emoji", "•"), x.optString("cat"), x.getLong("at"), x.optString("amt"), x.optBoolean("plus"))
                },
                days = if (ds == null) emptyMap() else ds.keys().asSequence().associateWith { k ->
                    val d = ds.getJSONObject(k)
                    d.optString("spent").ifEmpty { null } to d.optString("in").ifEmpty { null }
                },
            )
        }

        private fun parseColor(hex: String) = try {
            Color.parseColor(hex)
        } catch (_: IllegalArgumentException) {
            Color.GRAY
        }
    }
}

/** Widget state in SharedPreferences. The app writes the snapshot; the widget's buttons write the rest. */
object WidgetStore {
    private const val PREFS = "subwayboard_widget"
    private const val BACK_DAYS = 7L
    private const val AHEAD_DAYS = 28L

    private var cacheRaw: String? = null
    private var cache: Snapshot? = null

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Stores the app's snapshot; false when it's identical to the last one. */
    fun saveSnapshot(c: Context, raw: String): Boolean {
        if (prefs(c).getString("snapshot", null) == raw) return false
        // apply(): readers see it at once; the disk write happens off the main thread.
        prefs(c).edit().putString("snapshot", raw).apply()
        return true
    }

    @Synchronized
    fun snapshot(c: Context): Snapshot? {
        val raw = prefs(c).getString("snapshot", null) ?: return null
        if (raw != cacheRaw) {
            cache = try {
                Snapshot.parse(raw)
            } catch (e: Exception) {
                null
            }
            cacheRaw = raw
        }
        return cache
    }

    fun week(c: Context) = prefs(c).getString("view", "day") == "week"

    /** Today's finished departures shown (the arrow by DEPARTURES). Folds again on another day. */
    fun showEnded(c: Context) = prefs(c).getBoolean("ended", false)

    fun toggleEnded(c: Context) = prefs(c).edit().putBoolean("ended", !showEnded(c)).commit()

    fun toggleView(c: Context) = prefs(c).edit().putString("view", if (week(c)) "day" else "week").commit()

    /** The day shown. Follows today (across midnight) until the user steps away from it. */
    fun sel(c: Context): LocalDate {
        val today = Time.today()
        val p = prefs(c)
        if (p.getBoolean("follow", true)) return today
        val d = try {
            LocalDate.parse(p.getString("sel", null) ?: return today)
        } catch (_: Exception) {
            return today
        }
        return clamp(d, today)
    }

    fun move(c: Context, days: Long) {
        val today = Time.today()
        val d = clamp(sel(c).plusDays(days), today)
        prefs(c).edit().putString("sel", d.toString()).putBoolean("follow", d == today).putBoolean("ended", false).commit()
    }

    fun goToday(c: Context) = prefs(c).edit().putBoolean("follow", true).putBoolean("ended", false).commit()

    // The app pushes about five weeks around today, so the widget stays inside that.
    private fun clamp(d: LocalDate, today: LocalDate): LocalDate {
        val lo = today.minusDays(BACK_DAYS)
        val hi = today.plusDays(AHEAD_DAYS)
        return if (d.isBefore(lo)) lo else if (d.isAfter(hi)) hi else d
    }
}

/** The app's board palette (theme.dart). */
class Pal private constructor(val light: Boolean) {
    val board = if (light) 0xFFF6F3EC.toInt() else 0xFF0B0B0D.toInt()
    val rowNext = if (light) 0xFFEBE3CF.toInt() else 0xFF18181C.toInt()
    val rule = if (light) 0xFFE2DDD1.toInt() else 0xFF232328.toInt()
    val text = if (light) 0xFF111111.toInt() else WHITE
    val sub = if (light) 0xFF57534E.toInt() else 0xFFA1A1AA.toInt()
    val nextNum = if (light) 0xFF111111.toInt() else YELLOW
    val btn = if (light) 0xFFE2DDD1.toInt() else 0xFF26262B.toInt()
    val green = if (light) 0xFF15803D.toInt() else 0xFF22C55E.toInt()
    val red = 0xFFEF4444.toInt()

    /** The app's inkFor: a line color that still reads on this board (yellow darkens on light). */
    fun ink(color: Int) = if (light && 0.299 * Color.red(color) + 0.587 * Color.green(color) + 0.114 * Color.blue(color) > 165) blend(color, BLACK, .62) else color
    val track = if (light) 0xFFE2DDD1.toInt() else 0xFF1C1C20.toInt()

    companion object {
        /** [theme] is the app's Appearance setting: system | dark | light. */
        fun of(c: Context, theme: String): Pal {
            val night = (c.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            return Pal(theme == "light" || (theme == "system" && !night))
        }
    }
}

/** [a] over [b] at [t] (0..1), opaque. Stands in for alpha, which RemoteViews can't animate or reliably set. */
fun blend(a: Int, b: Int, t: Double): Int {
    fun ch(x: Int, y: Int) = (x * t + y * (1 - t)).toInt().coerceIn(0, 255)
    return Color.rgb(ch(Color.red(a), Color.red(b)), ch(Color.green(a), Color.green(b)), ch(Color.blue(a), Color.blue(b)))
}

object Time {
    const val DAY = 86_400_000L
    private val hm = DateTimeFormatter.ofPattern("HH:mm")
    private val md = DateTimeFormatter.ofPattern("MMM d", Locale.ENGLISH)

    val zone: ZoneId get() = ZoneId.systemDefault()
    fun today(): LocalDate = LocalDate.now(zone)
    fun ms(d: LocalDate) = d.atStartOfDay(zone).toInstant().toEpochMilli()
    fun date(ms: Long): LocalDate = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()

    /** HH:MM, 24-hour (the board's SCHED / UNTIL numbers). */
    fun hm(ms: Long): String = Instant.ofEpochMilli(ms).atZone(zone).format(hm)

    /** "Oct 20" */
    fun monthDay(ms: Long): String = Instant.ofEpochMilli(ms).atZone(zone).format(md)

    /** Time of day in the phone's 12/24-hour preference, like the app's fmtT. */
    fun clock(c: Context, ms: Long): String = android.text.format.DateFormat.getTimeFormat(c).format(Date(ms))
}
