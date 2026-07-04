package com.familytracker.reporter.net

import android.content.Context
import android.util.Log
import java.io.File

/**
 * Simple file-based queue for positions that couldn't be sent due to
 * network errors. Each line is a ready-to-send URL query string.
 *
 * On each successful post, we attempt to flush any queued positions.
 * Max queue size: 500 entries (~50 KB). Oldest are dropped if exceeded.
 */
class PositionQueue(context: Context) {

    private val tag = "Reporter/Queue"
    private val file = File(context.filesDir, "position_queue.txt")
    private val maxEntries = 500

    /** Add a failed position URL to the queue. */
    @Synchronized
    fun enqueue(url: String) {
        try {
            file.appendText("$url\n")
            trimIfNeeded()
            Log.i(tag, "Queued position (${count()} in queue)")
        } catch (e: Exception) {
            Log.w(tag, "Failed to queue position", e)
        }
    }

    /** Returns all queued URLs and clears the file. */
    @Synchronized
    fun drainAll(): List<String> {
        if (!file.exists()) return emptyList()
        try {
            val lines = file.readLines().filter { it.isNotBlank() }
            file.writeText("")
            return lines
        } catch (e: Exception) {
            Log.w(tag, "Failed to drain queue", e)
            return emptyList()
        }
    }

    fun count(): Int {
        if (!file.exists()) return 0
        return try {
            file.readLines().count { it.isNotBlank() }
        } catch (_: Exception) {
            0
        }
    }

    private fun trimIfNeeded() {
        if (!file.exists()) return
        try {
            val lines = file.readLines().filter { it.isNotBlank() }
            if (lines.size > maxEntries) {
                val trimmed = lines.takeLast(maxEntries)
                file.writeText(trimmed.joinToString("\n") + "\n")
                Log.i(tag, "Trimmed queue to $maxEntries entries")
            }
        } catch (_: Exception) {}
    }
}
