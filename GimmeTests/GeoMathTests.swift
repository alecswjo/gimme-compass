import CoreLocation
import XCTest
@testable import Gimme

final class GeoMathTests: XCTestCase {

    private let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    private let sanFrancisco = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    private let losAngeles = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)

    // MARK: - Bearing

    func testBearingDueEast() {
        let bearing = GeoMath.initialBearing(from: origin, to: CLLocationCoordinate2D(latitude: 0, longitude: 1))
        XCTAssertEqual(bearing, 90, accuracy: 0.001)
    }

    func testBearingDueNorth() {
        let bearing = GeoMath.initialBearing(from: origin, to: CLLocationCoordinate2D(latitude: 1, longitude: 0))
        XCTAssertEqual(bearing, 0, accuracy: 0.001)
    }

    func testBearingDueSouth() {
        let bearing = GeoMath.initialBearing(from: origin, to: CLLocationCoordinate2D(latitude: -1, longitude: 0))
        XCTAssertEqual(bearing, 180, accuracy: 0.001)
    }

    func testBearingDueWestNormalizedPositive() {
        let bearing = GeoMath.initialBearing(from: origin, to: CLLocationCoordinate2D(latitude: 0, longitude: -1))
        XCTAssertEqual(bearing, 270, accuracy: 0.001)
    }

    func testBearingSanFranciscoToLosAngeles() {
        let bearing = GeoMath.initialBearing(from: sanFrancisco, to: losAngeles)
        XCTAssertEqual(bearing, 136.5, accuracy: 1.0)
    }

    // MARK: - Distance

    func testDistanceOneDegreeLongitudeAtEquator() {
        let distance = GeoMath.distanceMeters(from: origin, to: CLLocationCoordinate2D(latitude: 0, longitude: 1))
        XCTAssertEqual(distance, 111_195, accuracy: 50)
    }

    func testDistanceSanFranciscoToLosAngeles() {
        let distance = GeoMath.distanceMeters(from: sanFrancisco, to: losAngeles)
        XCTAssertEqual(distance, 559_000, accuracy: 5_000)
    }

    func testDistanceMatchesCoreLocation() {
        let from = CLLocation(latitude: sanFrancisco.latitude, longitude: sanFrancisco.longitude)
        let to = CLLocation(latitude: 37.8044, longitude: -122.2712) // Oakland
        let haversine = GeoMath.distanceMeters(from: sanFrancisco, to: CLLocationCoordinate2D(latitude: 37.8044, longitude: -122.2712))
        XCTAssertEqual(haversine, from.distance(from: to), accuracy: from.distance(from: to) * 0.005)
    }

    // MARK: - Signed delta & unwrap (the spin bug, spec §6.5)

    func testShortestSignedDeltaAcrossNorthClockwise() {
        XCTAssertEqual(GeoMath.shortestSignedDelta(from: 350, to: 10), 20, accuracy: 0.001)
    }

    func testShortestSignedDeltaAcrossNorthCounterClockwise() {
        XCTAssertEqual(GeoMath.shortestSignedDelta(from: 10, to: 350), -20, accuracy: 0.001)
    }

    func testShortestSignedDeltaHalfTurnIsPositive() {
        XCTAssertEqual(GeoMath.shortestSignedDelta(from: 0, to: 180), 180, accuracy: 0.001)
        XCTAssertEqual(GeoMath.shortestSignedDelta(from: 180, to: 0), 180, accuracy: 0.001)
    }

    func testUnwrapContinuesPastFullRotation() {
        XCTAssertEqual(GeoMath.unwrap(target: 10, previous: 350), 370, accuracy: 0.001)
        XCTAssertEqual(GeoMath.unwrap(target: 350, previous: 0), -10, accuracy: 0.001)
    }

    func testUnwrapWorksFarFromBaseRevolution() {
        XCTAssertEqual(GeoMath.unwrap(target: 350, previous: 720), 710, accuracy: 0.001)
        XCTAssertEqual(GeoMath.unwrap(target: 340, previous: -10), -20, accuracy: 0.001)
    }

    func testUnwrapSequenceNeverJumpsMoreThanHalfTurn() {
        var previous = 0.0
        for target in stride(from: 0.0, through: 3600.0, by: 17.0) {
            let next = GeoMath.unwrap(target: target, previous: previous)
            XCTAssertLessThanOrEqual(abs(next - previous), 180.001)
            previous = next
        }
    }

    // MARK: - Quantization

    func testCardinal16() {
        XCTAssertEqual(GeoMath.cardinal16(forBearing: 0), "N")
        XCTAssertEqual(GeoMath.cardinal16(forBearing: 45), "NE")
        XCTAssertEqual(GeoMath.cardinal16(forBearing: 90), "E")
        XCTAssertEqual(GeoMath.cardinal16(forBearing: 225), "SW")
        XCTAssertEqual(GeoMath.cardinal16(forBearing: 337.4), "NNW")
        XCTAssertEqual(GeoMath.cardinal16(forBearing: 359), "N")
    }

    func testRelativeDirectionSectors() {
        XCTAssertEqual(GeoMath.relativeDirection(bearing: 90, heading: 90), .ahead)
        XCTAssertEqual(GeoMath.relativeDirection(bearing: 90, heading: 0), .right)
        XCTAssertEqual(GeoMath.relativeDirection(bearing: 0, heading: 90), .left)
        XCTAssertEqual(GeoMath.relativeDirection(bearing: 180, heading: 0), .behind)
        XCTAssertEqual(GeoMath.relativeDirection(bearing: 45, heading: 0), .aheadRight)
    }

    func testNormalizeDegrees() {
        XCTAssertEqual(GeoMath.normalizeDegrees(-10), 350, accuracy: 0.001)
        XCTAssertEqual(GeoMath.normalizeDegrees(370), 10, accuracy: 0.001)
        XCTAssertEqual(GeoMath.normalizeDegrees(0), 0, accuracy: 0.001)
        XCTAssertEqual(GeoMath.normalizeDegrees(360), 0, accuracy: 0.001)
    }
}
