package com.foehammer.console_app

import android.app.Activity
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Match Frame Rate (lib/services/display_match.dart): switches the TV's output to the mode
 * Dart picked for a video (23.976 Hz for film, 50 for PAL...) through the window's
 * preferredDisplayModeId, as Kodi and Plex's own app do, and back to the TV's own choice
 * (mode 0) afterwards. Only this window asks, so Android puts the TV's mode back by itself
 * whenever another app comes to the front or Liquiflux closes.
 *
 * Calls on [CHANNEL]:
 * - `modes`: {current: id, modes: [{id, width, height, refreshRate}]}, physical sizes.
 * - `set` {id}: asks for that mode; answers true once the display reports it (HDMI may take a
 *   moment more to show a picture), false if it hadn't after [TIMEOUT_MS] or the id is unknown.
 * - `restore`: back to the TV's own mode, answered at once.
 */
class DisplayModes(private val activity: Activity) {
    companion object {
        const val CHANNEL = "liquiflux/display"
        private const val TAG = "DisplayModes"
        private const val TIMEOUT_MS = 5000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private val displays = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

    /** The switch still waiting for the display, answered when it lands or times out. */
    private var pending: Pending? = null

    private inner class Pending(val id: Int, val result: MethodChannel.Result) : DisplayManager.DisplayListener, Runnable {
        private var done = false

        fun start() {
            displays.registerDisplayListener(this, handler)
            handler.postDelayed(this, TIMEOUT_MS)
        }

        fun finish(ok: Boolean) {
            if (done) return
            done = true
            displays.unregisterDisplayListener(this)
            handler.removeCallbacks(this)
            if (pending === this) pending = null
            Log.i(TAG, if (ok) "now ${describe(display()?.mode)}" else "mode $id didn't come in time")
            result.success(ok)
        }

        override fun onDisplayChanged(displayId: Int) {
            if (display()?.displayId == displayId && display()?.mode?.modeId == id) finish(true)
        }

        override fun onDisplayAdded(displayId: Int) {}
        override fun onDisplayRemoved(displayId: Int) {}

        /** The timeout. */
        override fun run() = finish(display()?.mode?.modeId == id)
    }

    @Suppress("DEPRECATION")
    private fun display(): Display? = activity.windowManager.defaultDisplay

    private fun describe(m: Display.Mode?) = if (m == null) "none" else "${m.physicalWidth}x${m.physicalHeight}@${m.refreshRate}"

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "modes" -> {
                val d = display() ?: return result.success(null)
                result.success(
                    mapOf(
                        "current" to d.mode.modeId,
                        "modes" to d.supportedModes.map {
                            mapOf("id" to it.modeId, "width" to it.physicalWidth, "height" to it.physicalHeight, "refreshRate" to it.refreshRate.toDouble())
                        },
                    ),
                )
            }
            "set" -> set(call.argument<Int>("id") ?: 0, result)
            "restore" -> {
                pending?.finish(false)
                apply(0)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun set(id: Int, result: MethodChannel.Result) {
        val d = display()
        if (d == null || d.supportedModes.none { it.modeId == id }) return result.success(false)
        pending?.finish(false)
        if (d.mode.modeId == id) {
            apply(id)
            return result.success(true)
        }
        Log.i(TAG, "${describe(d.mode)} -> ${describe(d.supportedModes.first { it.modeId == id })}")
        val p = Pending(id, result)
        pending = p
        p.start()
        apply(id)
    }

    private fun apply(id: Int) {
        val window = activity.window ?: return
        val attrs = window.attributes
        if (attrs.preferredDisplayModeId == id) return
        attrs.preferredDisplayModeId = id
        window.attributes = attrs
    }

    fun dispose() {
        pending?.finish(false)
    }
}
