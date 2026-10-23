package io.github.wikg1018.sitemark.system

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.nio.file.Files
import java.util.TimeZone

class GalleryImportPolicyTest {
    @Test fun sourceTimeIsStrictAndSupportsExplicitOffset() {
        assertNull(GalleryImportPolicy.parseExifTime("2024:02:30 12:00:00", null))
        assertNull(GalleryImportPolicy.parseExifTime("", null))
        assertEquals(0L, GalleryImportPolicy.parseExifTime("1970:01:01 08:00:00", "+08:00"))
        assertEquals(0L, GalleryImportPolicy.parseExifTime("1970:01:01 00:00:00", null, TimeZone.getTimeZone("UTC")))
    }

    @Test fun boundedCopyRejectsEmptyAndOversizeWithoutLeavingPartialFile() {
        val dir = Files.createTempDirectory("gallery-policy").toFile()
        try {
            val target = dir.resolve("image.jpg")
            for (bytes in listOf(byteArrayOf(), ByteArray(9))) {
                assertThrows(IllegalArgumentException::class.java) {
                    GalleryImportPolicy.copyAtomically(ByteArrayInputStream(bytes), target, 8) { }
                }
                assertFalse(target.exists())
                assertFalse(dir.resolve("image.jpg.part").exists())
            }
        } finally { dir.deleteRecursively() }
    }

    @Test fun validatedCopyPreservesBytesAndNeverOverwritesExistingOriginal() {
        val dir = Files.createTempDirectory("gallery-policy").toFile()
        try {
            val target = dir.resolve("image.jpg")
            val bytes = byteArrayOf(1, 2, 3, 4)
            GalleryImportPolicy.copyAtomically(ByteArrayInputStream(bytes), target, 8) { }
            assertArrayEquals(bytes, target.readBytes())
            assertThrows(IllegalStateException::class.java) {
                GalleryImportPolicy.copyAtomically(ByteArrayInputStream(byteArrayOf(9)), target, 8) { }
            }
            assertArrayEquals(bytes, target.readBytes())
        } finally { dir.deleteRecursively() }
    }

    @Test fun validationFailureDoesNotPublishPartialOriginal() {
        val dir = Files.createTempDirectory("gallery-policy").toFile()
        try {
            val target = dir.resolve("image.jpg")
            assertThrows(IllegalArgumentException::class.java) {
                GalleryImportPolicy.copyAtomically(ByteArrayInputStream(byteArrayOf(1)), target, 8) {
                    throw IllegalArgumentException("unsupported")
                }
            }
            assertFalse(target.exists())
            assertEquals(0, dir.listFiles()!!.size)
        } finally { dir.deleteRecursively() }
    }
}
