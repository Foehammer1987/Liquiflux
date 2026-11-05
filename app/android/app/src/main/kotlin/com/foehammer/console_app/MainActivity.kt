package com.foehammer.console_app

import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.os.Process
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** A 32-bit app (isLowMemoryTv in platform.dart): the 2019 Shield, Fire TV sticks. */
    private val lowMemory = !Process.is64Bit()

    private var textureView: FlutterTextureView? = null
    private var started = false
    private var reconnectPending = false
    private var updater: AppUpdater? = null
    private var displayModes: DisplayModes? = null

    /**
     * Measuring switches for one launch, from adb (services/probe.dart):
     * `adb shell am start -n com.foehammer.liquiflux/com.foehammer.console_app.Probe --es probe surface`
     *
     * They play titles and join rooms by themselves, so another app on the TV must not be able
     * to set them: a release build only takes them through the Probe alias, which needs the
     * DUMP permission that adb's shell has and ordinary apps can't get. A debug build also
     * takes them on MainActivity.
     */
    private val probe: String by lazy {
        val extra = intent?.getStringExtra("probe").orEmpty()
        val viaAlias = intent?.component?.className == PROBE_ALIAS
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (extra.isEmpty() || viaAlias || debuggable) extra else {
            Log.w("MainActivity", "ignoring probe switches not given through the Probe alias")
            ""
        }
    }

    /** The probe's `surface`: Flutter on its own surface as before 0.9.9, to measure the TextureView. */
    private val ownSurface get() = probe.split(',').contains("surface")

    // On 32-bit TVs Flutter draws into a transparent TextureView so the picture's SurfaceView
    // (VideoPlane) can sit underneath it, as Plezy does. Elsewhere Flutter keeps its own surface.
    override fun getRenderMode(): RenderMode = if (lowMemory && !ownSurface) RenderMode.texture else super.getRenderMode()

    override fun getTransparencyMode(): TransparencyMode = if (lowMemory && !ownSurface) TransparencyMode.transparent else super.getTransparencyMode()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Flutter swaps the launch theme for NormalTheme (black) here, well before its first frame,
        // which flashed black between the launch screen and the intro. Keep the launch screen's
        // dark grey until the intro is over; then lib/ui/intro.dart asks for black back ("plain")
        // for video.
        window.setBackgroundDrawableResource(R.drawable.launch_background)
    }

    override fun onFlutterTextureViewCreated(flutterTextureView: FlutterTextureView) {
        super.onFlutterTextureViewCreated(flutterTextureView)
        textureView = flutterTextureView
    }

    override fun onStop() {
        started = false
        reconnectPending = textureView != null
        super.onStop()
    }

    override fun onStart() {
        super.onStart()
        started = true
        reconnectSurface()
    }

    /**
     * Some TVs keep a TextureView "available" through standby while dropping its surface, which
     * leaves the app black on waking. Swapping Flutter's surface out and back in redraws it.
     * The same fix Plezy needed for its TextureView on TVs.
     */
    private fun reconnectSurface() {
        val view = textureView ?: return
        view.post {
            if (!started || !reconnectPending || view !== textureView || !view.isAttachedToWindow || !view.isAvailable) return@post
            reconnectPending = false
            Log.i("MainActivity", "reconnecting Flutter's surface after standby")
            view.pause()
            view.resume()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val planeChannel = MethodChannel(messenger, VideoPlane.CHANNEL)
        val plane = VideoPlane(this, planeChannel)
        planeChannel.setMethodCallHandler(plane::onMethodCall)
        MethodChannel(messenger, SleepService.CHANNEL).setMethodCallHandler(SleepService.Channel(this)::onMethodCall)
        val updateChannel = MethodChannel(messenger, AppUpdater.CHANNEL)
        updater = AppUpdater(this, updateChannel).also { updateChannel.setMethodCallHandler(it::onMethodCall) }
        val displayChannel = MethodChannel(messenger, DisplayModes.CHANNEL)
        displayModes = DisplayModes(this).also { displayChannel.setMethodCallHandler(it::onMethodCall) }
        MethodChannel(messenger, "liquiflux/probe").setMethodCallHandler { call, result ->
            if (call.method == "flags") result.success(probe) else result.notImplemented()
        }
        MethodChannel(messenger, "liquiflux/window").setMethodCallHandler { call, result ->
            if (call.method != "plain") return@setMethodCallHandler result.notImplemented()
            window.setBackgroundDrawableResource(android.R.color.black)
            result.success(null)
        }
    }

    override fun onDestroy() {
        updater?.dispose()
        updater = null
        displayModes?.dispose()
        displayModes = null
        super.onDestroy()
    }

    companion object {
        /** The manifest's activity-alias for the probe. */
        const val PROBE_ALIAS = "com.foehammer.console_app.Probe"
    }
}
