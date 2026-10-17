package com.mattermost.mattermost_flutter

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

class InstallResultActivity : Activity() {
    companion object {
        const val EXTRA_SESSION_ID = "sessionId"
        const val UPDATE_NOTIFICATION_ID = 1001

        private const val UPDATE_NOTIFICATION_CHANNEL = "app_updates"
        private const val OPEN_APP_REQUEST_CODE = 1002
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleInstallResult(intent)
    }

    private fun handleInstallResult(source: Intent) {
        val status = source.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                InstallStatusBus.emit(mapOf("type" to "awaitingUserAction"))
                confirmationIntent(source)?.let(::startActivity)
                    ?: InstallStatusBus.emit(
                        failureEvent(source, status, "confirmation_unavailable"),
                    )
            }
            PackageInstaller.STATUS_SUCCESS -> {
                InstallStatusBus.emit(mapOf("type" to "success"))
                showUpdateInstalledNotification()
                openMattermost()
            }
            PackageInstaller.STATUS_FAILURE_ABORTED ->
                InstallStatusBus.emit(mapOf("type" to "cancelled"))
            PackageInstaller.STATUS_FAILURE_BLOCKED ->
                InstallStatusBus.emit(failureEvent(source, status, "blocked"))
            PackageInstaller.STATUS_FAILURE_CONFLICT ->
                InstallStatusBus.emit(failureEvent(source, status, "conflict"))
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE ->
                InstallStatusBus.emit(failureEvent(source, status, "incompatible"))
            PackageInstaller.STATUS_FAILURE_INVALID ->
                InstallStatusBus.emit(failureEvent(source, status, "invalid"))
            PackageInstaller.STATUS_FAILURE_STORAGE ->
                InstallStatusBus.emit(failureEvent(source, status, "storage"))
            else -> InstallStatusBus.emit(failureEvent(source, status, "unknown"))
        }
        finish()
    }

    private fun openMattermost() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(launchIntent)
    }

    private fun showUpdateInstalledNotification() {
        val notificationManager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(
                    UPDATE_NOTIFICATION_CHANNEL,
                    getString(R.string.update_notification_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this,
            OPEN_APP_REQUEST_CODE,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, UPDATE_NOTIFICATION_CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        notificationManager.notify(
            UPDATE_NOTIFICATION_ID,
            builder
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(getString(R.string.update_installed_notification_title))
                .setContentText(getString(R.string.update_installed_notification_body))
                .setContentIntent(openAppPendingIntent)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_STATUS)
                .build(),
        )
    }

    private fun failureEvent(
        source: Intent,
        status: Int,
        reason: String,
    ): Map<String, String> {
        val statusMessage = source.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val rawError = buildString {
            append("status=")
            append(status)
            if (!statusMessage.isNullOrBlank()) {
                append("; message=")
                append(statusMessage)
            }
        }
        return mapOf(
            "type" to "failure",
            "reason" to reason,
            "rawError" to rawError,
        )
    }

    @Suppress("DEPRECATION")
    private fun confirmationIntent(source: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            source.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            source.getParcelableExtra(Intent.EXTRA_INTENT)
        }
}

object InstallStatusBus {
    private val handler = Handler(Looper.getMainLooper())
    private val pending = ArrayDeque<Map<String, String>>()
    private var sink: EventChannel.EventSink? = null

    @Synchronized
    fun attach(eventSink: EventChannel.EventSink) {
        sink = eventSink
        while (pending.isNotEmpty()) {
            eventSink.success(pending.removeFirst())
        }
    }

    @Synchronized
    fun detach() {
        sink = null
    }

    fun emit(event: Map<String, String>) {
        handler.post {
            synchronized(this) {
                val current = sink
                if (current == null) {
                    if (pending.size == 8) pending.removeFirst()
                    pending.addLast(event)
                } else {
                    current.success(event)
                }
            }
        }
    }
}
