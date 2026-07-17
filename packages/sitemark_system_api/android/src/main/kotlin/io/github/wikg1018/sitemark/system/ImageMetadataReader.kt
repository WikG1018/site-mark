package io.github.wikg1018.sitemark.system

import android.graphics.BitmapFactory
import androidx.exifinterface.media.ExifInterface
import java.io.File

fun interface ImageMetadataReader {
    fun read(file: File): ImageMetadataResult
}

internal class AndroidXImageMetadataReader : ImageMetadataReader {
    override fun read(file: File): ImageMetadataResult {
        val exif = ExifInterface(file)
        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        val latLong = FloatArray(2)
        val hasGps = exif.getLatLong(latLong)
        val latitude = if (hasGps) latLong[0].toDouble() else null
        val longitude = if (hasGps) latLong[1].toDouble() else null
        val validGps = latitude != null && longitude != null &&
            latitude in -90.0..90.0 && longitude in -180.0..180.0
        return ImageMetadataResult(
            width = bounds.outWidth.coerceAtLeast(0).toLong(),
            height = bounds.outHeight.coerceAtLeast(0).toLong(),
            fileSizeBytes = file.length(),
            mimeType = bounds.outMimeType ?: "image/jpeg",
            latitude = if (validGps) latitude else null,
            longitude = if (validGps) longitude else null,
        )
    }
}