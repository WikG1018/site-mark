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
    fun `replacement publishes a new row and reports the explicit old one`() {
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
            // The publisher NEVER deletes the old row itself: a legacy
            // upgrade can leave two records sharing one URI, so the caller
            // must queue a reference-checked, delete-only cleanup instead.
            assertEquals(listOf(FakePublishedImageStore.OLD_URI), published.supersededUris)
            // The old row survives until the caller's cleanup runs, and the
            // new row is finalized with the new bytes — never a half-written
            // row left visible.
            assertEquals("old-image", store.rows[FakePublishedImageStore.OLD_URI]?.bytes)
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
    fun `every candidate is reported verbatim and no row is ever deleted`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(
                existingBytes = "old-image",
                duplicateBytes = "older-image",
            )
            val publisher = SafeMediaPublisher(store)

            // The publish SUCCEEDED (new row finalized); every stale
            // candidate — including ones whose delete could never succeed —
            // is reported independently for the caller's cleanup queue.
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
            // Neither stale row was touched by the publisher.
            assertEquals("old-image", store.rows[FakePublishedImageStore.OLD_URI]?.bytes)
            assertEquals("older-image", store.rows[FakePublishedImageStore.DUPLICATE_URI]?.bytes)
        } finally {
            directory.deleteRecursively()
        }
    }

    // Regression (backup restore): which rows may be superseded is decided
    // EXCLUSIVELY by the caller's explicit candidate list. A same-named row
    // owned by ANOTHER capture — e.g. the original project's row while a
    // restored project re-saves its photo with the same preserved photo
    // number — must NEVER become a candidate.
    @Test
    fun `same-named rows outside the explicit candidates are never reported`() {
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
            // Only the explicit candidate is reported for cleanup...
            assertEquals(listOf(FakePublishedImageStore.OLD_URI), published.supersededUris)
            // ...while the same-named row of the OTHER capture is neither
            // deleted nor queued — deleting it would destroy the original
            // project's published photo.
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
    fun `journal records the finalized publish before any superseded cleanup`() {
        val directory = Files.createTempDirectory("safe-media-publisher").toFile()
        try {
            val source = File(directory, "replacement.jpg").apply { writeText("new-image") }
            val store = FakePublishedImageStore(existingBytes = "old-image")
            val calls = mutableListOf<Triple<String, String, List<String>>>()
            val journal = PublishJournalSink { captureId, uri, superseded ->
                calls += Triple(captureId, uri, superseded)
                // 时序证明：journal 被调用时新行已转正、旧行还未被任何
                // 清理触碰 —— 转正之后、清理之前。
                assertTrue(store.rows.containsKey(FakePublishedImageStore.OLD_URI))
                assertEquals(false, store.rows[FakePublishedImageStore.NEW_URI]?.pending)
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
            assertEquals(FakePublishedImageStore.NEW_URI, published.contentUri)
            assertEquals(listOf(FakePublishedImageStore.OLD_URI), published.supersededUris)
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
        rows.remove(contentUri)
    }

    companion object {
        const val OLD_URI = "content://media/site-mark/1"
        const val DUPLICATE_URI = "content://media/site-mark/0"
        const val NEW_URI = "content://media/site-mark/2"
    }
}
