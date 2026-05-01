package com.example.geminiprompttest.prompt

import android.util.Log
import com.google.mlkit.genai.prompt.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import kotlinx.coroutines.tasks.await

private const val TAG = "GeminiNanoClient"

// NOTE: Generation.getClient() returns a GenerativeModel bound to Gemini Nano via AICore.
// The API surface below is based on genai-prompt:1.0.0-beta1.
// If compilation errors occur, check the exact class/method names in the unpacked AAR.
class GeminiNanoClient {

    private val model: GenerativeModel = Generation.getClient()

    /**
     * Returns the current on-device feature availability status.
     *
     * checkFeatureStatus() returns Task<FeatureStatus> in beta1 — we await it.
     * If the library switches to a suspend function in a later build, remove .await().
     */
    suspend fun checkFeatureStatus(): FeatureStatus {
        return try {
            model.checkFeatureStatus().await()
        } catch (e: Exception) {
            Log.w(TAG, "checkFeatureStatus failed", e)
            FeatureStatus.UNAVAILABLE
        }
    }

    /**
     * Triggers model/adapter download when status is DOWNLOADABLE.
     * Returns true when the model is available after the call.
     */
    suspend fun prepareModel(onProgress: (String) -> Unit): Boolean {
        return try {
            val status = checkFeatureStatus()
            Log.d(TAG, "Feature status: $status")
            when (status) {
                FeatureStatus.AVAILABLE -> true
                FeatureStatus.DOWNLOADABLE -> {
                    onProgress("モデルをダウンロード中…")
                    model.downloadFeature().await()
                    onProgress("ダウンロード完了")
                    checkFeatureStatus() == FeatureStatus.AVAILABLE
                }
                FeatureStatus.DOWNLOADING -> {
                    onProgress("ダウンロード中（バックグラウンド）…")
                    // Poll until available (simple linear wait, max 60s)
                    repeat(12) {
                        kotlinx.coroutines.delay(5_000)
                        if (checkFeatureStatus() == FeatureStatus.AVAILABLE) return true
                    }
                    false
                }
                else -> {
                    onProgress("このデバイスはGemini Nanoに対応していません")
                    false
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "prepareModel failed", e)
            onProgress("モデル準備エラー: ${e.message}")
            false
        }
    }

    /**
     * Sends [prompt] to Gemini Nano and returns the raw text response.
     *
     * generateContent(String) is a suspend function per community samples.
     * maxOutputTokens is constrained to 256 via GenerateContentRequest DSL.
     *
     * If GenerateContentRequest DSL is unavailable in beta1, fall back to the
     * simple String overload (commented out below) and accept default token limits.
     */
    suspend fun generate(prompt: String): String {
        return try {
            // --- Option A: DSL builder (preferred, caps output to 256 tokens) ---
            val request = com.google.mlkit.genai.prompt.generateContentRequest(
                com.google.mlkit.genai.prompt.TextPart(prompt)
            ) {
                temperature = 0.7f
                topK = 40
                candidateCount = 1
                maxOutputTokens = 256
            }
            val response = model.generateContent(request)
            response.candidates.firstOrNull()?.text ?: ""

            // --- Option B: plain String overload (fallback if Option A won't compile) ---
            // val response = model.generateContent(prompt)
            // response.candidates.firstOrNull()?.text ?: ""
        } catch (e: Exception) {
            Log.e(TAG, "generate failed", e)
            throw e
        }
    }

    fun close() {
        try {
            model.close()
        } catch (_: Exception) {
        }
    }
}
