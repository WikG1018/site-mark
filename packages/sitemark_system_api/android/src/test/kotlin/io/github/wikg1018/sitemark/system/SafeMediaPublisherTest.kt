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
    fun `replacement publishes a new row and deletes the explicit old one`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image")
            val publisher = SafeMediaPublisher(store)

            val published = publisher.publish(
                source,
                "capture.jpg",
                "capture-1",
                supersededCandidates = listOf(FakePublishedImageStore.OLD_URI),
            )

            assertEquals(FakePublishedImageStore.NEW_URI, published.contentUri)
            assertTrue(published.supersededUris.isEmpty())
            // The explicit old row is gone and the new row is finalized with
            // the new bytes — never a half-written row left visible.
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
                publisher.publish(
                    source,
                    "capture.jpg",
                    "capture-1",
                    supersededCandidates = listOf(FakePublishedImageStore.OLD_URI),
                )
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
            val published = publisher.publish(
                source,
                "capture.jpg",
                "capture-1",
                supersededCandidates = listOf(FakePublishedImageStore.OLD_URI),
            )

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

    // Regression (backup restore): which rows may be supersed is decided
    // EXCLUSIVELY by the caller's explicit candidate list. A same-named row
    // owned by ANOTHER capture — e.g. the original project's row while a
    // restored project re-saves its photo with the same preserved photo
    // number — must NEVER be deleted.
    @Test
    fun `same-named rows outside the explicit candidates are never deleted`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            // Both pre-existing rows share the display name "capture.jpg",
            // but only OLD_URI belongs to THIS capture.
            val store = FakePublishedImageStore(
                existingBytes = "old-image",
                duplicateBytes = "other-captures-image",
            )
            val publisher = SafeMediaPublisher(store)

            val published = publisher.publish(
                source,
                "capture.jpg",
                "capture-1",
                supersededCandidates = listOf(FakePublishedImageStore.OLD_URI),
            )

            assertEquals(FakePublishedImageStore.NEW_URI, published.contentUri)
            assertTrue(published.supersededUris.isEmpty())
            // The explicit candidate is gone...
            assertNull(store.rows[FakePublishedImageStore.OLD_URI])
            // ...while the same-named row of the OTHER capture survives
            // untouched — deleting it would destroy the original project's
            // published photo.
            assertEquals(
                "other-captures-image",
                store.rows[FakePublishedImageStore.DUPLICATE_URI]?.bytes,
            )
            assertEquals(false, store.rows[FakePublishedImageStore.DUPLICATE_URI]?.pending)
            assertEquals(false, store.rows[FakePublishedImageStore.NEW_URI]?.pending)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `failing candidate deletes are all reported as superseded`() {
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
            val published = publisher.publish(
                source,
                "capture.jpg",
                "capture-1",
                supersededCandidates = listOf(
                    FakePublishedImageStore.OLD_URI,
                    FakePublishedImageStore.DUPLICATE_URI,
                ),
            )

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
                publisher.publish(
                    source,
                    "capture.jpg",
                    "capture-1",
                    supersededCandidates = listOf(FakePublishedImageStore.OLD_URI),
                )
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
            val journal = PublishJournalSink { captureId, uri, superseded ->
                calls += Triple(captureId, uri, superseded)
                // 时序证明：journal 被调用时旧行还在 —— 即转正之后、删除之前。
                assertTrue(store.rows.containsKey(FakePublishedImageStore.OLD_URI))
                true
            }
            val publisher = SafeMediaPublisher(store, journal)

            val published = publisher.publish(
                source,
                "capture.jpg",
                "capture-1",
                supersededCandidates = listOf(FakePublishedImageStore.OLD_URI),
            )

            // journal 恰好记录一次，键为稳定的 captureId（绝非照片编号：
            // 备份恢复后两个项目可能同时存在相同编号）。
            assertEquals(
                listOf(
                    Triple(
                        "capture-1",
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

    // Regression: a journal that failed to persist durably MUST fail the
    // publish. Returning "success" would let the process die between this
    // return and the caller's database commit, leaving the finalized new
    // gallery photo tracked by nobody. The new row is rolled back
    // (best-effort) and the untouched superseded rows stay published.
    @Test
    fun `journal write failure rolls back the finalized row and fails the publish`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image")
            val journal = PublishJournalSink { _, _, _ -> false }
            val publisher = SafeMediaPublisher(store, journal)

            assertThrows(IllegalStateException::class.java) {
                publisher.publish(
                    source,
                    "capture.jpg",
                    "capture-1",
                    supersededCandidates = listOf(FakePublishedImageStore.OLD_URI),
                )
            }

            // The finalized new row was rolled back...
            assertNull(store.rows[FakePublishedImageStore.NEW_URI])
            // ...and the superseded row was never deleted (it is still the
            // photo the caller's database references).
            assertEquals("old-image", store.rows[FakePublishedImageStore.OLD_URI]?.bytes)
            assertEquals(false, store.rows[FakePublishedImageStore.OLD_URI]?.pending)
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
            val journal = PublishJournalSink { captureId, uri, superseded ->
                calls += Triple(captureId, uri, superseded)
                true
            }
            val publisher = SafeMediaPublisher(store, journal)

            val published = publisher.publish(
                source,
                "capture.jpg",
                "capture-1",
                supersededCandidates = emptyList(),
            )

            // 首次发布也要 journal：否则提交前崩溃会留下无人追踪的孤儿。
            assertEquals(
                listOf(Triple("capture-1", FakePublishedImageStore.NEW_URI, emptyList<String>())),
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
                publisher.publish(
                    source,
                    "capture.jpg",
                    "capture-1",
                    supersededCandidates = emptyList(),
                )
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
