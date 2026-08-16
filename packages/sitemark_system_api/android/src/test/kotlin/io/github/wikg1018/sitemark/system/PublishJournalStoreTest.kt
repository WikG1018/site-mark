package io.github.wikg1018.sitemark.system

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Verifies [PublishJournalStore] against an in-memory [SharedPreferences]
 * double: record/recover round-trip, durable-commit failure reporting,
 * skipping of incomplete entries, and targeted clear.
 */
class PublishJournalStoreTest {

    @Test
    fun `record and recover round-trips an entry`() {
        val preferences = FakeSharedPreferences()
        val store = PublishJournalStore(preferences)

        val recorded = store.record(
            "SM-1",
            "content://media/external/images/2",
            listOf("u1", "u2"),
        )

        assertTrue(recorded)
        val entry = store.recover().single()
        assertEquals("SM-1", entry.captureId)
        assertEquals("content://media/external/images/2", entry.contentUri)
        assertEquals(listOf("u1", "u2"), entry.supersededUris)
    }

    @Test
    fun `record reports a failed durable commit`() {
        // commit() 同步落盘失败（磁盘满/损坏）必须让调用方知道，
        // 否则发布方会误以为 journal 已持久化而删除旧行。
        val preferences = FakeSharedPreferences().apply { commitResult = false }
        val store = PublishJournalStore(preferences)

        assertFalse(store.record("SM-1", "content://media/external/images/2", listOf("u1")))
    }

    @Test
    fun `recover skips incomplete entries`() {
        val preferences = FakeSharedPreferences()
        // 残缺条目 A：有 .exists 与 .staleCount 但缺 .newUri —— 恢复时被跳过。
        preferences.values["journal.Broken\u0000.exists"] = true
        preferences.values["journal.Broken\u0000.staleCount"] = 1
        preferences.values["journal.Broken\u0000.stale.0"] = "content://media/old/1"
        // 残缺条目 B：有 .newUri 但缺 .exists —— 扫描只从 .exists 键出发，不可见。
        preferences.values["journal.Ghost\u0000.newUri"] = "content://media/ghost/9"
        preferences.values["journal.Ghost\u0000.staleCount"] = 0
        val store = PublishJournalStore(preferences)

        assertTrue(store.recover().isEmpty())
    }

    @Test
    fun `clear removes only the targeted entry`() {
        val preferences = FakeSharedPreferences()
        val store = PublishJournalStore(preferences)
        store.record("SM-1", "content://media/external/images/1", listOf("content://media/old/1"))
        store.record("SM-2", "content://media/external/images/2", emptyList())

        assertTrue(store.clear("SM-1", "content://media/external/images/1"))

        val remaining = store.recover()
        assertEquals(listOf("SM-2"), remaining.map { it.captureId })
        val entry = remaining.single()
        assertEquals("SM-2", entry.captureId)
        assertEquals("content://media/external/images/2", entry.contentUri)
        assertTrue(entry.supersededUris.isEmpty())
    }

    @Test
    fun `clearing a missing entry is an idempotent success`() {
        val preferences = FakeSharedPreferences()
        val store = PublishJournalStore(preferences)

        assertTrue(store.clear("SM-1", "content://media/external/images/1"))
        assertTrue(store.recover().isEmpty())
    }

    // Regression (interleaved same-capture publishes): an OLDER operation
    // must never clear an entry that a NEWER publish already overwrote —
    // losing it would make the newer finalized publish unrecoverable after
    // a crash. P1 journals U2; P2 journals U3 over it; P1's conditional
    // clear(U2) must leave the journal (still U3) untouched.
    @Test
    fun `clear with a stale expected URI leaves a newer entry untouched`() {
        val preferences = FakeSharedPreferences()
        val store = PublishJournalStore(preferences)
        store.record("SM-1", "content://media/external/images/2", listOf("content://media/old/1"))
        store.record("SM-1", "content://media/external/images/3", listOf("content://media/old/2"))

        assertFalse(store.clear("SM-1", "content://media/external/images/2"))

        val entry = store.recover().single()
        assertEquals("SM-1", entry.captureId)
        assertEquals("content://media/external/images/3", entry.contentUri)
        assertEquals(listOf("content://media/old/2"), entry.supersededUris)
    }

    @Test
    fun `peek returns the complete entry including superseded URIs`() {
        val preferences = FakeSharedPreferences()
        val store = PublishJournalStore(preferences)

        assertTrue(store.peek("SM-1") == null)
        store.record("SM-1", "content://media/external/images/2", listOf("content://media/old/1"))

        val entry = store.peek("SM-1")
        assertEquals("content://media/external/images/2", entry?.contentUri)
        assertEquals(listOf("content://media/old/1"), entry?.supersededUris)
    }

    // Regression (consecutive crashes): a second publish of the same
    // capture must fold the ENTIRE leftover journal entry — its content URI
    // AND its superseded URIs — into the new candidates. Reading only the
    // content URI would permanently lose tracking of the earliest stale
    // URIs. The overwrite must also drop stale slots beyond the new count
    // so recovery can never mix URIs of two different publishes.
    @Test
    fun `re-publish over a leftover entry replaces it without residue`() {
        val preferences = FakeSharedPreferences()
        val store = PublishJournalStore(preferences)
        // First crashed publish: U2 with two stale candidates.
        store.record("SM-1", "content://media/external/images/2", listOf("u1", "u2"))
        // Second publish overwrites the entry with fewer stale URIs.
        store.record("SM-1", "content://media/external/images/3", listOf("u1"))

        val entry = store.recover().single()
        assertEquals("content://media/external/images/3", entry.contentUri)
        assertEquals(listOf("u1"), entry.supersededUris)
        // The stale slot of the overwritten entry is gone too.
        val peeked = store.peek("SM-1")
        assertEquals(listOf("u1"), peeked?.supersededUris)
    }
}

/** In-memory [SharedPreferences] double; editor writes go straight into [values]. */
private class FakeSharedPreferences : SharedPreferences {
    val values = mutableMapOf<String, Any>()

    /** Returned by every editor [SharedPreferences.Editor.commit]; flip to simulate disk failure. */
    var commitResult = true

    override fun getAll(): Map<String, *> = values

    override fun getString(key: String?, defValue: String?): String? =
        values[key] as? String ?: defValue

    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
        @Suppress("UNCHECKED_CAST")
        values[key] as? MutableSet<String> ?: defValues

    override fun getInt(key: String?, defValue: Int): Int = values[key] as? Int ?: defValue

    override fun getLong(key: String?, defValue: Long): Long = values[key] as? Long ?: defValue

    override fun getFloat(key: String?, defValue: Float): Float = values[key] as? Float ?: defValue

    override fun getBoolean(key: String?, defValue: Boolean): Boolean =
        values[key] as? Boolean ?: defValue

    override fun contains(key: String?): Boolean = values.containsKey(key)

    override fun edit(): SharedPreferences.Editor = FakeEditor(this)

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    private class FakeEditor(private val preferences: FakeSharedPreferences) :
        SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        private val removed = Any()

        override fun putString(key: String, value: String?): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putStringSet(
            key: String,
            values: MutableSet<String>?,
        ): SharedPreferences.Editor {
            pending[key] = values
            return this
        }

        override fun putInt(key: String, value: Int): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putLong(key: String, value: Long): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putFloat(key: String, value: Float): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun remove(key: String): SharedPreferences.Editor {
            pending[key] = removed
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            val cleared = mutableMapOf<String, Any?>()
            preferences.values.keys.forEach { cleared[it] = removed }
            pending.clear()
            pending.putAll(cleared)
            return this
        }

        override fun commit(): Boolean {
            pending.forEach { (key, value) ->
                if (value === removed || value == null) {
                    preferences.values.remove(key)
                } else {
                    preferences.values[key] = value
                }
            }
            pending.clear()
            return preferences.commitResult
        }

        override fun apply() {
            commit()
        }
    }
}
