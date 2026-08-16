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

            assertEquals(FakePublishedImageStore.NEW_URI, published.contentUri)
            assertTrue(published.supersededUris.isEmpty())
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
    fun `old row delete failure keeps the finalized new row published`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image").apply {
                failDeleteOldRow = true
            }
            val publisher = SafeMediaPublisher(store)

            // The new row was already finalized, so the publish is a SUCCESS
            // even though the old-row delete failed. It must NOT throw: a
            // fake failure would make the caller re-publish and accumulate
            // gallery duplicates.
            val published = publisher.publish(source, "capture.jpg")

            assertEquals(FakePublishedImageStore.NEW_URI, published.contentUri)
            // The stale URI is reported so the caller can retry ONLY the
            // delete through the persistent cleanup queue.
            assertEquals(listOf(FakePublishedImageStore.OLD_URI), published.supersededUris)
            // The new row stays finalized and published — deleting both rows
            // could leave the gallery empty. The old row remains as a
            // temporary duplicate until the next cleanup pass retries the
            // delete.
            assertEquals("new-image", store.rows[FakePublishedImageStore.NEW_URI]?.bytes)
            assertEquals(false, store.rows[FakePublishedImageStore.NEW_URI]?.pending)
            assertEquals("old-image", store.rows[FakePublishedImageStore.OLD_URI]?.bytes)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `every duplicate row with the same name is deleted on replacement`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(
                existingBytes = "old-image",
                duplicateBytes = "older-image",
            )
            val publisher = SafeMediaPublisher(store)

            val published = publisher.publish(source, "capture.jpg")

            assertEquals(FakePublishedImageStore.NEW_URI, published.contentUri)
            assertTrue(published.supersededUris.isEmpty())
            // Historical duplicates (e.g. left by an earlier failed
            // replacement) converge too — only the finalized new row stays.
            assertNull(store.rows[FakePublishedImageStore.OLD_URI])
            assertNull(store.rows[FakePublishedImageStore.DUPLICATE_URI])
            assertEquals("new-image", store.rows[FakePublishedImageStore.NEW_URI]?.bytes)
            assertEquals(false, store.rows[FakePublishedImageStore.NEW_URI]?.pending)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `failing duplicate deletes are all reported as superseded`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(
                existingBytes = "old-image",
                duplicateBytes = "older-image",
            ).apply {
                failDeleteOldRow = true
                failDeleteDuplicateRow = true
            }
            val publisher = SafeMediaPublisher(store)

            // The new row was already finalized, so the publish is a SUCCESS
            // and every un-deletable stale URI is reported independently.
            val published = publisher.publish(source, "capture.jpg")

            assertEquals(FakePublishedImageStore.NEW_URI, published.contentUri)
            assertEquals(
                setOf(FakePublishedImageStore.OLD_URI, FakePublishedImageStore.DUPLICATE_URI),
                published.supersededUris.toSet(),
            )
            assertEquals(false, store.rows[FakePublishedImageStore.NEW_URI]?.pending)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `finalize failure keeps the old row and cleans the pending row`() {
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

            // Finalization happens before the old row is removed, so the old
            // published photo is untouched and the unfinalized pending row
            // must not linger as an orphan; the caller can safely retry.
            assertEquals("old-image", store.rows[FakePublishedImageStore.OLD_URI]?.bytes)
            assertEquals(false, store.rows[FakePublishedImageStore.OLD_URI]?.pending)
            assertNull(store.rows[FakePublishedImageStore.NEW_URI])
            assertEquals(0, error.suppressed.size)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `journal records the finalized publish before deleting superseded rows`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image")
            val calls = mutableListOf<Triple<String, String, List<String>>>()
            val journal = PublishJournalSink { name, uri, superseded ->
                calls += Triple(name, uri, superseded)
                // 时序证明：journal 被调用时旧行还在 —— 即转正之后、删除之前。
                assertTrue(store.rows.containsKey(FakePublishedImageStore.OLD_URI))
                true
            }
            val publisher = SafeMediaPublisher(store, journal)

            val published = publisher.publish(source, "capture.jpg")

            // journal 恰好记录一次，内容为 (displayName, 新 URI, 全部被取代的旧 URI)。
            assertEquals(
                listOf(
                    Triple(
                        "capture.jpg",
                        FakePublishedImageStore.NEW_URI,
                        listOf(FakePublishedImageStore.OLD_URI),
                    ),
                ),
                calls,
            )
            assertNull(store.rows[FakePublishedImageStore.OLD_URI])
            assertEquals(FakePublishedImageStore.NEW_URI, published.contentUri)
            assertTrue(published.supersededUris.isEmpty())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `journal write failure keeps old rows and reports them all superseded`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(
                existingBytes = "old-image",
                duplicateBytes = "older-image",
            )
            // journal 落盘失败：不能再删旧行（删了就没人跟踪了），
            // 旧行全部上报为 superseded，交给调用方的清理队列跟踪。
            val journal = PublishJournalSink { _, _, _ -> false }
            val publisher = SafeMediaPublisher(store, journal)

            val published = publisher.publish(source, "capture.jpg")

            assertEquals(FakePublishedImageStore.NEW_URI, published.contentUri)
            assertEquals(
                listOf(FakePublishedImageStore.OLD_URI, FakePublishedImageStore.DUPLICATE_URI),
                published.supersededUris,
            )
            // 旧行 bytes 原样保留且仍非 pending。
            assertEquals("old-image", store.rows[FakePublishedImageStore.OLD_URI]?.bytes)
            assertEquals(false, store.rows[FakePublishedImageStore.OLD_URI]?.pending)
            assertEquals("older-image", store.rows[FakePublishedImageStore.DUPLICATE_URI]?.bytes)
            assertEquals(false, store.rows[FakePublishedImageStore.DUPLICATE_URI]?.pending)
            // 新行已转正 —— 发布本身是成功的。
            assertEquals(false, store.rows[FakePublishedImageStore.NEW_URI]?.pending)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `first publish journals the new row with no superseded candidates`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "new.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = null)
            val calls = mutableListOf<Triple<String, String, List<String>>>()
            val journal = PublishJournalSink { name, uri, superseded ->
                calls += Triple(name, uri, superseded)
                true
            }
            val publisher = SafeMediaPublisher(store, journal)

            val published = publisher.publish(source, "capture.jpg")

            // 首次发布也要 journal：否则提交前崩溃会留下无人追踪的孤儿。
            assertEquals(
                listOf(Triple("capture.jpg", FakePublishedImageStore.NEW_URI, emptyList<String>())),
                calls,
            )
            assertEquals(FakePublishedImageStore.NEW_URI, published.contentUri)
            assertTrue(published.supersededUris.isEmpty())
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

private class FakePublishedImageStore(
    existingBytes: String?,
    duplicateBytes: String? = null,
) : PublishedImageStore {
    class Row(var bytes: String, var pending: Boolean)

    val rows = linkedMapOf<String, Row>()
    var failWrite = false
    var failFinalize = false
    var failDeleteOldRow = false
    var failDeleteDuplicateRow = false

    init {
        if (existingBytes != null) {
            rows[OLD_URI] = Row(existingBytes, pending = false)
        }
        if (duplicateBytes != null) {
            rows[DUPLICATE_URI] = Row(duplicateBytes, pending = false)
        }
    }

    override fun findAll(displayName: String): List<String> =
        rows.filterValues { !it.pending }.keys.toList()

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
        if (contentUri == DUPLICATE_URI && failDeleteDuplicateRow) error("delete failed")
        rows.remove(contentUri)
    }

    companion object {
        const val OLD_URI = "content://media/site-mark/1"
        const val DUPLICATE_URI = "content://media/site-mark/0"
        const val NEW_URI = "content://media/site-mark/2"
    }
}
