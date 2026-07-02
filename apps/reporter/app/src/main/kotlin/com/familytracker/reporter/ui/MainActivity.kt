package com.familytracker.reporter.ui

import android.annotation.SuppressLint
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.tasks.await
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.familytracker.reporter.ApprovalStatus
import com.familytracker.reporter.Storage
import com.familytracker.reporter.net.RelayClient
import com.familytracker.reporter.service.LocationForegroundService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : AppCompatActivity() {

    private val tag = "Reporter/Main"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var pollJob: Job? = null
    private var registerJob: Job? = null

    private lateinit var storage: Storage
    private lateinit var relay: RelayClient

    private lateinit var titleView: TextView
    private lateinit var subtitleView: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var actionButton: Button

    private val requestCodeRuntime = 100
    private val requestCodeBackground = 101

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        storage = Storage(this)
        relay = RelayClient()
        buildUi()
        refresh()
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }

    // ── UI ───────────────────────────────────────────────────────────

    private fun buildUi() {
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(64, 128, 64, 128)
        }

        titleView = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            gravity = Gravity.CENTER
        }
        subtitleView = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 32)
        }
        progressBar = ProgressBar(this).apply { visibility = View.GONE }
        actionButton = Button(this).apply {
            visibility = View.GONE
            setOnClickListener { onActionClicked() }
        }

        container.addView(titleView)
        container.addView(subtitleView)
        container.addView(progressBar)
        container.addView(actionButton)
        setContentView(container)
    }

    private fun show(
        title: String,
        subtitle: String = "",
        showSpinner: Boolean = false,
        buttonLabel: String? = null
    ) {
        titleView.text = title
        subtitleView.text = subtitle
        progressBar.visibility = if (showSpinner) View.VISIBLE else View.GONE
        if (buttonLabel != null) {
            actionButton.text = buttonLabel
            actionButton.visibility = View.VISIBLE
        } else {
            actionButton.visibility = View.GONE
        }
    }

    // ── State machine ─────────────────────────────────────────────────

    private var currentAction: (() -> Unit)? = null

    private fun onActionClicked() {
        currentAction?.invoke()
    }

    private fun refresh() {
        when (storage.approval) {
            ApprovalStatus.APPROVED -> onApproved()
            ApprovalStatus.REMOVED -> onRemoved()
            ApprovalStatus.PENDING, ApprovalStatus.UNKNOWN -> onPending()
        }
    }

    private fun onPending() {
        val perms = PermissionSequence.snapshot(this)
        if (!perms.allGranted) {
            requestNextMissingPermission(perms)
            return
        }
        if (storage.joinRegistered) {
            show(
                title = "Waiting for approval...",
                subtitle = "You may close this screen.\nTracking will begin automatically after approval.",
                showSpinner = true
            )
            startPolling()
        } else {
            attemptRegistration()
        }
    }

    private fun onApproved() {
        LocationForegroundService.start(this)
        stopPolling()
        cancelRegistration()
        show(
            title = "All set",
            subtitle = "Location tracking is now active.\nYou may close this screen."
        )
    }

    private fun onRemoved() {
        LocationForegroundService.stop(this)
        stopPolling()
        cancelRegistration()
        show(
            title = "Device removed",
            subtitle = "This device is no longer being tracked."
        )
    }

    // ── Permission flow ───────────────────────────────────────────────

    private fun requestNextMissingPermission(perms: PermissionState) {
        when {
            !perms.locationEnabledOnDevice -> {
                show(
                    title = "Location is off",
                    subtitle = "Please turn on device Location in Settings.",
                    buttonLabel = "Open Settings"
                )
                currentAction = { PermissionSequence.openLocationSettings(this) }
            }
            !perms.notificationsGranted || !perms.fineLocationGranted -> {
                show(title = "Setting up", subtitle = "Please grant the requested permissions.", showSpinner = true)
                requestPermissions(
                    PermissionSequence.runtimePermissionsToRequest(this),
                    requestCodeRuntime
                )
            }
            !perms.backgroundLocationGranted -> {
                show(
                    title = "Background location",
                    subtitle = "Please choose \"Allow all the time\" so tracking works when the app is closed.",
                    buttonLabel = "Continue"
                )
                currentAction = {
                    PermissionSequence.requestBackgroundLocation(this, requestCodeBackground)
                }
            }
            !perms.batteryOptExempt -> {
                show(
                    title = "Battery optimization",
                    subtitle = "Please exempt this app from battery optimization to keep tracking reliable.",
                    buttonLabel = "Continue"
                )
                currentAction = { PermissionSequence.requestBatteryOptExemption(this) }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        refresh()
    }

    // ── Registration ──────────────────────────────────────────────────

    private fun cancelRegistration() {
        registerJob?.cancel()
        registerJob = null
    }

    private fun attemptRegistration() {
        cancelRegistration()
        show(title = "Registering device...", subtitle = "", showSpinner = true)

        registerJob = scope.launch {
            val androidId = getStableDeviceId()
            storage.androidId = androidId

            val error = withContext(Dispatchers.IO) {
                try {
                    val fcmToken = fetchFcmToken()
                    storage.fcmToken = fcmToken
                    storage.fcmTokenDirty = false

                    relay.submitJoin(
                        androidId = androidId,
                        deviceModel = Build.MODEL ?: "android device",
                        fcmToken = fcmToken ?: "no-fcm-token",
                        osVersion = "${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})"
                    )
                    null
                } catch (e: Exception) {
                    Log.w(tag, "Join failed", e)
                    e
                }
            }

            if (error == null) {
                storage.joinRegistered = true
                storage.approval = ApprovalStatus.PENDING
                onPending()
            } else {
                show(
                    title = "Registration failed",
                    subtitle = friendlyError(error),
                    buttonLabel = "Try Again"
                )
                currentAction = { attemptRegistration() }
            }
        }
    }

    private fun friendlyError(e: Throwable): String {
        val s = e.toString()
        return when {
            "Connection refused" in s || "ECONNREFUSED" in s ->
                "Cannot reach server. Check that the server is running and this device is on the same network."
            "timeout" in s.lowercase() ->
                "Server did not respond in time. Try again."
            "Unable to resolve host" in s ->
                "Cannot resolve server address."
            else -> s
        }
    }

    /**
     * Returns a stable identifier for this device that survives app data
     * clears and reinstalls. Only changes on factory reset.
     *
     * We prefer the value we already stored (in case Android ever changed
     * ANDROID_ID under us). Only fall back to a generated timestamp if the
     * platform value is somehow missing.
     */
    @SuppressLint("HardwareIds")
    private fun getStableDeviceId(): String {
        storage.androidId?.let { return it }

        val platformId = try {
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        } catch (_: Exception) {
            null
        }

        if (!platformId.isNullOrBlank() && platformId != "9774d56d682e549c") {
            // Prefix so it's clearly a device id in logs, and to keep the
            // shape consistent with our historical `android-...` values.
            return "android-$platformId"
        }

        // Absolute fallback: some emulators return null or the well-known
        // buggy value above. Generate a timestamp id and store it.
        val fallback = "android-${System.currentTimeMillis().toString(36)}"
        Log.w(tag, "ANDROID_ID unavailable; using fallback id")
        return fallback
    }

    private suspend fun fetchFcmToken(): String? {
        return try {
            FirebaseMessaging.getInstance().token.await()
        } catch (e: Exception) {
            Log.w(tag, "FCM token fetch failed", e)
            null
        }
    }

    // ── Polling ───────────────────────────────────────────────────────

    private fun startPolling() {
        if (pollJob?.isActive == true) return
        val androidId = storage.androidId ?: return

        pollJob = scope.launch {
            while (true) {
                try {
                    val status = withContext(Dispatchers.IO) {
                        relay.getDeviceStatus(androidId)
                    }
                    Log.i(tag, "Poll status=${status.status}")

                    when (status.status) {
                        "approved" -> {
                            storage.approval = ApprovalStatus.APPROVED
                            storage.ingestToken = status.ingestToken
                            storage.ingestUrl = status.ingestUrl
                            onApproved()
                            return@launch
                        }
                        "removed" -> {
                            storage.approval = ApprovalStatus.REMOVED
                            onRemoved()
                            return@launch
                        }
                        else -> { /* still pending */ }
                    }
                } catch (e: Exception) {
                    Log.w(tag, "Poll failed", e)
                }
                delay(15_000L)
            }
        }
    }

    private fun stopPolling() {
        pollJob?.cancel()
        pollJob = null
    }
}
