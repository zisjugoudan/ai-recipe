package com.airecipe.ai_recipe.ocr

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream

class LocalOcrImageSource private constructor(
    private val context: Context,
    private val contentUri: Uri?,
    private val file: File?,
    val mimeType: String?
) {
    fun decodeBitmap(): Bitmap {
        val bytes = readBytes()
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val width = bounds.outWidth
        val height = bounds.outHeight
        if (width <= 0 || height <= 0) {
            throw LocalOcrException("invalid_input", "OCR image could not be decoded.")
        }
        if (width > MAX_IMAGE_DIMENSION || height > MAX_IMAGE_DIMENSION) {
            throw LocalOcrException("image_too_large", "OCR image dimensions are too large.")
        }

        val sampleSize = calculateSampleSize(width, height)
        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inSampleSize = sampleSize
        }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
            ?: throw LocalOcrException("invalid_input", "OCR image could not be decoded.")
    }

    private fun readBytes(): ByteArray {
        file?.let { sourceFile ->
            if (!sourceFile.exists() || !sourceFile.isFile) {
                throw LocalOcrException("invalid_input", "OCR image file is unavailable.")
            }
            if (sourceFile.length() > MAX_IMAGE_BYTES) {
                throw LocalOcrException("image_too_large", "OCR image file is too large.")
            }
            return sourceFile.inputStream().use(::readLimited)
        }

        val uri = contentUri
            ?: throw LocalOcrException("invalid_input", "OCR image source is unavailable.")
        val declaredLength = try {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { descriptor ->
                descriptor.length
            }
        } catch (_: SecurityException) {
            throw LocalOcrException("image_permission_denied", "OCR image access was denied.")
        } catch (_: Throwable) {
            null
        }
        if (declaredLength != null && declaredLength > MAX_IMAGE_BYTES) {
            throw LocalOcrException("image_too_large", "OCR image file is too large.")
        }
        val stream = try {
            context.contentResolver.openInputStream(uri)
        } catch (_: SecurityException) {
            throw LocalOcrException("image_permission_denied", "OCR image access was denied.")
        } catch (_: Throwable) {
            null
        } ?: throw LocalOcrException("invalid_input", "OCR image source is unavailable.")
        return stream.use(::readLimited)
    }

    private fun readLimited(stream: InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            total += count
            if (total > MAX_IMAGE_BYTES) {
                throw LocalOcrException("image_too_large", "OCR image file is too large.")
            }
            output.write(buffer, 0, count)
        }
        if (total == 0L) {
            throw LocalOcrException("invalid_input", "OCR image source is empty.")
        }
        return output.toByteArray()
    }

    private fun calculateSampleSize(width: Int, height: Int): Int {
        var sampleSize = 1
        while (width / sampleSize > MAX_DECODED_DIMENSION ||
            height / sampleSize > MAX_DECODED_DIMENSION ||
            width.toLong() * height.toLong() / sampleSize / sampleSize > MAX_DECODED_PIXELS
        ) {
            sampleSize *= 2
        }
        return sampleSize
    }

    companion object {
        fun fromMethodArguments(context: Context, arguments: Any?): LocalOcrImageSource {
            val args = arguments.asStringMap("Invalid OCR model request.")
            val image = args.requiredMap("image", "Missing OCR image input.")
            val remoteUrl = image.optionalString("remoteUrl")
            val localAssetId = image.optionalString("localAssetId")
            val mimeType = image.optionalString("mimeType")?.lowercase()
            if (mimeType != null && !mimeType.startsWith("image/")) {
                throw LocalOcrException("invalid_input", "OCR input MIME type is not an image.")
            }
            if (localAssetId == null) {
                if (remoteUrl != null) {
                    throw LocalOcrException(
                        "image_source_unavailable",
                        "Remote OCR images must be staged locally before recognition."
                    )
                }
                throw LocalOcrException("invalid_input", "Missing OCR local image source.")
            }

            val uri = Uri.parse(localAssetId)
            return when (uri.scheme?.lowercase()) {
                "content" -> {
                    val resolvedMimeType = try {
                        context.contentResolver.getType(uri)?.lowercase()
                    } catch (_: SecurityException) {
                        throw LocalOcrException(
                            "image_permission_denied",
                            "OCR image access was denied."
                        )
                    } catch (_: Throwable) {
                        null
                    }
                    if (resolvedMimeType != null && !resolvedMimeType.startsWith("image/")) {
                        throw LocalOcrException(
                            "invalid_input",
                            "OCR content URI does not reference an image."
                        )
                    }
                    LocalOcrImageSource(
                        context = context,
                        contentUri = uri,
                        file = null,
                        mimeType = resolvedMimeType ?: mimeType
                    )
                }
                "file" -> fromPrivateFile(context, uri.path, mimeType)
                null, "" -> fromPrivateFile(context, localAssetId, mimeType)
                else -> throw LocalOcrException(
                    "invalid_input",
                    "Unsupported OCR local image source."
                )
            }
        }

        private fun fromPrivateFile(
            context: Context,
            path: String?,
            mimeType: String?
        ): LocalOcrImageSource {
            val candidatePath = path?.trim()?.takeIf { it.isNotEmpty() }
                ?: throw LocalOcrException("invalid_input", "Missing OCR image file path.")
            val candidate = try {
                File(candidatePath).canonicalFile
            } catch (_: SecurityException) {
                throw LocalOcrException(
                    "image_permission_denied",
                    "OCR image access was denied."
                )
            } catch (_: Throwable) {
                throw LocalOcrException("invalid_input", "OCR image file is unavailable.")
            }
            if (!candidate.isAbsolute || !isInsideAppStorage(context, candidate)) {
                throw LocalOcrException(
                    "image_permission_denied",
                    "OCR image file is outside application storage."
                )
            }
            return LocalOcrImageSource(
                context = context,
                contentUri = null,
                file = candidate,
                mimeType = mimeType
            )
        }

        private fun isInsideAppStorage(context: Context, candidate: File): Boolean {
            val roots = buildList {
                add(context.filesDir)
                add(context.cacheDir)
                add(context.noBackupFilesDir)
                context.externalCacheDir?.let(::add)
                context.getExternalFilesDirs(null).filterNotNull().forEach(::add)
            }
            return roots.any { root ->
                val canonicalRoot = try {
                    root.canonicalFile
                } catch (_: Throwable) {
                    return@any false
                }
                candidate == canonicalRoot ||
                    candidate.path.startsWith(canonicalRoot.path + File.separator)
            }
        }

        private const val MAX_IMAGE_BYTES = 32L * 1024L * 1024L
        private const val MAX_IMAGE_DIMENSION = 16_384
        private const val MAX_DECODED_DIMENSION = 8_192
        private const val MAX_DECODED_PIXELS = 20_000_000L
    }
}
