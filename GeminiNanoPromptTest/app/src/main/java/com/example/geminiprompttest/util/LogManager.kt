package com.example.geminiprompttest.util

import android.content.Context
import android.util.Log
import com.example.geminiprompttest.data.PromptResult
import com.google.gson.GsonBuilder
import java.io.File

private const val TAG = "LogManager"
private const val LOG_FILENAME = "prompt_test_logs.jsonl"

object LogManager {

    private val gson = GsonBuilder().setPrettyPrinting().create()

    /** Returns the log file in the app's private files directory. */
    fun getLogFile(context: Context): File =
        File(context.filesDir, LOG_FILENAME)

    /**
     * Appends [result] as a single JSON line to the log file.
     * Uses JSON Lines format (one object per line) for easy parsing.
     */
    fun append(context: Context, result: PromptResult) {
        try {
            val logFile = getLogFile(context)
            val entry = buildString {
                appendLine("=== ${result.timestampFormatted} | ${result.scenarioTitle} | ${result.elapsedMs}ms ===")
                appendLine(gson.toJson(result))
                appendLine()
            }
            logFile.appendText(entry, Charsets.UTF_8)
            Log.d(TAG, "Appended log entry for scenario ${result.scenarioId} to ${logFile.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write log", e)
        }
    }

    /** Returns all saved log entries as raw text. */
    fun readAll(context: Context): String {
        return try {
            val logFile = getLogFile(context)
            if (logFile.exists()) logFile.readText(Charsets.UTF_8) else "(ログファイルなし)"
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read log", e)
            "読み込みエラー: ${e.message}"
        }
    }

    /** Deletes the log file. Returns true on success. */
    fun clear(context: Context): Boolean {
        return try {
            getLogFile(context).delete().also {
                Log.d(TAG, "Log file deleted: $it")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear log", e)
            false
        }
    }

    /** Returns a human-readable summary of the log file location and size. */
    fun fileInfo(context: Context): String {
        val file = getLogFile(context)
        return if (file.exists()) {
            "保存先: ${file.absolutePath}\nサイズ: ${file.length() / 1024} KB"
        } else {
            "ログファイル未作成"
        }
    }
}
