import CoreLocation
import Foundation

/// Everything the view model needs to know from CoreLocation, as one event stream.
enum LocationEvent {
    case location(CLLocation)
    case heading(degrees: Double, accuracy: Double)
    case authorization(CLAuthorizationStatus, reducedAccuracy: Bool)
}

protocol LocationProviding: AnyObject {
    /// Single-consumer stream; the view model is the only subscriber.
    var events: AsyncStream<LocationEvent> { get }
    var authorizationStatus: CLAuthorizationStatus { get }
    var isHeadingAvailable: Bool { get }
    var isReducedAccuracy: Bool { get }
    func requestWhenInUseAuthorization()
    func start()
    func stop()
}

/// CLLocationManager wrapper. Delegate-based because heading has no async API.
/// Policy decisions live here so the view model stays pure:
/// - drop invalid fixes (negative horizontal accuracy) and stale fixes (> 30 s)
/// - prefer true heading, fall back to magnetic (spec §6.6)
final class LocationService: NSObject, LocationProviding, CLLocationManagerDelegate {

    let events: AsyncStream<LocationEvent>
    private let continuation: AsyncStream<LocationEvent>.Continuation
    private let manager = CLLocationManager()

    static let maxFixAgeSeconds: TimeInterval = 30

    override init() {
        (events, continuation) = AsyncStream.makeStream(
            of: LocationEvent.self,
            bufferingPolicy: .bufferingNewest(16)
        )
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.headingFilter = 2
        manager.activityType = .otherNavigation
    }

    deinit {
        continuation.finish()
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    var isHeadingAvailable: Bool { CLLocationManager.headingAvailable() }

    var isReducedAccuracy: Bool { manager.accuracyAuthorization == .reducedAccuracy }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        manager.startUpdatingLocation()
        if isHeadingAvailable {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        continuation.yield(.authorization(
            manager.authorizationStatus,
            reducedAccuracy: manager.accuracyAuthorization == .reducedAccuracy
        ))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last,
              latest.horizontalAccuracy >= 0,
              abs(latest.timestamp.timeIntervalSinceNow) < Self.maxFixAgeSeconds
        else { return }
        continuation.yield(.location(latest))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // trueHeading is negative when invalid (needs location for declination).
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard degrees >= 0 else { return }
        continuation.yield(.heading(degrees: degrees, accuracy: newHeading.headingAccuracy))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is transient — keep waiting. Denial arrives via
        // the authorization callback, which is the one we act on.
    }
}
