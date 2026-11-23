package com.arunvijey.subwayboard

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Small platform calls every engine needs (the app, the widget's quick add
 * and its background worker). They used to come from the path_provider and
 * audioplayers plugins; these few lines replace both, with no JNI library.
 */
object AppChannels {
    fun register(c: Context, messenger: BinaryMessenger) {
        val app = c.applicationContext
        MethodChannel(messenger, "subwayboard/app").setMethodCallHandler { call, result ->
            when (call.method) {
                // Same folders path_provider returned, so existing data is found where it was.
                "docsDir" -> result.success(app.getDir("flutter", Context.MODE_PRIVATE).path)
                "externalDir" -> result.success(app.getExternalFilesDir(null)?.absolutePath)
                "chime" -> {
                    Chime.play(app, call.arguments == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}

/** The in-app chime: the same sounds the notification channels use (res/raw). */
private object Chime {
    private var player: MediaPlayer? = null
    private var focus: AudioFocusRequest? = null

    private val attrs: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    fun play(c: Context, boarding: Boolean) {
        stop(c)
        val am = c.getSystemService(AudioManager::class.java) ?: return
        val mp = try {
            MediaPlayer.create(c, if (boarding) R.raw.chime_boarding else R.raw.chime_departing, attrs, am.generateAudioSessionId())
        } catch (_: Exception) {
            null
        } ?: return
        // Music playing elsewhere just dips for the chime, then carries on.
        if (Build.VERSION.SDK_INT >= 26) {
            focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(attrs).build().also { am.requestAudioFocus(it) }
        }
        mp.setOnCompletionListener { stop(c) }
        player = mp
        mp.start()
    }

    private fun stop(c: Context) {
        player?.let {
            try {
                it.stop()
            } catch (_: Exception) {
            }
            it.release()
        }
        player = null
        if (Build.VERSION.SDK_INT >= 26) focus?.let { c.getSystemService(AudioManager::class.java)?.abandonAudioFocusRequest(it) }
        focus = null
    }
}
