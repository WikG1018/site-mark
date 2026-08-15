package io.github.wikg1018.sitemark.system

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class SafeMediaPublisherTest {
    @Test
    fun `replacement publishes a new row and deletes the old one`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image")
            val publisher = SafeMediaPublisher(store)

            val published = publisher.publish(source, "capture.jpg")

            assertEquals(FakePublishedImageStore.NEW_URI, published)
            // The old row is gone and the new row is finalized with the new
            // bytes — never a half-written row left visible.
            assertNull(store.rows[FakePublishedImageStore.OLD_URI])
            val newRow = store.rows[FakePublishedImageStore.NEW_URI]
            assertEquals("new-image", newRow?.bytes)
            assertEquals(false, newRow?.pending)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `replacement write failure keeps the old row intact`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image").apply {
                failWrite = true
            }
            val publisher = SafeMediaPublisher(store)

            assertThrows(IllegalStateException::class.java) {
                publisher.publish(source, "capture.jpg")
            }

            // The old published row was never touched...
            assertEquals("old-image", store.rows[FakePublishedImageStore.OLD_URI]?.bytes)
            assertEquals(false, store.rows[FakePublishedImageStore.OLD_URI]?.pending)
            // ...and the partially written pending row is cleaned up.
            assertNull(store.rows[FakePublishedImageStore.NEW_URI])
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `old row delete failure restores a consistent published state`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image").apply {
                failDeleteOldRow = true
            }
            val publisher = SafeMediaPublisher(store)

            assertThrows(IllegalStateException::class.java) {
                publisher.publish(source, "capture.jpg")
            }

            // The old row is still published with the old bytes and the
            // prepared replacement row is removed — no duplicate names.
            assertEquals("old-image", store.rows[FakePublishedImageStore.OLD_URI]?.bytes)
            assertEquals(false, store.rows[FakePublishedImageStore.OLD_URI]?.pending)
            assertNull(store.rows[FakePublishedImageStore.NEW_URI])
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `finalize failure after old row removal cleans the pending row`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image").apply {
                failFinalize = true
            }
            val publisher = SafeMediaPublisher(store)

            val error = assertThrows(IllegalStateException::class.java) {
                publisher.publish(source, "capture.jpg")
            }

            // The old row is already gone (documented narrow window) and the
            // unfinalized new row must not linger as an orphan; the caller
            // re-publishes from the private original to recover.
            assertNull(store.rows[FakePublishedImageStore.OLD_URI])
            assertNull(store.rows[FakePublishedImageStore.NEW_URI])
            assertEquals(0, error.suppressed.size)
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
                failWrite = true
            }
            val publisher = SafeMediaPublisher(store)

            assertThrows(IllegalStateException::class.java) {
                publisher.publish(source, "capture.jpg")
            }

            assertTrue(store.rows.isEmpty())
        } finally {
            directory.deleteRecursively()
        }
    }
}

private class FakePublishedImageStore(existingBytes: String?) : PublishedImageStore {
    class Row(var bytes: String, var pending: Boolean)

    val rows = linkedMapOf<String, Row>()
    var failWrite = false
    var failFinalize = false
    var failDeleteOldRow = false

    init {
        if (existingBytes != null) {
            rows[OLD_URI] = Row(existingBytes, pending = false)
        }
    }

    override fun find(displayName: String): String? =
        rows.entries.firstOrNull { !it.value.pending }?.key

    override fun insertPending(displayName: String): String {
        rows[NEW_URI] = Row("", pending = true)
        return NEW_URI
    }

    override fun write(contentUri: String, source: File) {
        val row = rows.getValue(contentUri)
        row.bytes = "partial"
        if (failWrite) error("write failed")
        row.bytes = source.readText()
    }

    override fun setPending(contentUri: String, pending: Boolean) {
        if (!pending && failFinalize) error("finalize failed")
        rows.getValue(contentUri).pending = pending
    }

    override fun delete(contentUri: String) {
        if (contentUri == OLD_URI && failDeleteOldRow) error("delete failed")
        rows.remove(contentUri)
    }

    companion object {
        const val OLD_URI = "content://media/site-mark/1"
        const val NEW_URI = "content://media/site-mark/2"
    }
}
