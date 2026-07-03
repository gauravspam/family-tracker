package com.familytracker.reporter.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.familytracker.reporter.ui.MainActivity

/**
 * Short-lived foreground service that plays a loud sound (alarm stream, at max
 * volume) for [EXTRA_DURATION_SEC] seconds. Used by the admin's "Ring device"
 * command to find a misplaced phone.
 */
class RingService : Service() {

    private val tag = "Reporter/Ring"

    private var mediaPlayer: MediaPlayer? = null
    private var previousVolume: Int = -1
    private val handler = Handler(Looper.getMainLooper())
    private val stopRunnable = Runnable { stopSelf() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val duration = intent?.getIntExtra(EXTRA_DURATION_SEC, DEFAULT_DURATION_SEC)
            ?: DEFAULT_DURATION_SEC

        // Always keep the foreground notification fresh so the service
        // stays alive even on repeat commands.
        startForeground(NOTIFICATION_ID, buildNotification())

        // If a ring is already playing, just extend the auto-stop timer
        // rather than tearing down and restarting the MediaPlayer.
        if (mediaPlayer?.isPlaying == true) {
            Log.i(tag, "Ring already playing — extending timer to $duration s")
            handler.removeCallbacks(stopRunnable)
            handler.postDelayed(stopRunnable, duration * 1000L)
            return START_NOT_STICKY
        }

        Log.i(tag, "Ring started for $duration s")
        try {
            startRinging()
            handler.removeCallbacks(stopRunnable)
            handler.postDelayed(stopRunnable, duration * 1000L)
        } catch (e: Exception) {
            Log.e(tag, "Failed to start ring", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.i(tag, "Ring stopped")
        handler.removeCallbacks(stopRunnable)
        stopRinging()
    }

    // ── Media ─────────────────────────────────────────────────────────

    private fun startRinging() {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Boost alarm volume to max, remembering the previous value.
        previousVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
        val maxVolume = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        try {
            audio.setStreamVolume(AudioManager.STREAM_ALARM, maxVolume, 0)
        } catch (e: SecurityException) {
            Log.w(tag, "Could not raise alarm volume: $e")
        }

        val uri = RingtoneManager.getActualDefaultRingtoneUri(
            this, RingtoneManager.TYPE_ALARM,
        ) ?: RingtoneManager.getActualDefaultRingtoneUri(
            this, RingtoneManager.TYPE_RINGTONE,
        )

        if (uri == null) {
            Log.w(tag, "No ringtone URI available")
            return
        }

        mediaPlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            setDataSource(this@RingService, uri)
            isLooping = true
            prepare()
            start()
        }
    }

    private fun stopRinging() {
        mediaPlayer?.apply {
            try {
                if (isPlaying) stop()
            } catch (_: Exception) {}
            release()
        }
        mediaPlayer = null

        if (previousVolume >= 0) {
            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            try {
                audio.setStreamVolume(AudioManager.STREAM_ALARM, previousVolume, 0)
            } catch (_: SecurityException) {}
            previousVolume = -1
        }
    }

    // ── Notification ──────────────────────────────────────────────────

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ring alerts",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Loud alert to help locate this phone"
                setShowBadge(true)
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentPi = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Tapping the "Stop" action fires a broadcast to stop the service.
        val stopIntent = Intent(this, RingStopReceiver::class.java)
        val stopPi = PendingIntent.getBroadcast(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Ringing this phone")
            .setContentText("Tap Stop to silence")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setContentIntent(contentPi)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopPi)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "reporter_ring"
        private const val NOTIFICATION_ID = 2
        private const val DEFAULT_DURATION_SEC = 30
        const val EXTRA_DURATION_SEC = "duration_sec"

        fun start(context: Context, durationSec: Int) {
            val intent = Intent(context, RingService::class.java).apply {
                putExtra(EXTRA_DURATION_SEC, durationSec)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RingService::class.java))
        }
    }
}
