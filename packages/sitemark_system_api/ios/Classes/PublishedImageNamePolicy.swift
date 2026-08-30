import Foundation

/// Normalizes the display name of a published JPEG. Ported verbatim from
/// AndroidSystemApi.normalizedJpegName, including the case-sensitive,
/// sequential suffix stripping quirk ("photo.JPG" keeps its suffix and
/// becomes "photo.JPG.jpg").
public enum PublishedImageNamePolicy {
    // Unified forbidden set: control chars (Cc incl. C1), Unicode
    // separators (Z: spaces, NBSP, EM SPACE, line/para separators),
    // ZWNBSP/BOM, and path/shell metacharacters.
    private static let forbiddenRegex = try! NSRegularExpression(
        pattern: #"[\p{Cc}\p{Z}\uFEFF/\\:*?"<>|]"#)

    public static func normalizedJpegName(_ displayName: String) throws -> String {
        var base = displayName
        if base.hasSuffix(".jpg") {
            base = String(base.dropLast(4))
        }
        if base.hasSuffix(".jpeg") {
            base = String(base.dropLast(5))
        }
        guard !base.isEmpty, !containsForbiddenCharacter(base) else {
            throw PolicyError.invalidPublishedImageName
        }
        return base + ".jpg"
    }

    private static func containsForbiddenCharacter(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        return forbiddenRegex.firstMatch(in: name, range: range) != nil
    }
}
