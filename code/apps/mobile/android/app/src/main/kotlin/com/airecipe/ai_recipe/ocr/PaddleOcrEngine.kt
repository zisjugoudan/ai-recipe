package com.airecipe.ai_recipe.ocr

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import java.io.Closeable
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class PaddleOcrEngine : Closeable {
    private val environment = OrtEnvironment.getEnvironment()
    private var cachedRuntime: CachedRuntime? = null

    @Synchronized
    fun recognize(bitmap: Bitmap, modelPackage: OcrModelPackage): Map<String, Any?> {
        val contract = modelPackage.runtime
            ?: throw LocalOcrException(
                "invalid_input",
                "OCR model package does not define an inference contract."
            )
        val startedAt = System.nanoTime()
        val runtime = runtimeFor(modelPackage, contract)
        val boxes = detect(bitmap, contract.detector, runtime)
            .sortedWith(compareBy<DetectedBox>({ it.top }, { it.left }))

        val blocks = mutableListOf<Map<String, Any?>>()
        boxes.forEach { box ->
            val crop = crop(bitmap, box)
            try {
                val recognition = recognizeCrop(crop, contract.recognizer, runtime)
                if (recognition.text.isNotBlank()) {
                    val order = blocks.size
                    blocks += mapOf(
                        "text" to recognition.text,
                        "confidence" to recognition.confidence.toDouble().coerceIn(0.0, 1.0),
                        "readingOrder" to order,
                        "pageIndex" to 0,
                        "polygon" to box.normalizedPolygon(bitmap.width, bitmap.height)
                    )
                }
            } finally {
                crop.recycle()
            }
        }

        val durationMs = ((System.nanoTime() - startedAt) / 1_000_000L)
            .coerceAtMost(Int.MAX_VALUE.toLong())
            .toInt()
        return mapOf(
            "providerId" to "local-paddleocr",
            "modelVersion" to modelPackage.version,
            "language" to modelPackage.primaryLanguage,
            "durationMs" to durationMs,
            "blocks" to blocks
        )
    }

    @Synchronized
    override fun close() {
        cachedRuntime?.close()
        cachedRuntime = null
    }

    private fun runtimeFor(
        modelPackage: OcrModelPackage,
        contract: PaddleOcrContract
    ): CachedRuntime {
        cachedRuntime?.takeIf { it.cacheKey == modelPackage.cacheKey }?.let { return it }
        cachedRuntime?.close()
        cachedRuntime = null

        val detectorFile = modelPackage.filesByRole.getValue(contract.detector.modelRole)
        val recognizerFile = modelPackage.filesByRole.getValue(contract.recognizer.modelRole)
        val dictionaryFile = modelPackage.filesByRole.getValue(contract.recognizer.dictionaryRole)
        val detectorSession = createSession(detectorFile.path)
        try {
            val recognizerSession = createSession(recognizerFile.path)
            try {
                val symbols = OcrDictionary.load(
                    dictionaryFile,
                    contract.recognizer.useSpaceCharacter
                )
                if (contract.recognizer.blankIndex > symbols.size) {
                    throw LocalOcrException(
                        "invalid_input",
                        "OCR dictionary does not match the recognizer contract."
                    )
                }
                return CachedRuntime(
                    cacheKey = modelPackage.cacheKey,
                    detectorSession = detectorSession,
                    detectorInputName = resolveTensorName(
                        detectorSession.inputNames,
                        contract.detector.tensor.inputName,
                        "detector input"
                    ),
                    detectorOutputName = resolveTensorName(
                        detectorSession.outputNames,
                        contract.detector.tensor.outputName,
                        "detector output"
                    ),
                    recognizerSession = recognizerSession,
                    recognizerInputName = resolveTensorName(
                        recognizerSession.inputNames,
                        contract.recognizer.tensor.inputName,
                        "recognizer input"
                    ),
                    recognizerOutputName = resolveTensorName(
                        recognizerSession.outputNames,
                        contract.recognizer.tensor.outputName,
                        "recognizer output"
                    ),
                    symbols = symbols
                ).also { cachedRuntime = it }
            } catch (error: Throwable) {
                recognizerSession.close()
                throw error
            }
        } catch (error: Throwable) {
            detectorSession.close()
            throw error
        }
    }

    private fun createSession(modelPath: String): OrtSession {
        val options = OrtSession.SessionOptions()
        return try {
            environment.createSession(modelPath, options)
        } finally {
            options.close()
        }
    }

    private fun resolveTensorName(
        names: Set<String>,
        configuredName: String?,
        description: String
    ): String {
        if (configuredName != null) {
            if (!names.contains(configuredName)) {
                throw LocalOcrException(
                    "inference_failed",
                    "OCR $description binding is missing."
                )
            }
            return configuredName
        }
        if (names.size != 1) {
            throw LocalOcrException(
                "inference_failed",
                "OCR $description binding is ambiguous."
            )
        }
        return names.single()
    }

    private fun detect(
        bitmap: Bitmap,
        contract: PaddleDetectorContract,
        runtime: CachedRuntime
    ): List<DetectedBox> {
        val resized = resizeForDetector(bitmap, contract.resizeLongSide)
        try {
            val input = imageTensor(resized, contract.normalization)
            input.use { tensor ->
                runtime.detectorSession.run(
                    mapOf(runtime.detectorInputName to tensor)
                ).use { result ->
                    val output = result.get(runtime.detectorOutputName).orElse(null) as? OnnxTensor
                        ?: throw LocalOcrException(
                            "inference_failed",
                            "OCR detector returned an invalid output."
                        )
                    val shape = output.info.shape
                    if (shape.size != 4 || shape[0] != 1L || shape[1] != 1L ||
                        shape[2] <= 0L || shape[3] <= 0L ||
                        shape[2] > MAX_DETECTOR_OUTPUT_SIDE ||
                        shape[3] > MAX_DETECTOR_OUTPUT_SIDE
                    ) {
                        throw LocalOcrException(
                            "inference_failed",
                            "OCR detector output shape is unsupported."
                        )
                    }
                    val mapHeight = shape[2].toInt()
                    val mapWidth = shape[3].toInt()
                    val expectedValues = mapWidth.toLong() * mapHeight.toLong()
                    if (expectedValues > MAX_DETECTOR_OUTPUT_PIXELS) {
                        throw LocalOcrException(
                            "inference_failed",
                            "OCR detector output is too large."
                        )
                    }
                    val probabilities = FloatArray(expectedValues.toInt())
                    val buffer = output.floatBuffer
                    if (buffer.remaining() < probabilities.size) {
                        throw LocalOcrException(
                            "inference_failed",
                            "OCR detector output is incomplete."
                        )
                    }
                    buffer.get(probabilities)
                    return boxesFromProbabilityMap(
                        probabilities = probabilities,
                        width = mapWidth,
                        height = mapHeight,
                        originalWidth = bitmap.width,
                        originalHeight = bitmap.height,
                        contract = contract
                    )
                }
            }
        } finally {
            if (resized !== bitmap) resized.recycle()
        }
    }

    private fun resizeForDetector(bitmap: Bitmap, longSideLimit: Int): Bitmap {
        val sourceLongSide = max(bitmap.width, bitmap.height)
        val scale = min(1f, longSideLimit.toFloat() / sourceLongSide.toFloat())
        val scaledWidth = max(1, (bitmap.width * scale).roundToInt())
        val scaledHeight = max(1, (bitmap.height * scale).roundToInt())
        val targetWidth = multipleOf32(scaledWidth, longSideLimit)
        val targetHeight = multipleOf32(scaledHeight, longSideLimit)
        if (targetWidth == bitmap.width && targetHeight == bitmap.height) return bitmap
        return Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
    }

    private fun multipleOf32(value: Int, limit: Int): Int {
        val rounded = max(32, ((value + 16) / 32) * 32)
        val maximum = max(32, (limit / 32) * 32)
        return min(rounded, maximum)
    }

    private fun imageTensor(bitmap: Bitmap, normalization: OcrImageNormalization): OnnxTensor {
        val pixelCount = bitmap.width * bitmap.height
        val pixels = IntArray(pixelCount)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        val floatBuffer = ByteBuffer.allocateDirect(pixelCount * 3 * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        for (channel in 0..2) {
            pixels.forEach { pixel ->
                val component = when (normalization.colorOrder) {
                    PaddleColorOrder.RGB -> when (channel) {
                        0 -> Color.red(pixel)
                        1 -> Color.green(pixel)
                        else -> Color.blue(pixel)
                    }
                    PaddleColorOrder.BGR -> when (channel) {
                        0 -> Color.blue(pixel)
                        1 -> Color.green(pixel)
                        else -> Color.red(pixel)
                    }
                }
                val normalized = (
                    component.toFloat() * normalization.scale - normalization.mean[channel]
                    ) / normalization.standardDeviation[channel]
                floatBuffer.put(normalized)
            }
        }
        floatBuffer.rewind()
        return OnnxTensor.createTensor(
            environment,
            floatBuffer,
            longArrayOf(1, 3, bitmap.height.toLong(), bitmap.width.toLong())
        )
    }

    private fun boxesFromProbabilityMap(
        probabilities: FloatArray,
        width: Int,
        height: Int,
        originalWidth: Int,
        originalHeight: Int,
        contract: PaddleDetectorContract
    ): List<DetectedBox> {
        val visited = BooleanArray(probabilities.size)
        val queue = IntArray(probabilities.size)
        val candidates = mutableListOf<ScoredBox>()
        for (seed in probabilities.indices) {
            if (visited[seed] || !probabilities[seed].isFinite() ||
                probabilities[seed] < contract.pixelThreshold
            ) {
                continue
            }
            var head = 0
            var tail = 0
            queue[tail++] = seed
            visited[seed] = true
            var minX = width
            var minY = height
            var maxX = 0
            var maxY = 0
            var scoreTotal = 0.0
            var foregroundCount = 0
            while (head < tail) {
                val index = queue[head++]
                val y = index / width
                val x = index - y * width
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                val probability = probabilities[index]
                if (probability.isFinite()) scoreTotal += probability.toDouble()
                foregroundCount++
                enqueueIfForeground(index - 1, x > 0, probabilities, visited, queue, tail, contract)
                    .also { tail = it }
                enqueueIfForeground(index + 1, x + 1 < width, probabilities, visited, queue, tail, contract)
                    .also { tail = it }
                enqueueIfForeground(index - width, y > 0, probabilities, visited, queue, tail, contract)
                    .also { tail = it }
                enqueueIfForeground(index + width, y + 1 < height, probabilities, visited, queue, tail, contract)
                    .also { tail = it }
            }
            val componentWidth = maxX - minX + 1
            val componentHeight = maxY - minY + 1
            val score = if (foregroundCount == 0) 0f else (scoreTotal / foregroundCount).toFloat()
            if (foregroundCount < MIN_COMPONENT_PIXELS ||
                componentWidth < MIN_COMPONENT_SIDE ||
                componentHeight < MIN_COMPONENT_SIDE ||
                score < contract.boxThreshold
            ) {
                continue
            }
            val area = componentWidth.toFloat() * componentHeight.toFloat()
            val perimeter = 2f * (componentWidth + componentHeight)
            val expansion = if (perimeter <= 0f) 0f else area * contract.unclipRatio / perimeter
            val expandedLeft = (minX - expansion).coerceAtLeast(0f)
            val expandedTop = (minY - expansion).coerceAtLeast(0f)
            val expandedRight = (maxX + 1f + expansion).coerceAtMost(width.toFloat())
            val expandedBottom = (maxY + 1f + expansion).coerceAtMost(height.toFloat())
            candidates += ScoredBox(
                score = score,
                box = DetectedBox(
                    left = expandedLeft / width * originalWidth,
                    top = expandedTop / height * originalHeight,
                    right = expandedRight / width * originalWidth,
                    bottom = expandedBottom / height * originalHeight
                )
            )
        }
        return candidates
            .sortedByDescending { it.score }
            .take(contract.maxCandidates)
            .map { it.box }
            .filter { it.width >= MIN_CROP_SIDE && it.height >= MIN_CROP_SIDE }
    }

    private fun enqueueIfForeground(
        index: Int,
        valid: Boolean,
        probabilities: FloatArray,
        visited: BooleanArray,
        queue: IntArray,
        tail: Int,
        contract: PaddleDetectorContract
    ): Int {
        if (!valid || visited[index] || !probabilities[index].isFinite() ||
            probabilities[index] < contract.pixelThreshold
        ) {
            return tail
        }
        visited[index] = true
        queue[tail] = index
        return tail + 1
    }

    private fun crop(bitmap: Bitmap, box: DetectedBox): Bitmap {
        val left = box.left.toInt().coerceIn(0, bitmap.width - 1)
        val top = box.top.toInt().coerceIn(0, bitmap.height - 1)
        val right = ceil(box.right.toDouble()).toInt().coerceIn(left + 1, bitmap.width)
        val bottom = ceil(box.bottom.toDouble()).toInt().coerceIn(top + 1, bitmap.height)
        return Bitmap.createBitmap(bitmap, left, top, right - left, bottom - top)
    }

    private fun recognizeCrop(
        crop: Bitmap,
        contract: PaddleRecognizerContract,
        runtime: CachedRuntime
    ): Recognition {
        val targetHeight = contract.imageShape[1]
        val targetWidth = contract.imageShape[2]
        val scaledWidth = min(
            targetWidth,
            max(1, ceil(crop.width.toDouble() * targetHeight / crop.height).toInt())
        )
        val scaled = Bitmap.createScaledBitmap(crop, scaledWidth, targetHeight, true)
        val inputBitmap = Bitmap.createBitmap(
            targetWidth,
            targetHeight,
            Bitmap.Config.ARGB_8888
        )
        try {
            val canvas = Canvas(inputBitmap)
            canvas.drawColor(Color.WHITE)
            canvas.drawBitmap(scaled, 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG))
            val input = imageTensor(inputBitmap, contract.normalization)
            input.use { tensor ->
                runtime.recognizerSession.run(
                    mapOf(runtime.recognizerInputName to tensor)
                ).use { result ->
                    val output = result.get(runtime.recognizerOutputName).orElse(null) as? OnnxTensor
                        ?: throw LocalOcrException(
                            "inference_failed",
                            "OCR recognizer returned an invalid output."
                        )
                    val shape = output.info.shape
                    if (shape.size != 3 || shape[0] != 1L || shape[1] <= 0L || shape[2] <= 1L ||
                        shape[1] > MAX_RECOGNIZER_TIMESTEPS ||
                        shape[2] > MAX_RECOGNIZER_CLASSES
                    ) {
                        throw LocalOcrException(
                            "inference_failed",
                            "OCR recognizer output shape is unsupported."
                        )
                    }
                    val timesteps = shape[1].toInt()
                    val classes = shape[2].toInt()
                    // PP-OCRv4 系列：classes = symbols + 1（blank 在 0，额外）；
                    // PP-OCRv5 系列（实测 RapidOCR mobile）：classes = symbols + 2
                    // （blank 0 + dict 1..N + 尾随额外类），因此按范围校验。
                    if (classes < runtime.symbols.size + 1 ||
                        classes > runtime.symbols.size + 2 ||
                        contract.blankIndex >= classes
                    ) {
                        throw LocalOcrException(
                            "inference_failed",
                            "OCR recognizer classes do not match the dictionary."
                        )
                    }
                    val values = FloatArray(timesteps * classes)
                    val buffer = output.floatBuffer
                    if (buffer.remaining() < values.size) {
                        throw LocalOcrException(
                            "inference_failed",
                            "OCR recognizer output is incomplete."
                        )
                    }
                    buffer.get(values)
                    return OcrCtcDecoder.decode(
                        values = values,
                        timesteps = timesteps,
                        classes = classes,
                        blankIndex = contract.blankIndex,
                        symbols = runtime.symbols
                    )
                }
            }
        } finally {
            if (scaled !== crop) scaled.recycle()
            inputBitmap.recycle()
        }
    }

    private data class CachedRuntime(
        val cacheKey: String,
        val detectorSession: OrtSession,
        val detectorInputName: String,
        val detectorOutputName: String,
        val recognizerSession: OrtSession,
        val recognizerInputName: String,
        val recognizerOutputName: String,
        val symbols: List<String>
    ) : Closeable {
        override fun close() {
            recognizerSession.close()
            detectorSession.close()
        }
    }

    private data class ScoredBox(val score: Float, val box: DetectedBox)

    private data class DetectedBox(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float
    ) {
        val width: Float get() = right - left
        val height: Float get() = bottom - top

        fun normalizedPolygon(imageWidth: Int, imageHeight: Int): List<Map<String, Double>> {
            val leftX = (left / imageWidth).toDouble().coerceIn(0.0, 1.0)
            val rightX = (right / imageWidth).toDouble().coerceIn(0.0, 1.0)
            val topY = (top / imageHeight).toDouble().coerceIn(0.0, 1.0)
            val bottomY = (bottom / imageHeight).toDouble().coerceIn(0.0, 1.0)
            return listOf(
                mapOf("x" to leftX, "y" to topY),
                mapOf("x" to rightX, "y" to topY),
                mapOf("x" to rightX, "y" to bottomY),
                mapOf("x" to leftX, "y" to bottomY)
            )
        }
    }

    private companion object {
        const val MAX_DETECTOR_OUTPUT_SIDE = 4096L
        const val MAX_DETECTOR_OUTPUT_PIXELS = 16_777_216L
        const val MAX_RECOGNIZER_TIMESTEPS = 8192L
        const val MAX_RECOGNIZER_CLASSES = 100_001L
        const val MIN_COMPONENT_PIXELS = 4
        const val MIN_COMPONENT_SIDE = 2
        const val MIN_CROP_SIDE = 2f
    }
}

object OcrCtcDecoder {
    fun decode(
        values: FloatArray,
        timesteps: Int,
        classes: Int,
        blankIndex: Int,
        symbols: List<String>
    ): Recognition {
        // PP-OCRv4 系列 classes = symbols + 1；PP-OCRv5 系列 classes = symbols + 2
        // （末尾额外的类不映射字符，解码时跳过）。其余一律视为不匹配。
        if (timesteps <= 0 || classes <= 1 || values.size != timesteps * classes ||
            blankIndex !in 0 until classes ||
            classes < symbols.size + 1 || classes > symbols.size + 2
        ) {
            throw LocalOcrException("inference_failed", "Invalid OCR recognizer output.")
        }
        val text = StringBuilder()
        var confidenceTotal = 0.0
        var emitted = 0
        var previousClass = -1
        for (time in 0 until timesteps) {
            val offset = time * classes
            var bestClass = 0
            var bestValue = values[offset]
            var sum = 0.0
            var probabilities = bestValue.isFinite() && bestValue in 0f..1f
            for (classIndex in 0 until classes) {
                val value = values[offset + classIndex]
                if (!value.isFinite()) {
                    probabilities = false
                } else {
                    sum += value.toDouble()
                    if (value > bestValue || !bestValue.isFinite()) {
                        bestValue = value
                        bestClass = classIndex
                    }
                    if (value !in 0f..1f) probabilities = false
                }
            }
            if (bestClass != blankIndex && bestClass != previousClass) {
                val symbolIndex = if (bestClass < blankIndex) bestClass else bestClass - 1
                val symbol = symbols.getOrNull(symbolIndex)
                // 模型末尾的额外类（如 PP-OCRv5 的 classes = symbols + 2）不映射
                // 字符，直接跳过本帧，不视为推理错误。
                if (symbol != null) {
                    text.append(symbol)
                    confidenceTotal += if (probabilities && sum in 0.9..1.1) {
                        bestValue.toDouble().coerceIn(0.0, 1.0)
                    } else {
                        softmaxProbability(values, offset, classes, bestClass)
                    }
                    emitted++
                }
            }
            previousClass = bestClass
        }
        return Recognition(
            text = text.toString(),
            confidence = if (emitted == 0) 0f else (confidenceTotal / emitted).toFloat()
        )
    }

    private fun softmaxProbability(
        values: FloatArray,
        offset: Int,
        classes: Int,
        selectedClass: Int
    ): Double {
        var maximum = Double.NEGATIVE_INFINITY
        for (index in 0 until classes) {
            val value = values[offset + index].toDouble()
            if (value.isFinite()) maximum = max(maximum, value)
        }
        if (!maximum.isFinite()) return 0.0
        var denominator = 0.0
        var numerator = 0.0
        for (index in 0 until classes) {
            val value = values[offset + index].toDouble()
            val exponent = if (value.isFinite()) exp(value - maximum) else 0.0
            denominator += exponent
            if (index == selectedClass) numerator = exponent
        }
        return if (denominator <= 0.0) 0.0 else (numerator / denominator).coerceIn(0.0, 1.0)
    }
}

data class Recognition(val text: String, val confidence: Float)
