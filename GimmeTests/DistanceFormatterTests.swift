import XCTest
@testable import Gimme

final class DistanceFormatterTests: XCTestCase {

    private let imperial = DistanceFormatter(system: .imperial, locale: Locale(identifier: "en_US"))
    private let metric = DistanceFormatter(system: .metric, locale: Locale(identifier: "en_US"))

    // MARK: - Imperial

    func testImperialShortDistancesUseFeetRoundedToTen() {
        XCTAssertEqual(imperial.string(fromMeters: 100), "330 ft")
        XCTAssertEqual(imperial.string(fromMeters: 200), "660 ft")
    }

    func testImperialThresholdToMiles() {
        XCTAssertEqual(imperial.string(fromMeters: 289), "950 ft") // 0.1796 mi — still feet
        XCTAssertEqual(imperial.string(fromMeters: 291), "0.2 mi") // 0.1808 mi — flips to miles
    }

    func testImperialMilesOneDecimal() {
        XCTAssertEqual(imperial.string(fromMeters: 1609.344), "1.0 mi")
        XCTAssertEqual(imperial.string(fromMeters: 5000), "3.1 mi")
    }

    func testImperialZero() {
        XCTAssertEqual(imperial.string(fromMeters: 0), "0 ft")
    }

    // MARK: - Metric

    func testMetricShortDistancesRoundedToTen() {
        XCTAssertEqual(metric.string(fromMeters: 444), "440 m")
        XCTAssertEqual(metric.string(fromMeters: 446), "450 m")
    }

    func testMetricThresholdToKilometers() {
        XCTAssertEqual(metric.string(fromMeters: 994), "990 m")
        XCTAssertEqual(metric.string(fromMeters: 999.6), "1.0 km")
        XCTAssertEqual(metric.string(fromMeters: 1500), "1.5 km")
    }

    func testNegativeInputClampsToZero() {
        XCTAssertEqual(metric.string(fromMeters: -5), "0 m")
    }

    // MARK: - Locale inference

    func testLocaleInference() {
        XCTAssertEqual(DistanceFormatter(locale: Locale(identifier: "en_US")).system, .imperial)
        XCTAssertEqual(DistanceFormatter(locale: Locale(identifier: "fr_FR")).system, .metric)
    }
}
