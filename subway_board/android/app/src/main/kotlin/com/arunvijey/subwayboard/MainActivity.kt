package com.arunvijey.subwayboard

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.os.Bundle
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import com.arunvijey.subwayboard.widget.BoardWidgetProvider
import com.arunvijey.subwayboard.widget.WidgetActions
import com.arunvijey.subwayboard.widget.WidgetStore
import com.arunvijey.subwayboard.widget.Worker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter app and bridges the home-screen widget: Dart pushes a
 * snapshot of upcoming events, and widget taps come back as launch requests.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** The widget tap that started the app, until Dart asks for it. */
    private var pending: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppChannels.register(this, flutterEngine.dartExecutor.binaryMessenger)
        pending = launchOf(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "subwayboard/widget").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        // Unchanged data: don't make the widget reload its list.
                        if (WidgetStore.saveSnapshot(this@MainActivity, call.arguments as String)) BoardWidgetProvider.refreshAll(this@MainActivity)
                        result.success(null)
                    }
                    "takeLaunch" -> {
                        result.success(pending)
                        pending = null
                    }
                    "pin" -> result.success(BoardWidgetProvider.requestPin(this@MainActivity))
                    // Ticks and quick adds made on the widget, applied by this app while it's open.
                    "peekActions" -> result.success(WidgetActions.peek(this@MainActivity))
                    "ackActions" -> {
                        @Suppress("UNCHECKED_CAST")
                        WidgetActions.ack(this@MainActivity, (call.arguments as? List<String>) ?: emptyList())
                        BoardWidgetProvider.refreshAll(this@MainActivity)
                        result.success(null)
                    }
                    "idle", "quickMode" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
        }
        // From now on this engine owns the data: the widget's background worker stops.
        Worker.shutdown()
        WidgetActions.main = channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "subwayboard/backup").setMethodCallHandler { call, result ->
            when (call.method) {
                // Lets the user choose (or create) the backup file once; access is kept across restarts.
                "pick" -> {
                    backupPick?.success(null)
                    backupPick = result
                    val i = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "subway-board-backup.json")
                    }
                    try {
                        @Suppress("DEPRECATION")
                        startActivityForResult(i, PICK_BACKUP)
                    } catch (e: Exception) {
                        backupPick = null
                        result.error("pick", e.message, null)
                    }
                }
                // Overwrites the chosen file, off the main thread (Drive can be slow).
                "write" -> {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    val bytes = (call.argument<String>("text") ?: "").toByteArray()
                    Thread {
                        try {
                            val out = try {
                                contentResolver.openOutputStream(uri, "wt")
                            } catch (_: Exception) {
                                contentResolver.openOutputStream(uri, "w")
                            }
                            out!!.use { it.write(bytes) }
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("write", e.message ?: "could not write", null) }
                        }
                    }.start()
                }
                "check" -> {
                    val uri = call.argument<String>("uri")
                    result.success(contentResolver.persistedUriPermissions.any { it.uri.toString() == uri && it.isWritePermission })
                }
                else -> result.notImplemented()
            }
        }
    }

    private var backupPick: MethodChannel.Result? = null

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (WidgetActions.main === channel) WidgetActions.main = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Deprecated("FlutterActivity has no activity-result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_BACKUP) return
        val r = backupPick
        backupPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            r?.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        } catch (_: Exception) {
        }
        var name = uri.lastPathSegment ?: "backup"
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) name = it.getString(0) }
        } catch (_: Exception) {
        }
        r?.success(mapOf("uri" to uri.toString(), "name" to name))
    }

    companion object {
        private const val PICK_BACKUP = 4711
    }

    /**
     * Back on the board sends the app to the background instead of finishing
     * it, so the Flutter engine stays alive and reopening (from the widget or
     * the icon) is an instant resume, not a cold start.
     *
     * Android 13+ delivers Back only to registered callbacks (Android 16 with
     * target 36 no longer calls onBackPressed). Flutter unregisters its own
     * callback when the board can't go back, and Android's default would then
     * finish a task the widget started. This fallback sits underneath: Flutter
     * re-registers on top whenever the app needs Back itself (closing the form).
     */
    private val toBackground: Any? = if (Build.VERSION.SDK_INT >= 33) OnBackInvokedCallback { moveTaskToBack(true) } else null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, toBackground as OnBackInvokedCallback)
        }
    }

    // Older Android: Back reaches Flutter, which ends here when the board can't pop.
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

    // App already running: a widget tap arrives here.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val launch = launchOf(intent) ?: return
        channel?.invokeMethod("launch", launch)
    }

    /** Reads a widget tap once; the action is cleared so a recreated activity doesn't replay it. */
    private fun launchOf(i: Intent?): Map<String, String?>? {
        if (i?.action != BoardWidgetProvider.ACTION_OPEN) return null
        val m = mapOf(
            "type" to i.getStringExtra(BoardWidgetProvider.EXTRA_TYPE),
            "id" to i.getStringExtra(BoardWidgetProvider.EXTRA_ID),
            "day" to i.getStringExtra(BoardWidgetProvider.EXTRA_DAY),
        )
        i.action = Intent.ACTION_MAIN
        return m
    }
}
