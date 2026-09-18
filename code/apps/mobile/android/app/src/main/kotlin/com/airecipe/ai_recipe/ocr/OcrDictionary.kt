package com.airecipe.ai_recipe.ocr

import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

object OcrDictionary {
    const val MAX_BYTES = 8L * 1024L * 1024L
    const val MAX_LINES = 100_000

    fun load(file: File, useSpaceCharacter: Boolean): List<String> {
        if (!file.exists() || !file.isFile) {
            throw LocalOcrException("model_not_installed", "OCR dictionary is missing.")
        }
        if (file.length() > MAX_BYTES) {
            throw LocalOcrException("invalid_input", "OCR dictionary is too large.")
        }
        val bytes = file.readBytes()
        if (bytes.any { it == 0.toByte() }) {
            throw LocalOcrException("invalid_input", "OCR dictionary contains invalid data.")
        }
        val decoder = StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        val text = try {
            decoder.decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: Throwable) {
            throw LocalOcrException("invalid_input", "OCR dictionary is not valid UTF-8.")
        }
        val entries = text.lineSequence()
            .mapIndexed { index, line ->
                val withoutCarriageReturn = line.removeSuffix("\r")
                if (index == 0) withoutCarriageReturn.removePrefix("\uFEFF")
                else withoutCarriageReturn
            }
            .filter { it.isNotEmpty() }
            .take(MAX_LINES + 1)
            .toMutableList()
        if (entries.isEmpty()) {
            throw LocalOcrException("invalid_input", "OCR dictionary is empty.")
        }
        if (entries.size > MAX_LINES) {
            throw LocalOcrException("invalid_input", "OCR dictionary has too many entries.")
        }
        if (useSpaceCharacter && entries.lastOrNull() != " ") entries += " "
        return entries.toList()
    }
}
