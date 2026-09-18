package com.airecipe.ai_recipe.ocr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OcrCtcDecoderTest {
    @Test
    fun `decodes when blank class is first`() {
        val result = decode(
            rows = listOf(
                row(0.05f, 0.90f, 0.05f),
                row(0.05f, 0.90f, 0.05f),
                row(0.90f, 0.05f, 0.05f),
                row(0.05f, 0.85f, 0.10f),
                row(0.05f, 0.10f, 0.85f)
            ),
            blankIndex = 0,
            symbols = listOf("A", "B")
        )

        assertEquals("AAB", result.text)
        assertEquals(0.866f, result.confidence, 0.01f)
    }

    @Test
    fun `decodes when blank class is in the middle`() {
        val result = decode(
            rows = listOf(
                row(0.90f, 0.05f, 0.05f),
                row(0.05f, 0.90f, 0.05f),
                row(0.05f, 0.05f, 0.90f)
            ),
            blankIndex = 1,
            symbols = listOf("A", "B")
        )

        assertEquals("AB", result.text)
    }

    @Test
    fun `decodes when blank class is last`() {
        val result = decode(
            rows = listOf(
                row(0.90f, 0.05f, 0.05f),
                row(0.05f, 0.90f, 0.05f),
                row(0.05f, 0.05f, 0.90f)
            ),
            blankIndex = 2,
            symbols = listOf("A", "B")
        )

        assertEquals("AB", result.text)
    }

    @Test
    fun `collapses adjacent duplicates but keeps blank separated duplicates`() {
        val result = decode(
            rows = listOf(
                row(0.05f, 0.90f, 0.05f),
                row(0.05f, 0.90f, 0.05f),
                row(0.90f, 0.05f, 0.05f),
                row(0.05f, 0.90f, 0.05f)
            ),
            blankIndex = 0,
            symbols = listOf("A", "B")
        )

        assertEquals("AA", result.text)
    }

    @Test
    fun `returns empty text when every timestep is blank`() {
        val result = decode(
            rows = listOf(
                row(0.95f, 0.03f, 0.02f),
                row(0.90f, 0.05f, 0.05f)
            ),
            blankIndex = 0,
            symbols = listOf("A", "B")
        )

        assertEquals("", result.text)
        assertEquals(0f, result.confidence, 0f)
    }

    @Test
    fun `uses softmax confidence for logits`() {
        val result = decode(
            rows = listOf(row(-1f, 3f, 0f)),
            blankIndex = 0,
            symbols = listOf("A", "B")
        )

        assertEquals("A", result.text)
        assertTrue(result.confidence in 0.93f..0.94f)
    }

    @Test(expected = LocalOcrException::class)
    fun `rejects dictionary and class count mismatch`() {
        // symbols=1：合法 classes 范围是 2..3（+1 blank 或 +2 含尾随类）；
        // classes=4 超出范围，应拒绝。
        OcrCtcDecoder.decode(
            values = row(0.1f, 0.9f, 0f, 0f),
            timesteps = 1,
            classes = 4,
            blankIndex = 0,
            symbols = listOf("A")
        )
    }

    @Test
    fun `skips trailing extra class that does not map to a symbol`() {
        // PP-OCRv5 场景：classes = symbols + 2，末尾额外类不发射。
        val result = decode(
            rows = listOf(
                row(0.05f, 0.90f, 0.05f, 0.00f),
                row(0.05f, 0.05f, 0.90f, 0.00f),
                row(0.02f, 0.02f, 0.02f, 0.94f)
            ),
            blankIndex = 0,
            symbols = listOf("A", "B")
        )

        assertEquals("AB", result.text)
    }

    private fun decode(
        rows: List<FloatArray>,
        blankIndex: Int,
        symbols: List<String>
    ): Recognition {
        val classes = rows.first().size
        return OcrCtcDecoder.decode(
            values = rows.flatMap { it.asIterable() }.toFloatArray(),
            timesteps = rows.size,
            classes = classes,
            blankIndex = blankIndex,
            symbols = symbols
        )
    }

    private fun row(vararg values: Float): FloatArray = values
}
