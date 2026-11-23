// What's done on the home-screen widget (ticks, quick adds) and who applies it.
//
// Actions wait in a queue in SharedPreferences until a copy of the app has
// applied and saved them: the open app if its engine is alive, otherwise a
// short-lived background engine ([Worker]) running the Dart `widgetWorker`.
// Only one of the two ever writes the data. Applying is idempotent on the
// Dart side, so an action applied twice (the app closed before acking) is
// harmless. Until then the widget draws pending ticks as already done.
package com.arunvijey.subwayboard.widget

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.arunvijey.subwayboard.AppChannels
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

object WidgetActions {
    private const val PREFS = "subwayboard_widget"
    private const val KEY = "actions"

    /** The open app's widget channel, while its engine is alive (main thread only). */
    var main: MethodChannel? = null

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun load(c: Context): JSONArray = try {
        JSONArray(prefs(c).getString(KEY, "[]"))
    } catch (_: Exception) {
        JSONArray()
    }

    /** Adds an action (JSON object text); stamps it with an id and the time it was made. */
    @Synchronized
    fun enqueue(c: Context, json: String) {
        val o = JSONObject(json)
        if (!o.has("aid")) o.put("aid", UUID.randomUUID().toString())
        if (!o.has("at")) o.put("at", System.currentTimeMillis())
        val all = load(c).put(o)
        prefs(c).edit().putString(KEY, all.toString()).commit()
    }

    /** A tick (or un-tick) of [task] as seen on [day]. */
    fun tick(c: Context, task: String, day: String, done: Boolean) =
        enqueue(c, JSONObject().put("type", "tick").put("task", task).put("day", day).put("done", done).toString())

    @Synchronized
    fun peek(c: Context): List<String> {
        val a = load(c)
        return (0 until a.length()).map { a.getJSONObject(it).toString() }
    }

    @Synchronized
    fun ack(c: Context, ids: Collection<String>) {
        val a = load(c)
        val keep = JSONArray()
        for (i in 0 until a.length()) {
            val o = a.getJSONObject(i)
            if (o.optString("aid") !in ids) keep.put(o)
        }
        prefs(c).edit().putString(KEY, keep.toString()).commit()
    }

    /** Ticks not applied yet: "task|day" to the state they were set to. Later ones win. */
    @Synchronized
    fun pendingTicks(c: Context): Map<String, Boolean> {
        val a = load(c)
        val out = HashMap<String, Boolean>()
        for (i in 0 until a.length()) {
            val o = a.getJSONObject(i)
            if (o.optString("type") == "tick") out["${o.optString("task")}|${o.optString("day")}"] = o.optBoolean("done")
        }
        return out
    }

    /**
     * Gets the queue applied: by the open app, or by a background worker.
     * [done] runs (on the main thread) once that's handed over or finished.
     */
    fun dispatch(c: Context, done: (() -> Unit)? = null) {
        Handler(Looper.getMainLooper()).post {
            val m = main
            if (m != null) {
                m.invokeMethod("kick", null)
                done?.invoke()
            } else {
                Worker.kick(c.applicationContext, done)
            }
        }
    }
}

/**
 * A headless Flutter engine that applies the widget's queue when the app
 * isn't open. Lives for a few seconds after its last batch, then goes away.
 */
object Worker {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private val waiters = mutableListOf<() -> Unit>()
    private val h = Handler(Looper.getMainLooper())
    private val stop = Runnable { shutdown() }

    /** Main thread only. */
    fun kick(app: Context, done: (() -> Unit)?) {
        if (done != null) waiters += done
        // Never let a stuck engine keep the process (or a receiver) hanging.
        h.removeCallbacks(stop)
        h.postDelayed(stop, 25_000)
        h.postDelayed({ release() }, 9_000)
        channel?.let {
            it.invokeMethod("kick", null)
            return
        }
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(app)
            loader.ensureInitializationComplete(app, null)
            val e = FlutterEngine(app)
            AppChannels.register(app, e.dartExecutor.binaryMessenger)
            channel = MethodChannel(e.dartExecutor.binaryMessenger, "subwayboard/widget").apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "update" -> {
                            WidgetStore.saveSnapshot(app, call.arguments as String)
                            BoardWidgetProvider.refreshAll(app)
                            result.success(null)
                        }
                        "peekActions" -> result.success(WidgetActions.peek(app))
                        "ackActions" -> {
                            @Suppress("UNCHECKED_CAST")
                            WidgetActions.ack(app, (call.arguments as? List<String>) ?: emptyList())
                            BoardWidgetProvider.refreshAll(app)
                            result.success(null)
                        }
                        "idle" -> {
                            result.success(null)
                            release()
                            h.removeCallbacks(stop)
                            h.postDelayed(stop, 15_000)
                        }
                        "takeLaunch", "quickMode" -> result.success(null)
                        else -> result.notImplemented()
                    }
                }
            }
            engine = e
            e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "widgetWorker"))
        } catch (_: Exception) {
            shutdown()
        }
    }

    /** Lets whoever's waiting (a widget broadcast) finish. */
    private fun release() {
        val w = waiters.toList()
        waiters.clear()
        w.forEach { it() }
    }

    /** Main thread only. Also called when the app opens: from then on it applies the queue. */
    fun shutdown() {
        h.removeCallbacks(stop)
        release()
        channel = null
        engine?.destroy()
        engine = null
    }
}
