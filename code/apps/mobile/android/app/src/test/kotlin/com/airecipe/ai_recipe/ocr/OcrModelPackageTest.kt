package com.airecipe.ai_recipe.ocr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class OcrModelPackageTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `parses schema two runtime contract`() {
        val root = temporaryFolder.newFolder("model")
        val modelPackage = OcrModelPackage.fromMethodArguments(arguments(root.path))

        assertEquals("package", modelPackage.packageId)
        assertEquals("1.0.0", modelPackage.version)
        assertEquals(listOf("zh-Hans"), modelPackage.languages)
        assertEquals(setOf("detector", "recognizer", "dictionary"), modelPackage.filesByRole.keys)
        assertNotNull(modelPackage.runtime)
        assertEquals(960, modelPackage.runtime!!.detector.resizeLongSide)
        assertEquals(listOf(3, 48, 320), modelPackage.runtime!!.recognizer.imageShape)
    }

    @Test
    fun `requires runtime contract for schema two`() {
        val root = temporaryFolder.newFolder("missing-runtime")
        val manifest = manifest().toMutableMap().apply { remove("runtimeConfig") }

        val error = assertThrows(LocalOcrException::class.java) {
            OcrModelPackage.fromMethodArguments(
                mapOf("modelDirectory" to root.path, "manifest" to manifest)
            )
        }

        assertEquals("invalid_input", error.code)
    }

    @Test
    fun `rejects missing roles and unsafe model paths`() {
        val root = temporaryFolder.newFolder("invalid")
        val missingRole = manifest().toMutableMap().apply {
            this["files"] = files().filter { it["role"] != "dictionary" }
        }
        assertEquals(
            "invalid_input",
            assertThrows(LocalOcrException::class.java) {
                OcrModelPackage.fromMethodArguments(
                    mapOf("modelDirectory" to root.path, "manifest" to missingRole)
                )
            }.code
        )

        val unsafe = manifest().toMutableMap().apply {
            this["files"] = files().map {
                if (it["role"] == "detector") it + ("path" to "../detector.onnx") else it
            }
        }
        assertEquals(
            "invalid_input",
            assertThrows(LocalOcrException::class.java) {
                OcrModelPackage.fromMethodArguments(
                    mapOf("modelDirectory" to root.path, "manifest" to unsafe)
                )
            }.code
        )
    }

    private fun arguments(modelDirectory: String): Map<String, Any?> = mapOf(
        "modelDirectory" to modelDirectory,
        "manifest" to manifest()
    )

    private fun manifest(): Map<String, Any?> = mapOf(
        "schemaVersion" to 2,
        "packageId" to "package",
        "version" to "1.0.0",
        "engine" to "onnxruntime",
        "languages" to listOf("zh-Hans"),
        "files" to files(),
        "runtimeConfig" to mapOf(
            "type" to "paddleocr-ppocrv5",
            "detector" to mapOf(
                "modelRole" to "detector",
                "tensor" to mapOf("inputName" to null, "outputName" to null),
                "resizeLongSide" to 960,
                "normalization" to mapOf(
                    "scale" to 1.0 / 255.0,
                    "mean" to listOf(0.485, 0.456, 0.406),
                    "standardDeviation" to listOf(0.229, 0.224, 0.225),
                    "colorOrder" to "bgr"
                ),
                "pixelThreshold" to 0.3,
                "boxThreshold" to 0.6,
                "maxCandidates" to 1000,
                "unclipRatio" to 1.5
            ),
            "recognizer" to mapOf(
                "modelRole" to "recognizer",
                "dictionaryRole" to "dictionary",
                "tensor" to mapOf("inputName" to null, "outputName" to null),
                "imageShape" to listOf(3, 48, 320),
                "normalization" to mapOf(
                    "scale" to 1.0 / 255.0,
                    "mean" to listOf(0.5, 0.5, 0.5),
                    "standardDeviation" to listOf(0.5, 0.5, 0.5),
                    "colorOrder" to "bgr"
                ),
                "blankIndex" to 0,
                "useSpaceCharacter" to false
            )
        )
    )

    private fun files(): List<Map<String, Any?>> = listOf(
        mapOf("role" to "detector", "path" to "models/detector.onnx"),
        mapOf("role" to "recognizer", "path" to "models/recognizer.onnx"),
        mapOf("role" to "dictionary", "path" to "models/dictionary.txt")
    )
}
