package com.airecipe.ai_recipe.ocr

import java.io.File

enum class PaddleColorOrder {
    BGR,
    RGB
}

data class OcrTensorBinding(
    val inputName: String?,
    val outputName: String?
)

data class OcrImageNormalization(
    val scale: Float,
    val mean: FloatArray,
    val standardDeviation: FloatArray,
    val colorOrder: PaddleColorOrder
)

data class PaddleDetectorContract(
    val modelRole: String,
    val tensor: OcrTensorBinding,
    val resizeLongSide: Int,
    val normalization: OcrImageNormalization,
    val pixelThreshold: Float,
    val boxThreshold: Float,
    val maxCandidates: Int,
    val unclipRatio: Float
)

data class PaddleRecognizerContract(
    val modelRole: String,
    val dictionaryRole: String,
    val tensor: OcrTensorBinding,
    val imageShape: List<Int>,
    val normalization: OcrImageNormalization,
    val blankIndex: Int,
    val useSpaceCharacter: Boolean
)

data class PaddleOcrContract(
    val detector: PaddleDetectorContract,
    val recognizer: PaddleRecognizerContract
)

data class OcrModelPackage(
    val root: File,
    val packageId: String,
    val version: String,
    val languages: List<String>,
    val filesByRole: Map<String, File>,
    val onnxFiles: List<File>,
    val runtime: PaddleOcrContract?
) {
    val cacheKey: String
        get() = "${root.path}\u0000$version"

    val primaryLanguage: String
        get() = languages.firstOrNull() ?: "und"

    companion object {
        fun fromMethodArguments(arguments: Any?): OcrModelPackage {
            val args = arguments.asStringMap("Invalid OCR model request.")
            val directoryPath = args.requiredString(
                "modelDirectory",
                "Missing OCR model directory."
            )
            val manifest = args.requiredMap("manifest", "Missing OCR model manifest.")
            val schemaVersion = manifest.requiredInt(
                "schemaVersion",
                "Missing OCR manifest schema version."
            )
            if (schemaVersion != 1 && schemaVersion != 2) {
                throw LocalOcrException("invalid_input", "Unsupported OCR manifest schema.")
            }
            val engine = manifest.requiredString("engine", "Missing OCR runtime engine.")
            if (engine != "onnxruntime") {
                throw LocalOcrException("invalid_input", "Unsupported OCR runtime engine.")
            }
            val packageId = manifest.requiredString("packageId", "Missing OCR package ID.")
            val version = manifest.requiredString("version", "Missing OCR model version.")
            val languages = manifest.requiredStringList(
                "languages",
                "Missing OCR model languages."
            )
            if (languages.isEmpty()) {
                throw LocalOcrException("invalid_input", "OCR model languages are empty.")
            }
            val modelRoot = File(directoryPath).canonicalFile
            if (!modelRoot.exists() || !modelRoot.isDirectory) {
                throw LocalOcrException(
                    "model_not_installed",
                    "OCR model package is not installed."
                )
            }

            val entries = manifest.requiredList("files", "Missing OCR model files.")
            if (entries.isEmpty()) {
                throw LocalOcrException("invalid_input", "OCR package has no model files.")
            }
            val filesByRole = linkedMapOf<String, File>()
            entries.forEach { rawEntry ->
                val entry = rawEntry.asStringMap("Invalid OCR model file entry.")
                val role = entry.requiredRole("role", "Missing OCR model file role.")
                val path = entry.requiredString("path", "Missing OCR model file path.")
                if (filesByRole.containsKey(role)) {
                    throw LocalOcrException("invalid_input", "Duplicate OCR model file role.")
                }
                filesByRole[role] = resolveModelFile(modelRoot, path)
            }
            if (filesByRole.values.toSet().size != filesByRole.size) {
                throw LocalOcrException("invalid_input", "Duplicate OCR model file path.")
            }

            val onnxFiles = filesByRole.values.filter {
                it.extension.equals("onnx", ignoreCase = true)
            }
            if (onnxFiles.isEmpty()) {
                throw LocalOcrException("invalid_input", "OCR package has no ONNX model file.")
            }

            val runtime = when (schemaVersion) {
                1 -> {
                    if (manifest["runtimeConfig"] != null) {
                        throw LocalOcrException(
                            "invalid_input",
                            "OCR manifest schema 1 cannot define runtime config."
                        )
                    }
                    null
                }
                2 -> parseRuntime(manifest, filesByRole)
                else -> null
            }
            return OcrModelPackage(
                root = modelRoot,
                packageId = packageId,
                version = version,
                languages = languages,
                filesByRole = filesByRole.toMap(),
                onnxFiles = onnxFiles,
                runtime = runtime
            )
        }

        private fun parseRuntime(
            manifest: Map<String, Any?>,
            filesByRole: Map<String, File>
        ): PaddleOcrContract {
            val runtime = manifest.requiredMap(
                "runtimeConfig",
                "OCR manifest schema 2 requires runtime config."
            )
            if (runtime.requiredString("type", "Missing OCR runtime type.") !=
                "paddleocr-ppocrv5"
            ) {
                throw LocalOcrException("invalid_input", "Unsupported OCR runtime type.")
            }
            val detectorMap = runtime.requiredMap("detector", "Missing detector config.")
            val recognizerMap = runtime.requiredMap("recognizer", "Missing recognizer config.")
            val detector = PaddleDetectorContract(
                modelRole = detectorMap.requiredRole("modelRole", "Missing detector role."),
                tensor = parseTensor(detectorMap),
                resizeLongSide = detectorMap.requiredInt(
                    "resizeLongSide",
                    "Missing detector resize limit."
                ),
                normalization = parseNormalization(detectorMap),
                pixelThreshold = detectorMap.requiredFloat(
                    "pixelThreshold",
                    "Missing detector pixel threshold."
                ),
                boxThreshold = detectorMap.requiredFloat(
                    "boxThreshold",
                    "Missing detector box threshold."
                ),
                maxCandidates = detectorMap.requiredInt(
                    "maxCandidates",
                    "Missing detector candidate limit."
                ),
                unclipRatio = detectorMap.requiredFloat(
                    "unclipRatio",
                    "Missing detector unclip ratio."
                )
            )
            if (detector.resizeLongSide !in 32..4096 ||
                detector.pixelThreshold !in 0f..1f ||
                detector.boxThreshold !in 0f..1f ||
                detector.maxCandidates !in 1..10_000 ||
                !detector.unclipRatio.isFinite() ||
                detector.unclipRatio <= 0f ||
                detector.unclipRatio > 10f
            ) {
                throw LocalOcrException("invalid_input", "Invalid detector runtime config.")
            }

            val recognizer = PaddleRecognizerContract(
                modelRole = recognizerMap.requiredRole(
                    "modelRole",
                    "Missing recognizer role."
                ),
                dictionaryRole = recognizerMap.requiredRole(
                    "dictionaryRole",
                    "Missing OCR dictionary role."
                ),
                tensor = parseTensor(recognizerMap),
                imageShape = recognizerMap.requiredIntList(
                    "imageShape",
                    "Missing recognizer image shape."
                ),
                normalization = parseNormalization(recognizerMap),
                blankIndex = recognizerMap.requiredInt(
                    "blankIndex",
                    "Missing recognizer blank index."
                ),
                useSpaceCharacter = recognizerMap.requiredBoolean(
                    "useSpaceCharacter",
                    "Missing recognizer space-character flag."
                )
            )
            if (recognizer.imageShape.size != 3 ||
                recognizer.imageShape[0] != 3 ||
                recognizer.imageShape[1] <= 0 ||
                recognizer.imageShape[2] <= 0 ||
                recognizer.blankIndex < 0
            ) {
                throw LocalOcrException("invalid_input", "Invalid recognizer runtime config.")
            }
            val roles = setOf(
                detector.modelRole,
                recognizer.modelRole,
                recognizer.dictionaryRole
            )
            if (roles.size != 3 || !filesByRole.keys.containsAll(roles)) {
                throw LocalOcrException(
                    "invalid_input",
                    "OCR runtime references missing or duplicate file roles."
                )
            }
            if (!filesByRole.getValue(detector.modelRole).extension.equals(
                    "onnx",
                    ignoreCase = true
                ) ||
                !filesByRole.getValue(recognizer.modelRole).extension.equals(
                    "onnx",
                    ignoreCase = true
                ) ||
                !filesByRole.getValue(recognizer.dictionaryRole).extension.equals(
                    "txt",
                    ignoreCase = true
                )
            ) {
                throw LocalOcrException(
                    "invalid_input",
                    "OCR runtime model or dictionary file type is invalid."
                )
            }
            return PaddleOcrContract(detector = detector, recognizer = recognizer)
        }

        private fun parseTensor(config: Map<String, Any?>): OcrTensorBinding {
            val tensor = config.requiredMap("tensor", "Missing OCR tensor binding.")
            return OcrTensorBinding(
                inputName = tensor.optionalString("inputName"),
                outputName = tensor.optionalString("outputName")
            )
        }

        private fun parseNormalization(config: Map<String, Any?>): OcrImageNormalization {
            val normalization = config.requiredMap(
                "normalization",
                "Missing OCR image normalization."
            )
            val scale = normalization.requiredFloat(
                "scale",
                "Missing OCR normalization scale."
            )
            val mean = normalization.requiredFloatArray(
                "mean",
                "Missing OCR normalization mean."
            )
            val standardDeviation = normalization.requiredFloatArray(
                "standardDeviation",
                "Missing OCR normalization standard deviation."
            )
            val colorOrder = when (
                normalization.requiredString("colorOrder", "Missing OCR color order.")
            ) {
                "bgr" -> PaddleColorOrder.BGR
                "rgb" -> PaddleColorOrder.RGB
                else -> throw LocalOcrException("invalid_input", "Unsupported OCR color order.")
            }
            if (!scale.isFinite() || scale <= 0f ||
                mean.size != 3 || mean.any { !it.isFinite() || it < 0f } ||
                standardDeviation.size != 3 ||
                standardDeviation.any { !it.isFinite() || it <= 0f }
            ) {
                throw LocalOcrException("invalid_input", "Invalid OCR image normalization.")
            }
            return OcrImageNormalization(
                scale = scale,
                mean = mean,
                standardDeviation = standardDeviation,
                colorOrder = colorOrder
            )
        }

        private fun resolveModelFile(modelRoot: File, relativePath: String): File {
            if (relativePath.startsWith("/") ||
                relativePath.contains('\\') ||
                relativePath.split('/').any { it.isEmpty() || it == ".." }
            ) {
                throw LocalOcrException("invalid_input", "Invalid OCR model file path.")
            }
            val modelFile = File(modelRoot, relativePath).canonicalFile
            val rootPath = modelRoot.path + File.separator
            if (!modelFile.path.startsWith(rootPath)) {
                throw LocalOcrException("invalid_input", "Invalid OCR model file path.")
            }
            return modelFile
        }
    }
}

fun Any?.asStringMap(message: String): Map<String, Any?> {
    val raw = this as? Map<*, *>
        ?: throw LocalOcrException("invalid_input", message)
    return raw.entries.associate { entry ->
        val key = entry.key as? String
            ?: throw LocalOcrException("invalid_input", message)
        key to entry.value
    }
}

fun Map<String, Any?>.requiredMap(
    key: String,
    message: String
): Map<String, Any?> = this[key].asStringMap(message)

fun Map<String, Any?>.requiredList(key: String, message: String): List<*> =
    this[key] as? List<*> ?: throw LocalOcrException("invalid_input", message)

fun Map<String, Any?>.requiredString(key: String, message: String): String {
    val value = (this[key] as? String)?.trim()
    if (value.isNullOrEmpty()) throw LocalOcrException("invalid_input", message)
    return value
}

fun Map<String, Any?>.optionalString(key: String): String? {
    val value = this[key] ?: return null
    if (value !is String) {
        throw LocalOcrException("invalid_input", "Invalid OCR string value.")
    }
    return value.trim().takeIf { it.isNotEmpty() }
}


fun Map<String, Any?>.requiredStringList(key: String, message: String): List<String> {
    val list = this[key] as? List<*> ?: throw LocalOcrException("invalid_input", message)
    if (list.any { it !is String || it.trim().isEmpty() }) {
        throw LocalOcrException("invalid_input", message)
    }
    return list.filterIsInstance<String>().map { it.trim() }
}
fun Map<String, Any?>.requiredInt(key: String, message: String): Int =
    this[key] as? Int ?: throw LocalOcrException("invalid_input", message)

fun Map<String, Any?>.requiredBoolean(key: String, message: String): Boolean =
    this[key] as? Boolean ?: throw LocalOcrException("invalid_input", message)

fun Map<String, Any?>.requiredFloat(key: String, message: String): Float {
    val value = this[key] as? Number ?: throw LocalOcrException("invalid_input", message)
    return value.toFloat()
}

fun Map<String, Any?>.requiredIntList(key: String, message: String): List<Int> {
    val list = this[key] as? List<*> ?: throw LocalOcrException("invalid_input", message)
    if (list.any { it !is Int }) throw LocalOcrException("invalid_input", message)
    return list.filterIsInstance<Int>()
}

fun Map<String, Any?>.requiredFloatArray(key: String, message: String): FloatArray {
    val list = this[key] as? List<*> ?: throw LocalOcrException("invalid_input", message)
    if (list.any { it !is Number }) throw LocalOcrException("invalid_input", message)
    return list.map { (it as Number).toFloat() }.toFloatArray()
}

fun Map<String, Any?>.requiredRole(key: String, message: String): String {
    val role = requiredString(key, message)
    if (!Regex("^[a-z][a-z0-9_-]*$").matches(role)) {
        throw LocalOcrException("invalid_input", "Invalid OCR model file role.")
    }
    return role
}
