package com.example.geminiprompttest.data

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class PromptResult(
    val scenarioId: Int,
    val scenarioTitle: String,
    val previousContext: String,
    val fullPrompt: String,
    val rawOutput: String,
    val parseSuccess: Boolean,
    val summary: String? = null,
    val tags: List<String> = emptyList(),
    val mood: String? = null,
    val feedback: String? = null,
    val parseError: String? = null,
    val elapsedMs: Long = 0L,
    val timestamp: Long = System.currentTimeMillis(),
) {
    val timestampFormatted: String
        get() = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date(timestamp))
}
