package com.familytracker.reporter.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Fires when the user taps "Stop" in the ring notification. */
class RingStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        RingService.stop(context)
    }
}
