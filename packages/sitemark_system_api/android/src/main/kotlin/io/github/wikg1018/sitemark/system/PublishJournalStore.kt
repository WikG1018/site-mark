package io.github.wikg1018.sitemark.system

import android.content.SharedPreferences

/**
 * Durable journal of finalized MediaStore publishes whose caller has NOT yet
 * committed the new URI to its database.
 *
 * The publisher records an entry SYNCHRONOUSLY — via [SharedPreferences.Editor.commit],
 * not `apply()` — immediately after the replacement row is finalized and
 * BEFORE any superseded row is deleted. That closes the crash window where
 * the native side finalized the new row, deleted the old rows, and the
 * process died before Dart committed `publishedUri`: without the journal the
 * database would keep pointing at an already-deleted URI and the new photo
 * would be an untracked orphan.
 *
 * Entries are keyed by the caller's stable CAPTURE ID — never by the display
 * name / photo number. A backup restore preserves photo numbers, so the
 * original and the restored project can hold records with the SAME photo
 * number at the same time; keying by name would let one capture's publish
 * or recovery mutate the other capture's row. Capture IDs are unique per
 * record, so a same-capture re-publish overwrites the previous entry safely:
 * before overwriting, the publisher folds the previous entry's URI into the
 * new publish's superseded candidates, so the overwritten URI is deleted or
 * reported through `supersededUris` and never lost.
 *
 * The entry intentionally records ALL superseded candidates (not just the
 * failed deletes): recovery re-queues them through the idempotent delete-only
 * cleanup path, where an already-deleted row counts as success.
 */
internal class PublishJournalStore(private val preferences: SharedPreferences) {

    /** Returns false when the synchronous commit failed (disk full/corrupt). */
    fun record(
        captureId: String,
        contentUri: String,
        supersededUris: List<String>,
    ): Boolean {
        val prefix = keyPrefix(captureId)
        val editor = preferences.edit()
            .putString("$prefix$KEY_NEW_URI", contentUri)
            .putInt("$prefix$KEY_STALE_COUNT", supersededUris.size)
            .putBoolean("$prefix$KEY_EXISTS", true)
        supersededUris.forEachIndexed { index, uri ->
            editor.putString("$prefix$KEY_STALE_PREFIX$index", uri)
        }
        // A same-capture re-publish replaces the previous entry outright:
        // stale slots beyond the new count are removed so recovery can never
        // mix URIs of two different publishes.
        val previousCount = (preferences.all?.get("$prefix$KEY_STALE_COUNT") as? Int) ?: 0
        for (index in supersededUris.size until previousCount) {
            editor.remove("$prefix$KEY_STALE_PREFIX$index")
        }
        return editor.commit()
    }

    /**
     * Returns the journaled content URI for [captureId], or null when no
     * complete entry exists. The publisher consults this BEFORE publishing
     * so a leftover row from a previously crashed publish of the SAME
     * capture becomes a superseded candidate of the new publish instead of
     * an untracked duplicate.
     */
    fun peekContentUri(captureId: String): String? {
        val prefix = keyPrefix(captureId)
        val entries = preferences.all ?: return null
        if (entries["$prefix$KEY_EXISTS"] !is Boolean) return null
        return entries["$prefix$KEY_NEW_URI"] as? String
    }

    fun recover(): List<RecoveredPublishJournal> {
        val entries = preferences.all ?: return emptyList()
        val result = mutableListOf<RecoveredPublishJournal>()
        for (key in entries.keys) {
            if (!key.endsWith(KEY_EXISTS)) continue
            val prefix = key.removeSuffix(KEY_EXISTS)
            if (!entries.containsKey("$prefix$KEY_NEW_URI")) continue
            val contentUri = entries["$prefix$KEY_NEW_URI"] as? String ?: continue
            val captureId = prefix.removePrefix(JOURNAL_KEY_PREFIX).removeSuffix(KEY_SEPARATOR)
            if (captureId.isEmpty()) continue
            val staleCount = (entries["$prefix$KEY_STALE_COUNT"] as? Int) ?: 0
            val staleUris = mutableListOf<String>()
            for (index in 0 until staleCount) {
                (entries["$prefix$KEY_STALE_PREFIX$index"] as? String)?.let(staleUris::add)
            }
            result.add(
                RecoveredPublishJournal(
                    captureId = captureId,
                    contentUri = contentUri,
                    supersededUris = staleUris,
                ),
            )
        }
        return result
    }

    fun clear(captureId: String) {
        val prefix = keyPrefix(captureId)
        val editor = preferences.edit()
        for (key in preferences.all.orEmpty().keys) {
            if (key.startsWith(prefix)) editor.remove(key)
        }
        editor.commit()
    }

    private fun keyPrefix(captureId: String): String =
        "$JOURNAL_KEY_PREFIX$captureId$KEY_SEPARATOR"

    private companion object {
        private const val JOURNAL_KEY_PREFIX = "journal."
        private const val KEY_SEPARATOR = "\u0000"
        private const val KEY_EXISTS = ".exists"
        private const val KEY_NEW_URI = ".newUri"
        private const val KEY_STALE_COUNT = ".staleCount"
        private const val KEY_STALE_PREFIX = ".stale."
    }
}
