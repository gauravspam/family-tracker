package com.familytracker.reporter.fcm

import android.util.Log
import com.familytracker.reporter.ApprovalStatus
import com.familytracker.reporter.Storage
import com.familytracker.reporter.TrackingMode
import com.familytracker.reporter.service.LocationForegroundService
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class FcmService : FirebaseMessagingService() {

    private val tag = "Reporter/FCM"

    override fun onNewToken(token: String) {
        Log.i(tag, "FCM token refreshed")
        val storage = Storage(applicationContext)
        storage.fcmToken = token
        storage.fcmTokenDirty = true
    }

    override fun onMessageReceived(msg: RemoteMessage) {
        val data = msg.data
        val command = data["command"] ?: return
        Log.i(tag, "FCM command=$command data=$data")

        val storage = Storage(applicationContext)
        when (command) {
            "approved" -> handleApproved(storage, data)
            "live_mode" -> handleLive(storage, data)
            "idle_mode" -> handleIdle(storage)
            "removed" -> handleRemoved(storage)
            else -> Log.w(tag, "Unknown command $command")
        }
    }

    private fun handleApproved(storage: Storage, data: Map<String, String>) {
        val token = data["ingestToken"]
        val url = data["ingestUrl"]
        if (token.isNullOrBlank() || url.isNullOrBlank()) {
            Log.w(tag, "approved command missing ingestToken/ingestUrl")
            return
        }
        storage.approval = ApprovalStatus.APPROVED
        storage.ingestToken = token
        storage.ingestUrl = url
        LocationForegroundService.start(applicationContext)
    }

    private fun handleLive(storage: Storage, data: Map<String, String>) {
        val expiresAt = data["expiresAt"]
        val expiresMs = expiresAt?.let {
            try {
                java.time.Instant.parse(it).toEpochMilli()
            } catch (_: Exception) {
                0L
            }
        } ?: 0L

        if (expiresMs <= System.currentTimeMillis()) {
            Log.w(tag, "live_mode expiresAt in the past; ignoring")
            return
        }

        storage.mode = TrackingMode.LIVE
        storage.liveExpiresAt = expiresMs
        LocationForegroundService.start(applicationContext)
    }

    private fun handleIdle(storage: Storage) {
        storage.mode = TrackingMode.IDLE
        storage.liveExpiresAt = 0
        LocationForegroundService.start(applicationContext)
    }

    private fun handleRemoved(storage: Storage) {
        storage.approval = ApprovalStatus.REMOVED
        LocationForegroundService.stop(applicationContext)
    }
}
