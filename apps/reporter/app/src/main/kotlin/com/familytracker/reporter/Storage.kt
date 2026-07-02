package com.familytracker.reporter

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class Storage(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val securePrefs: SharedPreferences by lazy {
        val master = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            SECURE_PREFS_NAME,
            master,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    // ── Approval state ─────────────────────────────────────────────
    var approval: ApprovalStatus
        get() = ApprovalStatus.valueOf(prefs.getString(KEY_APPROVAL, "PENDING")!!)
        set(v) = prefs.edit().putString(KEY_APPROVAL, v.name).apply()

    var mode: TrackingMode
        get() = TrackingMode.valueOf(prefs.getString(KEY_MODE, "IDLE")!!)
        set(v) = prefs.edit().putString(KEY_MODE, v.name).apply()

    var liveExpiresAt: Long
        get() = prefs.getLong(KEY_LIVE_EXPIRES_AT, 0L)
        set(v) = prefs.edit().putLong(KEY_LIVE_EXPIRES_AT, v).apply()

    var androidId: String?
        get() = prefs.getString(KEY_ANDROID_ID, null)
        set(v) = prefs.edit().putString(KEY_ANDROID_ID, v).apply()

    var joinRegistered: Boolean
        get() = prefs.getBoolean(KEY_JOIN_REGISTERED, false)
        set(v) = prefs.edit().putBoolean(KEY_JOIN_REGISTERED, v).apply()

    var ingestUrl: String?
        get() = prefs.getString(KEY_INGEST_URL, null)
        set(v) = prefs.edit().putString(KEY_INGEST_URL, v).apply()

    // ── Secrets ────────────────────────────────────────────────────
    var ingestToken: String?
        get() = securePrefs.getString(KEY_INGEST_TOKEN, null)
        set(v) = securePrefs.edit().putString(KEY_INGEST_TOKEN, v).apply()

    companion object {
        private const val PREFS_NAME = "reporter_prefs"
        private const val SECURE_PREFS_NAME = "reporter_secure_prefs"
        private const val KEY_APPROVAL = "approval"
        private const val KEY_MODE = "mode"
        private const val KEY_LIVE_EXPIRES_AT = "live_expires_at"
        private const val KEY_ANDROID_ID = "android_id"
        private const val KEY_JOIN_REGISTERED = "join_registered"
        private const val KEY_INGEST_URL = "ingest_url"
        private const val KEY_INGEST_TOKEN = "ingest_token"
    }
}
