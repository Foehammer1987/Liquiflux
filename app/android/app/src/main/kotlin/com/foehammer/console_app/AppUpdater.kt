package com.foehammer.console_app

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Installs a Liquiflux update that lib/services/updater.dart downloaded and checked
 * (sha256 against the GitHub release). Before Android's installer sees the APK, this checks
 * it is Liquiflux, newer than what's installed, and signed with the same key; Android would
 * refuse a different key anyway, but this way the person gets a clear reason.
 *
 * The APK goes in through a PackageInstaller session, so no file is ever shared with another
 * app. Android asks the person to confirm, then replaces this app (and closes it).
 *
 * Not used when an app store installed Liquiflux (stores update their own apps and don't
 * allow self-updating), or in the store build, which has no REQUEST_INSTALL_PACKAGES.
 */
class AppUpdater(private val activity: Activity, private val channel: MethodChannel) {
    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "selfUpdate" -> result.success(selfUpdate())
            "canInstall" -> result.success(canInstall())
            "allowInstalls" -> result.success(allowInstalls())
            "install" -> {
                val path = call.argument<String>("path")
                if (path == null) result.error("args", "No file to install.", null) else result.success(install(path))
            }
            else -> result.notImplemented()
        }
    }

    private val pm get() = activity.packageManager

    /** Whether this copy may update itself: it asks for the permission and no store installed it. */
    private fun selfUpdate(): Boolean {
        val requested = try {
            pm.getPackageInfo(activity.packageName, PackageManager.GET_PERMISSIONS).requestedPermissions?.contains(Manifest.permission.REQUEST_INSTALL_PACKAGES) == true
        } catch (e: Exception) {
            false
        }
        if (!requested) return false
        val installer = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                pm.getInstallSourceInfo(activity.packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                pm.getInstallerPackageName(activity.packageName)
            }
        } catch (e: Exception) {
            null
        }
        return installer !in STORES
    }

    private fun canInstall(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || pm.canRequestPackageInstalls()

    /** Android's "install unknown apps" switch for Liquiflux (Shield: Apps > Security & restrictions). */
    private fun allowInstalls(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        for (intent in listOf(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")),
            Intent(Settings.ACTION_SECURITY_SETTINGS),
        )) {
            try {
                activity.startActivity(intent)
                return true
            } catch (e: Exception) {
                Log.w(TAG, "can't open ${intent.action}: $e")
            }
        }
        return false
    }

    /** "ok" once Android's installer has the APK, else why not. */
    private fun install(path: String): String {
        val file = File(path)
        // Only files the updater downloaded into this app's own cache.
        val cache = File(activity.cacheDir, "liquiflux-update").canonicalPath + File.separator
        if (!file.canonicalPath.startsWith(cache) || !file.isFile) return "The update file is missing."
        val problem = check(file)
        if (problem != null) {
            file.delete()
            return problem
        }
        return try {
            commit(file)
            "ok"
        } catch (e: Exception) {
            Log.w(TAG, "install: $e")
            "Android couldn't start installing the update."
        }
    }

    /** Why [apk] must not be installed, or null if it's a newer Liquiflux signed like this one. */
    private fun check(apk: File): String? {
        val sigFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val archive = pm.getPackageArchiveInfo(apk.path, sigFlags) ?: return "The download isn't an app Android can read."
        val installed = pm.getPackageInfo(activity.packageName, sigFlags)
        if (archive.packageName != activity.packageName) return "The download isn't Liquiflux."
        if (versionCode(archive) <= versionCode(installed)) return "The download isn't newer than this Liquiflux."
        val theirs = signers(archive)
        val ours = signers(installed)
        // Android checks this again itself; an archive whose certificates can't be read here is left to it.
        if (theirs.isNotEmpty() && ours.isNotEmpty() && theirs != ours) {
            return "The update is signed with a different key than this Liquiflux, so Android would refuse it. Install it by hand from GitHub."
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun versionCode(p: PackageInfo): Long = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) p.longVersionCode else p.versionCode.toLong()

    /** SHA-256 of each signing certificate. */
    @Suppress("DEPRECATION")
    private fun signers(p: PackageInfo): Set<String> {
        val certs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = p.signingInfo ?: return emptySet()
            if (info.hasMultipleSigners()) info.apkContentsSigners else info.signingCertificateHistory
        } else {
            p.signatures
        } ?: return emptySet()
        // With key rotation the history lists older keys too; the newest (last) is what counts.
        val list = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && p.signingInfo?.hasMultipleSigners() == false) listOf(certs.last()) else certs.toList()
        return list.map { sig -> MessageDigest.getInstance("SHA-256").digest(sig.toByteArray()).joinToString("") { "%02x".format(it) } }.toSet()
    }

    private fun commit(apk: File) {
        val installer = pm.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(activity.packageName)
            setSize(apk.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
        }
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("liquiflux.apk", 0, apk.length()).use { out ->
                    input.copyTo(out, 1 shl 16)
                    session.fsync(out)
                }
            }
            listen()
            val intent = Intent(ACTION).setPackage(activity.packageName)
            // Mutable: the installer adds the status and its confirmation screen to it.
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            session.commit(PendingIntent.getBroadcast(activity, id, intent, flags).intentSender)
        }
        apk.delete()
    }

    private var receiver: BroadcastReceiver? = null

    /** Android's answers: show its confirmation screen, or tell Dart how it ended. */
    private fun listen() {
        if (receiver != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
                if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                    @Suppress("DEPRECATION")
                    val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                    if (confirm != null) {
                        try {
                            activity.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        } catch (e: Exception) {
                            Log.w(TAG, "confirm: $e")
                            channel.invokeMethod("finished", mapOf("ok" to false, "message" to "Android's installer didn't open."))
                        }
                    }
                    return
                }
                val ok = status == PackageInstaller.STATUS_SUCCESS
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                Log.i(TAG, "install finished: status $status $message")
                channel.invokeMethod(
                    "finished",
                    mapOf("ok" to ok, "message" to if (status == PackageInstaller.STATUS_FAILURE_ABORTED) "The update was cancelled." else "Android didn't install the update ($status)."),
                )
            }
        }
        val filter = IntentFilter(ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(r, filter)
        }
        receiver = r
    }

    fun dispose() {
        receiver?.let { runCatching { activity.unregisterReceiver(it) } }
        receiver = null
    }

    companion object {
        const val CHANNEL = "liquiflux/update"
        private const val TAG = "AppUpdater"
        private const val ACTION = "com.foehammer.liquiflux.UPDATE_STATUS"

        /** Google Play and the Amazon Appstore, which keep their apps up to date themselves. */
        private val STORES = setOf("com.android.vending", "com.amazon.venezia")
    }
}
