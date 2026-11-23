// Home-screen widget: the header (date, nav, DAY/WEEK, +) and the list of the
// day's departures, tasks and money. Buttons and ticks are handled here
// without opening the app; taps on rows open it there.
//
// Android 12+ gets the whole list inside one update (RemoteCollectionItems).
// The older adapter route is asynchronous on Android 17 (remote adapter
// conversion), which let a stale header land after a fresh one; one atomic
// update can't. Drawing happens on one background thread, so updates stay in
// order and never block the app or a broadcast.
package com.arunvijey.subwayboard.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.RemoteViews
import com.arunvijey.subwayboard.MainActivity
import com.arunvijey.subwayboard.QuickAddActivity
import com.arunvijey.subwayboard.R
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.Executors

class BoardWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val done = goAsync()
        refreshAll(context) { done.finish() }
    }

    // Resizing: the header and rows adapt to the new size.
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        val done = goAsync()
        refreshAll(context) { done.finish() }
    }

    override fun onEnabled(context: Context) = scheduleTick(context)

    override fun onDisabled(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(tickIntent(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_PREV -> WidgetStore.move(context, -step(context))
            ACTION_NEXT -> WidgetStore.move(context, step(context))
            ACTION_TODAY -> WidgetStore.goToday(context)
            ACTION_TOGGLE -> WidgetStore.toggleView(context)
            ACTION_ITEM -> return item(context, intent)
            ACTION_TICK, Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> Unit
            else -> return super.onReceive(context, intent)
        }
        val done = goAsync()
        refreshAll(context) { done.finish() }
    }

    /** A tap inside the list: a tick (applied in the background) or a row (opens the app). */
    private fun item(c: Context, i: Intent) {
        if (i.getStringExtra(EXTRA_ACT) == "fold") {
            WidgetStore.toggleEnded(c)
            val done = goAsync()
            return refreshAll(c) { done.finish() }
        }
        if (i.getStringExtra(EXTRA_ACT) != "tick") return openApp(c, i.getStringExtra(EXTRA_TYPE), i.getStringExtra(EXTRA_ID), i.getStringExtra(EXTRA_DAY))
        val task = i.getStringExtra(EXTRA_ID) ?: return
        val day = i.getStringExtra(EXTRA_DAY) ?: return
        WidgetActions.tick(c, task, day, i.getBooleanExtra(EXTRA_DONE, true))
        val done = goAsync()
        // Show the tick at once, then have the app (or the worker) apply it.
        refreshAll(c) { WidgetActions.dispatch(c) { done.finish() } }
    }

    companion object {
        const val ACTION_OPEN = "com.arunvijey.subwayboard.widget.OPEN"
        const val EXTRA_TYPE = "type" // event | day | add | task | money
        const val EXTRA_ID = "id"
        const val EXTRA_DAY = "day"
        const val EXTRA_ACT = "act" // open | tick | fold
        const val EXTRA_DONE = "done"

        private const val ACTION_PREV = "com.arunvijey.subwayboard.widget.PREV"
        private const val ACTION_NEXT = "com.arunvijey.subwayboard.widget.NEXT"
        private const val ACTION_TODAY = "com.arunvijey.subwayboard.widget.TODAY"
        private const val ACTION_TOGGLE = "com.arunvijey.subwayboard.widget.TOGGLE"
        private const val ACTION_TICK = "com.arunvijey.subwayboard.widget.TICK"
        private const val ACTION_ITEM = "com.arunvijey.subwayboard.widget.ITEM"

        private val MUTABLE = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        private val dayFmt = DateTimeFormatter.ofPattern("EEEE, MMM d", Locale.ENGLISH)
        private val monthDay = DateTimeFormatter.ofPattern("MMM d", Locale.ENGLISH)

        /** One drawing thread: updates land in the order they were asked for. */
        private val exec = Executors.newSingleThreadExecutor()
        private val main = Handler(Looper.getMainLooper())

        private fun step(c: Context) = if (WidgetStore.week(c)) 7L else 1L

        /**
         * Redraws every placed widget (in the background). Called when the app
         * pushes new data, on each tick, and after a button or tick. [after]
         * runs on the main thread once it's done.
         */
        fun refreshAll(c: Context, after: (() -> Unit)? = null) {
            val app = c.applicationContext
            exec.execute {
                try {
                    val manager = AppWidgetManager.getInstance(app)
                    val ids = manager.getAppWidgetIds(ComponentName(app, BoardWidgetProvider::class.java))
                    for (id in ids) render(app, manager, id)
                    if (ids.isNotEmpty()) scheduleTick(app)
                } catch (_: Exception) {
                } finally {
                    if (after != null) main.post(after)
                }
            }
        }

        /** Asks the launcher to place the widget (Android 8+). False when the launcher can't. */
        fun requestPin(c: Context): Boolean {
            val manager = AppWidgetManager.getInstance(c)
            if (Build.VERSION.SDK_INT < 26 || !manager.isRequestPinAppWidgetSupported) return false
            return manager.requestPinAppWidget(ComponentName(c, BoardWidgetProvider::class.java), null, null)
        }

        /** Width/height in dp the launcher gives this widget (portrait: min width, max height). */
        fun size(manager: AppWidgetManager, id: Int): Pair<Int, Int> {
            val o = manager.getAppWidgetOptions(id)
            return o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250) to o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 180)
        }

        private fun render(c: Context, manager: AppWidgetManager, id: Int) {
            val (w, h) = size(manager, id)
            if (Build.VERSION.SDK_INT >= 31) {
                // A week of rows is a lot of text bitmaps; if the launcher's memory cap
                // is hit, try again with fewer rows rather than show nothing.
                var cap = Int.MAX_VALUE
                while (true) {
                    try {
                        manager.updateAppWidget(id, views(c, id, w, h, cap))
                        return
                    } catch (e: IllegalArgumentException) {
                        if (cap <= 8) return
                        cap = if (cap == Int.MAX_VALUE) 40 else cap / 2
                    }
                }
            } else {
                manager.updateAppWidget(id, views(c, id, w, h, 0))
                @Suppress("DEPRECATION")
                manager.notifyAppWidgetViewDataChanged(id, R.id.list)
            }
        }

        /** Header + list. [cap] limits the rows (Android 12+); 0 = the list comes from the service. */
        private fun views(c: Context, id: Int, w: Int, h: Int, cap: Int): RemoteViews {
            val snap = WidgetStore.snapshot(c)
            val pal = Pal.of(c, snap?.theme ?: "system")
            val sel = WidgetStore.sel(c)
            val today = Time.today()
            val week = WidgetStore.week(c)
            val rv = RemoteViews(c.packageName, R.layout.widget_board)

            // Black body (the app's header color), then the board in the theme's color.
            rv.setInt(R.id.board_bg, "setColorFilter", pal.board)
            rv.setInt(R.id.board_rule, "setColorFilter", pal.rule)

            val title = if (week) {
                val end = sel.plusDays(6)
                if (end.month == sel.month) "${sel.format(monthDay)} – ${end.dayOfMonth}" else "${sel.format(monthDay)} – ${end.format(monthDay)}"
            } else {
                sel.format(dayFmt)
            }.uppercase(Locale.ENGLISH)
            // The board's big condensed date, shrunk to fit beside the add button.
            val titleMax = (Ink.dp(c, w.toFloat()) - Ink.dp(c, 16f * 2 + 40f + 8f)).toInt()
            var sp = 32f
            while (sp > 20f && Ink.width(c, title, Style(Ink.cond(c, 800), sp, -.01f)) > titleMax) sp -= 1f
            Ink.text(rv, R.id.title, c, title, Style(Ink.cond(c, 800), sp, -.01f), WHITE, titleMax)

            for (icon in listOf(R.id.btn_add_icon, R.id.btn_prev_icon, R.id.btn_next_icon)) rv.setInt(icon, "setColorFilter", WHITE)

            // Short widgets keep just the date and add button; narrow ones drop the toggle.
            rv.setViewVisibility(R.id.row_b, if (h >= 150) View.VISIBLE else View.GONE)
            rv.setViewVisibility(R.id.btn_today, if (sel != today && w >= 230) View.VISIBLE else View.GONE)
            rv.setImageViewBitmap(R.id.btn_today, Ink.pill(c, "TODAY", Style(Ink.cond(c, 800), 14f, .06f), YELLOW, BLACK, 14f, 34f, 17f))
            rv.setViewVisibility(R.id.toggle, if (w >= 200) View.VISIBLE else View.GONE)
            rv.setImageViewBitmap(R.id.toggle, Ink.segmented(c, listOf("DAY", "WEEK"), if (week) 1 else 0, 54f, 34f))

            if (cap > 0 && Build.VERSION.SDK_INT >= 31) {
                val rows = WidgetRows(c, w)
                val items = rows.build(sel, week).let { if (it.size > cap) it.take(cap) + Item.Msg("OPEN THE APP FOR THE REST", small = true) else it }
                val b = RemoteViews.RemoteCollectionItems.Builder().setViewTypeCount(ROW_TYPES).setHasStableIds(false)
                items.forEachIndexed { i, item -> b.addItem(i.toLong(), rows.view(item)) }
                rv.setRemoteAdapter(R.id.list, b.build())
            } else {
                // The data URI makes each widget's adapter intent distinct.
                val svc = Intent(c, BoardWidgetService::class.java).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                svc.data = Uri.parse(svc.toUri(Intent.URI_INTENT_SCHEME))
                @Suppress("DEPRECATION")
                rv.setRemoteAdapter(R.id.list, svc)
            }
            // Rows and ticks come back here; a row then opens the app, a tick is applied in the background.
            rv.setPendingIntentTemplate(R.id.list, broadcast(c, ACTION_ITEM, 3, mutable = true))

            rv.setOnClickPendingIntent(R.id.btn_prev, broadcast(c, ACTION_PREV, 11))
            rv.setOnClickPendingIntent(R.id.btn_next, broadcast(c, ACTION_NEXT, 12))
            rv.setOnClickPendingIntent(R.id.btn_today, broadcast(c, ACTION_TODAY, 13))
            rv.setOnClickPendingIntent(R.id.toggle, broadcast(c, ACTION_TOGGLE, 14))
            rv.setOnClickPendingIntent(R.id.btn_add, quickAdd(c))
            rv.setOnClickPendingIntent(R.id.title_box, open(c, 2, "day", sel.toString()))
            return rv
        }

        private fun broadcast(c: Context, action: String, code: Int, mutable: Boolean = false): PendingIntent = PendingIntent.getBroadcast(
            c, code, Intent(c, BoardWidgetProvider::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or (if (mutable) MUTABLE else PendingIntent.FLAG_IMMUTABLE),
        )

        private fun appIntent(c: Context, type: String?, id: String?, day: String?): Intent {
            val i = Intent(c, MainActivity::class.java)
                .setAction(ACTION_OPEN)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (type != null) i.putExtra(EXTRA_TYPE, type)
            if (id != null) i.putExtra(EXTRA_ID, id)
            if (day != null) i.putExtra(EXTRA_DAY, day)
            return i
        }

        /** Opens the app (header taps). */
        private fun open(c: Context, code: Int, type: String?, day: String?): PendingIntent =
            PendingIntent.getActivity(c, code, appIntent(c, type, null, day), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        /** A row was tapped: open the app on it. The widget tap lets this broadcast start it. */
        private fun openApp(c: Context, type: String?, id: String?, day: String?) {
            try {
                c.startActivity(appIntent(c, type, id, day))
            } catch (_: Exception) {
            }
        }

        /** The + : the quick-add sheet over the home screen, starting as a task. */
        private fun quickAdd(c: Context): PendingIntent = PendingIntent.getActivity(
            c, 1,
            Intent(c, QuickAddActivity::class.java)
                .putExtra(QuickAddActivity.EXTRA_MODE, "task")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        private fun tickIntent(c: Context): PendingIntent = broadcast(c, ACTION_TICK, 10)

        /**
         * Next redraw: every minute while something is live or starts within the
         * hour (so countdowns stay right), otherwise every 5 minutes, and always
         * at the next start/end. Inexact, so no special alarm permission.
         */
        private fun scheduleTick(c: Context) {
            val am = c.getSystemService(AlarmManager::class.java) ?: return
            val now = System.currentTimeMillis()
            var delay = 5 * 60_000L
            WidgetStore.snapshot(c)?.events?.forEach { e ->
                if (e.allDay) return@forEach
                if ((e.start <= now && e.end >= now) || (e.start > now && e.start - now <= 3_600_000L)) delay = minOf(delay, 60_000L)
                if (e.start > now) delay = minOf(delay, e.start - now + 1_000L)
                if (e.end > now) delay = minOf(delay, e.end - now + 1_000L)
            }
            am.setAndAllowWhileIdle(AlarmManager.RTC, now + maxOf(delay, 20_000L), tickIntent(c))
        }
    }
}
