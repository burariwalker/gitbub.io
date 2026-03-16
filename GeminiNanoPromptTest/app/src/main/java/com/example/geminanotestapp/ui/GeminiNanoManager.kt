package com.example.geminanotestapp.ui

import android.content.Context
import android.util.Log
import com.google.mlkit.genai.common.DownloadCallback
import com.google.mlkit.genai.common.DownloadConfig
import com.google.mlkit.genai.prompt.PromptClient
import com.google.mlkit.genai.prompt.PromptOptions
import com.google.mlkit.genai.prompt.PromptRequest
import com.google.mlkit.genai.prompt.PromptResponse
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class GeminiNanoManager(private val context: Context) {

    companion object {
        private const val TAG = "GeminiNanoManager"

        private const val SYSTEM_PROMPT = """You are a highly efficient life-logging assistant.
Analyze the following Japanese conversation transcript and provide a brief analysis.
Output STRICTLY in JSON format without any markdown tags or conversational text."""

        private const val PROMPT_TEMPLATE = """[Previous Context]
{previous_summary}

[Current Transcript]
{current_transcript}

[Output JSON Format]
{"summary": "1-2 sentences summarizing the transcript in Japanese.", "tags": ["keyword1", "keyword2"], "mood": "One Japanese word describing the emotional tone", "feedback": "One short Japanese sentence of advice or encouragement based on the activity."}"""
    }

    private var promptClient: PromptClient? = null

    suspend fun initialize(): Result<Unit> = suspendCancellableCoroutine { continuation ->
        try {
            val client = PromptClient.create(context)
            promptClient = client

            client.checkFeatureStatus()
                .addOnSuccessListener { featureStatus ->
                    Log.d(TAG, "Feature status: $featureStatus")
                    continuation.resume(Result.success(Unit))
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Feature status check failed", e)
                    continuation.resumeWithException(e)
                }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create PromptClient", e)
            continuation.resumeWithException(e)
        }
    }

    suspend fun downloadModelIfNeeded(): Result<Unit> = suspendCancellableCoroutine { continuation ->
        val client = promptClient ?: run {
            continuation.resumeWithException(IllegalStateException("PromptClient not initialized"))
            return@suspendCancellableCoroutine
        }

        val downloadConfig = DownloadConfig.Builder().build()
        client.downloadIfNeeded(downloadConfig, object : DownloadCallback {
            override fun onDownloadStarted(bytesToDownload: Long) {
                Log.d(TAG, "Download started: $bytesToDownload bytes")
            }

            override fun onDownloadFailed(e: Exception) {
                Log.e(TAG, "Download failed", e)
                continuation.resumeWithException(e)
            }

            override fun onDownloadProgress(bytesDownloaded: Long, bytesTotal: Long) {
                Log.d(TAG, "Download progress: $bytesDownloaded / $bytesTotal")
            }

            override fun onDownloadComplete() {
                Log.d(TAG, "Download complete")
                continuation.resume(Result.success(Unit))
            }
        })
    }

    suspend fun runPrompt(
        previousContext: String,
        transcript: String
    ): Result<String> = suspendCancellableCoroutine { continuation ->
        val client = promptClient ?: run {
            continuation.resumeWithException(IllegalStateException("PromptClient not initialized"))
            return@suspendCancellableCoroutine
        }

        val userPrompt = PROMPT_TEMPLATE
            .replace("{previous_summary}", previousContext.ifBlank { "なし" })
            .replace("{current_transcript}", transcript)

        val promptOptions = PromptOptions.Builder()
            .setSystemInstruction(SYSTEM_PROMPT)
            .build()

        val request = PromptRequest.Builder()
            .addTextPrompt(userPrompt)
            .setPromptOptions(promptOptions)
            .build()

        Log.d(TAG, "Sending prompt, length: ${userPrompt.length} chars")

        client.runPrompt(request)
            .addOnSuccessListener { response: PromptResponse ->
                val rawText = response.text ?: ""
                Log.d(TAG, "Raw response: $rawText")
                continuation.resume(Result.success(rawText))
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Prompt execution failed", e)
                continuation.resumeWithException(e)
            }
    }

    fun close() {
        promptClient?.close()
        promptClient = null
    }
}
