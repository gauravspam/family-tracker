package com.familytracker.reporter.service

import android.app.ActivityManager
import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.familytracker.reporter.ApprovalStatus
import com.familytracker.reporter.Storage
import java.util.concurrent.TimeUnit

/**
 * Periodic watchdog that checks whether [LocationForegroundService] is still
 * running. If the device is approved but the service has been killed (by OEM
 * battery optimization, low memory, etc.), it restarts it.
 *
 * Runs every 15 minutes via WorkManager, which is more resilient to OEM
 * killers than foreground services alone.
 */
class WatchdogWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val storage = Storage(applicationContext)

        if (storage.approval != ApprovalStatus.APPROVED) {
            Log.i(TAG, "Not approved; skipping watchdog")
            return Result.success()
        }

        if (isServiceRunning()) {
            Log.i(TAG, "Service is running; nothing to do")
            return Result.success()
        }

        Log.w(TAG, "Service not running! Restarting...")
        LocationForegroundService.start(applicationContext)
        return Result.success()
    }

    private fun isServiceRunning(): Boolean {
        val am = applicationContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        @Suppress("DEPRECATION")
        for (info in am.getRunningServices(100)) {
            if (info.service.className == LocationForegroundService::class.java.name) {
                return true
            }
        }
        return false
    }

    companion object {
        private const val TAG = "Reporter/Watchdog"
        private const val WORK_NAME = "location_watchdog"

        /** Schedule the periodic watchdog. Idempotent — safe to call multiple times. */
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<WatchdogWorker>(
                15, TimeUnit.MINUTES,
            ).build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
            Log.i(TAG, "Watchdog scheduled")
        }
    }
}
