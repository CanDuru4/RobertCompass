import Foundation
import CoreLocation

/// Fetches a recent location with explicit denied, inaccurate, and timeout outcomes.
/// - Note: Location updates run only while answering or centering the map.
/// - Example: `let location = try await manager.currentLocation()`.
@MainActor
final class LocationManager: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<CLLocation, Error>?
    private var timeout: Task<Void, Never>?

    /// Configure delegation before requesting location permission.
    /// - Returns: A location service ready for one request at a time.
    /// - Example: `let manager = LocationManager()`.
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Request a fresh location and stop updates when it succeeds or times out.
    /// - Returns: A recent location with positive horizontal accuracy.
    /// - Throws: `LocationError` for denied permission, timeout, or concurrent requests.
    /// - Example: `try await manager.currentLocation()`.
    func currentLocation() async throws -> CLLocation {
        guard pending == nil else { throw LocationError.busy }
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finish(.failure(LocationError.timeout))
            }
            authorize()
        }
    }

    private func authorize() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        case .denied, .restricted: finish(.failure(LocationError.denied))
        @unknown default: finish(.failure(LocationError.denied))
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        manager.stopUpdatingLocation()
        timeout?.cancel()
        timeout = nil
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }

    /// Continue an outstanding request when the permission dialog resolves.
    /// - Parameter manager: System location manager.
    /// - Returns: Nothing.
    /// - Example: Called by Core Location after authorization changes.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if pending != nil { authorize() }
    }

    /// Accept only a recent, usable fix instead of the oldest cached location.
    /// - Parameters:
    ///   - manager: System location manager.
    ///   - locations: Newly delivered location samples.
    /// - Returns: Nothing; completes the pending request once.
    /// - Example: Called by Core Location during a request.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 50, abs(location.timestamp.timeIntervalSinceNow) <= 15 else { return }
        finish(.success(location))
    }

    /// Surface terminal failures while allowing transient GPS errors to recover.
    /// - Parameters:
    ///   - manager: System location manager.
    ///   - error: Location acquisition error.
    /// - Returns: Nothing.
    /// - Example: Called when Core Location cannot deliver a fix.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { return }
        finish(.failure(error))
    }
}

enum LocationError: LocalizedError {
    case denied, timeout, busy
    var errorDescription: String? {
        switch self {
        case .denied: return "Location access is off. Enable While Using the App and Precise Location in Settings to answer checkpoints."
        case .timeout: return "A precise GPS location could not be found. Move outdoors, check Precise Location in Settings, and try again."
        case .busy: return "A location request is already in progress."
        }
    }
}
