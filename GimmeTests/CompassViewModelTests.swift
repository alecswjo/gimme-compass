import CoreLocation
import XCTest
@testable import Gimme

@MainActor
final class CompassViewModelTests: XCTestCase {

    private var provider: MockLocationProvider!
    private var searcher: MockSearcher!
    private var defaults: UserDefaults!

    private let targetCoordinate = CLLocationCoordinate2D(latitude: 37.7842, longitude: -122.4395)

    override func setUp() {
        super.setUp()
        provider = MockLocationProvider()
        searcher = MockSearcher()
        defaults = UserDefaults(suiteName: "gimme.tests.vm")!
        defaults.removePersistentDomain(forName: "gimme.tests.vm")
    }

    private func makeModel(isConfigured: Bool = true) -> CompassViewModel {
        CompassViewModel(
            isConfigured: isConfigured,
            locationProvider: provider,
            searcher: searcher,
            interpreter: RuleBasedInterpreter(),
            recentsStore: RecentQueriesStore(defaults: defaults)
        )
    }

    private func locatedModel() -> CompassViewModel {
        let model = makeModel()
        model.handle(.location(CLLocation(latitude: Fixtures.userCoordinate.latitude, longitude: Fixtures.userCoordinate.longitude)))
        return model
    }

    // MARK: - Setup / permission states

    func testMissingConfigurationShowsSetupRequired() {
        let model = makeModel(isConfigured: false)
        XCTAssertEqual(model.phase, .setupRequired)
        XCTAssertNil(model.submitQuery("gas"))
        XCTAssertEqual(model.phase, .setupRequired)
    }

    func testStartWithUndeterminedPermissionAsksForIt() {
        provider.authorizationStatus = .notDetermined
        let model = makeModel()
        model.start()
        XCTAssertEqual(model.phase, .needsPermission)
        XCTAssertEqual(provider.startCount, 0)
    }

    func testDeniedPermission() {
        let model = makeModel()
        model.handle(.authorization(.denied, reducedAccuracy: false))
        XCTAssertEqual(model.phase, .permissionDenied)
    }

    func testGrantStartsLocationAndShowsLocating() {
        let model = makeModel()
        model.handle(.authorization(.authorizedWhenInUse, reducedAccuracy: false))
        XCTAssertEqual(model.phase, .locating)
        XCTAssertEqual(provider.startCount, 1)
    }

    func testFirstFixMovesToIdle() {
        let model = makeModel()
        model.handle(.authorization(.authorizedWhenInUse, reducedAccuracy: false))
        model.handle(.location(CLLocation(latitude: 37.77, longitude: -122.42)))
        XCTAssertEqual(model.phase, .idle)
    }

    // MARK: - Search flow

    func testSubmitFindsTargetAndPoints() async {
        let place = Fixtures.place(at: targetCoordinate)
        searcher.onSearch = { _, _ in [place] }
        let model = locatedModel()

        await model.submitQuery("Zyns")?.value

        XCTAssertEqual(model.phase, .pointing)
        XCTAssertEqual(model.target, place)
        XCTAssertEqual(model.resolvedLabel, "convenience store")
        XCTAssertEqual(searcher.queries, ["convenience store"]) // interpreted, not raw
        XCTAssertNotNil(model.distanceMeters)
        XCTAssertNotNil(model.bearingDegrees)
        XCTAssertEqual(model.recents.first, "Zyns")
    }

    func testPassthroughQueryHidesResolvedLabel() async {
        searcher.onSearch = { _, _ in [Fixtures.place(at: self.targetCoordinate)] }
        let model = locatedModel()

        await model.submitQuery("birria tacos")?.value

        XCTAssertNil(model.resolvedLabel)
    }

    func testEmptyResultsShowNoResults() async {
        searcher.onSearch = { _, _ in [] }
        let model = locatedModel()

        await model.submitQuery("zorbblefruit")?.value

        XCTAssertEqual(model.phase, .noResults)
        XCTAssertNil(model.target)
    }

    func testSearchErrorSurfaces() async {
        searcher.onSearch = { _, _ in throw GimmeError.offline }
        let model = locatedModel()

        await model.submitQuery("gas")?.value

        XCTAssertEqual(model.phase, .error(.offline))
    }

    func testBlankSubmitIsNoOp() {
        let model = locatedModel()
        XCTAssertNil(model.submitQuery("   "))
        XCTAssertEqual(model.phase, .idle)
    }

    func testLatestSubmitWins() async {
        let slowPlace = Fixtures.place(id: "slow", name: "Slow", at: targetCoordinate)
        let fastPlace = Fixtures.place(id: "fast", name: "Fast", at: targetCoordinate)
        searcher.onSearch = { call, _ in
            if call == 1 {
                // Slow first search; wakes early if cancelled, which is fine —
                // the view model must discard its result either way.
                try? await Task.sleep(nanoseconds: 150_000_000)
                return [slowPlace]
            }
            return [fastPlace]
        }
        let model = locatedModel()

        let first = model.submitQuery("first query")
        // Let the first search actually reach the searcher before superseding it.
        while searcher.queries.isEmpty {
            await Task.yield()
        }
        let second = model.submitQuery("second query")
        await first?.value
        await second?.value

        XCTAssertEqual(model.target, fastPlace)
        XCTAssertEqual(model.phase, .pointing)
    }

    func testSubmitBeforeFirstFixRunsOnceLocated() async {
        let place = Fixtures.place(at: targetCoordinate)
        searcher.onSearch = { _, _ in [place] }
        let model = makeModel()

        XCTAssertNil(model.submitQuery("gas")) // no location yet → queued
        XCTAssertTrue(searcher.queries.isEmpty)

        model.handle(.location(CLLocation(latitude: 37.77, longitude: -122.42)))
        await model.searchTask?.value

        XCTAssertEqual(model.phase, .pointing)
        XCTAssertEqual(model.target, place)
    }

    // MARK: - Geometry & heading

    func testArrowUsesHeadingWhenAvailable() async {
        // User at equator/prime meridian, target due east → bearing 90.
        let place = Fixtures.place(at: CLLocationCoordinate2D(latitude: 0, longitude: 0.01))
        searcher.onSearch = { _, _ in [place] }
        let model = makeModel()
        model.handle(.location(CLLocation(latitude: 0, longitude: 0)))
        await model.submitQuery("gas")?.value

        model.handle(.heading(degrees: 90, accuracy: 5))
        XCTAssertEqual(model.arrowRotation, 0, accuracy: 0.5) // facing the target

        model.handle(.heading(degrees: 350, accuracy: 5))
        XCTAssertEqual(model.arrowRotation, 100, accuracy: 0.5) // target now to the right
    }

    func testArrowFallsBackToNorthUpWithoutHeading() async {
        provider.isHeadingAvailable = false
        let place = Fixtures.place(at: CLLocationCoordinate2D(latitude: 0, longitude: 0.01))
        searcher.onSearch = { _, _ in [place] }
        let model = makeModel()
        model.handle(.location(CLLocation(latitude: 0, longitude: 0)))
        await model.submitQuery("gas")?.value

        XCTAssertEqual(model.arrowRotation, 90, accuracy: 0.5) // absolute bearing
    }

    func testCalibrationHint() {
        let model = locatedModel()
        model.handle(.heading(degrees: 10, accuracy: 30))
        XCTAssertTrue(model.showCalibrationHint)
        model.handle(.heading(degrees: 10, accuracy: 5))
        XCTAssertFalse(model.showCalibrationHint)
    }

    // MARK: - Arrival hysteresis (spec §5.3 / review F7)

    func testArrivalHysteresis() async {
        let place = Fixtures.place(at: targetCoordinate)
        searcher.onSearch = { _, _ in [place] }
        let model = makeModel()
        model.handle(.location(Fixtures.location(metersNorthOf: targetCoordinate, 100)))
        await model.submitQuery("gas")?.value
        XCTAssertEqual(model.phase, .pointing)

        model.handle(.location(Fixtures.location(metersNorthOf: targetCoordinate, 20)))
        XCTAssertEqual(model.phase, .arrived)

        // Inside the exit threshold: still arrived (no flapping).
        model.handle(.location(Fixtures.location(metersNorthOf: targetCoordinate, 32)))
        XCTAssertEqual(model.phase, .arrived)

        // Beyond exit threshold: back to pointing.
        model.handle(.location(Fixtures.location(metersNorthOf: targetCoordinate, 50)))
        XCTAssertEqual(model.phase, .pointing)
    }

    // MARK: - Movement re-search (spec §5.3 / review F6)

    func testMovingFarTriggersSilentResearch() async {
        let nearOriginal = Fixtures.place(id: "a", name: "A", at: targetCoordinate)
        let newNearest = Fixtures.place(id: "b", name: "B", at: CLLocationCoordinate2D(latitude: 37.79, longitude: -122.44))
        searcher.onSearch = { call, _ in call == 1 ? [nearOriginal] : [newNearest] }

        let model = makeModel()
        let origin = CLLocation(latitude: 37.7749, longitude: -122.4194)
        model.handle(.location(origin))
        await model.submitQuery("gas")?.value
        XCTAssertEqual(model.target, nearOriginal)

        // Move 300 m north — beyond the 250 m re-search threshold.
        model.handle(.location(Fixtures.location(metersNorthOf: origin.coordinate, 300)))
        await model.refreshTask?.value

        XCTAssertEqual(model.target, newNearest)
        XCTAssertEqual(model.phase, .pointing) // silent: never went back to .searching
        XCTAssertEqual(searcher.queries.count, 2)
    }

    func testSmallMovementDoesNotResearch() async {
        searcher.onSearch = { _, _ in [Fixtures.place(at: self.targetCoordinate)] }
        let model = makeModel()
        let origin = CLLocation(latitude: 37.7749, longitude: -122.4194)
        model.handle(.location(origin))
        await model.submitQuery("gas")?.value

        model.handle(.location(Fixtures.location(metersNorthOf: origin.coordinate, 100)))
        XCTAssertNil(model.refreshTask)
        XCTAssertEqual(searcher.queries.count, 1)
    }

    // MARK: - Retry

    func testRetryReRunsLastQuery() async {
        searcher.onSearch = { call, _ in
            if call == 1 { throw GimmeError.offline }
            return [Fixtures.place(at: self.targetCoordinate)]
        }
        let model = locatedModel()

        await model.submitQuery("gas")?.value
        XCTAssertEqual(model.phase, .error(.offline))

        model.retry()
        await model.searchTask?.value
        XCTAssertEqual(model.phase, .pointing)
        XCTAssertEqual(searcher.queries.count, 2)
    }
}
