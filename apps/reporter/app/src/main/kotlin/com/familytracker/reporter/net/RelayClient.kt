package com.familytracker.reporter.net

import com.familytracker.reporter.Config
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class RelayClient {

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .build()

    private val json = "application/json".toMediaType()

    /** POST /join — returns nothing on success, throws on failure. */
    fun submitJoin(
        androidId: String,
        deviceModel: String,
        fcmToken: String,
        osVersion: String
    ) {
        val body = JSONObject().apply {
            put("androidId", androidId)
            put("deviceModel", deviceModel)
            put("fcmToken", fcmToken)
            put("osVersion", osVersion)
        }

        val req = Request.Builder()
            .url(Config.RELAY_BASE_URL + Config.JOIN_PATH)
            .post(body.toString().toRequestBody(json))
            .build()

        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                throw RuntimeException("Join failed: HTTP ${resp.code}")
            }
        }
    }

    /** GET /api/device/status?androidId=... */
    fun getDeviceStatus(androidId: String): DeviceStatus {
        val url = Config.RELAY_BASE_URL + Config.STATUS_PATH + "?androidId=" + androidId
        val req = Request.Builder().url(url).get().build()

        client.newCall(req).execute().use { resp ->
            val bodyStr = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                throw RuntimeException("Status failed: HTTP ${resp.code} $bodyStr")
            }
            val obj = JSONObject(bodyStr)
            return DeviceStatus(
                status = obj.getString("status"),
                ingestToken = obj.optString("ingestToken").ifEmpty { null },
                ingestUrl = obj.optString("ingestUrl").ifEmpty { null }
            )
        }
    }

    /**
     * Pushes a rotated FCM token to the relay so it can reach this device.
     * Authenticates with the ingest token (which we already hold post-approval).
     */
    fun refreshFcm(androidId: String, ingestToken: String, fcmToken: String) {
        val body = JSONObject().apply {
            put("androidId", androidId)
            put("ingestToken", ingestToken)
            put("fcmToken", fcmToken)
        }
        val req = Request.Builder()
            .url(Config.RELAY_BASE_URL + "/api/device/refresh-fcm")
            .post(body.toString().toRequestBody(json))
            .build()

        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                throw RuntimeException("refresh-fcm failed: HTTP ${resp.code}")
            }
        }
    }
}

data class DeviceStatus(
    val status: String,
    val ingestToken: String?,
    val ingestUrl: String?
)
