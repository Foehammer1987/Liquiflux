package com.foehammer.console_app

import android.annotation.TargetApi
import android.app.Activity
import android.app.PictureInPictureParams
import android.os.Build
import android.util.Log
import android.util.Rational
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Picture-in-picture for the phone and tablet build (lib/services/pip.dart). Only that build's
 * manifest (src/mobile/AndroidManifest.xml) allows it; the Dart side never calls this on a TV.
 *
 * While a video plays, Dart says so ("playing"), and leaving the app with Home shrinks the
 * player into a floating window: by itself on Android 12 and later (auto-enter), from
 * [onUserLeaveHint] on 8 to 11. "enter" does it straight away (the player's button).
 */
class PictureInPicture(private val activity: Activity, private val channel: MethodChannel) {
    private var playing = false
    private var aspect: Rational = Rational(16, 9)

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return result.success(false)
        when (call.method) {
            "playing" -> {
                playing = call.argument<Boolean>("on") == true
                call.argument<Double>("aspect")?.let { aspect = rational(it) }
                update()
                result.success(true)
            }
            "enter" -> {
                call.argument<Double>("aspect")?.let { aspect = rational(it) }
                result.success(enter())
            }
            else -> result.notImplemented()
        }
    }

    /** Android allows ratios between 1:2.39 and 2.39:1. */
    private fun rational(a: Double): Rational {
        val clamped = a.coerceIn(1 / 2.39 + 0.01, 2.39 - 0.01)
        return Rational((clamped * 1000).toInt(), 1000)
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun params(): PictureInPictureParams {
        val b = PictureInPictureParams.Builder().setAspectRatio(aspect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setAutoEnterEnabled(playing)
            b.setSeamlessResizeEnabled(true)
        }
        return b.build()
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun update() {
        val p = params()
        try {
            activity.setPictureInPictureParams(p)
        } catch (e: Exception) {
            // The TV build's manifest doesn't allow picture-in-picture.
            Log.w("PictureInPicture", "params refused: ${e.message}")
        }
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun enter(): Boolean {
        val p = params()
        return try {
            activity.enterPictureInPictureMode(p)
        } catch (e: Exception) {
            Log.w("PictureInPicture", "enter refused: ${e.message}")
            false
        }
    }

    /** Home pressed while a video plays, on Android 8 to 11 (12 and later auto-enter). */
    fun onUserLeaveHint() {
        if (playing && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enter()
    }

    fun onModeChanged(inPip: Boolean) {
        channel.invokeMethod("changed", inPip)
    }

    companion object {
        const val CHANNEL = "liquiflux/pip"
    }
}
