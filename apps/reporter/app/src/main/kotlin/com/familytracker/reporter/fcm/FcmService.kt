package com.familytracker.reporter.fcm

import android.util.Log
import com.familytracker.reporter.ApprovalStatus
import com.familytracker.reporter.Storage
import com.familytracker.reporter.net.RelayClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import com.familytracker.reporter.TrackingMode
import com.familytracker.reporter.service.LocationForegroundService
import com.familytracker.reporter.service.RingService
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class FcmService : FirebaseMessagingService() {

    private val tag = "Reporter/FCM"

    override fun onNewToken(token: String) {
        Log.i(tag, "FCM token refreshed")
        val storage = Storage(applicationContext)
        storage.fcmToken = token
        storage.fcmTokenDirty = true

        // If we're already approved, push the new token to the relay so it
        // can keep reaching us with FCM commands. If we're not yet approved
        // the token will be sent as part of the next /join request.
        val androidId = storage.androidId
        val ingestToken = storage.ingestToken
        if (androidId != null && ingestToken != null) {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    RelayClient().refreshFcm(androidId, ingestToken, token)
                    storage.fcmTokenDirty = false
                    Log.i(tag, "FCM token pushed to relay")
                } catch (e: Exception) {
                    Log.w(tag, "Failed to push FCM token to relay; will retry later", e)
                }
            }
        }
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
            "locate" -> handleLocate(storage)
            "removed" -> handleRemoved(storage)
            "ring" -> handleRing(data)
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
        // Fetch a single position immediately so the admin sees coordinates,
        // address, speed, accuracy and battery right after approval.
        LocationForegroundService.startLocate(applicationContext)
    }

    private fun handleLocate(storage: Storage) {
        if (storage.approval != ApprovalStatus.APPROVED) {
            Log.w(tag, "locate: not approved; ignoring")
            return
        }
        LocationForegroundService.startLocate(applicationContext)
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
        LocationForegroundService.stop(applicationContext)
    }

    private fun handleRemoved(storage: Storage) {
        storage.approval = ApprovalStatus.REMOVED
        LocationForegroundService.stop(applicationContext)
    }

    private fun handleRing(data: Map<String, String>) {
        val duration = data["durationSec"]?.toIntOrNull() ?: 30
        RingService.start(applicationContext, duration)
    }

}
