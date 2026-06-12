import CoreLocation
import Foundation
import Observation

/// Single source of truth for the whole screen. Owns the Phase state machine
/// (spec §3.2) and all geometry derived from location + heading.
@MainActor
@Observable
final class CompassViewModel {

    enum Phase: Equatable {
        case setupRequired
        case needsPermission
        case permissionDenied
        case locating
        case idle
        case searching
        case pointing
        case arrived
        case noResults
        case error(GimmeError)
    }

    // MARK: - Tunables (spec §5.3)

    static let arrivalEnterMeters: Double = 25
    static let arrivalExitMeters: Double = 40
    static let researchAfterMeters: Double = 250
    static let calibrationHintThresholdDegrees: Double = 25

    // MARK: - Observable state

    private(set) var phase: Phase
    var query = ""
    private(set) var target: Place?
    /// Category caption ("convenience store") when it differs from what was typed.
    private(set) var resolvedLabel: String?
    private(set) var distanceMeters: Double?
    private(set) var bearingDegrees: Double?
    /// Continuous (unwrapped) rotation for the arrow — safe to animate.
    private(set) var arrowRotation: Double = 0
    private(set) var headingDegrees: Double?
    private(set) var headingAccuracy: Double?
    private(set) var isReducedAccuracy = false
    private(set) var recents: [String] = []

    let suggestions = ["Zyns", "Gas", "Ice cream", "Coffee", "ATM"]

    var isHeadingAvailable: Bool { locationProvider.isHeadingAvailable }

    // MARK: - Dependencies

    private let locationProvider: any LocationProviding
    private let searcher: any PlaceSearching
    private let interpreter: any QueryInterpreting
    private let recentsStore: RecentQueriesStore
    private let distanceFormatter = DistanceFormatter()

    // MARK: - Internals (read-only exposed for deterministic tests)

    private(set) var location: CLLocation?
    private(set) var searchOrigin: CLLocation?
    private(set) var searchTask: Task<Void, Never>?
    private(set) var refreshTask: Task<Void, Never>?
    private var lastInterpreted: InterpretedQuery?
    private var lastSubmittedRaw: String?
    private var pendingQuery: String?
    private var eventsTask: Task<Void, Never>?

    // MARK: - Init

    init(
        isConfigured: Bool,
        locationProvider: any LocationProviding,
        searcher: any PlaceSearching,
        interpreter: any QueryInterpreting,
        recentsStore: RecentQueriesStore
    ) {
        self.locationProvider = locationProvider
        self.searcher = searcher
        self.interpreter = interpreter
        self.recentsStore = recentsStore
        self.phase = isConfigured ? .locating : .setupRequired
    }

    static func live() -> CompassViewModel {
        let config = AppConfig.fromBundle()
        let interpreter: any QueryInterpreting
        if let proxyURL = config.proxyURL {
            interpreter = ClaudeProxyInterpreter(endpoint: proxyURL, authToken: config.proxyAuthToken)
        } else {
            interpreter = RuleBasedInterpreter()
        }
        return CompassViewModel(
            isConfigured: config.isConfigured,
            locationProvider: LocationService(),
            searcher: GooglePlacesClient(apiKey: config.placesAPIKey),
            interpreter: interpreter,
            recentsStore: RecentQueriesStore()
        )
    }

    // MARK: - Lifecycle

    /// Idempotent; called once from the root view's `.task`.
    func start() {
        guard phase != .setupRequired else { return }
        recents = recentsStore.all()
        isReducedAccuracy = locationProvider.isReducedAccuracy

        if eventsTask == nil {
            eventsTask = Task { [weak self] in
                guard let events = self?.locationProvider.events else { return }
                for await event in events {
                    guard let self, !Task.isCancelled else { break }
                    self.handle(event)
                }
            }
        }

        applyAuthorization(locationProvider.authorizationStatus)
    }

    func scenePhaseChanged(isActive: Bool) {
        guard phase != .setupRequired else { return }
        if isActive {
            if isAuthorized(locationProvider.authorizationStatus) {
                locationProvider.start()
            }
        } else {
            locationProvider.stop()
        }
    }

    func requestPermission() {
        locationProvider.requestWhenInUseAuthorization()
    }

    // MARK: - Event handling (internal so tests can drive it deterministically)

    func handle(_ event: LocationEvent) {
        switch event {
        case .location(let newLocation):
            location = newLocation
            if phase == .locating {
                phase = target == nil ? .idle : .pointing
            }
            if let pendingQuery {
                self.pendingQuery = nil
                submitQuery(pendingQuery)
                return
            }
            recomputeGeometry()
            checkArrival()
            checkMovementRefresh()

        case .heading(let degrees, let accuracy):
            headingDegrees = degrees
            headingAccuracy = accuracy
            recomputeGeometry()

        case .authorization(let status, let reducedAccuracy):
            isReducedAccuracy = reducedAccuracy
            applyAuthorization(status)
        }
    }

    private func applyAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            phase = .needsPermission
        case .denied, .restricted:
            phase = .permissionDenied
        case .authorizedWhenInUse, .authorizedAlways:
            locationProvider.start()
            if location == nil {
                phase = .locating
            } else if phase == .needsPermission || phase == .permissionDenied || phase == .locating {
                phase = target == nil ? .idle : .pointing
            }
        @unknown default:
            phase = .needsPermission
        }
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    // MARK: - Search

    func submit() {
        submitQuery(query)
    }

    @discardableResult
    func submitQuery(_ raw: String) -> Task<Void, Never>? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, phase != .setupRequired else { return nil }
        query = trimmed

        guard let location else {
            // Located soon; run the search on the first fix.
            pendingQuery = trimmed
            return nil
        }

        searchTask?.cancel()
        refreshTask?.cancel()
        lastSubmittedRaw = trimmed
        phase = .searching

        let task = Task { [weak self] in
            guard let self else { return }
            let interpreted = await self.interpreter.interpret(trimmed)
            guard !Task.isCancelled else { return }
            do {
                let places = try await self.searcher.searchNearest(
                    matching: interpreted.searchText,
                    near: location.coordinate
                )
                guard !Task.isCancelled else { return }
                self.completeSearch(raw: trimmed, interpreted: interpreted, places: places, origin: location)
            } catch is CancellationError {
                return
            } catch let error as GimmeError {
                guard !Task.isCancelled else { return }
                self.phase = .error(error)
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .error(.searchFailed)
            }
        }
        searchTask = task
        return task
    }

    func retry() {
        if let lastSubmittedRaw {
            submitQuery(lastSubmittedRaw)
        } else {
            phase = location == nil ? .locating : .idle
        }
    }

    private func completeSearch(raw: String, interpreted: InterpretedQuery, places: [Place], origin: CLLocation) {
        lastInterpreted = interpreted
        recentsStore.add(raw)
        recents = recentsStore.all()

        guard let nearest = places.first else {
            target = nil
            distanceMeters = nil
            bearingDegrees = nil
            phase = .noResults
            return
        }

        searchOrigin = origin
        target = nearest
        resolvedLabel = interpreted.displayLabel.caseInsensitiveCompare(raw) == .orderedSame
            ? nil
            : interpreted.displayLabel
        phase = .pointing
        recomputeGeometry()
        checkArrival()
    }

    /// Silent refresh after significant movement: never shows a spinner, never
    /// degrades a working target on failure (spec §5.3 / review F6).
    private func checkMovementRefresh() {
        guard phase == .pointing || phase == .arrived,
              refreshTask == nil,
              let location,
              let origin = searchOrigin,
              let interpreted = lastInterpreted,
              location.distance(from: origin) > Self.researchAfterMeters
        else { return }

        searchOrigin = location // move the origin immediately so we don't re-trigger every fix
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            guard let places = try? await self.searcher.searchNearest(
                matching: interpreted.searchText,
                near: location.coordinate
            ), let nearest = places.first else { return }
            guard !Task.isCancelled else { return }
            if nearest != self.target {
                self.target = nearest
                self.recomputeGeometry()
                self.checkArrival()
            }
        }
    }

    // MARK: - Geometry

    private func recomputeGeometry() {
        guard let location, let target else {
            distanceMeters = nil
            bearingDegrees = nil
            return
        }
        distanceMeters = GeoMath.distanceMeters(from: location.coordinate, to: target.coordinate)
        let bearing = GeoMath.initialBearing(from: location.coordinate, to: target.coordinate)
        bearingDegrees = bearing

        // With a heading, the arrow is relative to where the phone points;
        // without one (Simulator, no magnetometer) it is drawn north-up (§3.3).
        let rawRotation: Double
        if isHeadingAvailable, let headingDegrees {
            rawRotation = bearing - headingDegrees
        } else {
            rawRotation = bearing
        }
        arrowRotation = GeoMath.unwrap(target: rawRotation, previous: arrowRotation)
    }

    private func checkArrival() {
        guard let distanceMeters else { return }
        if phase == .pointing, distanceMeters < Self.arrivalEnterMeters {
            phase = .arrived
        } else if phase == .arrived, distanceMeters > Self.arrivalExitMeters {
            phase = .pointing
        }
    }

    // MARK: - Display helpers

    var distanceText: String? {
        distanceMeters.map { distanceFormatter.string(fromMeters: $0) }
    }

    var cardinalText: String? {
        bearingDegrees.map(GeoMath.cardinal16(forBearing:))
    }

    var showCalibrationHint: Bool {
        guard isHeadingAvailable, let headingAccuracy else { return false }
        return headingAccuracy < 0 || headingAccuracy > Self.calibrationHintThresholdDegrees
    }

    /// Chips: fixed suggestions plus recents that aren't already suggestions.
    var chips: [String] {
        let extraRecents = recents.filter { recent in
            !suggestions.contains { $0.caseInsensitiveCompare(recent) == .orderedSame }
        }
        return suggestions + extraRecents
    }

    var accessibilitySummary: String {
        guard let target else { return "No destination set" }
        var parts = [target.name]
        if let distanceText {
            parts.append(distanceText)
        }
        if let bearingDegrees {
            if isHeadingAvailable, let headingDegrees {
                parts.append(GeoMath.relativeDirection(bearing: bearingDegrees, heading: headingDegrees).spoken)
            } else {
                parts.append("to the \(GeoMath.cardinal16(forBearing: bearingDegrees))")
            }
        }
        return parts.joined(separator: ", ")
    }
}
