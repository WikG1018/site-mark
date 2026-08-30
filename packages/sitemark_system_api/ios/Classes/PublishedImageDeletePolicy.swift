import Foundation

/// Allowlist for `deletePublishedImage` on iOS: only identifiers shaped
/// like a real PHAsset `localIdentifier` (`<UUID>/L0/<NNN>`) may reach the
/// photo-library fetch, and callers must only pass identifiers this app
/// obtained from `publishJpeg` or journal recovery. Android validates a
/// MediaStore authority/relative path instead — a platform delta recorded
/// in the design doc — but the rule is the same: reject everything the
/// system media provider could not have issued.
public enum PublishedImageDeletePolicy {
    private static let localIdentifierRegex = try! NSRegularExpression(
        pattern:
            "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/L0/\\d{3}$")

    public static func allowsDelete(localIdentifier: String?) -> Bool {
        guard let identifier = localIdentifier, !identifier.isEmpty else { return false }
        let range = NSRange(identifier.startIndex..., in: identifier)
        return localIdentifierRegex.firstMatch(in: identifier, range: range) != nil
    }
}
