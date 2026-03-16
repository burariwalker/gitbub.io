package com.example.geminanotestapp.ui

import android.content.Context
import android.util.Log
import com.example.geminanotestapp.model.AnalysisResult
import com.example.geminanotestapp.model.TestLogEntry
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import java.io.File
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

class LogManager(private val context: Context) {

    companion object {
        private const val TAG = "LogManager"
        private const val LOG_DIR = "gemini_nano_logs"
        private val TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd_HH-mm-ss")
        private val LOG_TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
    }

    private val gson: Gson = GsonBuilder().setPrettyPrinting().create()

    private fun getLogDirectory(): File {
        val logDir = File(context.filesDir, LOG_DIR)
        if (!logDir.exists()) {
            logDir.mkdirs()
        }
        return logDir
    }

    fun saveLog(entry: TestLogEntry): File? {
        return try {
            val logDir = getLogDirectory()
            val timestamp = LocalDateTime.now().format(TIMESTAMP_FORMAT)
            val scenarioName = entry.scenarioTitle.replace(" ", "_").replace("/", "-")
            val fileName = "log_${timestamp}_${scenarioName}.json"
            val file = File(logDir, fileName)

            val jsonContent = gson.toJson(entry)
            file.writeText(jsonContent, Charsets.UTF_8)

            Log.d(TAG, "Log saved: ${file.absolutePath}")
            file
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save log", e)
            null
        }
    }

    fun buildLogEntry(
        scenarioTitle: String,
        previousContext: String,
        rawOutput: String,
        parseSuccess: Boolean,
        parsedResult: AnalysisResult?,
        errorMessage: String?
    ): TestLogEntry {
        return TestLogEntry(
            timestamp = LocalDateTime.now().format(LOG_TIMESTAMP_FORMAT),
            scenarioTitle = scenarioTitle,
            previousContext = previousContext,
            rawOutput = rawOutput,
            parseSuccess = parseSuccess,
            parsedResult = parsedResult,
            errorMessage = errorMessage
        )
    }

    fun listLogFiles(): List<File> {
        return try {
            getLogDirectory().listFiles()
                ?.filter { it.extension == "json" }
                ?.sortedByDescending { it.lastModified() }
                ?: emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to list log files", e)
            emptyList()
        }
    }

    fun getLogDirectoryPath(): String = getLogDirectory().absolutePath
}
