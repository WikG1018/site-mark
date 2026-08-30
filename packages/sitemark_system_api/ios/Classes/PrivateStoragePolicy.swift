import Foundation

/// Canonical-path containment for files the native side reads or writes.
/// Android validates sources against `context.dataDir`; the iOS sandbox
/// root (`NSHomeDirectory()`) plays the same role and covers tmp,
/// Application Support, Documents, and Caches.
public enum PrivateStoragePolicy {
    public static func validatedPrivateFile(path: String, sandboxRoot: URL) throws -> URL {
        let file = canonicalURL(path)
        let root = canonicalURL(sandboxRoot.path)
        guard file.path.hasPrefix(root.path + "/") else {
            throw PolicyError.privateStorageRequired
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size]
                  as? Int64,
              size > 0
        else {
            throw PolicyError.privateFileMissingOrEmpty
        }
        return file
    }

    /// Kotlin's `canonicalFile` leniency: symlinks are resolved on the
    /// existing prefix, so temp-directory indirection cannot sneak a source
    /// past the containment check.
    static func canonicalURL(_ path: String) -> URL {
        var url = URL(fileURLWithPath: path)
        if !url.path.hasPrefix("/") {
            url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(path)
        }
        return url.resolvingSymlinksInPath()
    }
}
