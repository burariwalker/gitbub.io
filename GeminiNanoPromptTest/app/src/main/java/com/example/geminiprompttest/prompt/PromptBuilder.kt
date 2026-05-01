package com.example.geminiprompttest.prompt

object PromptBuilder {

    // System prompt in English per official recommendation (ja unverified for Nano)
    private const val SYSTEM_PROMPT = """You are a highly efficient life-logging assistant.
Analyze the following Japanese conversation transcript and provide a brief analysis.
Output STRICTLY in JSON format without any markdown tags or conversational text."""

    private const val OUTPUT_FORMAT = """{
  "summary": "1-2 sentences summarizing the transcript in Japanese.",
  "tags": ["keyword1", "keyword2"],
  "mood": "One Japanese word describing the emotional tone",
  "feedback": "One short Japanese sentence of advice or encouragement based on the activity."
}"""

    fun build(transcript: String, previousSummary: String): String {
        val previousSection = if (previousSummary.isBlank()) "なし" else previousSummary.trim()
        return buildString {
            appendLine(SYSTEM_PROMPT)
            appendLine()
            appendLine("[Previous Context]")
            appendLine(previousSection)
            appendLine()
            appendLine("[Current Transcript]")
            appendLine(transcript.trim())
            appendLine()
            appendLine("[Output JSON Format]")
            append(OUTPUT_FORMAT)
        }
    }

    /** Rough token estimate: ~1 token per 0.6 Japanese chars, 1 token per ~4 English chars */
    fun estimateTokenCount(text: String): Int {
        val japaneseCharCount = text.count { it.code in 0x3000..0x9FFF || it.code in 0xF900..0xFAFF }
        val otherCharCount = text.length - japaneseCharCount
        return (japaneseCharCount / 0.6 + otherCharCount / 4.0).toInt()
    }
}
