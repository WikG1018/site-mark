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
 * Entries are keyed by display name: a same-named re-publish overwrites the
 * previous entry, which is safe because the overwritten new URI becomes a
 * superseded candidate of the next publish (found by `findAll`) and is either
 * deleted or reported through `supersededUris`, so it is never lost.
 *
 * The entry intentionally records ALL superseded candidates (not just the
 * failed deletes): recovery re-queues them through the idempotent delete-only
 * cleanup path, where an already-deleted row counts as success.
 */
internal class PublishJournalStore(private val preferences: SharedPreferences) {

    /** Returns false when the synchronous commit failed (disk full/corrupt). */
    fun record(
        displayName: String,
        contentUri: String,
        supersededUris: List<String>,
    ): Boolean {
        val prefix = keyPrefix(displayName)
        val editor = preferences.edit()
            .putString("$prefix$KEY_NEW_URI", contentUri)
            .putInt("$prefix$KEY_STALE_COUNT", supersededUris.size)
            .putBoolean("$prefix$KEY_EXISTS", true)
        supersededUris.forEachIndexed { index, uri ->
            editor.putString("$prefix$KEY_STALE_PREFIX$index", uri)
        }
        return editor.commit()
    }

    fun recover(): List<RecoveredPublishJournal> {
        val entries = preferences.all
        val result = mutableListOf<RecoveredPublishJournal>()
        for (key in entries.keys) {
            if (!key.endsWith(KEY_EXISTS)) continue
            val prefix = key.removeSuffix(KEY_EXISTS)
            if (!entries.containsKey("$prefix$KEY_NEW_URI")) continue
            val contentUri = entries["$prefix$KEY_NEW_URI"] as? String ?: continue
            val staleCount = (entries["$prefix$KEY_STALE_COUNT"] as? Int) ?: 0
            val staleUris = mutableListOf<String>()
            for (index in 0 until staleCount) {
                (entries["$prefix$KEY_STALE_PREFIX$index"] as? String)?.let(staleUris::add)
            }
            // Journal keys are prefixed with the display name, which is also
            // the reconciliation key for the caller's database row.
            val displayName = prefix.removePrefix(JOURNAL_KEY_PREFIX).removeSuffix(KEY_SEPARATOR)
            if (displayName.isEmpty()) continue
            result.add(
                RecoveredPublishJournal(
                    journalId = displayName,
                    displayName = displayName,
                    contentUri = contentUri,
                    supersededUris = staleUris,
                ),
            )
        }
        return result
    }

    fun clear(journalId: String) {
        val prefix = keyPrefix(journalId)
        val editor = preferences.edit()
        for (key in preferences.all.keys) {
            if (key.startsWith(prefix)) editor.remove(key)
        }
        editor.commit()
    }

    private fun keyPrefix(displayName: String): String =
        "$JOURNAL_KEY_PREFIX$displayName$KEY_SEPARATOR"

    private companion object {
        private const val JOURNAL_KEY_PREFIX = "journal."
        private const val KEY_SEPARATOR = "\u0000"
        private const val KEY_EXISTS = ".exists"
        private const val KEY_NEW_URI = ".newUri"
        private const val KEY_STALE_COUNT = ".staleCount"
        private const val KEY_STALE_PREFIX = ".stale."
    }
}
