package com.airecipe.ai_recipe.ocr

import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class OcrDictionaryTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `loads utf8 dictionary and removes leading bom`() {
        val dictionary = temporaryFolder.newFile("dictionary.txt")
        dictionary.writeBytes("\uFEFFa\r\nb\r\n".toByteArray(Charsets.UTF_8))

        assertEquals(listOf("a", "b"), OcrDictionary.load(dictionary, false))
    }

    @Test
    fun `adds a single space entry when requested`() {
        val dictionary = temporaryFolder.newFile("dictionary.txt")
        dictionary.writeText("a\nb\n", Charsets.UTF_8)

        assertEquals(listOf("a", "b", " "), OcrDictionary.load(dictionary, true))
    }

    @Test
    fun `rejects null bytes and malformed utf8`() {
        val nullDictionary = temporaryFolder.newFile("null.txt")
        nullDictionary.writeBytes(byteArrayOf('a'.code.toByte(), 0, 'b'.code.toByte()))
        assertEquals(
            "invalid_input",
            assertThrows(LocalOcrException::class.java) {
                OcrDictionary.load(nullDictionary, false)
            }.code
        )

        val malformedDictionary = temporaryFolder.newFile("malformed.txt")
        Files.write(malformedDictionary.toPath(), byteArrayOf(0xC3.toByte(), 0x28))
        assertEquals(
            "invalid_input",
            assertThrows(LocalOcrException::class.java) {
                OcrDictionary.load(malformedDictionary, false)
            }.code
        )
    }
}
