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

    /** A complete journal entry as stored for one capture. */
    data class JournalEntry(
        val contentUri: String,
        val supersededUris: List<String>,
    )

    /** Returns false when the synchronous commit failed (disk full/corrupt). */
    fun record(
        captureId: String,
        contentUri: String,
        supersededUris: List<String>,
    ): Boolean {
        synchronized(JOURNAL_LOCK) {
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
    }

    /**
     * Returns the COMPLETE journaled entry for [captureId], or null when no
     * complete entry exists. The publisher consults this BEFORE publishing
     * so the previous crashed publish's URI AND its superseded URIs all
     * become cleanup candidates of the new publish: reading only the
     * content URI would permanently lose tracking of the earlier stale
     * URIs after a second consecutive crash.
     */
    fun peek(captureId: String): JournalEntry? {
        synchronized(JOURNAL_LOCK) {
            val prefix = keyPrefix(captureId)
            val entries = preferences.all ?: return null
            if (entries["$prefix$KEY_EXISTS"] !is Boolean) return null
            val contentUri = entries["$prefix$KEY_NEW_URI"] as? String ?: return null
            val staleCount = (entries["$prefix$KEY_STALE_COUNT"] as? Int) ?: 0
            val staleUris = mutableListOf<String>()
            for (index in 0 until staleCount) {
                (entries["$prefix$KEY_STALE_PREFIX$index"] as? String)?.let(staleUris::add)
            }
            return JournalEntry(contentUri = contentUri, supersededUris = staleUris)
        }
    }

    fun recover(): List<RecoveredPublishJournal> {
        synchronized(JOURNAL_LOCK) {
            val entries = preferences.all ?: return emptyList()
            val result = mutableListOf<RecoveredPublishJournal>()
            for (key in entries.keys) {
                if (!key.endsWith(".$KEY_EXISTS")) continue
                // `key` is `journal.<encoded-id>.exists`, so the stripped
                // prefix has NO trailing dot — re-attach it before looking
                // up the sibling field keys (`journal.<encoded-id>.<field>`).
                val prefix = "${key.removeSuffix(".$KEY_EXISTS")}."
                if (!entries.containsKey("$prefix$KEY_NEW_URI")) continue
                val contentUri = entries["$prefix$KEY_NEW_URI"] as? String ?: continue
                val captureId = decodeCaptureId(prefix) ?: continue
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
    }

    /**
     * Clears the capture's entry ONLY while it still records
     * [expectedContentUri]. An OLDER operation whose newer same-capture
     * publish already overwrote the journal must not clear the newer
     * entry: losing it would make the newer finalized publish
     * unrecoverable after a crash. Clearing a missing entry is an
     * idempotent success.
     *
     * @return true when the journal is (or already was) clear for this
     *         capture; false when a NEWER entry was left untouched or the
     *         durable commit failed.
     */
    fun clear(captureId: String, expectedContentUri: String): Boolean {
        synchronized(JOURNAL_LOCK) {
            val prefix = keyPrefix(captureId)
            val entries = preferences.all
            if (entries == null || entries["$prefix$KEY_EXISTS"] !is Boolean) return true
            val current = entries["$prefix$KEY_NEW_URI"] as? String
            if (current != null && current != expectedContentUri) return false
            val editor = preferences.edit()
            for (key in entries.keys) {
                if (key.startsWith(prefix)) editor.remove(key)
            }
            return editor.commit()
        }
    }

    // The capture ID is embedded in preference keys as unpadded base64url
    // ([A-Za-z0-9_-], no '.'), so ANY capture ID — including ones holding
    // '.', NUL, or surrogate pairs — maps to keys drawn from a fixed,
    // XML-1.0-safe alphabet that can never collide with the field-suffix
    // separator. The full key layout is therefore always
    // `journal.<base64url-id>.<field>` with a SINGLE '.' separator. A
    // literal '\u0000' separator (used by an earlier draft) is illegal in
    // XML 1.0 and could make the underlying SharedPreferences XML
    // persistence throw or silently corrupt on real devices.
    private fun keyPrefix(captureId: String): String =
        "$JOURNAL_KEY_PREFIX${encodeCaptureId(captureId)}."

    private fun encodeCaptureId(captureId: String): String =
        CAPTURE_ID_ENCODER.encodeToString(captureId.toByteArray(Charsets.UTF_8))

    private fun decodeCaptureId(keyPrefix: String): String? {
        if (!keyPrefix.startsWith(JOURNAL_KEY_PREFIX)) return null
        val encoded = keyPrefix.removePrefix(JOURNAL_KEY_PREFIX).removeSuffix(".")
        if (encoded.isEmpty()) return null
        return try {
            String(CAPTURE_ID_DECODER.decode(encoded), Charsets.UTF_8)
        } catch (_: IllegalArgumentException) {
            // Not a base64url capture ID (e.g. residue of the retired
            // '\u0000' key format): ignore the entry entirely.
            null
        }
    }

    private companion object {
        // SharedPreferences offers atomicity per Editor.commit(), not across
        // the compare-then-remove sequence in clear(). Publishing runs on an
        // IO executor while Pigeon clear/recovery calls can arrive on another
        // thread, and AndroidSystemApi may construct more than one store
        // instance over the same preference file. A process-wide lock keeps
        // every journal snapshot and mutation in one critical section.
        private val JOURNAL_LOCK = Any()
        private val CAPTURE_ID_ENCODER = java.util.Base64.getUrlEncoder().withoutPadding()
        private val CAPTURE_ID_DECODER = java.util.Base64.getUrlDecoder()
        private const val JOURNAL_KEY_PREFIX = "journal."
        private const val KEY_EXISTS = "exists"
        private const val KEY_NEW_URI = "newUri"
        private const val KEY_STALE_COUNT = "staleCount"
        private const val KEY_STALE_PREFIX = "stale."
    }
}
