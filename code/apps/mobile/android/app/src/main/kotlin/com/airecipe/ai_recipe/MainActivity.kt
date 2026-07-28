package com.airecipe.ai_recipe

import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtException
import ai.onnxruntime.OrtSession
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai_recipe/local_ocr"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> handleProbe(result)
                "healthCheck" -> handleHealthCheck(call, result)
                "recognize" -> result.error(
                    "inference_not_implemented",
                    "Local OCR image recognition is not implemented yet.",
                    null
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun handleProbe(result: MethodChannel.Result) {
        try {
            OrtEnvironment.getEnvironment()
            result.success(
                mapOf(
                    "runtimeAvailable" to true,
                    "recognitionSupported" to false,
                    "runtimeVersion" to "onnxruntime-android"
                )
            )
        } catch (_: Throwable) {
            result.success(
                mapOf(
                    "runtimeAvailable" to false,
                    "recognitionSupported" to false,
                    "runtimeVersion" to null
                )
            )
        }
    }

    private fun handleHealthCheck(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *>
                ?: throw LocalOcrException("invalid_input", "Invalid OCR health check request.")
            val modelDirectory = args["modelDirectory"] as? String
                ?: throw LocalOcrException("invalid_input", "Missing OCR model directory.")
            val manifest = args["manifest"] as? Map<*, *>
                ?: throw LocalOcrException("invalid_input", "Missing OCR model manifest.")
            val files = manifest["files"] as? List<*>
                ?: throw LocalOcrException("invalid_input", "Missing OCR model files.")

            val modelRoot = File(modelDirectory).canonicalFile
            if (!modelRoot.exists() || !modelRoot.isDirectory) {
                throw LocalOcrException("model_not_installed", "OCR model package is not installed.")
            }

            val onnxFiles = files.mapNotNull { entry ->
                val file = entry as? Map<*, *> ?: return@mapNotNull null
                val relativePath = file["path"] as? String ?: return@mapNotNull null
                if (!relativePath.endsWith(".onnx", ignoreCase = true)) return@mapNotNull null
                resolveModelFile(modelRoot, relativePath)
            }
            if (onnxFiles.isEmpty()) {
                throw LocalOcrException("invalid_input", "OCR package has no ONNX model file.")
            }

            val environment = OrtEnvironment.getEnvironment()
            onnxFiles.forEach { modelFile ->
                if (!modelFile.exists() || !modelFile.isFile) {
                    throw LocalOcrException("model_not_installed", "OCR model file is missing.")
                }
                OrtSession.SessionOptions().use { options ->
                    environment.createSession(modelFile.path, options).use { session ->
                        if (session.inputInfo.isEmpty() || session.outputInfo.isEmpty()) {
                            throw LocalOcrException(
                                "inference_failed",
                                "OCR model session has no input or output."
                            )
                        }
                    }
                }
            }
            result.success(null)
        } catch (error: LocalOcrException) {
            result.error(error.code, error.safeMessage, null)
        } catch (_: OrtException) {
            result.error("inference_failed", "OCR model health check failed.", null)
        } catch (_: Throwable) {
            result.error("runtime_unavailable", "Local OCR runtime is unavailable.", null)
        }
    }

    private fun resolveModelFile(modelRoot: File, relativePath: String): File {
        if (relativePath.startsWith("/") || relativePath.contains('\\') || relativePath.contains("..")) {
            throw LocalOcrException("invalid_input", "Invalid OCR model file path.")
        }
        val modelFile = File(modelRoot, relativePath).canonicalFile
        val rootPath = modelRoot.path + File.separator
        if (!modelFile.path.startsWith(rootPath)) {
            throw LocalOcrException("invalid_input", "Invalid OCR model file path.")
        }
        return modelFile
    }

    private class LocalOcrException(val code: String, message: String) : Exception(message) {
        val safeMessage: String = message.replace(Regex("\\s+"), " ").take(240)
    }
}
