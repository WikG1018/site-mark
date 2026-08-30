import Foundation

/// Production journal backend: one JSON file in Application Support,
/// rewritten atomically on every commit — the durability contract of the
/// Android `SharedPreferences.Editor.commit` this replaces.
public final class JournalFilePersistence: JournalPersistence {
    private let fileURL: URL

    public init(directory: URL, filename: String = "publish-journal.json") {
        self.fileURL = directory.appendingPathComponent(filename)
    }

    public func snapshot() -> [String: JournalValue]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard !data.isEmpty else { return [:] }
        return try? JSONDecoder().decode([String: JournalValue].self, from: data)
    }

    public func commit(_ mutations: [String: JournalMutation]) -> Bool {
        var values = snapshot() ?? [:]
        for (key, mutation) in mutations {
            switch mutation {
            case .put(let value):
                values[key] = value
            case .remove:
                values.removeValue(forKey: key)
            }
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(values)
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            return (try? data.write(to: fileURL, options: .atomic)) != nil
        } catch {
            return false
        }
    }
}
