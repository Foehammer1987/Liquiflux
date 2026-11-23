package com.foehammer.console_app

import android.app.Activity
import android.provider.Settings
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The player's brightness gesture on a phone or tablet (services/screen_brightness.dart): it
 * sets this window's brightness only, never the system setting, and `reset` hands the window
 * back to the system's brightness when the player closes.
 */
class ScreenBrightness(private val activity: Activity) {
    companion object {
        const val CHANNEL = "liquiflux/brightness"
    }

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "get" -> {
                val own = activity.window.attributes.screenBrightness
                if (own >= 0f) return result.success(own.toDouble())
                val system = try {
                    Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS)
                } catch (e: Exception) {
                    128
                }
                result.success((system / 255.0).coerceIn(0.0, 1.0))
            }
            "set" -> {
                val value = (call.arguments as? Double ?: 0.5).coerceIn(0.0, 1.0)
                setWindow(value.toFloat())
                result.success(null)
            }
            "reset" -> {
                setWindow(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun setWindow(value: Float) {
        val attrs = activity.window.attributes
        attrs.screenBrightness = value
        activity.window.attributes = attrs
    }
}
