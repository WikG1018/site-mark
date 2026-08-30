import Foundation

/// Typed value in the journal's flat key→value map, mirroring the
/// SharedPreferences String/Int/Bool mix the Android journal persists.
public enum JournalValue: Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
}

extension JournalValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported journal value type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}

/// A single key mutation applied atomically by `JournalPersistence.commit`.
/// A dedicated enum avoids the `[String: JournalValue?]` subscript trap
/// where assigning nil would drop the entry instead of storing a removal.
public enum JournalMutation {
    case put(JournalValue)
    case remove
}

/// Durable flat key→value persistence behind the journal. Android injects
/// SharedPreferences; the production iOS backend is an atomically written
/// JSON file (`JournalFilePersistence`) and tests inject an in-memory
/// double.
public protocol JournalPersistence: AnyObject {
    /// Full map snapshot, or nil when the store is unreadable (mirrors the
    /// null `SharedPreferences.getAll` path).
    func snapshot() -> [String: JournalValue]?

    /// Applies put/remove mutations atomically and synchronously. Returns
    /// false on durable failure (mirrors `SharedPreferences.commit`).
    @discardableResult
    func commit(_ mutations: [String: JournalMutation]) -> Bool
}

/// A complete journal entry as stored for one capture.
public struct JournalEntry: Equatable {
    public let contentUri: String
    public let supersededUris: [String]

    public init(contentUri: String, supersededUris: [String]) {
        self.contentUri = contentUri
        self.supersededUris = supersededUris
    }
}

/// Recovered journal entry on the core layer. The Pigeon glue defines its
/// own `RecoveredPublishJournal`; the Phase 2b plugin maps this struct onto
/// it so the pure core never imports Flutter.
public struct RecoveredJournalEntry: Equatable {
    public let captureId: String
    public let contentUri: String
    public let supersededUris: [String]

    public init(captureId: String, contentUri: String, supersededUris: [String]) {
        self.captureId = captureId
        self.contentUri = contentUri
        self.supersededUris = supersededUris
    }
}

/// Durable journal of finalized photo-library publishes whose caller has
/// NOT yet committed the new URI to its database.
///
/// The publisher records an entry SYNCHRONOUSLY immediately after the new
/// asset is finalized and BEFORE any superseded row is deleted. That closes
/// the crash window where the native side finalized the new row, the
/// process died, and the caller never learned the new URI: without the
/// journal the database would keep pointing at an outdated asset and the
/// new photo would be an untracked orphan.
///
/// Entries are keyed by the caller's stable CAPTURE ID — never by the
/// display name / photo number. A backup restore preserves photo numbers,
/// so the original and the restored project can hold records with the SAME
/// photo number at the same time; keying by name would let one capture's
/// publish or recovery mutate the other capture's row. Capture IDs are
/// unique per record, so a same-capture re-publish overwrites the previous
/// entry safely: before overwriting, the publisher folds the previous
/// entry's URI into the new publish's superseded candidates so the
/// overwritten URI is deleted or reported through `supersededUris` and
/// never lost.
///
/// The entry intentionally records ALL superseded candidates (not just the
/// failed deletes): recovery re-queues them through the idempotent
/// delete-only cleanup path, where an already-deleted row counts as success.
public final class PublishJournalStore {
    // Persistence offers atomicity per commit, not across the
    // compare-then-remove sequence in clear(). Publishing runs on a
    // worker while Pigeon clear/recovery calls can arrive concurrently,
    // and more than one store instance may exist over the same file. A
    // process-wide lock keeps every journal snapshot and mutation in one
    // critical section.
    private static let journalLock = NSLock()

    private let persistence: JournalPersistence

    public init(_ persistence: JournalPersistence) {
        self.persistence = persistence
    }

    /// Returns false when the synchronous commit failed (disk full/corrupt).
    @discardableResult
    public func record(
        captureId: String,
        contentUri: String,
        supersededUris: [String]
    ) -> Bool {
        Self.journalLock.lock()
        defer { Self.journalLock.unlock() }
        let prefix = Self.keyPrefix(captureId: captureId)
        var mutations: [String: JournalMutation] = [
            prefix + Self.keyNewUri: .put(.string(contentUri)),
            prefix + Self.keyStaleCount: .put(.int(supersededUris.count)),
            prefix + Self.keyExists: .put(.bool(true)),
        ]
        for (index, uri) in supersededUris.enumerated() {
            mutations[prefix + Self.keyStalePrefix + String(index)] = .put(.string(uri))
        }
        // A same-capture re-publish replaces the previous entry outright:
        // stale slots beyond the new count are removed so recovery can never
        // mix URIs of two different publishes.
        let previousCount: Int
        if let snapshot = persistence.snapshot(),
            case .int(let count)? = snapshot[prefix + Self.keyStaleCount]
        {
            previousCount = count
        } else {
            previousCount = 0
        }
        if previousCount > supersededUris.count {
            for index in supersededUris.count..<previousCount {
                mutations[prefix + Self.keyStalePrefix + String(index)] = .remove
            }
        }
        return persistence.commit(mutations)
    }

    /// Returns the COMPLETE journaled entry for the capture, or nil when no
    /// complete entry exists. The publisher consults this BEFORE publishing
    /// so the previous crashed publish's URI AND its superseded URIs all
    /// become cleanup candidates of the new publish: reading only the
    /// content URI would permanently lose tracking of the earlier stale
    /// URIs after a second consecutive crash.
    public func peek(captureId: String) -> JournalEntry? {
        Self.journalLock.lock()
        defer { Self.journalLock.unlock() }
        return peekLocked(captureId: captureId)
    }

    /// Lists every complete journal entry, keyed by capture ID.
    public func recover() -> [RecoveredJournalEntry] {
        Self.journalLock.lock()
        defer { Self.journalLock.unlock() }
        guard let entries = persistence.snapshot() else { return [] }
        var result: [RecoveredJournalEntry] = []
        // Sorted for deterministic output; Android iterates a HashMap whose
        // order the caller never relies on.
        for key in entries.keys.sorted() where key.hasSuffix("." + Self.keyExists) {
            // `key` is `journal.<encoded-id>.exists`, so the stripped prefix
            // has NO trailing dot — re-attach it before looking up the
            // sibling field keys (`journal.<encoded-id>.<field>`).
            let stripped = String(key.dropLast(Self.keyExists.count + 1))
            let prefix = stripped + "."
            guard case .string(let contentUri)? = entries[prefix + Self.keyNewUri] else {
                continue
            }
            guard let captureId = Self.decodeCaptureId(keyPrefix: prefix) else { continue }
            let staleCount: Int
            if case .int(let count)? = entries[prefix + Self.keyStaleCount] {
                staleCount = count
            } else {
                staleCount = 0
            }
            var staleUris: [String] = []
            for index in 0..<staleCount {
                if case .string(let uri)? = entries[prefix + Self.keyStalePrefix + String(index)]
                {
                    staleUris.append(uri)
                }
            }
            result.append(
                RecoveredJournalEntry(
                    captureId: captureId,
                    contentUri: contentUri,
                    supersededUris: staleUris))
        }
        return result
    }

    /// Clears the capture's entry ONLY while it still records
    /// `expectedContentUri`. An OLDER operation whose newer same-capture
    /// publish already overwrote the journal must not clear the newer
    /// entry: losing it would make the newer finalized publish
    /// unrecoverable after a crash. Clearing a missing entry is an
    /// idempotent success.
    ///
    /// Returns true when the journal is (or already was) clear for this
    /// capture; false when a NEWER entry was left untouched or the durable
    /// commit failed.
    @discardableResult
    public func clear(captureId: String, expectedContentUri: String) -> Bool {
        Self.journalLock.lock()
        defer { Self.journalLock.unlock() }
        guard let entries = persistence.snapshot() else { return true }
        let prefix = Self.keyPrefix(captureId: captureId)
        guard case .some(.bool) = entries[prefix + Self.keyExists] else { return true }
        if case .string(let current)? = entries[prefix + Self.keyNewUri],
            current != expectedContentUri
        {
            return false
        }
        var mutations: [String: JournalMutation] = [:]
        for key in entries.keys where key.hasPrefix(prefix) {
            mutations[key] = .remove
        }
        return persistence.commit(mutations)
    }

    private func peekLocked(captureId: String) -> JournalEntry? {
        guard let entries = persistence.snapshot() else { return nil }
        let prefix = Self.keyPrefix(captureId: captureId)
        guard case .some(.bool) = entries[prefix + Self.keyExists] else { return nil }
        guard case .string(let contentUri)? = entries[prefix + Self.keyNewUri] else {
            return nil
        }
        let staleCount: Int
        if case .int(let count)? = entries[prefix + Self.keyStaleCount] {
            staleCount = count
        } else {
            staleCount = 0
        }
        var staleUris: [String] = []
        for index in 0..<staleCount {
            if case .string(let uri)? = entries[prefix + Self.keyStalePrefix + String(index)] {
                staleUris.append(uri)
            }
        }
        return JournalEntry(contentUri: contentUri, supersededUris: staleUris)
    }

    // The capture ID is embedded in keys as unpadded base64url
    // ([A-Za-z0-9_-], no '.'), so ANY capture ID — including ones holding
    // '.', NUL, or surrogate pairs — maps to keys drawn from a fixed,
    // persistence-safe alphabet that can never collide with the field
    // suffix separator. The key layout is always
    // `journal.<base64url-id>.<field>` with a SINGLE '.' separator.
    static func keyPrefix(captureId: String) -> String {
        Self.journalKeyPrefix + Self.encodeCaptureId(captureId) + "."
    }

    static func encodeCaptureId(_ captureId: String) -> String {
        Data(captureId.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeCaptureId(keyPrefix: String) -> String? {
        guard keyPrefix.hasPrefix(Self.journalKeyPrefix) else { return nil }
        let encoded = String(keyPrefix.dropFirst(Self.journalKeyPrefix.count))
            .droppingSuffix(".")
        if encoded.isEmpty { return nil }
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else {
            // Not a base64url capture ID (e.g. residue of the retired
            // NUL-separated key format): ignore the entry entirely.
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static let journalKeyPrefix = "journal."
    private static let keyExists = "exists"
    private static let keyNewUri = "newUri"
    private static let keyStaleCount = "staleCount"
    private static let keyStalePrefix = "stale."
}

extension String {
    fileprivate func droppingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
