package com.arunvijey.subwayboard

import com.arunvijey.subwayboard.widget.WidgetActions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The widget's + : the app's quick-add sheet on its own, over the home screen
 * (a transparent window running the Dart `quickAddMain`). It never writes the
 * data: what's added is queued for the app, or the widget's worker, to apply.
 */
class QuickAddActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName() = "quickAddMain"

    override fun getBackgroundMode() = FlutterActivityLaunchConfigs.BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppChannels.register(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "subwayboard/widget").setMethodCallHandler { call, result ->
            when (call.method) {
                "quickMode" -> result.success(intent.getStringExtra(EXTRA_MODE))
                "enqueue" -> {
                    WidgetActions.enqueue(this, call.arguments as String)
                    WidgetActions.dispatch(applicationContext)
                    result.success(null)
                }
                "update", "takeLaunch", "idle", "ackActions" -> result.success(null)
                "peekActions" -> result.success(emptyList<String>())
                else -> result.notImplemented()
            }
        }
    }

    override fun finish() {
        super.finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }

    companion object {
        const val EXTRA_MODE = "mode"
    }
}
