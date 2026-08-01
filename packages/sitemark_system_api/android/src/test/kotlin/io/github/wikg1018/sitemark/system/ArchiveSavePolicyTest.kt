package io.github.wikg1018.sitemark.system

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files

class ArchiveSavePolicyTest {
    @Test
    fun validatesPrivateZipAndStreamsItsBytes() {
        val root = Files.createTempDirectory("sitemark-archive-").toFile()
        try {
            val source = File(root, "backup.zip").apply {
                writeBytes(ByteArray(64 * 1024) { (it % 251).toByte() })
            }
            val validated = ArchiveSavePolicy.validateSource(source.path, root)
            val output = ByteArrayOutputStream()

            ArchiveSavePolicy.copy(validated, output)

            assertArrayEquals(source.readBytes(), output.toByteArray())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun rejectsOutsidePrivateStorageAndNonZipFiles() {
        val root = Files.createTempDirectory("sitemark-private-").toFile()
        val outside = Files.createTempDirectory("sitemark-outside-").toFile()
        try {
            val outsideZip = File(outside, "backup.zip").apply { writeText("zip") }
            val privateText = File(root, "backup.txt").apply { writeText("text") }

            assertThrows(IllegalArgumentException::class.java) {
                ArchiveSavePolicy.validateSource(outsideZip.path, root)
            }
            assertThrows(IllegalArgumentException::class.java) {
                ArchiveSavePolicy.validateSource(privateText.path, root)
            }
        } finally {
            root.deleteRecursively()
            outside.deleteRecursively()
        }
    }

    @Test
    fun normalizesOnlySafeZipNames() {
        assertEquals(
            "sitemark-backup-123.zip",
            ArchiveSavePolicy.normalizeSuggestedName("sitemark-backup-123.zip"),
        )
        assertThrows(IllegalArgumentException::class.java) {
            ArchiveSavePolicy.normalizeSuggestedName("../backup.zip")
        }
        assertThrows(IllegalArgumentException::class.java) {
            ArchiveSavePolicy.normalizeSuggestedName("backup.jpg")
        }
    }
}
