package com.example.geminanotestapp

import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.example.geminanotestapp.databinding.ActivityMainBinding
import com.example.geminanotestapp.model.Scenario
import com.example.geminanotestapp.model.ScenarioData
import com.example.geminanotestapp.ui.GeminiNanoManager
import com.example.geminanotestapp.ui.JsonParser
import com.example.geminanotestapp.ui.LogManager
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "MainActivity"
    }

    private lateinit var binding: ActivityMainBinding
    private lateinit var geminiNanoManager: GeminiNanoManager
    private lateinit var jsonParser: JsonParser
    private lateinit var logManager: LogManager

    private var selectedScenario: Scenario? = null
    private var isInitialized = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        geminiNanoManager = GeminiNanoManager(this)
        jsonParser = JsonParser()
        logManager = LogManager(this)

        setupScenarioButtons()
        setupRunButton()
        setupClearButton()
        initializeGeminiNano()
    }

    private fun initializeGeminiNano() {
        setStatus("Gemini Nano を初期化中...")
        binding.btnRun.isEnabled = false

        lifecycleScope.launch {
            try {
                geminiNanoManager.initialize().getOrThrow()
                setStatus("モデルのダウンロード確認中...")

                geminiNanoManager.downloadModelIfNeeded().getOrThrow()
                isInitialized = true
                setStatus("準備完了。シナリオを選択して実行してください。")
                binding.btnRun.isEnabled = true
                Log.d(TAG, "Gemini Nano initialized successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Initialization failed", e)
                setStatus("初期化エラー: ${e.message}\n\nPixel 10実機で実行してください。")
                showError("Gemini Nano の初期化に失敗しました: ${e.message}")
            }
        }
    }

    private fun setupScenarioButtons() {
        binding.btnScenario1.setOnClickListener {
            selectScenario(ScenarioData.scenarios[0])
        }
        binding.btnScenario2.setOnClickListener {
            selectScenario(ScenarioData.scenarios[1])
        }
        binding.btnScenario3.setOnClickListener {
            selectScenario(ScenarioData.scenarios[2])
        }
    }

    private fun selectScenario(scenario: Scenario) {
        selectedScenario = scenario

        // Update button highlights
        val buttons = listOf(binding.btnScenario1, binding.btnScenario2, binding.btnScenario3)
        buttons.forEachIndexed { index, button ->
            button.isSelected = index == scenario.id - 1
        }

        binding.tvTranscriptPreview.text = scenario.transcript
        binding.tvTranscriptPreview.visibility = View.VISIBLE
        binding.tvScenarioLabel.text = "選択中: ${scenario.title} — ${scenario.description}"

        Log.d(TAG, "Scenario selected: ${scenario.title}")
    }

    private fun setupRunButton() {
        binding.btnRun.setOnClickListener {
            val scenario = selectedScenario
            if (scenario == null) {
                showError("シナリオを選択してください")
                return@setOnClickListener
            }
            if (!isInitialized) {
                showError("Gemini Nano がまだ初期化されていません")
                return@setOnClickListener
            }
            runPrompt(scenario)
        }
    }

    private fun setupClearButton() {
        binding.btnClearContext.setOnClickListener {
            binding.etPreviousContext.text?.clear()
            Toast.makeText(this, "Previous Context をクリアしました", Toast.LENGTH_SHORT).show()
        }
    }

    private fun runPrompt(scenario: Scenario) {
        val previousContext = binding.etPreviousContext.text?.toString() ?: ""

        setLoading(true)
        setStatus("Gemini Nano に送信中...")
        clearResults()

        lifecycleScope.launch {
            try {
                val rawOutput = geminiNanoManager.runPrompt(
                    previousContext = previousContext,
                    transcript = scenario.transcript
                ).getOrThrow()

                displayRawOutput(rawOutput)
                setStatus("出力を受信。JSONパース中...")

                val parseResult = jsonParser.parse(rawOutput)
                displayParseResult(parseResult)

                // Save log
                val logEntry = logManager.buildLogEntry(
                    scenarioTitle = scenario.title,
                    previousContext = previousContext,
                    rawOutput = rawOutput,
                    parseSuccess = parseResult.success,
                    parsedResult = parseResult.result,
                    errorMessage = parseResult.errorMessage
                )
                val savedFile = logManager.saveLog(logEntry)

                val statusMsg = if (parseResult.success) {
                    "✓ 完了。ログ保存先: ${savedFile?.name ?: "保存失敗"}"
                } else {
                    "⚠ JSONパース失敗。ログ保存先: ${savedFile?.name ?: "保存失敗"}"
                }
                setStatus(statusMsg)

                // Auto-fill previous context with summary for sliding window test
                if (parseResult.success && parseResult.result != null) {
                    val summary = parseResult.result.summary
                    if (summary.isNotBlank()) {
                        binding.etPreviousContext.setText(summary)
                    }
                }

            } catch (e: Exception) {
                Log.e(TAG, "Prompt execution failed", e)
                setStatus("エラー: ${e.message}")
                showError("プロンプト実行エラー: ${e.message}")
            } finally {
                setLoading(false)
            }
        }
    }

    private fun displayRawOutput(rawOutput: String) {
        binding.tvRawOutputLabel.visibility = View.VISIBLE
        binding.tvRawOutput.visibility = View.VISIBLE
        binding.tvRawOutput.text = rawOutput.ifBlank { "(空の出力)" }
        binding.tvCharCount.text = "文字数: ${rawOutput.length}"
        binding.tvCharCount.visibility = View.VISIBLE
    }

    private fun displayParseResult(parseResult: JsonParser.ParseResult) {
        binding.tvParseResultLabel.visibility = View.VISIBLE
        binding.tvParseStatus.visibility = View.VISIBLE
        binding.cardParseDetails.visibility = View.VISIBLE

        if (parseResult.success && parseResult.result != null) {
            val result = parseResult.result
            binding.tvParseStatus.text = "✓ JSONパース成功"
            binding.tvParseStatus.setTextColor(getColor(R.color.success_green))

            binding.tvSummary.text = result.summary.ifBlank { "(なし)" }
            binding.tvTags.text = if (result.tags.isNotEmpty()) {
                result.tags.joinToString("、") { "#$it" }
            } else {
                "(なし)"
            }
            binding.tvMood.text = result.mood.ifBlank { "(なし)" }
            binding.tvFeedback.text = result.feedback.ifBlank { "(なし)" }
        } else {
            binding.tvParseStatus.text = "✗ JSONパース失敗\n理由: ${parseResult.errorMessage}"
            binding.tvParseStatus.setTextColor(getColor(R.color.error_red))

            binding.tvSummary.text = "(パース失敗)"
            binding.tvTags.text = "(パース失敗)"
            binding.tvMood.text = "(パース失敗)"
            binding.tvFeedback.text = "(パース失敗)"
        }
    }

    private fun clearResults() {
        binding.tvRawOutputLabel.visibility = View.GONE
        binding.tvRawOutput.visibility = View.GONE
        binding.tvCharCount.visibility = View.GONE
        binding.tvParseResultLabel.visibility = View.GONE
        binding.tvParseStatus.visibility = View.GONE
        binding.cardParseDetails.visibility = View.GONE
    }

    private fun setStatus(message: String) {
        binding.tvStatus.text = message
    }

    private fun setLoading(loading: Boolean) {
        binding.progressBar.visibility = if (loading) View.VISIBLE else View.GONE
        binding.btnRun.isEnabled = !loading
        binding.btnScenario1.isEnabled = !loading
        binding.btnScenario2.isEnabled = !loading
        binding.btnScenario3.isEnabled = !loading
        binding.btnClearContext.isEnabled = !loading
    }

    private fun showError(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    override fun onDestroy() {
        super.onDestroy()
        geminiNanoManager.close()
    }
}
