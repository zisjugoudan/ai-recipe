package com.airecipe.ai_recipe.ocr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalOcrProbeContractTest {
    @Test
    fun `reports recognition when runtime is available`() {
        val response = localOcrProbeResponse(runtimeAvailable = true)

        assertTrue(response["runtimeAvailable"] as Boolean)
        assertTrue(response["recognitionSupported"] as Boolean)
        assertEquals("onnxruntime-android", response["runtimeVersion"])
    }

    @Test
    fun `does not report recognition when runtime is unavailable`() {
        val response = localOcrProbeResponse(runtimeAvailable = false)

        assertFalse(response["runtimeAvailable"] as Boolean)
        assertFalse(response["recognitionSupported"] as Boolean)
        assertNull(response["runtimeVersion"])
    }
}
