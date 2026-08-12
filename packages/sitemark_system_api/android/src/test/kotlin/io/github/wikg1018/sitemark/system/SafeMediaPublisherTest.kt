package io.github.wikg1018.sitemark.system

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class SafeMediaPublisherTest {
    @Test
    fun `replacement failure restores previous bytes and published state`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image").apply {
                failSource = source
            }
            val backup = File(directory, "backup.jpg")
            val publisher = SafeMediaPublisher(store) { backup }

            assertThrows(IllegalStateException::class.java) {
                publisher.publish(source, "capture.jpg")
            }

            assertEquals("old-image", store.existingBytes)
            assertFalse(store.pending)
            assertFalse(backup.exists())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `backup failure leaves existing image untouched`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image").apply {
                failBackup = true
            }
            val publisher = SafeMediaPublisher(store) { File(directory, "backup.jpg") }

            assertThrows(IllegalStateException::class.java) {
                publisher.publish(source, "capture.jpg")
            }

            assertEquals("old-image", store.existingBytes)
            assertFalse(store.pending)
            assertEquals(0, store.stateChanges)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `new image failure deletes its pending row`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "new.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = null).apply {
                failSource = source
            }
            val publisher = SafeMediaPublisher(store) { File(directory, "unused.jpg") }

            assertThrows(IllegalStateException::class.java) {
                publisher.publish(source, "capture.jpg")
            }

            assertTrue(store.deleted)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `double write failure keeps potentially partial image hidden`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image").apply {
                failAllWrites = true
            }
            val publisher = SafeMediaPublisher(store) { File(directory, "backup.jpg") }

            val error = assertThrows(IllegalStateException::class.java) {
                publisher.publish(source, "capture.jpg")
            }

            assertTrue(store.pending)
            assertEquals(1, error.suppressed.size)
        } finally {
            directory.deleteRecursively()
        }
    }
}

private class FakePublishedImageStore(existingBytes: String?) : PublishedImageStore {
    var existingBytes = existingBytes
    var pending = false
    var deleted = false
    var stateChanges = 0
    var failBackup = false
    var failAllWrites = false
    var failSource: File? = null

    override fun find(displayName: String): String? =
        if (existingBytes == null) null else CONTENT_URI

    override fun insertPending(displayName: String): String {
        existingBytes = ""
        pending = true
        return CONTENT_URI
    }

    override fun backup(contentUri: String, destination: File) {
        if (failBackup) error("backup failed")
        destination.writeText(checkNotNull(existingBytes))
    }

    override fun write(contentUri: String, source: File) {
        existingBytes = "partial"
        if (failAllWrites || source == failSource) error("write failed")
        existingBytes = source.readText()
    }

    override fun setPending(contentUri: String, pending: Boolean) {
        this.pending = pending
        stateChanges += 1
    }

    override fun delete(contentUri: String) {
        deleted = true
        existingBytes = null
    }

    companion object {
        private const val CONTENT_URI = "content://media/site-mark/1"
    }
}
