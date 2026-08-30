import Foundation

/// Where a recovered camera capture stands. Mirrors the Pigeon
/// `CameraOutcome` split the Dart layer consumes on recovery.
public enum RecoveryDisposition {
    case captured
    case cancelled
}

/// Errors thrown by the system-bridge policy layer. The Kotlin
/// counterparts throw `IllegalArgumentException`; Swift callers match on
/// these cases instead.
public enum PolicyError: Error, Equatable {
    case invalidCaptureId
    case backupSourceNotPrivate
    case backupSourceNotZip
    case backupSourceEmpty
    case invalidBackupFilename
    case unableToPersistPublishJournal
}

/// Pure rules for naming and judging camera capture targets inside the
/// app-private originals directory.
public enum CaptureTargetPolicy {
    private static let safeCaptureIdRegex = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$")

    public static func fileName(captureId: String) throws -> String {
        guard matchesSafeCaptureId(captureId) else { throw PolicyError.invalidCaptureId }
        return captureId + ".jpg"
    }

    public static func isValidCaptureId(_ captureId: String) -> Bool {
        matchesSafeCaptureId(captureId)
    }

    /// Only a non-empty target counts as captured during recovery: an
    /// existing but empty file is the signature of a cancelled shutter.
    public static func recoveryDisposition(exists: Bool, length: Int64) -> RecoveryDisposition {
        exists && length > 0 ? .captured : .cancelled
    }

    static func matchesSafeCaptureId(_ captureId: String) -> Bool {
        let range = NSRange(captureId.startIndex..., in: captureId)
        return safeCaptureIdRegex.firstMatch(in: captureId, range: range) != nil
    }
}
