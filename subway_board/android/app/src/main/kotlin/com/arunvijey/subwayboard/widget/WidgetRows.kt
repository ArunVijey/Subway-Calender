// The widget's list, drawn like the app: for each day its departures (events,
// with a tick when made with a task), the tasks due (TO DO) and the money
// logged. DAY shows one day in full; WEEK puts seven under day headings.
//
// Used two ways: Android 12+ gets every row at once (RemoteCollectionItems, one
// atomic update); older Android fetches rows through BoardWidgetService.
package com.arunvijey.subwayboard.widget

import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import com.arunvijey.subwayboard.R
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.roundToLong

sealed class Item {
    class Dep(val ev: WEvent, val day: LocalDate, val isToday: Boolean, val primary: Boolean, val next: Boolean, val ended: Boolean = false) : Item()
    class Day(val day: LocalDate, val summary: String) : Item()
    class Card(val ev: WEvent, val day: LocalDate) : Item()
    class Msg(val text: String, val small: Boolean = false, val tight: Boolean = false) : Item()
    /** [fold]: the heading's right side shows / hides today's ended departures. */
    class Head(val label: String, val count: Int?, val right: String?, val fold: Boolean = false) : Item()
    class Task(val t: WTask, val day: LocalDate, val done: Boolean, val overdue: Boolean) : Item()
    class Txn(val x: WTxn) : Item()
}

/** Distinct row layouts (for the collection's view type count). */
const val ROW_TYPES = 7

class WidgetRows(private val c: Context, widthDp: Int) {
    val snap: Snapshot? = WidgetStore.snapshot(c)
    private val pal = Pal.of(c, snap?.theme ?: "system")
    private val compact = widthDp < 200
    private val widthPx = dp(widthDp)
    private val now = System.currentTimeMillis()

    /** Ticks waiting for the app to apply them: drawn as already done. */
    private val pend = WidgetActions.pendingTicks(c)

    private val wd = DateTimeFormatter.ofPattern("EEE", Locale.ENGLISH)
    private val mon = DateTimeFormatter.ofPattern("MMM", Locale.ENGLISH)

    // The app's type, a touch smaller to suit a widget (board.dart / tasks.dart sizes in comments).
    private val sLetter by lazy { Style(Ink.cond(c, 800), 16f) } // 17
    private val sTitle by lazy { Style(Ink.cond(c, 700), 22f) } // 25
    private val sLoc by lazy { Style(Ink.inter(c, 500), 13f) } // 14
    private val sWhen by lazy { Style(Ink.cond(c, 700), 15f, .02f) } // 16
    private val sNum by lazy { Style(Ink.cond(c, 800), 44f, -.01f, tnum = true) } // 52
    private val sUnit by lazy { Style(Ink.cond(c, 800), 12f, .1f) } // 13
    private val sTag by lazy { Style(Ink.cond(c, 800), 12f, .1f) } // 13
    private val sDay by lazy { Style(Ink.cond(c, 800), 21f, .02f) } // 23
    private val sSmall by lazy { Style(Ink.cond(c, 800), 11f, .1f) } // 12
    private val sCardTitle by lazy { Style(Ink.cond(c, 700), 19f) } // 21
    private val sCardSub by lazy { Style(Ink.inter(c, 600), 13f) } // 13.5
    private val sCardLetter by lazy { Style(Ink.cond(c, 800), 13f) } // 13
    private val sMsg by lazy { Style(Ink.cond(c, 700), 14f, .06f) } // 14
    private val sHead by lazy { Style(Ink.cond(c, 800), 13f, .1f) } // GroupHead 14
    private val sTaskTitle by lazy { Style(Ink.cond(c, 700), 20f) } // 23
    private val sMeta by lazy { Style(Ink.inter(c, 600), 12.5f) } // 13.5
    private val sAmt by lazy { Style(Ink.cond(c, 800), 19f, tnum = true) } // 22
    private val sEmoji by lazy { Style(Ink.inter(c, 500), 16f) }

    // ---------- what's in the list ----------

    fun build(sel: LocalDate, week: Boolean): List<Item> {
        val s = snap ?: return listOf(Item.Msg("OPEN SUBWAY BOARD ONCE TO LOAD YOUR DAY"))
        val today = Time.today()
        return if (week) week(s, sel, today) else day(s, sel, today)
    }

    // Same rules as the board: today hides what has ended; yellow = first live, highlighted = next.
    private fun day(s: Snapshot, d: LocalDate, today: LocalDate): List<Item> {
        val d0 = Time.ms(d)
        val d1 = Time.ms(d.plusDays(1))
        if (!s.covers(d0, d1)) return listOf(Item.Msg("OPEN THE APP TO LOAD THIS DAY"))
        val isToday = d == today
        val all = s.events.filter { it.overlaps(d0, d1) }
        val allDay = all.filter { it.allDay }.sortedBy { it.start }
        val ended = if (isToday) all.filter { !it.allDay && it.end < now }.sortedBy { it.start } else emptyList()
        val timed = all.filter { !it.allDay && !(isToday && it.end < now) }.sortedBy { it.start }
        val liveIdx = if (isToday) timed.indexOfFirst { now >= it.start && now <= it.end } else -1
        val nextIdx = if (isToday) (if (liveIdx == 0) 1 else 0) else -1
        val showEnded = WidgetStore.showEnded(c)
        val out = mutableListOf<Item>()
        val todo = tasks(s, d, today)
        val money = txns(s, d)
        // A heading once there's more than departures to tell apart, or something to unfold.
        if (ended.isNotEmpty() || todo.isNotEmpty() || money.isNotEmpty()) {
            val fold = if (ended.isEmpty()) null else if (showEnded) "HIDE ENDED ▴" else "${ended.size} ENDED ▾"
            out += Item.Head("DEPARTURES", if (all.isEmpty()) null else all.size, fold, fold = fold != null)
        }
        allDay.forEach { out += Item.Dep(it, d, isToday, primary = false, next = false) }
        if (showEnded) ended.forEach { out += Item.Dep(it, d, isToday, primary = false, next = false, ended = true) }
        timed.forEachIndexed { i, e -> out += Item.Dep(e, d, isToday, primary = i == liveIdx, next = i == nextIdx) }

        if (out.none { it is Item.Dep }) {
            out += Item.Msg(if (isToday) "NO MORE DEPARTURES TODAY" else "NO SCHEDULED DEPARTURES", tight = todo.isNotEmpty() || money.isNotEmpty())
        }
        if (todo.isNotEmpty()) {
            out += Item.Head("TO DO", todo.count { !it.done }, null)
            out += todo
        }
        if (money.isNotEmpty()) {
            val (spent, inc) = s.days[d.toString()] ?: (null to null)
            out += Item.Head("MONEY", null, listOfNotNull(spent?.let { "$it SPENT" }, inc).joinToString("  ·  ").ifEmpty { null })
            out += money
        }
        return out
    }

    private fun week(s: Snapshot, start: LocalDate, today: LocalDate): List<Item> {
        val out = mutableListOf<Item>()
        for (i in 0L until 7L) {
            val d = start.plusDays(i)
            val d0 = Time.ms(d)
            val d1 = Time.ms(d.plusDays(1))
            if (!s.covers(d0, d1)) {
                out += Item.Msg("OPEN THE APP TO LOAD MORE DAYS")
                break
            }
            // Today drops what has already ended, like the day view.
            val isToday = d == today
            val evs = s.events.filter { it.overlaps(d0, d1) && !(isToday && !it.allDay && it.end < now && !WidgetStore.showEnded(c)) }
            val sorted = evs.filter { it.allDay }.sortedBy { it.start } + evs.filter { !it.allDay }.sortedBy { it.start }
            val todo = tasks(s, d, today)
            val money = txns(s, d)
            val spent = s.days[d.toString()]?.first
            val open = todo.count { !it.done }
            val summary = listOfNotNull(
                if (evs.isNotEmpty()) "${evs.size} ${if (evs.size == 1) "DEPARTURE" else "DEPARTURES"}" else null,
                if (open > 0) "$open TO DO" else null,
                spent,
            ).joinToString("  ·  ")
            out += Item.Day(d, summary)
            if (sorted.isEmpty() && todo.isEmpty() && money.isEmpty()) {
                out += Item.Msg(if (isToday) "NO MORE DEPARTURES TODAY" else "NO DEPARTURES", small = true)
            }
            sorted.forEach { out += Item.Card(it, d) }
            out += todo
            out += money
        }
        return out
    }

    /**
     * TO DO for [d], like AppState.tasksFor: open tasks due that day (today
     * also gets overdue ones), then the ones ticked off that day. A task on
     * the board as a timed event rides on that row instead, until today's
     * slot is over (then it comes back here so it isn't missed).
     */
    private fun tasks(s: Snapshot, d: LocalDate, today: LocalDate): List<Item.Task> {
        val ds = d.toString()
        val todayS = today.toString()
        val d0 = Time.ms(d)
        val d1 = Time.ms(d.plusDays(1))
        val linked = s.events.filter { it.task != null && it.overlaps(d0, d1) }
        fun riding(t: WTask) = t.due == ds && linked.any { it.task == t.id && !it.allDay && (d != today || it.end >= now) }
        val open = s.tasks
            .filter { !it.done && (it.due == ds || (d == today && it.due.isNotEmpty() && it.due < todayS)) && !riding(it) }
            .sortedWith(compareBy<WTask>({ it.due }, { it.time ?: 1440 }, { if (it.star) 0 else 1 }, { -it.created }))
        val done = s.tasks.filter { it.done && it.doneDay == ds && linked.none { e -> e.task == it.id } }
        return open.map { Item.Task(it, d, pend["${it.id}|$ds"] ?: false, it.due < todayS) } +
            done.map { Item.Task(it, d, pend["${it.id}|$ds"] ?: true, false) }
    }

    /** Money logged on [d], newest first. */
    private fun txns(s: Snapshot, d: LocalDate): List<Item.Txn> {
        val d0 = Time.ms(d)
        val d1 = Time.ms(d.plusDays(1))
        return s.txns.filter { it.at in d0 until d1 }.sortedByDescending { it.at }.map { Item.Txn(it) }
    }

    // ---------- rows ----------

    fun view(item: Item): RemoteViews = when (item) {
        is Item.Dep -> dep(item)
        is Item.Day -> dayHeader(item)
        is Item.Card -> card(item)
        is Item.Msg -> msg(item)
        is Item.Head -> head(item)
        is Item.Task -> task(item)
        is Item.Txn -> txn(item)
    }

    private fun open(type: String, id: String?, d: LocalDate?) = Intent()
        .putExtra(BoardWidgetProvider.EXTRA_ACT, "open")
        .putExtra(BoardWidgetProvider.EXTRA_TYPE, type)
        .putExtra(BoardWidgetProvider.EXTRA_ID, id)
        .putExtra(BoardWidgetProvider.EXTRA_DAY, d?.toString())

    private fun tick(task: String, d: LocalDate, done: Boolean) = Intent()
        .putExtra(BoardWidgetProvider.EXTRA_ACT, "tick")
        .putExtra(BoardWidgetProvider.EXTRA_ID, task)
        .putExtra(BoardWidgetProvider.EXTRA_DAY, d.toString())
        .putExtra(BoardWidgetProvider.EXTRA_DONE, done)
        // Distinct data per tick, so fill-ins never collapse into one another.
        .setData(android.net.Uri.parse("subwayboard://tick/$task/$d"))

    /** A linked event's tick state on [d], with any pending tick on top. */
    private fun linkedDone(ev: WEvent, d: LocalDate) = pend["${ev.task}|$d"] ?: ev.done

    /** Countdown number + unit, exactly as the board shows them. */
    private fun numbers(ev: WEvent, d0: Long, isToday: Boolean, ended: Boolean = false): Pair<String, String> = when {
        ended -> Time.hm(ev.end) to "ENDED"
        ev.allDay -> {
            val tot = ((ev.end - ev.start).toDouble() / Time.DAY).roundToLong()
            if (tot > 1) "${((d0 - ev.start).toDouble() / Time.DAY).roundToLong() + 1}/$tot" to "DAYS" else "ALL" to "DAY"
        }
        isToday -> {
            val live = now >= ev.start && now <= ev.end
            val m = max(1, ceil(((if (live) ev.end else ev.start) - now) / 60_000.0).toInt())
            val n = if (m >= 60) "${m / 60}:${(m % 60).toString().padStart(2, '0')}" else "$m"
            n to (if (live) "MIN LEFT" else if (m >= 60) "HR" else "MIN")
        }
        ev.start < d0 -> Time.hm(ev.end) to "UNTIL"
        else -> Time.hm(ev.start) to "SCHED"
    }

    private fun dep(it: Item.Dep): RemoteViews {
        val s = snap!!
        val rv = RemoteViews(c.packageName, R.layout.widget_row_dep)
        val ev = it.ev
        val line = s.line(ev.cat)
        val d0 = Time.ms(it.day)
        val live = it.isToday && !ev.allDay && now >= ev.start && now <= ev.end
        val primary = it.primary
        val linked = ev.task != null
        val ticked = linked && linkedDone(ev, it.day)
        val (n, u) = numbers(ev, d0, it.isToday, it.ended)
        val rowBg = if (primary) YELLOW else if (it.next) pal.rowNext else pal.board
        val fg = if (primary) BLACK else if (ticked || it.ended) pal.sub else pal.text
        val sub = if (primary) 0xFF1C1917.toInt() else pal.sub
        val num = if (primary) BLACK else if (ticked || it.ended) pal.sub else if (it.next) pal.nextNum else pal.text

        rv.setInt(R.id.row_bg, "setColorFilter", rowBg)
        // The live row breathes between yellow and bright yellow, like the board.
        rv.setViewVisibility(R.id.row_glow, if (primary) View.VISIBLE else View.GONE)
        rv.setInt(R.id.row_rule, "setColorFilter", pal.rule)

        // Made with a task: its tick leads the row (BoardRow does the same).
        rv.setViewVisibility(R.id.row_tick, if (linked) View.VISIBLE else View.GONE)
        rv.setViewPadding(R.id.row_inner, dp(if (linked) 7 else 16), dp(14), dp(16), dp(14))
        if (linked) {
            rv.setImageViewBitmap(R.id.row_tick, Ink.check(c, ticked, if (primary) BLACK else pal.ink(line.color), 24f))
            // A repeating task's past days stay done; tapping them just opens the app.
            if (ticked && ev.taskRepeats) rv.setOnClickFillInIntent(R.id.row_tick, open("event", ev.id, it.day))
            else rv.setOnClickFillInIntent(R.id.row_tick, tick(ev.task!!, it.day, !ticked))
        }

        // Live row: the badge becomes a black ring, like the board.
        rv.setViewVisibility(R.id.row_badge, if (primary) View.GONE else View.VISIBLE)
        rv.setViewVisibility(R.id.row_ring, if (primary) View.VISIBLE else View.GONE)
        rv.setInt(R.id.row_badge, "setColorFilter", line.color)
        Ink.text(rv, R.id.row_letter, c, line.label, sLetter, if (primary || line.darkText) BLACK else WHITE)

        // Text column gets what the tick, badge and countdown leave.
        val numW = max(Ink.width(c, n, sNum), Ink.width(c, u, sUnit))
        val textMax = widthPx - dp((if (linked) 7 + 42 + 2 else 16) + 38 + 14 + 14 + 16) - numW

        rv.setViewVisibility(R.id.row_live_box, if (live) View.VISIBLE else View.GONE)
        if (live) {
            val (tag, halo) = Ink.liveTag(c, sTag, if (primary) BLACK else YELLOW, if (primary) YELLOW else BLACK, if (primary) BLACK else YELLOW, 7f, 21f, 3f)
            rv.setImageViewBitmap(R.id.row_live, tag)
            rv.setImageViewBitmap(R.id.row_live_halo, halo)
        }

        Ink.text(rv, R.id.row_title, c, ev.title, sTitle, fg, textMax, strike = ticked)
        val showLoc = ev.loc.isNotEmpty() && !compact
        rv.setViewVisibility(R.id.row_loc, if (showLoc) View.VISIBLE else View.GONE)
        if (showLoc) Ink.text(rv, R.id.row_loc, c, ev.loc, sLoc, sub, textMax)
        val whenText = when {
            ev.allDay -> "All day"
            ev.start < d0 -> "Since ${Time.monthDay(ev.start)}"
            else -> Time.clock(c, ev.start)
        }
        val bill = if (ev.amt != null) " · ${ev.amt}${if (ticked) " paid" else ""}" else ""
        Ink.text(rv, R.id.row_when, c, (if (ev.repeating) "↻ " else "") + whenText + bill, sWhen, sub, textMax)

        Ink.text(rv, R.id.row_num, c, n, sNum, num, seam = true)
        Ink.text(rv, R.id.row_unit, c, u, sUnit, sub)

        val pb = if (!live) 0 else if (primary) R.id.row_pb_yellow_row else if (pal.light) R.id.row_pb_light else R.id.row_pb_dark
        for (id in listOf(R.id.row_pb_yellow_row, R.id.row_pb_dark, R.id.row_pb_light)) rv.setViewVisibility(id, if (id == pb) View.VISIBLE else View.GONE)
        if (pb != 0) rv.setProgressBar(pb, 1000, progress(ev), false)

        rv.setOnClickFillInIntent(R.id.row_root, open("event", ev.id, it.day))
        return rv
    }

    private fun dayHeader(it: Item.Day): RemoteViews {
        val rv = RemoteViews(c.packageName, R.layout.widget_row_day)
        val isToday = it.day == Time.today()
        val dayText = "${it.day.format(wd).uppercase(Locale.ENGLISH)} ${it.day.dayOfMonth}"
        val monText = it.day.format(mon).uppercase(Locale.ENGLISH)
        Ink.text(rv, R.id.dh_day, c, dayText, sDay, if (isToday && !pal.light) YELLOW else pal.text)
        Ink.text(rv, R.id.dh_mon, c, monText, sDay, pal.sub)
        rv.setViewVisibility(R.id.dh_today, if (isToday) View.VISIBLE else View.GONE)
        var used = Ink.width(c, dayText, sDay) + dp(6) + Ink.width(c, monText, sDay)
        if (isToday) {
            val pill = Ink.pill(c, "TODAY", sSmall, YELLOW, BLACK, 7f, 19f, 3f)
            rv.setImageViewBitmap(R.id.dh_today, pill)
            used += dp(9) + pill.width
        }
        rv.setViewVisibility(R.id.dh_count, if (it.summary.isNotEmpty()) View.VISIBLE else View.GONE)
        if (it.summary.isNotEmpty()) Ink.text(rv, R.id.dh_count, c, it.summary, sSmall, pal.sub, max(dp(40), widthPx - dp(18 * 2 + 12) - used))
        rv.setOnClickFillInIntent(R.id.row_root, open("day", null, it.day))
        return rv
    }

    // Agenda card: line color fill (tinted for all-day), yellow while ongoing, faded once over.
    private fun card(it: Item.Card): RemoteViews {
        val rv = RemoteViews(c.packageName, R.layout.widget_row_card)
        val ev = it.ev
        val line = snap!!.line(ev.cat)
        val d0 = Time.ms(it.day)
        val live = !ev.allDay && now >= ev.start && now <= ev.end
        val past = !ev.allDay && ev.end < now
        val onLine = if (line.darkText) BLACK else WHITE
        val linked = ev.task != null
        val ticked = linked && linkedDone(ev, it.day)

        var bg = when {
            live -> YELLOW
            ev.allDay -> blend(line.color, pal.board, if (pal.light) .14 else .16)
            else -> line.color
        }
        var fg = if (live) BLACK else if (ev.allDay) pal.text else onLine
        var badge = if (live || ev.allDay) line.color else blend(fg, line.color, .18)
        var letter = if (live || ev.allDay) onLine else fg
        if (past) {
            bg = blend(bg, pal.board, .45)
            fg = blend(fg, pal.board, .45)
            badge = blend(badge, pal.board, .45)
            letter = blend(letter, pal.board, .45)
        }
        val sub = blend(fg, bg, .82)

        val text = when {
            ev.allDay -> {
                val tot = ((ev.end - ev.start).toDouble() / Time.DAY).roundToInt()
                val w = if (tot > 1) "Day ${((d0 - ev.start).toDouble() / Time.DAY).roundToInt() + 1} of $tot" else "All day"
                if (ev.loc.isNotEmpty()) "$w · ${ev.loc}" else w
            }
            else -> {
                val w = if (ev.start < d0) "Until ${Time.clock(c, ev.end)}" else Time.clock(c, ev.start)
                if (ev.loc.isNotEmpty()) "$w at ${ev.loc}" else if (ev.start < d0) w else "$w – ${Time.clock(c, ev.end)}"
            }
        } + (if (ev.amt != null) " · ${ev.amt}${if (ticked) " paid" else ""}" else "")

        rv.setViewVisibility(R.id.card_tick, if (linked) View.VISIBLE else View.GONE)
        rv.setViewPadding(R.id.card_inner, dp(if (linked) 2 else 14), dp(if (linked) 4 else 11), dp(12), dp(if (linked) 5 else 12))
        if (linked) {
            rv.setImageViewBitmap(R.id.card_tick, Ink.check(c, ticked, fg, 22f))
            if (ticked && ev.taskRepeats) rv.setOnClickFillInIntent(R.id.card_tick, open("event", ev.id, it.day))
            else rv.setOnClickFillInIntent(R.id.card_tick, tick(ev.task!!, it.day, !ticked))
        }

        val tag = if (live) Ink.liveTag(c, sSmall, BLACK, YELLOW, BLACK, 6f, 19f, 3f) else null
        val textMax = widthPx - dp(14 * 2 + (if (linked) 2 + 40 else 14) + 12 + 10 + 26)
        rv.setInt(R.id.card_bg, "setColorFilter", bg)
        rv.setViewVisibility(R.id.card_glow, if (live) View.VISIBLE else View.GONE)
        rv.setViewVisibility(R.id.card_live_box, if (tag != null) View.VISIBLE else View.GONE)
        if (tag != null) {
            rv.setImageViewBitmap(R.id.card_live, tag.first)
            rv.setImageViewBitmap(R.id.card_live_halo, tag.second)
        }
        Ink.text(rv, R.id.card_title, c, ev.title, sCardTitle, fg, textMax - (if (tag != null) tag.first.width - dp(8) else 0), strike = ticked)
        Ink.text(rv, R.id.card_sub, c, (if (ev.repeating) "↻ " else "") + text, sCardSub, sub, textMax)
        rv.setInt(R.id.card_badge, "setColorFilter", badge)
        Ink.text(rv, R.id.card_letter, c, line.label, sCardLetter, letter)
        rv.setViewVisibility(R.id.card_pb, if (live) View.VISIBLE else View.GONE)
        if (live) rv.setProgressBar(R.id.card_pb, 1000, progress(ev), false)
        rv.setOnClickFillInIntent(R.id.row_root, open("event", ev.id, it.day))
        return rv
    }

    // Big centered message, or (small) the outlined "NO DEPARTURES" slot of the week view.
    private fun msg(it: Item.Msg): RemoteViews {
        val rv = RemoteViews(c.packageName, R.layout.widget_row_msg)
        Ink.text(rv, R.id.msg, c, it.text, sMsg, if (it.small) blend(pal.sub, pal.board, .8) else pal.sub)
        rv.setViewVisibility(R.id.msg_box, if (it.small) View.VISIBLE else View.GONE)
        rv.setInt(R.id.msg_box, "setColorFilter", pal.rule)
        when {
            it.small -> rv.setViewPadding(R.id.msg_root, dp(14), 0, dp(14), dp(8))
            it.tight -> rv.setViewPadding(R.id.msg_root, dp(14), dp(26), dp(14), dp(18))
            else -> rv.setViewPadding(R.id.msg_root, dp(14), dp(40), dp(14), dp(40))
        }
        return rv
    }

    private fun head(it: Item.Head): RemoteViews {
        val rv = RemoteViews(c.packageName, R.layout.widget_row_head)
        Ink.text(rv, R.id.head_label, c, it.label, sHead, pal.sub)
        rv.setViewVisibility(R.id.head_count, if (it.count != null) View.VISIBLE else View.GONE)
        if (it.count != null) Ink.text(rv, R.id.head_count, c, "${it.count}", sHead, blend(pal.sub, pal.board, .6))
        rv.setViewVisibility(R.id.head_right, if (it.right != null) View.VISIBLE else View.GONE)
        if (it.right != null) Ink.text(rv, R.id.head_right, c, it.right, sHead, if (it.fold) pal.text else pal.sub)
        if (it.fold) rv.setOnClickFillInIntent(R.id.row_root, Intent().putExtra(BoardWidgetProvider.EXTRA_ACT, "fold"))
        return rv
    }

    private fun task(it: Item.Task): RemoteViews {
        val s = snap!!
        val rv = RemoteViews(c.packageName, R.layout.widget_row_task)
        val t = it.t
        val line = s.line(t.cat)
        val done = it.done
        rv.setInt(R.id.row_bg, "setColorFilter", pal.board)
        rv.setInt(R.id.row_rule, "setColorFilter", pal.rule)
        rv.setImageViewBitmap(R.id.task_tick, Ink.check(c, done, pal.ink(line.color), 24f))
        // A done copy of a repeating task can't be un-ticked here (it would come back as a duplicate).
        if (done && (t.noUndo || (t.repeating && !t.done))) rv.setOnClickFillInIntent(R.id.task_tick, open("task", t.id, it.day))
        else rv.setOnClickFillInIntent(R.id.task_tick, tick(t.id, it.day, !done))

        val amtW = if (t.amt != null) Ink.width(c, t.amt, sAmt) + dp(10) else 0
        val starW = if (t.star && !done) dp(24) else 0
        val textMax = widthPx - dp(7 + 42 + 2 + 16) - amtW - starW
        Ink.text(rv, R.id.task_title, c, t.title, sTaskTitle, if (done) pal.sub else pal.text, textMax, strike = done)

        // Meta like TaskRow: when (red if overdue) · line · repeat.
        val parts = mutableListOf<String>()
        val whenText = when {
            done -> "Done"
            it.overdue -> overdueLabel(t)
            t.time != null -> Time.clock(c, Time.ms(it.day) + t.time * 60_000L)
            else -> ""
        }
        if (whenText.isNotEmpty()) parts += whenText
        if (line.name.isNotEmpty()) parts += line.name
        if (t.repeating) parts += "↻"
        val meta = parts.joinToString("  ·  ")
        rv.setViewVisibility(R.id.task_meta, if (meta.isNotEmpty()) View.VISIBLE else View.GONE)
        if (meta.isNotEmpty()) Ink.text(rv, R.id.task_meta, c, meta, sMeta, if (it.overdue && !done) pal.red else pal.sub, textMax)

        rv.setViewVisibility(R.id.task_amt, if (t.amt != null) View.VISIBLE else View.GONE)
        if (t.amt != null) Ink.text(rv, R.id.task_amt, c, t.amt, sAmt, if (done) pal.sub else pal.text)
        rv.setViewVisibility(R.id.task_star, if (t.star && !done) View.VISIBLE else View.GONE)
        rv.setOnClickFillInIntent(R.id.row_root, open("task", t.id, it.day))
        return rv
    }

    /** "Yesterday 17:00", "Thu", "Nov 12": how late an overdue task is. */
    private fun overdueLabel(t: WTask): String {
        val due = try {
            LocalDate.parse(t.due)
        } catch (_: Exception) {
            return "Overdue"
        }
        val days = Time.today().toEpochDay() - due.toEpochDay()
        val d = when {
            days == 1L -> "Yesterday"
            days < 7 -> due.format(DateTimeFormatter.ofPattern("EEE", Locale.ENGLISH))
            else -> due.format(DateTimeFormatter.ofPattern("MMM d", Locale.ENGLISH))
        }
        return if (t.time != null) "$d ${Time.clock(c, Time.ms(due) + t.time * 60_000L)}" else d
    }

    private fun txn(it: Item.Txn): RemoteViews {
        val rv = RemoteViews(c.packageName, R.layout.widget_row_txn)
        val x = it.x
        rv.setInt(R.id.row_bg, "setColorFilter", pal.board)
        rv.setInt(R.id.row_rule, "setColorFilter", pal.rule)
        rv.setInt(R.id.txn_disc, "setColorFilter", pal.btn)
        Ink.text(rv, R.id.txn_emoji, c, x.emoji, sEmoji, pal.text)
        val amtW = Ink.width(c, x.amt, sAmt) + dp(10)
        val textMax = widthPx - dp(16 + 34 + 12 + 16) - amtW
        Ink.text(rv, R.id.txn_title, c, x.title, sTaskTitle, pal.text, textMax)
        Ink.text(rv, R.id.txn_meta, c, "${x.cat}  ·  ${Time.clock(c, x.at)}", sMeta, pal.sub, textMax)
        Ink.text(rv, R.id.txn_amt, c, x.amt, sAmt, if (x.plus) pal.green else pal.text)
        rv.setOnClickFillInIntent(R.id.row_root, open("money", x.id, Time.date(x.at)))
        return rv
    }

    private fun progress(ev: WEvent) = (((now - ev.start).toDouble() / max(1L, ev.end - ev.start)) * 1000).toInt().coerceIn(0, 1000)

    private fun dp(v: Int) = (v * c.resources.displayMetrics.density).roundToInt()
}
