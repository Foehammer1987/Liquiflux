package com.foehammer.console_app

import android.accessibilityservice.AccessibilityService
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Lets the sleep timer put the TV to sleep (lib/services/tv_sleep.dart). An app can't turn
 * the screen off by itself, and Android TV has no device admin (the 2019 Shield lacks the
 * feature), so this is an accessibility service whose only use is the "lock screen" action
 * (Android 9 and up), which sleeps the TV. On a Shield, sleeping also turns the TV off over
 * HDMI-CEC when that's on. It reads nothing on screen and handles no events.
 *
 * Switched on once under Settings > Device Preferences > Accessibility, or from adb (keep
 * any services already in the list, colon-separated):
 * `adb shell settings put secure enabled_accessibility_services com.foehammer.liquiflux/com.foehammer.console_app.SleepService`
 */
class SleepService : AccessibilityService() {
    companion object {
        const val CHANNEL = "liquiflux/sleep"

        /** Set while Android has the service connected, which is what switched on means. */
        @Volatile
        var running: SleepService? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        running = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        running = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        running = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    /** Answers the channel for [activity]. */
    class Channel(private val activity: Activity) {
        fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "allowed" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && running != null)
                "ask" -> result.success(openSettings())
                "now" -> result.success(sleepNow())
                else -> result.notImplemented()
            }
        }

        /**
         * The accessibility screen, where "Liquiflux sleep timer" is switched on. On the Shield the
         * plain ACTION_ACCESSIBILITY_SETTINGS goes to a framework stub ("You don't have an app that
         * can do this") without failing, so the TV Settings app is asked by name first, then its
         * main screen (the person goes on to Device Preferences > Accessibility).
         */
        private fun openSettings(): Boolean {
            val tv = "com.android.tv.settings"
            val tries = listOf(
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).setPackage(tv),
                Intent().setClassName(tv, "$tv.accessibility.AccessibilityActivity"),
                Intent(Settings.ACTION_SETTINGS).setPackage(tv),
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS),
            )
            for (intent in tries) {
                try {
                    activity.startActivity(intent)
                    return true
                } catch (e: ActivityNotFoundException) {
                } catch (e: SecurityException) {
                }
            }
            return false
        }

        private fun sleepNow(): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
            val service = running ?: return false
            val ok = service.performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
            if (!ok) Log.w("SleepService", "lock screen action refused")
            return ok
        }
    }
}
