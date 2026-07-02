package com.familytracker.reporter.service

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.familytracker.reporter.ApprovalStatus
import com.familytracker.reporter.Storage
import com.familytracker.reporter.TrackingMode
import com.familytracker.reporter.net.OsmAndClient
import com.familytracker.reporter.net.RelayClient
import com.familytracker.reporter.ui.MainActivity
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class LocationForegroundService : Service() {

    private val tag = "Reporter/FGS"

    private lateinit var storage: Storage
    private lateinit var osmand: OsmAndClient
    private lateinit var relay: RelayClient

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var currentInterval: Long = IDLE_INTERVAL_MS
    private var firstStart = true
    private var pollJob: Job? = null

    private val fusedClient by lazy {
        LocationServices.getFusedLocationProviderClient(this)
    }

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            for (loc in result.locations) {
                handleLocation(loc)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(tag, "Service created")
        storage = Storage(this)
        osmand = OsmAndClient()
        relay = RelayClient()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(tag, "Service started")
        startForegroundWithNotification("Location service active")
        applyInterval()
        startPollLoop()
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.i(tag, "Service destroyed")
        try {
            fusedClient.removeLocationUpdates(locationCallback)
        } catch (_: Exception) {}
        pollJob?.cancel()
        scope.cancel()
    }

    // ── Location handling ─────────────────────────────────────────────

    private fun applyInterval() {
        val desiredInterval = when (storage.mode) {
            TrackingMode.LIVE -> LIVE_INTERVAL_MS
            TrackingMode.IDLE -> IDLE_INTERVAL_MS
        }
        if (currentInterval == desiredInterval && !firstStart) return

        firstStart = false
        currentInterval = desiredInterval
        startLocationUpdates(desiredInterval)
    }

    private fun startLocationUpdates(intervalMs: Long) {
        if (ContextCompat.checkSelfPermission(
                this, Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(tag, "Location permission missing; cannot start updates")
            return
        }

        try {
            fusedClient.removeLocationUpdates(locationCallback)
        } catch (_: Exception) {}

        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, intervalMs)
            .setMinUpdateIntervalMillis(intervalMs / 2)
            .setWaitForAccurateLocation(false)
            .build()

        try {
            fusedClient.requestLocationUpdates(request, locationCallback, Looper.getMainLooper())
            Log.i(tag, "Location updates requested (interval=${intervalMs}ms)")
        } catch (e: SecurityException) {
            Log.e(tag, "Failed to request location updates", e)
        }
    }

    private fun handleLocation(loc: Location) {
        if (storage.mode == TrackingMode.LIVE && storage.liveExpiresAt > 0 &&
            System.currentTimeMillis() > storage.liveExpiresAt
        ) {
            Log.i(tag, "LIVE mode expired; dropping to IDLE")
            storage.mode = TrackingMode.IDLE
            storage.liveExpiresAt = 0
            applyInterval()
            return
        }

        val token = storage.ingestToken
        val url = storage.ingestUrl
        if (token.isNullOrEmpty() || url.isNullOrEmpty()) {
            Log.w(tag, "Missing ingestToken/ingestUrl; skipping post")
            return
        }

        val batt = readBatteryLevel()
        val course = if (loc.hasBearing()) loc.bearing else 0f

        scope.launch {
            try {
                osmand.postPosition(
                    ingestUrl = url,
                    ingestToken = token,
                    latitude = loc.latitude,
                    longitude = loc.longitude,
                    timestampEpochSec = loc.time / 1000L,
                    accuracyMeters = loc.accuracy,
                    altitudeMeters = if (loc.hasAltitude()) loc.altitude else 0.0,
                    speedMs = if (loc.hasSpeed()) loc.speed else 0f,
                    courseDeg = course,
                    batteryPercent = batt,
                )
            } catch (e: Exception) {
                Log.w(tag, "Post failed", e)
            }
        }
    }

    // ── Command polling ──────────────────────────────────────────────

    private fun startPollLoop() {
        pollJob?.cancel()
        pollJob = scope.launch {
            while (true) {
                delay(POLL_INTERVAL_MS)
                pollOnce()
            }
        }
    }

    private fun pollOnce() {
        val androidId = storage.androidId ?: return
        try {
            val status = relay.getDeviceStatus(androidId)
            Log.i(tag, "Poll status=${status.status}")

            when (status.status) {
                "removed" -> {
                    Log.i(tag, "Device removed by admin; stopping service")
                    storage.approval = ApprovalStatus.REMOVED
                    stopSelf()
                }
                "approved" -> {
                    status.ingestToken?.let { storage.ingestToken = it }
                    status.ingestUrl?.let { storage.ingestUrl = it }
                    applyInterval()
                }
                else -> { /* pending or unknown — do nothing */ }
            }
        } catch (e: Exception) {
            Log.w(tag, "Poll failed", e)
        }
    }


    private fun readBatteryLevel(): Int? {
        return try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            val level = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
            if (level in 0..100) level else null
        } catch (_: Exception) {
            null
        }
    }

    // ── Notification ──────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Location Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Persistent notification for background location tracking"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun startForegroundWithNotification(text: String) {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pi = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Recorder")
            .setContentText(text)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pi)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notif)
        }
    }

    companion object {
        private const val CHANNEL_ID = "reporter_location"
        private const val NOTIFICATION_ID = 1

        private const val IDLE_INTERVAL_MS = 30_000L
        private const val LIVE_INTERVAL_MS = 5_000L
        private const val POLL_INTERVAL_MS = 60_000L  // 1 minute for testing

        fun start(context: Context) {
            val intent = Intent(context, LocationForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, LocationForegroundService::class.java)
            context.stopService(intent)
        }
    }
}
