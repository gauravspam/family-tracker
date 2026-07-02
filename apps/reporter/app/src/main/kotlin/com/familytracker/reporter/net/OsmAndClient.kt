package com.familytracker.reporter.net

import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

class OsmAndClient {

    private val tag = "Reporter/OsmAnd"

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .build()

    /**
     * Sends a position via OsmAnd HTTP protocol.
     * Traccar returns 200 on success even with an empty body.
     */
    fun postPosition(
        ingestUrl: String,
        ingestToken: String,
        latitude: Double,
        longitude: Double,
        timestampEpochSec: Long,
        accuracyMeters: Float,
        altitudeMeters: Double,
        speedMs: Float
    ) {
        val url = buildString {
            append(ingestUrl.trimEnd('/'))
            append("/?id=")
            append(ingestToken)
            append("&lat=").append(latitude)
            append("&lon=").append(longitude)
            append("&timestamp=").append(timestampEpochSec)
            append("&hdop=").append(accuracyMeters)
            append("&altitude=").append(altitudeMeters)
            append("&speed=").append(speedMs)
        }

        val req = Request.Builder().url(url).get().build()

        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                Log.w(tag, "OsmAnd post failed: HTTP ${resp.code}")
                throw RuntimeException("OsmAnd HTTP ${resp.code}")
            }
            Log.i(tag, "Posted lat=$latitude lon=$longitude accuracy=$accuracyMeters")
        }
    }
}
