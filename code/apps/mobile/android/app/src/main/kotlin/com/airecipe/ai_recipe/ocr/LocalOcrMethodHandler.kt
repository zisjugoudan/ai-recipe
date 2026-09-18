package com.airecipe.ai_recipe.ocr

import ai.onnxruntime.NodeInfo
import ai.onnxruntime.OnnxJavaType
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtException
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.Closeable
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class LocalOcrMethodHandler(
    context: Context,
    private val executor: ExecutorService = Executors.newSingleThreadExecutor(),
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
    private val ocrEngine: PaddleOcrEngine = PaddleOcrEngine()
) : MethodChannel.MethodCallHandler, Closeable {
    private val applicationContext = context.applicationContext
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> handleProbe(result)
            "healthCheck" -> runInBackground(result) {
                val modelPackage = OcrModelPackage.fromMethodArguments(call.arguments)
                healthCheck(modelPackage)
                null
            }
            "getAvailableStorageBytes" -> handleAvailableStorageBytes(call, result)
            "recognize" -> runInBackground(result) {
                val modelPackage = OcrModelPackage.fromMethodArguments(call.arguments)
                val imageSource = LocalOcrImageSource.fromMethodArguments(
                    applicationContext,
                    call.arguments
                )
                val bitmap = imageSource.decodeBitmap()
                try {
                    ocrEngine.recognize(bitmap, modelPackage)
                } finally {
                    bitmap.recycle()
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun close() {
        ocrEngine.close()
        executor.shutdownNow()
    }

    private fun handleProbe(result: MethodChannel.Result) {
        val runtimeAvailable = try {
            OrtEnvironment.getEnvironment()
            true
        } catch (_: Throwable) {
            false
        }
        result.success(localOcrProbeResponse(runtimeAvailable))
    }

    private fun handleAvailableStorageBytes(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *>
                ?: throw LocalOcrException("invalid_input", "Invalid OCR storage request.")
            val directoryPath = (args["directory"] as? String)?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?: throw LocalOcrException("invalid_input", "Missing OCR storage directory.")
            var existingDirectory: File? = File(directoryPath).absoluteFile
            while (existingDirectory != null && !existingDirectory.exists()) {
                existingDirectory = existingDirectory.parentFile
            }
            if (existingDirectory == null || !existingDirectory.isDirectory) {
                throw LocalOcrException(
                    "storage_unavailable",
                    "OCR model storage is unavailable."
                )
            }
            result.success(StatFs(existingDirectory.path).availableBytes)
        } catch (error: LocalOcrException) {
            result.error(error.code, error.safeMessage, null)
        } catch (_: Throwable) {
            result.error("storage_unavailable", "OCR model storage is unavailable.", null)
        }
    }

    private fun healthCheck(modelPackage: OcrModelPackage) {
        modelPackage.filesByRole.values.forEach { modelFile ->
            if (!modelFile.exists() || !modelFile.isFile) {
                throw LocalOcrException("model_not_installed", "OCR model file is missing.")
            }
        }

        val environment = OrtEnvironment.getEnvironment()
        val runtime = modelPackage.runtime
        if (runtime == null) {
            modelPackage.onnxFiles.forEach { modelFile ->
                openSession(environment, modelFile) { session ->
                    validateBasicSession(session)
                }
            }
            return
        }

        validateDictionary(modelPackage, runtime.recognizer)

        val detectorFile = modelPackage.filesByRole.getValue(runtime.detector.modelRole)
        openSession(environment, detectorFile) { session ->
            validateDetectorSession(session, runtime.detector)
        }

        val recognizerFile = modelPackage.filesByRole.getValue(runtime.recognizer.modelRole)
        openSession(environment, recognizerFile) { session ->
            validateRecognizerSession(session, runtime.recognizer)
        }

        modelPackage.onnxFiles
            .filterNot { it == detectorFile || it == recognizerFile }
            .forEach { modelFile ->
                openSession(environment, modelFile) { session ->
                    validateBasicSession(session)
                }
            }
    }

    private fun validateDictionary(
        modelPackage: OcrModelPackage,
        recognizer: PaddleRecognizerContract
    ) {
        val dictionaryFile = modelPackage.filesByRole.getValue(recognizer.dictionaryRole)
        val symbols = OcrDictionary.load(dictionaryFile, recognizer.useSpaceCharacter)
        if (recognizer.blankIndex > symbols.size) {
            throw LocalOcrException("invalid_input", "OCR dictionary does not match the model.")
        }
    }

    private fun validateBasicSession(session: OrtSession) {
        if (session.inputInfo.isEmpty() || session.outputInfo.isEmpty()) {
            throw LocalOcrException(
                "inference_failed",
                "OCR model session has no input or output."
            )
        }
    }

    private fun validateDetectorSession(
        session: OrtSession,
        contract: PaddleDetectorContract
    ) {
        val input = resolveTensorInfo(
            session.inputInfo,
            contract.tensor.inputName,
            "input"
        )
        val output = resolveTensorInfo(
            session.outputInfo,
            contract.tensor.outputName,
            "output"
        )
        validateFloatImageInput(input, expectedHeight = null)
        validateFloatTensorRank(output, expectedRank = 4, tensorKind = "output")
    }

    private fun validateRecognizerSession(
        session: OrtSession,
        contract: PaddleRecognizerContract
    ) {
        val input = resolveTensorInfo(
            session.inputInfo,
            contract.tensor.inputName,
            "input"
        )
        val output = resolveTensorInfo(
            session.outputInfo,
            contract.tensor.outputName,
            "output"
        )
        validateFloatImageInput(input, expectedHeight = contract.imageShape[1].toLong())
        validateFloatTensorRank(output, expectedRank = 3, tensorKind = "output")
    }

    private fun resolveTensorInfo(
        tensors: Map<String, NodeInfo>,
        configuredName: String?,
        tensorKind: String
    ): TensorInfo {
        val nodeInfo = if (configuredName != null) {
            tensors[configuredName]
                ?: throw LocalOcrException(
                    "inference_failed",
                    "OCR model $tensorKind binding is missing."
                )
        } else {
            if (tensors.size != 1) {
                throw LocalOcrException(
                    "inference_failed",
                    "OCR model $tensorKind binding is ambiguous."
                )
            }
            tensors.values.single()
        }
        return nodeInfo.info as? TensorInfo
            ?: throw LocalOcrException(
                "inference_failed",
                "OCR model $tensorKind is not a tensor."
            )
    }

    private fun validateFloatImageInput(info: TensorInfo, expectedHeight: Long?) {
        validateFloatTensorRank(info, expectedRank = 4, tensorKind = "input")
        val shape = info.shape
        if (!isExpectedOrDynamic(shape[1], 3L)) {
            throw LocalOcrException(
                "inference_failed",
                "OCR model input channel count is invalid."
            )
        }
        if (expectedHeight != null && !isExpectedOrDynamic(shape[2], expectedHeight)) {
            throw LocalOcrException(
                "inference_failed",
                "OCR recognizer input height is invalid."
            )
        }
    }

    private fun validateFloatTensorRank(
        info: TensorInfo,
        expectedRank: Int,
        tensorKind: String
    ) {
        if (info.type != OnnxJavaType.FLOAT || info.shape.size != expectedRank) {
            throw LocalOcrException(
                "inference_failed",
                "OCR model $tensorKind tensor contract is invalid."
            )
        }
    }

    private fun isExpectedOrDynamic(value: Long, expected: Long): Boolean =
        value == expected || value == -1L

    private inline fun openSession(
        environment: OrtEnvironment,
        modelFile: File,
        validate: (OrtSession) -> Unit
    ) {
        OrtSession.SessionOptions().use { options ->
            environment.createSession(modelFile.path, options).use(validate)
        }
    }

    private fun runInBackground(
        result: MethodChannel.Result,
        operation: () -> Any?
    ) {
        executor.execute {
            try {
                val value = operation()
                mainHandler.post { result.success(value) }
            } catch (error: LocalOcrException) {
                mainHandler.post { result.error(error.code, error.safeMessage, null) }
            } catch (_: OrtException) {
                mainHandler.post {
                    result.error("inference_failed", "Local OCR inference failed.", null)
                }
            } catch (_: Throwable) {
                mainHandler.post {
                    result.error(
                        "runtime_unavailable",
                        "Local OCR runtime is unavailable.",
                        null
                    )
                }
            }
        }
    }

}

internal fun localOcrProbeResponse(runtimeAvailable: Boolean): Map<String, Any?> = mapOf(
    "runtimeAvailable" to runtimeAvailable,
    "recognitionSupported" to runtimeAvailable,
    "runtimeVersion" to if (runtimeAvailable) "onnxruntime-android" else null
)
