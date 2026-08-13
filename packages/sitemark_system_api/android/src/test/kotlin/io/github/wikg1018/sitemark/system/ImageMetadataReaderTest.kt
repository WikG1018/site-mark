package io.github.wikg1018.sitemark.system

import androidx.exifinterface.media.ExifInterface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.File

class ImageMetadataReaderTest {
    @Test
    fun orientationsFiveThroughEightSwapWidthAndHeight() {
        assertEquals(3000 to 4000, ImageOrientation.displaySize(4000, 3000, 5))
        assertEquals(3000 to 4000, ImageOrientation.displaySize(4000, 3000, 6))
        assertEquals(3000 to 4000, ImageOrientation.displaySize(4000, 3000, 7))
        assertEquals(3000 to 4000, ImageOrientation.displaySize(4000, 3000, 8))
        assertEquals(
            3000 to 4000,
            ImageOrientation.displaySize(4000, 3000, ExifInterface.ORIENTATION_ROTATE_90),
        )
        assertEquals(
            3000 to 4000,
            ImageOrientation.displaySize(4000, 3000, ExifInterface.ORIENTATION_ROTATE_270),
        )
    }

    @Test
    fun orientationsOneThroughFourKeepEncodedSize() {
        assertEquals(4000 to 3000, ImageOrientation.displaySize(4000, 3000, 1))
        assertEquals(4000 to 3000, ImageOrientation.displaySize(4000, 3000, 2))
        assertEquals(4000 to 3000, ImageOrientation.displaySize(4000, 3000, 3))
        assertEquals(4000 to 3000, ImageOrientation.displaySize(4000, 3000, 4))
        assertEquals(
            4000 to 3000,
            ImageOrientation.displaySize(4000, 3000, ExifInterface.ORIENTATION_NORMAL),
        )
    }

    @Test
    fun missingDecodedBoundsFailWithoutJpegMimeFallback() {
        val file = File.createTempFile("sitemark-empty", ".jpg")
        try {
            file.writeBytes(byteArrayOf(0, 1, 2, 3))
            val error = assertThrows(IllegalArgumentException::class.java) {
                AndroidXImageMetadataReader().read(file)
            }
            assertFalse(error.message.orEmpty().contains("image/jpeg"))
        } finally {
            file.delete()
        }
    }
}
