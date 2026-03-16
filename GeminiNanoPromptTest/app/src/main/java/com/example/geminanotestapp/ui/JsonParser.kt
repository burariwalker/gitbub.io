package com.example.geminanotestapp.ui

import android.util.Log
import com.example.geminanotestapp.model.AnalysisResult
import com.google.gson.Gson
import com.google.gson.JsonSyntaxException

class JsonParser {

    companion object {
        private const val TAG = "JsonParser"
    }

    private val gson = Gson()

    data class ParseResult(
        val success: Boolean,
        val result: AnalysisResult?,
        val errorMessage: String?,
        val cleanedJson: String
    )

    fun parse(rawOutput: String): ParseResult {
        val cleaned = extractJson(rawOutput)

        if (cleaned.isBlank()) {
            return ParseResult(
                success = false,
                result = null,
                errorMessage = "JSON not found in output",
                cleanedJson = rawOutput
            )
        }

        return try {
            val result = gson.fromJson(cleaned, AnalysisResult::class.java)

            // Validate required fields
            if (result.summary.isBlank()) {
                return ParseResult(
                    success = false,
                    result = result,
                    errorMessage = "Missing required field: summary",
                    cleanedJson = cleaned
                )
            }

            Log.d(TAG, "Parse success: $result")
            ParseResult(success = true, result = result, errorMessage = null, cleanedJson = cleaned)
        } catch (e: JsonSyntaxException) {
            Log.e(TAG, "JSON parse error: ${e.message}")
            ParseResult(
                success = false,
                result = null,
                errorMessage = "JSON syntax error: ${e.message}",
                cleanedJson = cleaned
            )
        } catch (e: Exception) {
            Log.e(TAG, "Parse failed", e)
            ParseResult(
                success = false,
                result = null,
                errorMessage = "Parse error: ${e.message}",
                cleanedJson = cleaned
            )
        }
    }

    private fun extractJson(text: String): String {
        // Remove markdown code blocks if present
        var cleaned = text.trim()
        cleaned = cleaned.removePrefix("```json").removePrefix("```").removeSuffix("```").trim()

        // Try to find JSON object boundaries
        val startIdx = cleaned.indexOf('{')
        val endIdx = cleaned.lastIndexOf('}')

        return if (startIdx >= 0 && endIdx > startIdx) {
            cleaned.substring(startIdx, endIdx + 1)
        } else {
            cleaned
        }
    }
}
