package com.familytracker.reporter

import android.app.Application
import android.util.Log
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ReporterApp : Application() {

    companion object {
        private const val MAX_CRASH_FILES = 10
        private const val TAG = "Reporter/Crash"
    }

    override fun onCreate() {
        super.onCreate()
        val handler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            writeCrashLog(throwable)
            handler?.uncaughtException(thread, throwable)
        }
    }

    private fun writeCrashLog(t: Throwable) {
        try {
            val dir = File(filesDir, "crash")
            if (!dir.exists()) dir.mkdirs()

            // Rotate old logs
            val files = dir.listFiles()?.sortedBy { it.lastModified() }?.toMutableList() ?: mutableListOf()
            while (files.size >= MAX_CRASH_FILES) {
                files.first().delete()
                files.removeAt(0)
            }

            val sdf = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US)
            val name = "crash_${sdf.format(Date())}.log"
            val file = File(dir, name)

            FileWriter(file).use { w ->
                w.write("=== CRASH ${Date()} ===\n")
                w.write("Thread: ${t.stackTrace[0].fileName}:${t.stackTrace[0].lineNumber}\n")
                w.write("${t.javaClass.name}: ${t.message}\n")
                for (el in t.stackTrace) {
                    w.write("\tat $el\n")
                }
                // Cause chain
                var cause = t.cause
                while (cause != null) {
                    w.write("Caused by: ${cause.javaClass.name}: ${cause.message}\n")
                    for (el in cause.stackTrace) {
                        w.write("\tat $el\n")
                    }
                    cause = cause.cause
                }
            }
            Log.i(TAG, "Crash log written to $name")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write crash log", e)
        }
    }
}
