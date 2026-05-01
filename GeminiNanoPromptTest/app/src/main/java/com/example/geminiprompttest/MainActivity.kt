package com.example.geminiprompttest

import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.example.geminiprompttest.data.PromptResult
import com.example.geminiprompttest.data.SCENARIOS
import com.example.geminiprompttest.data.Scenario
import com.example.geminiprompttest.databinding.ActivityMainBinding
import com.example.geminiprompttest.prompt.GeminiNanoClient
import com.example.geminiprompttest.prompt.PromptBuilder
import com.example.geminiprompttest.util.LogManager
import com.example.geminiprompttest.util.PromptJsonParser
import com.google.mlkit.genai.prompt.FeatureStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val client = GeminiNanoClient()
    private var selectedScenario: Scenario = SCENARIOS[0]
    private var lastResult: PromptResult? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupScenarioButtons()
        setupActionButtons()
        checkModelAvailability()
        updateScenarioPreview()
    }

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    private fun setupScenarioButtons() {
        binding.btnScenario1.setOnClickListener { selectScenario(SCENARIOS[0]) }
        binding.btnScenario2.setOnClickListener { selectScenario(SCENARIOS[1]) }
        binding.btnScenario3.setOnClickListener { selectScenario(SCENARIOS[2]) }
        // Highlight initial selection
        updateScenarioButtonHighlight()
    }

    private fun setupActionButtons() {
        binding.btnRun.setOnClickListener { runTest() }
        binding.btnSaveLog.setOnClickListener { saveLog() }
        binding.btnClearContext.setOnClickListener {
            binding.editPreviousContext.setText("")
            Toast.makeText(this, "Previous Context をクリアしました", Toast.LENGTH_SHORT).show()
        }
        binding.btnCopyOutput.setOnClickListener {
            val text = binding.tvRawOutput.text.toString()
            if (text.isNotBlank()) {
                val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                clipboard.setPrimaryClip(android.content.ClipData.newPlainText("raw_output", text))
                Toast.makeText(this, "コピーしました", Toast.LENGTH_SHORT).show()
            }
        }
        binding.btnUseSummaryAsContext.setOnClickListener {
            lastResult?.summary?.let { summary ->
                binding.editPreviousContext.setText(summary)
                Toast.makeText(this, "Summary を Previous Context にセット", Toast.LENGTH_SHORT).show()
            } ?: Toast.makeText(this, "先にテストを実行してください", Toast.LENGTH_SHORT).show()
        }
        binding.btnViewLogs.setOnClickListener { showLogDialog() }
        binding.btnClearLogs.setOnClickListener { confirmClearLogs() }
    }

    // -------------------------------------------------------------------------
    // Scenario Selection
    // -------------------------------------------------------------------------

    private fun selectScenario(scenario: Scenario) {
        selectedScenario = scenario
        updateScenarioButtonHighlight()
        updateScenarioPreview()
    }

    private fun updateScenarioButtonHighlight() {
        val buttons = listOf(binding.btnScenario1, binding.btnScenario2, binding.btnScenario3)
        SCENARIOS.forEachIndexed { index, scenario ->
            buttons[index].isSelected = scenario.id == selectedScenario.id
            buttons[index].alpha = if (scenario.id == selectedScenario.id) 1.0f else 0.6f
        }
    }

    private fun updateScenarioPreview() {
        binding.tvScenarioDescription.text = selectedScenario.description
        binding.tvTranscriptPreview.text = selectedScenario.transcript
        val estimatedTokens = PromptBuilder.estimateTokenCount(
            PromptBuilder.build(selectedScenario.transcript, "")
        )
        binding.tvTokenEstimate.text = "推定トークン数: ~$estimatedTokens (上限4,000)"
    }

    // -------------------------------------------------------------------------
    // Model Availability Check
    // -------------------------------------------------------------------------

    private fun checkModelAvailability() {
        lifecycleScope.launch {
            setStatusText("モデル状態を確認中…")
            val status = withContext(Dispatchers.IO) { client.checkFeatureStatus() }
            when (status) {
                FeatureStatus.AVAILABLE -> {
                    setStatusText("✅ Gemini Nano 使用可能")
                    binding.btnRun.isEnabled = true
                }
                FeatureStatus.DOWNLOADABLE -> {
                    setStatusText("⬇️ モデルのダウンロードが必要です")
                    showDownloadDialog()
                }
                FeatureStatus.DOWNLOADING -> {
                    setStatusText("⏳ モデルダウンロード中…")
                    binding.btnRun.isEnabled = false
                }
                else -> {
                    setStatusText("❌ このデバイスはGemini Nanoに非対応 (API 35 / Pixel 9+必須)")
                    binding.btnRun.isEnabled = false
                }
            }
        }
    }

    private fun showDownloadDialog() {
        AlertDialog.Builder(this)
            .setTitle("モデルのダウンロード")
            .setMessage("Gemini Nanoモデルのダウンロードが必要です。Wi-Fi接続を確認してください。\nダウンロードしますか？")
            .setPositiveButton("ダウンロード") { _, _ ->
                lifecycleScope.launch {
                    binding.btnRun.isEnabled = false
                    val ready = withContext(Dispatchers.IO) {
                        client.prepareModel { msg ->
                            lifecycleScope.launch(Dispatchers.Main) { setStatusText(msg) }
                        }
                    }
                    if (ready) {
                        setStatusText("✅ ダウンロード完了 — 使用可能")
                        binding.btnRun.isEnabled = true
                    } else {
                        setStatusText("❌ ダウンロード失敗")
                    }
                }
            }
            .setNegativeButton("キャンセル", null)
            .show()
    }

    // -------------------------------------------------------------------------
    // Run Test
    // -------------------------------------------------------------------------

    private fun runTest() {
        val previousContext = binding.editPreviousContext.text.toString()
        val fullPrompt = PromptBuilder.build(selectedScenario.transcript, previousContext)

        setLoading(true)
        clearResults()
        binding.tvFullPromptPreview.text = fullPrompt

        lifecycleScope.launch {
            val startMs = System.currentTimeMillis()
            try {
                val rawOutput = withContext(Dispatchers.IO) { client.generate(fullPrompt) }
                val elapsedMs = System.currentTimeMillis() - startMs

                val result = PromptJsonParser.toPromptResult(
                    scenario = selectedScenario,
                    previousContext = previousContext,
                    fullPrompt = fullPrompt,
                    rawOutput = rawOutput,
                    elapsedMs = elapsedMs,
                )
                lastResult = result
                displayResult(result)

            } catch (e: Exception) {
                val elapsedMs = System.currentTimeMillis() - startMs
                binding.tvRawOutput.text = "エラー: ${e.javaClass.simpleName}\n${e.message}"
                binding.tvParseStatus.text = "❌ 推論エラー (${elapsedMs}ms)"
                binding.tvParseStatus.setTextColor(getColor(android.R.color.holo_red_dark))
            } finally {
                setLoading(false)
            }
        }
    }

    // -------------------------------------------------------------------------
    // Display Results
    // -------------------------------------------------------------------------

    private fun displayResult(result: PromptResult) {
        // Raw output
        binding.tvRawOutput.text = result.rawOutput

        // Elapsed time
        binding.tvElapsed.text = "推論時間: ${result.elapsedMs}ms"

        // Parse status
        if (result.parseSuccess) {
            binding.tvParseStatus.text = "✅ JSONパース成功"
            binding.tvParseStatus.setTextColor(getColor(android.R.color.holo_green_dark))
        } else {
            binding.tvParseStatus.text = "❌ JSONパース失敗: ${result.parseError}"
            binding.tvParseStatus.setTextColor(getColor(android.R.color.holo_red_dark))
        }

        // Parsed fields
        binding.tvFieldSummary.text = result.summary ?: "(なし)"
        binding.tvFieldTags.text = result.tags.joinToString(", ").ifEmpty { "(なし)" }
        binding.tvFieldMood.text = result.mood ?: "(なし)"
        binding.tvFieldFeedback.text = result.feedback ?: "(なし)"

        // Quality indicators
        val qualityText = buildString {
            appendLine("【品質判定】")
            appendLine("• JSON整合性: ${if (result.parseSuccess) "✅" else "❌"}")
            appendLine("• summary: ${if (!result.summary.isNullOrBlank()) "✅" else "❌"}")
            appendLine("• tags: ${if (result.tags.isNotEmpty()) "✅ (${result.tags.size}件)" else "❌"}")
            appendLine("• mood: ${if (!result.mood.isNullOrBlank()) "✅" else "❌"}")
            appendLine("• feedback: ${if (!result.feedback.isNullOrBlank()) "✅ (${result.feedback!!.length}字)" else "❌"}")
        }
        binding.tvQualityCheck.text = qualityText

        binding.groupResults.visibility = View.VISIBLE
    }

    private fun clearResults() {
        binding.groupResults.visibility = View.GONE
        binding.tvRawOutput.text = ""
        binding.tvParseStatus.text = ""
        binding.tvFieldSummary.text = ""
        binding.tvFieldTags.text = ""
        binding.tvFieldMood.text = ""
        binding.tvFieldFeedback.text = ""
        binding.tvQualityCheck.text = ""
        binding.tvElapsed.text = ""
    }

    // -------------------------------------------------------------------------
    // Logging
    // -------------------------------------------------------------------------

    private fun saveLog() {
        val result = lastResult
        if (result == null) {
            Toast.makeText(this, "保存するデータがありません。先にテストを実行してください。", Toast.LENGTH_SHORT).show()
            return
        }
        LogManager.append(this, result)
        Toast.makeText(this, "ログを保存しました\n${LogManager.fileInfo(this)}", Toast.LENGTH_LONG).show()
    }

    private fun showLogDialog() {
        val logs = LogManager.readAll(this)
        AlertDialog.Builder(this)
            .setTitle("保存済みログ\n${LogManager.fileInfo(this)}")
            .setMessage(if (logs.length > 5000) logs.takeLast(5000) + "\n[…省略…]" else logs)
            .setPositiveButton("閉じる", null)
            .show()
    }

    private fun confirmClearLogs() {
        AlertDialog.Builder(this)
            .setTitle("ログを削除")
            .setMessage("保存済みログをすべて削除しますか？")
            .setPositiveButton("削除") { _, _ ->
                val deleted = LogManager.clear(this)
                Toast.makeText(this, if (deleted) "ログを削除しました" else "削除に失敗しました", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton("キャンセル", null)
            .show()
    }

    // -------------------------------------------------------------------------
    // UI Helpers
    // -------------------------------------------------------------------------

    private fun setLoading(loading: Boolean) {
        binding.progressBar.visibility = if (loading) View.VISIBLE else View.GONE
        binding.btnRun.isEnabled = !loading
        binding.btnRun.text = if (loading) "推論中…" else "▶ テスト実行"
    }

    private fun setStatusText(text: String) {
        binding.tvModelStatus.text = text
    }

    override fun onDestroy() {
        super.onDestroy()
        client.close()
    }
}
