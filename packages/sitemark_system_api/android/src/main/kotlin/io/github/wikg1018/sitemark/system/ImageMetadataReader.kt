package io.github.wikg1018.sitemark.system

import android.graphics.BitmapFactory
import androidx.exifinterface.media.ExifInterface
import java.io.File

fun interface ImageMetadataReader {
    fun read(file: File): ImageMetadataResult
}

internal object ImageOrientation {
    fun displaySize(encodedWidth: Int, encodedHeight: Int, orientation: Int): Pair<Int, Int> =
        if (swapsDimensions(orientation)) {
            encodedHeight to encodedWidth
        } else {
            encodedWidth to encodedHeight
        }

    fun swapsDimensions(orientation: Int): Boolean =
        orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
            orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
            orientation == ExifInterface.ORIENTATION_TRANSVERSE ||
            orientation == ExifInterface.ORIENTATION_ROTATE_270
}

internal class AndroidXImageMetadataReader : ImageMetadataReader {
    override fun read(file: File): ImageMetadataResult {
        val exif = ExifInterface(file)
        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) {
            "Image has no decodable dimensions"
        }
        val orientation = exif.getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
        val (width, height) = ImageOrientation.displaySize(
            bounds.outWidth,
            bounds.outHeight,
            orientation,
        )
        val latLong = FloatArray(2)
        val hasGps = exif.getLatLong(latLong)
        val latitude = if (hasGps) latLong[0].toDouble() else null
        val longitude = if (hasGps) latLong[1].toDouble() else null
        val validGps = latitude != null && longitude != null &&
            latitude in -90.0..90.0 && longitude in -180.0..180.0
        return ImageMetadataResult(
            width = width.toLong(),
            height = height.toLong(),
            fileSizeBytes = file.length(),
            mimeType = bounds.outMimeType ?: "image/jpeg",
            latitude = if (validGps) latitude else null,
            longitude = if (validGps) longitude else null,
        )
    }
}