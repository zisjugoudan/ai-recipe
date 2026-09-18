package com.airecipe.ai_recipe.ocr

class LocalOcrException(
    val code: String,
    message: String
) : Exception(message) {
    val safeMessage: String = message.replace(Regex("\\s+"), " ").take(240)
}
