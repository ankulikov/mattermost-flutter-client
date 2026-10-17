package com.mattermost.mattermost_flutter

import android.app.ActivityOptions
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.mattermost.mattermost_flutter/app_update"
        private const val EVENT_CHANNEL = "com.mattermost.mattermost_flutter/app_update_events"
    }

    private val installExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(::handleUpdateMethod)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                        InstallStatusBus.attach(events)
                    }

                    override fun onCancel(arguments: Any?) {
                        InstallStatusBus.detach()
                    }
                },
            )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        InstallStatusBus.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        installExecutor.shutdown()
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        getSystemService(NotificationManager::class.java)
            .cancel(InstallResultActivity.UPDATE_NOTIFICATION_ID)
    }

    private fun handleUpdateMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(true)
            "getSupportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "getVersionCodeOffset" -> result.success(versionCodeOffset())
            "canRequestPackageInstalls" -> result.success(canRequestPackageInstalls())
            "openPackageInstallSettings" -> openPackageInstallSettings(result)
            "installApk" -> installApk(call, result)
            else -> result.notImplemented()
        }
    }

    private fun canRequestPackageInstalls(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    private fun versionCodeOffset(): Int {
        val processAbi =
            if (android.os.Process.is64Bit()) {
                Build.SUPPORTED_64_BIT_ABIS.firstOrNull()
            } else {
                Build.SUPPORTED_32_BIT_ABIS.firstOrNull()
            }
        return when (processAbi) {
            "armeabi-v7a" -> 1000
            "arm64-v8a" -> 2000
            "x86_64" -> 4000
            else -> 0
        }
    }

    private fun openPackageInstallSettings(result: MethodChannel.Result) {
        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                )
            } else {
                Intent(Settings.ACTION_SECURITY_SETTINGS)
            }
        if (intent.resolveActivity(packageManager) == null) {
            result.error("settings_unavailable", "Install settings are unavailable.", null)
            return
        }
        startActivity(intent)
        result.success(null)
    }

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        if (!canRequestPackageInstalls()) {
            result.error("permission_required", "Install permission is required.", null)
            return
        }
        val path = call.argument<String>("path")
        val expectedPackageName = call.argument<String>("expectedPackageName")
        if (path == null || expectedPackageName == null) {
            result.error("invalid_arguments", "The update request is incomplete.", null)
            return
        }
        installExecutor.execute {
            try {
                val apk = validateUpdateApk(path, expectedPackageName)
                val sessionId = stageAndCommit(apk)
                runOnUiThread { result.success(sessionId) }
            } catch (error: UpdateValidationException) {
                runOnUiThread { result.error(error.code, error.message, null) }
            } catch (_: Exception) {
                runOnUiThread {
                    result.error("install_failed", "The update could not be prepared.", null)
                }
            }
        }
    }

    private fun validateUpdateApk(path: String, expectedPackageName: String): File {
        val cacheRoot = cacheDir.canonicalFile
        val apk = File(path).canonicalFile
        if (!apk.path.startsWith(cacheRoot.path + File.separator) || !apk.isFile) {
            throw UpdateValidationException("invalid_path", "The update file is invalid.")
        }
        if (expectedPackageName != packageName) {
            throw UpdateValidationException("package_mismatch", "The package identity changed.")
        }
        val archive = packageArchiveInfo(apk)
            ?: throw UpdateValidationException("invalid_apk", "The update package is invalid.")
        val installed = installedPackageInfo(packageName)
        if (archive.packageName != packageName) {
            throw UpdateValidationException("package_mismatch", "The package identity changed.")
        }
        if (packageVersionCode(archive) <= packageVersionCode(installed)) {
            throw UpdateValidationException("version_not_newer", "The update version is not newer.")
        }
        if (!hasCompatibleSigningIdentity(installed, archive)) {
            throw UpdateValidationException("signing_mismatch", "The signing identity changed.")
        }
        return apk
    }

    private fun stageAndCommit(apk: File): Int {
        val installer = packageManager.packageInstaller
        val params =
            PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(packageName)
        params.setSize(apk.length())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            params.setPackageSource(PackageInstaller.PACKAGE_SOURCE_DOWNLOADED_FILE)
        }
        val sessionId = installer.createSession(params)
        try {
            installer.openSession(sessionId).use { session ->
                apk.inputStream().use { input ->
                    session.openWrite("update.apk", 0, apk.length()).use { output ->
                        input.copyTo(output)
                        session.fsync(output)
                    }
                }
                val statusIntent = Intent(this, InstallResultActivity::class.java).apply {
                    putExtra(InstallResultActivity.EXTRA_SESSION_ID, sessionId)
                }
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    sessionId,
                    statusIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                PendingIntent.FLAG_MUTABLE
                            } else {
                                0
                            },
                    installResultActivityOptions(),
                )
                InstallStatusBus.emit(mapOf("type" to "installing"))
                session.commit(pendingIntent.intentSender)
            }
        } catch (error: Exception) {
            installer.abandonSession(sessionId)
            throw error
        }
        return sessionId
    }

    private fun installResultActivityOptions() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ActivityOptions.makeBasic().apply {
                pendingIntentCreatorBackgroundActivityStartMode =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_ALWAYS
                    } else {
                        @Suppress("DEPRECATION")
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                    }
            }.toBundle()
        } else {
            null
        }

    @Suppress("DEPRECATION")
    private fun packageArchiveInfo(apk: File): PackageInfo? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(
                apk.path,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong()),
            )
        } else {
            val flag =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    PackageManager.GET_SIGNING_CERTIFICATES
                } else {
                    PackageManager.GET_SIGNATURES
                }
            packageManager.getPackageArchiveInfo(apk.path, flag)
        }

    @Suppress("DEPRECATION")
    private fun installedPackageInfo(name: String): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                name,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong()),
            )
        } else {
            val flag =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    PackageManager.GET_SIGNING_CERTIFICATES
                } else {
                    PackageManager.GET_SIGNATURES
                }
            packageManager.getPackageInfo(name, flag)
        }

    @Suppress("DEPRECATION")
    private fun signingDigests(info: PackageInfo): Set<String> {
        val signatures =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signingInfo = info.signingInfo ?: return emptySet()
                signingInfo.apkContentsSigners
            } else {
                info.signatures ?: emptyArray()
            }
        return signatures.map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }.toSet()
    }

    private fun hasCompatibleSigningIdentity(
        installed: PackageInfo,
        archive: PackageInfo
    ): Boolean {
        val installedDigests = signingDigests(installed)
        val archiveDigests = signingDigests(archive)
        return installedDigests.isNotEmpty() && installedDigests == archiveDigests
    }

    @Suppress("DEPRECATION")
    private fun packageVersionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
}

private class UpdateValidationException(
    val code: String,
    override val message: String,
) : Exception(message)
