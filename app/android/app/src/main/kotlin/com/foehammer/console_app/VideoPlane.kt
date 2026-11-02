package com.foehammer.console_app

import android.app.Activity
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Method
import kotlin.math.roundToInt

/**
 * The player's picture on a plain Android SurfaceView placed behind the whole Flutter UI,
 * which MainActivity renders transparently on 32-bit TVs. The hardware decoder draws into it
 * and the TV's display shows it directly, as in Plex's own app. Plezy, a Flutter and mpv
 * Plex client, plays the same 4K files on the 2019 Shield this way; through a Flutter
 * texture (0.9.5 to 0.9.7) or a hybrid-composition platform view (0.9.6) Android closed
 * Liquiflux as the 4K decoder started.
 *
 * mpv takes the surface as a JNI global reference (its --wid), made with the helper media_kit
 * uses, and reported to Dart over [CHANNEL] as `surface` {wid, width, height}; wid 0 means
 * the surface is gone.
 */
class VideoPlane(private val activity: Activity, private val channel: MethodChannel) : SurfaceHolder.Callback {
    companion object {
        const val CHANNEL = "liquiflux/video_plane"
        private const val TAG = "VideoPlane"
        private val handler = Handler(Looper.getMainLooper())
        private val newRef: Method
        private val deleteRef: Method

        init {
            val helper = Class.forName("com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper")
            newRef = helper.getDeclaredMethod("newGlobalObjectRef", Any::class.java).apply { isAccessible = true }
            deleteRef = helper.getDeclaredMethod("deleteGlobalObjectRef", Long::class.javaPrimitiveType).apply { isAccessible = true }
        }
    }

    private var box: FrameLayout? = null
    private var view: SurfaceView? = null
    private var wid = 0L
    private var surfaceWidth = 0
    private var surfaceHeight = 0

    /** The picture's width over its height; 0 fills the screen (Picture Size: Stretch). */
    private var aspect = 0.0

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> show()
            "aspect" -> {
                aspect = call.argument<Number>("aspect")?.toDouble() ?: 0.0
                layout()
            }
            "hide" -> hide()
            else -> return result.notImplemented()
        }
        result.success(null)
    }

    /**
     * Puts a black backdrop with the picture's surface under the Flutter view. If it is already
     * there (the next episode's player taking over), its surface goes to the new player.
     */
    private fun show() {
        if (box != null) {
            if (wid != 0L) send(wid, surfaceWidth, surfaceHeight)
            return
        }
        val content = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        val surface = SurfaceView(activity).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, Gravity.CENTER)
            // Below the window, which it shows through by clearing its own area there.
            setZOrderOnTop(false)
            setZOrderMediaOverlay(false)
            // The remote moves focus between Flutter's controls; the picture never takes it.
            isFocusable = false
            isFocusableInTouchMode = false
            holder.addCallback(this@VideoPlane)
        }
        val backdrop = FrameLayout(activity).apply {
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            // The bars beside a picture of another shape, and the screen before the first frame.
            setBackgroundColor(Color.BLACK)
            isFocusable = false
            addView(surface)
            addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> layout() }
        }
        content.addView(backdrop, 0)
        box = backdrop
        view = surface
        Log.i(TAG, "shown")
    }

    /** The decoder scales the picture to the whole surface, so the surface takes its shape. */
    private fun layout() {
        val backdrop = box ?: return
        val surface = view ?: return
        val w = backdrop.width
        val h = backdrop.height
        if (w <= 0 || h <= 0) return
        val (vw, vh) = when {
            aspect <= 0 -> w to h
            w.toDouble() / h > aspect -> (h * aspect).roundToInt() to h
            else -> w to (w / aspect).roundToInt()
        }
        val lp = surface.layoutParams as FrameLayout.LayoutParams
        if (lp.width == vw && lp.height == vh) return
        lp.width = vw
        lp.height = vh
        lp.gravity = Gravity.CENTER
        // Called from a layout pass, so the new size goes in on the next one.
        surface.post { surface.layoutParams = lp }
    }

    private fun hide() {
        val backdrop = box ?: return
        box = null
        view = null
        aspect = 0.0
        // Removing the view destroys its surface, which reports wid 0 to Dart.
        (backdrop.parent as? ViewGroup)?.removeView(backdrop)
        Log.i(TAG, "hidden")
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        release()
        wid = newRef.invoke(null, holder.surface) as Long
        Log.i(TAG, "surfaceCreated")
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        Log.i(TAG, "surfaceChanged ${width}x$height")
        surfaceWidth = width
        surfaceHeight = height
        send(wid, width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        Log.i(TAG, "surfaceDestroyed")
        send(0, 0, 0)
        release()
    }

    private fun send(ref: Long, width: Int, height: Int) {
        channel.invokeMethod("surface", mapOf("wid" to ref, "width" to width, "height" to height))
    }

    /** mpv may still hold the old surface for a moment, so its reference goes later. */
    private fun release() {
        val old = wid
        wid = 0
        if (old != 0L) handler.postDelayed({
            try {
                deleteRef.invoke(null, old)
            } catch (e: Throwable) {
                Log.e(TAG, "deleteGlobalObjectRef", e)
            }
        }, 5000)
    }
}
