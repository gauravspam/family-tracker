package com.familytracker.reporter.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat

data class PermissionState(
    val notificationsGranted: Boolean,
    val fineLocationGranted: Boolean,
    val backgroundLocationGranted: Boolean,
    val batteryOptExempt: Boolean,
    val locationEnabledOnDevice: Boolean
) {
    val allGranted: Boolean
        get() = notificationsGranted &&
                fineLocationGranted &&
                backgroundLocationGranted &&
                batteryOptExempt &&
                locationEnabledOnDevice

    fun missingReason(): String? = when {
        !locationEnabledOnDevice -> "Location must be turned on in Settings"
        !notificationsGranted -> "Notification permission required"
        !fineLocationGranted -> "Precise location permission required"
        !backgroundLocationGranted -> "Background location permission required (Allow all the time)"
        !batteryOptExempt -> "Please exempt this app from battery optimization"
        else -> null
    }
}

object PermissionSequence {

    fun snapshot(context: Context): PermissionState {
        return PermissionState(
            notificationsGranted = notificationsGranted(context),
            fineLocationGranted = fineLocationGranted(context),
            backgroundLocationGranted = backgroundLocationGranted(context),
            batteryOptExempt = batteryOptExempt(context),
            locationEnabledOnDevice = locationEnabledOnDevice(context)
        )
    }

    private fun notificationsGranted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun fineLocationGranted(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun backgroundLocationGranted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun batteryOptExempt(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun locationEnabledOnDevice(context: Context): Boolean {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    /** Returns the list of runtime permissions to request as a single system dialog. */
    fun runtimePermissionsToRequest(context: Context): Array<String> {
        val list = mutableListOf<String>()
        if (!fineLocationGranted(context)) {
            list.add(Manifest.permission.ACCESS_FINE_LOCATION)
            list.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !notificationsGranted(context)) {
            list.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        return list.toTypedArray()
    }

    fun requestBackgroundLocation(activity: Activity, requestCode: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            activity.requestPermissions(
                arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                requestCode
            )
        }
    }

    fun requestBatteryOptExemption(activity: Activity) {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        activity.startActivity(intent)
    }

    fun openLocationSettings(activity: Activity) {
        activity.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
    }

    fun openAppSettings(activity: Activity) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        activity.startActivity(intent)
    }
}
