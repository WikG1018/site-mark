import CoreLocation

public enum LocationPermissionRequestPolicy {
    public static func shouldCompleteInFlightRequest(
        status: CLAuthorizationStatus
    ) -> Bool {
        status != .notDetermined
    }
}
