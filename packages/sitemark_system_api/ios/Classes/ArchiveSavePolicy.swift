import Foundation

/// Pure rules for saving a backup ZIP through the document picker: the
/// source must be a non-empty ZIP inside app-private storage, and the
/// suggested filename must be safe for arbitrary user-visible locations.
public enum ArchiveSavePolicy {
    /// Validates the backup source and returns its canonical URL. Kotlin's
    /// `canonicalFile` leniency is preserved: symlinks are resolved on the
    /// existing prefix, so temp-directory indirection cannot sneak a source
    /// past the containment check.
    public static func validateSource(sourcePath: String, dataDirectory: URL) throws -> URL {
        let source = canonicalURL(sourcePath)
        let privateRoot = canonicalURL(dataDirectory.path)
        guard source.path.hasPrefix(privateRoot.path + "/") else {
            throw PolicyError.backupSourceNotPrivate
        }
        guard source.pathExtension.lowercased() == "zip" else {
            throw PolicyError.backupSourceNotZip
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let size = try? FileManager.default.attributesOfItem(atPath: source.path)[.size]
                  as? Int64,
              size > 0
        else {
            throw PolicyError.backupSourceEmpty
        }
        return source
    }

    public static func normalizeSuggestedName(_ suggestedName: String) throws -> String {
        let name = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.lowercased().hasSuffix(".zip") else { throw PolicyError.invalidBackupFilename }
        guard name.count > 4 else { throw PolicyError.invalidBackupFilename }
        guard !containsForbiddenCharacter(name) else { throw PolicyError.invalidBackupFilename }
        return name
    }

    /// Streams the source into the destination in buffered chunks so a large
    /// backup never materializes in memory. The destination file is created
    /// (or truncated) first.
    public static func copy(source: URL, destination: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw PolicyError.backupSourceEmpty
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

    // Kotlin guards the filename against \p{Cc} control characters plus the
    // path/forbidden set / \ : * ? " < > |. ICU's \p{Cc} keeps the rule
    // identical on iOS.
    private static let forbiddenNameRegex = try! NSRegularExpression(
        pattern: #"[\p{Cc}/\\:*?"<>|]"#)

    private static func containsForbiddenCharacter(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        return forbiddenNameRegex.firstMatch(in: name, range: range) != nil
    }

    private static func canonicalURL(_ path: String) -> URL {
        var url = URL(fileURLWithPath: path)
        if !url.path.hasPrefix("/") {
            url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(path)
        }
        return url.resolvingSymlinksInPath()
    }
}
