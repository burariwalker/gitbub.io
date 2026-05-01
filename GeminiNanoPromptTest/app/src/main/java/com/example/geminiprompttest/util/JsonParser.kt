package com.example.geminiprompttest.util

import com.example.geminiprompttest.data.PromptResult
import com.example.geminiprompttest.data.Scenario
import com.google.gson.JsonParser
import com.google.gson.JsonSyntaxException

object PromptJsonParser {

    data class ParsedFields(
        val summary: String?,
        val tags: List<String>,
        val mood: String?,
        val feedback: String?,
    )

    /**
     * Extracts and parses the JSON from [rawOutput].
     * Nano sometimes wraps JSON in markdown fences or adds leading text —
     * we strip those before parsing.
     */
    fun parse(rawOutput: String): Result<ParsedFields> {
        val cleaned = extractJson(rawOutput)
        return try {
            val json = JsonParser.parseString(cleaned).asJsonObject

            val summary = json.get("summary")?.takeIf { !it.isJsonNull }?.asString
            val tags = json.getAsJsonArray("tags")
                ?.mapNotNull { it.takeIf { e -> !e.isJsonNull }?.asString }
                ?: emptyList()
            val mood = json.get("mood")?.takeIf { !it.isJsonNull }?.asString
            val feedback = json.get("feedback")?.takeIf { !it.isJsonNull }?.asString

            Result.success(ParsedFields(summary, tags, mood, feedback))
        } catch (e: JsonSyntaxException) {
            Result.failure(e)
        } catch (e: IllegalStateException) {
            Result.failure(e)
        }
    }

    fun toPromptResult(
        scenario: Scenario,
        previousContext: String,
        fullPrompt: String,
        rawOutput: String,
        elapsedMs: Long,
    ): PromptResult {
        val parseResult = parse(rawOutput)
        return if (parseResult.isSuccess) {
            val fields = parseResult.getOrThrow()
            PromptResult(
                scenarioId = scenario.id,
                scenarioTitle = scenario.title,
                previousContext = previousContext,
                fullPrompt = fullPrompt,
                rawOutput = rawOutput,
                parseSuccess = true,
                summary = fields.summary,
                tags = fields.tags,
                mood = fields.mood,
                feedback = fields.feedback,
                elapsedMs = elapsedMs,
            )
        } else {
            PromptResult(
                scenarioId = scenario.id,
                scenarioTitle = scenario.title,
                previousContext = previousContext,
                fullPrompt = fullPrompt,
                rawOutput = rawOutput,
                parseSuccess = false,
                parseError = parseResult.exceptionOrNull()?.message,
                elapsedMs = elapsedMs,
            )
        }
    }

    /** Strips markdown fences and leading/trailing non-JSON text, returns best-effort JSON string. */
    private fun extractJson(text: String): String {
        // Strip ```json ... ``` or ``` ... ```
        val fenceRegex = Regex("```(?:json)?\\s*([\\s\\S]*?)```", RegexOption.IGNORE_CASE)
        val fenceMatch = fenceRegex.find(text)
        if (fenceMatch != null) {
            return fenceMatch.groupValues[1].trim()
        }
        // Find first '{' and last '}' to handle leading/trailing garbage text
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start != -1 && end != -1 && end > start) {
            return text.substring(start, end + 1).trim()
        }
        return text.trim()
    }
}
