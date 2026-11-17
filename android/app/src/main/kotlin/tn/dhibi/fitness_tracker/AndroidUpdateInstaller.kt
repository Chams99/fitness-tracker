package tn.dhibi.fitness_tracker

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

private const val INSTALL_RESULT = "tn.dhibi.fitness_tracker.UPDATE_INSTALL_RESULT"

class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == INSTALL_RESULT) listener?.invoke(intent)
    }

    companion object {
        internal var listener: ((Intent) -> Unit)? = null
    }
}

internal class AndroidUpdateInstaller(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "tn.dhibi.fitness_tracker/update")
    private val pm = activity.packageManager
    private val installer = pm.packageInstaller
    private val cache = File(activity.cacheDir, "fitness-updates")
    private val reminders = activity.getSharedPreferences("android-updates", Context.MODE_PRIVATE)
    private val resultListener: (Intent) -> Unit = ::receiveStatus

    private class Attempt(val result: MethodChannel.Result) {
        var sessionId: Int? = null
        var statusIntent: PendingIntent? = null
        var confirmation: Intent? = null
    }

    private var attempt: Attempt? = null
    private var settingsResult: MethodChannel.Result? = null
    private var resumed = false

    init {
        channel.setMethodCallHandler(::onCall)
        UpdateInstallReceiver.listener = resultListener
    }

    fun onResume() {
        resumed = true
        showConfirmation()
    }

    fun onPause() {
        resumed = false
    }

    fun close() {
        channel.setMethodCallHandler(null)
        if (UpdateInstallReceiver.listener === resultListener) UpdateInstallReceiver.listener = null
        attempt?.let { finish(it, "cancelled", abandon = true) }
        settingsResult?.success(false)
        settingsResult = null
    }

    fun onActivityResult(requestCode: Int) {
        if (requestCode != INSTALL_SETTINGS_REQUEST) return
        val result = settingsResult
        settingsResult = null
        result?.success(canInstall())
    }

    private val hasPerAppInstallSettings: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    @Suppress("DEPRECATION")
    private fun canInstall() = if (hasPerAppInstallSettings) {
        pm.canRequestPackageInstalls()
    } else {
        Settings.Secure.getInt(activity.contentResolver, Settings.Secure.INSTALL_NON_MARKET_APPS, 0) == 1
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installPermission" -> result.success(
                when {
                    canInstall() -> "allowed"
                    hasPerAppInstallSettings -> "perApp"
                    else -> "legacy"
                },
            )
            "availableBytes" -> result.success(activity.cacheDir.usableSpace)
            "isDeferred" -> {
                val code = (call.arguments as? Number)?.toLong()
                result.success(
                    code == reminders.getLong("versionCode", -1) &&
                        System.currentTimeMillis() < reminders.getLong("until", 0),
                )
            }
            "defer" -> {
                val code = (call.arguments as? Number)?.toLong()
                if (code != null) {
                    reminders.edit()
                        .putLong("versionCode", code)
                        .putLong("until", System.currentTimeMillis() + TimeUnit.HOURS.toMillis(24))
                        .apply()
                }
                result.success(null)
            }
            "openInstallSettings" -> openSettings(result)
            "install" -> install(call, result)
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun openSettings(result: MethodChannel.Result) {
        if (canInstall()) {
            result.success(true)
            return
        }
        if (settingsResult != null) {
            result.success(false)
            return
        }
        val settings = if (hasPerAppInstallSettings) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.fromParts("package", activity.packageName, null),
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        try {
            settingsResult = result
            activity.startActivityForResult(settings, INSTALL_SETTINGS_REQUEST)
        } catch (_: Exception) {
            settingsResult = null
            result.error("settings_unavailable", "Android could not open installation settings.", null)
        }
    }

    private fun install(call: MethodCall, result: MethodChannel.Result) {
        val code = call.argument<Number>("versionCode")?.toLong()
        val name = call.argument<String>("versionName")
        val hash = call.argument<String>("sha256")
        if (code == null || code !in 1..2100000000L || name == null ||
            hash == null || !hash.matches(Regex("[a-f0-9]{64}"))
        ) {
            result.success("invalid")
            return
        }
        if (attempt != null || !canInstall()) {
            result.success("blocked")
            return
        }

        val apk = File(cache, "$code-$hash.apk")
        val current = Attempt(result)
        attempt = current
        Thread({
            var id: Int? = null
            try {
                @Suppress("DEPRECATION")
                val installed = pm.getPackageInfo(activity.packageName, 0)
                @Suppress("DEPRECATION")
                val archive = pm.getPackageArchiveInfo(apk.path, 0)
                val rejection = when {
                    !apk.isFile -> "missing"
                    archive == null -> "unreadable"
                    archive.packageName != activity.packageName || archive.versionName != name ||
                        archive.code != code || code <= installed.code -> "mismatch"
                    else -> null
                }
                if (rejection != null) {
                    activity.runOnUiThread { finish(current, rejection) }
                    return@Thread
                }

                val size = apk.length()
                if (size > activity.cacheDir.usableSpace) {
                    activity.runOnUiThread { finish(current, "storage") }
                    return@Thread
                }
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                params.setAppPackageName(activity.packageName)
                params.setSize(size)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
                }
                val sessionId = installer.createSession(params)
                id = sessionId
                val digest = MessageDigest.getInstance("SHA-256")
                installer.openSession(sessionId).use { session ->
                    session.openWrite("base.apk", 0, size).use { staged ->
                        apk.inputStream().use { input ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                digest.update(buffer, 0, count)
                                staged.write(buffer, 0, count)
                            }
                        }
                        session.fsync(staged)
                    }
                }
                val actual = digest.digest().joinToString("") { "%02x".format(it) }
                if (actual != hash) {
                    abandon(sessionId)
                    activity.runOnUiThread { finish(current, "invalid") }
                    return@Thread
                }
                activity.runOnUiThread { commit(current, sessionId) }
            } catch (error: Exception) {
                id?.let(::abandon)
                val status = when {
                    !apk.exists() -> "missing"
                    error is IOException && activity.cacheDir.usableSpace < apk.length() -> "storage"
                    else -> "failed"
                }
                activity.runOnUiThread { finish(current, status) }
            }
        }, "FitnessTrackerInstall").start()
    }

    private fun commit(current: Attempt, id: Int) {
        if (attempt !== current) {
            abandon(id)
            return
        }
        current.sessionId = id
        try {
            // The system supplies status extras. Use an explicit, private receiver.
            val callback = PendingIntent.getBroadcast(
                activity,
                id,
                Intent(activity, UpdateInstallReceiver::class.java).setAction(INSTALL_RESULT),
                PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0),
            )
            current.statusIntent = callback
            installer.openSession(id).use { it.commit(callback.intentSender) }
        } catch (_: Exception) {
            finish(current, "failed", abandon = true)
        }
    }

    private fun receiveStatus(intent: Intent) {
        val current = attempt ?: return
        if (current.sessionId != intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)) return
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirmation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                }
                if (confirmation == null) {
                    finish(current, "failed", abandon = true)
                } else {
                    current.confirmation = confirmation
                    showConfirmation()
                }
            }
            PackageInstaller.STATUS_SUCCESS -> finish(current, "success")
            PackageInstaller.STATUS_FAILURE_ABORTED -> finish(current, "cancelled")
            PackageInstaller.STATUS_FAILURE_STORAGE -> finish(current, "storage")
            PackageInstaller.STATUS_FAILURE_INVALID -> finish(current, "invalid")
            PackageInstaller.STATUS_FAILURE_BLOCKED -> finish(current, "blocked")
            PackageInstaller.STATUS_FAILURE_CONFLICT -> finish(current, "conflict")
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> finish(current, "incompatible")
            else -> finish(current, "failed")
        }
    }

    private fun showConfirmation() {
        val current = attempt ?: return
        val confirmation = current.confirmation ?: return
        if (!resumed) return
        current.confirmation = null
        try {
            activity.startActivity(confirmation)
        } catch (_: Exception) {
            finish(current, "failed", abandon = true)
        }
    }

    private fun finish(current: Attempt, status: String, abandon: Boolean = false) {
        if (attempt !== current) return
        attempt = null
        if (abandon) current.sessionId?.let(::abandon)
        current.statusIntent?.cancel()
        current.result.success(status)
    }

    private fun abandon(id: Int) {
        try {
            installer.abandonSession(id)
        } catch (_: Exception) {
            // A finalized session no longer belongs to this app.
        }
    }

    private val PackageInfo.code: Long
        @Suppress("DEPRECATION")
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) longVersionCode else versionCode.toLong()

    private companion object {
        const val INSTALL_SETTINGS_REQUEST = 5481
    }
}
