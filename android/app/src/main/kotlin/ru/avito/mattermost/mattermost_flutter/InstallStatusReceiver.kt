package com.mattermost.mattermost_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

class InstallStatusReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_SESSION_ID = "sessionId"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                InstallStatusBus.emit(mapOf("type" to "awaitingUserAction"))
                confirmationIntent(intent)?.let { confirmation ->
                    confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirmation)
                } ?: InstallStatusBus.emit(failureEvent(intent, status, "confirmation_unavailable"))
            }
            PackageInstaller.STATUS_SUCCESS ->
                InstallStatusBus.emit(mapOf("type" to "success"))
            PackageInstaller.STATUS_FAILURE_ABORTED ->
                InstallStatusBus.emit(mapOf("type" to "cancelled"))
            PackageInstaller.STATUS_FAILURE_BLOCKED ->
                InstallStatusBus.emit(failureEvent(intent, status, "blocked"))
            PackageInstaller.STATUS_FAILURE_CONFLICT ->
                InstallStatusBus.emit(failureEvent(intent, status, "conflict"))
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE ->
                InstallStatusBus.emit(failureEvent(intent, status, "incompatible"))
            PackageInstaller.STATUS_FAILURE_INVALID ->
                InstallStatusBus.emit(failureEvent(intent, status, "invalid"))
            PackageInstaller.STATUS_FAILURE_STORAGE ->
                InstallStatusBus.emit(failureEvent(intent, status, "storage"))
            else -> InstallStatusBus.emit(failureEvent(intent, status, "unknown"))
        }
    }

    private fun failureEvent(
        intent: Intent,
        status: Int,
        reason: String,
    ): Map<String, String> {
        val statusMessage = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
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
