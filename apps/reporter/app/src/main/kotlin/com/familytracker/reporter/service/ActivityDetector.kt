package com.familytracker.reporter.service

import android.util.Log

class ActivityDetector {

    companion object {
        private const val TAG = "Reporter/Activity"

        fun labelFromSpeed(speedMs: Float): String = when {
            speedMs > 8.0f -> "in_vehicle"
            speedMs > 4.0f -> "on_bicycle"
            speedMs > 1.5f -> "running"
            speedMs > 0.3f -> "walking"
            else           -> "still"
        }
    }

    private var lastSpeed: Float = 0f

    fun onLocation(speedMs: Float) {
        lastSpeed = speedMs
    }

    fun currentLabel(): String = labelFromSpeed(lastSpeed)
}
