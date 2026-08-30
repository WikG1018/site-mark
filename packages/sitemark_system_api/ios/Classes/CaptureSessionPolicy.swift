import Foundation

/// Synchronous, durable key-value editing for pending camera-session
/// state. Android clears pending state via `SharedPreferences.commit` so a
/// process death cannot resurrect a stale target; iOS has no content-URI
/// grant to revoke and no SharedPreferences, so this protocol plus the key
/// constants are the whole portable contract. The 2b production
/// implementation backs it with `UserDefaults` + an immediate synchronize.
public protocol CaptureStateStore: AnyObject {
    /// Removes the given keys durably and synchronously. Returns false when
    /// the durable write failed (mirrors `SharedPreferences.commit`).
    func removeValues(forKey keys: [String]) -> Bool
}

public enum CaptureSessionPolicy {
    /// Suite name for the pending-capture state, mirroring the Android
    /// preference file name so diagnostics stay comparable across platforms.
    public static let preferencesName = "sitemark_capture_recovery"
    public static let keyCaptureId = "capture_id"
    public static let keyCapturePath = "capture_path"

    /// Clears the pending capture state synchronously and durably.
    public static func clearPending(_ store: CaptureStateStore) -> Bool {
        store.removeValues(forKey: [keyCaptureId, keyCapturePath])
    }
}
