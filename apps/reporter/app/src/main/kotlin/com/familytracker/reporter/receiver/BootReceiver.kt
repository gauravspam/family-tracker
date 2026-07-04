package com.familytracker.reporter.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.familytracker.reporter.ApprovalStatus
import com.familytracker.reporter.Storage
import com.familytracker.reporter.service.LocationForegroundService
import com.familytracker.reporter.service.WatchdogWorker

class BootReceiver : BroadcastReceiver() {

    private val tag = "Reporter/Boot"

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val storage = Storage(context)
        Log.i(tag, "BOOT_COMPLETED received; approval=${storage.approval}")

        if (storage.approval == ApprovalStatus.APPROVED) {
            Log.i(tag, "Starting foreground service after boot")
            LocationForegroundService.start(context)
            WatchdogWorker.schedule(context)
        } else {
            Log.i(tag, "Not approved; skipping service start")
        }
    }
}
