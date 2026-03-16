package com.example.geminanotestapp.model

import com.google.gson.annotations.SerializedName

data class AnalysisResult(
    @SerializedName("summary") val summary: String = "",
    @SerializedName("tags") val tags: List<String> = emptyList(),
    @SerializedName("mood") val mood: String = "",
    @SerializedName("feedback") val feedback: String = ""
)

data class TestLogEntry(
    val timestamp: String,
    val scenarioTitle: String,
    val previousContext: String,
    val rawOutput: String,
    val parseSuccess: Boolean,
    val parsedResult: AnalysisResult?,
    val errorMessage: String?
)
