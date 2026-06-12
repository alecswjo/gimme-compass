import CoreLocation
import Foundation

/// Pure geographic math. No CoreLocation managers, no state — fully unit-testable.
enum GeoMath {

    private static let earthRadiusMeters = 6_371_000.0

    /// Initial great-circle bearing (forward azimuth) from `from` to `to`,
    /// in degrees relative to true north, normalized to [0, 360).
    static func initialBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let phi1 = from.latitude.degreesToRadians
        let phi2 = to.latitude.degreesToRadians
        let deltaLambda = (to.longitude - from.longitude).degreesToRadians

        let y = sin(deltaLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda)
        return normalizeDegrees(atan2(y, x).radiansToDegrees)
    }

    /// Haversine great-circle distance in meters.
    static func distanceMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let phi1 = from.latitude.degreesToRadians
        let phi2 = to.latitude.degreesToRadians
        let deltaPhi = (to.latitude - from.latitude).degreesToRadians
        let deltaLambda = (to.longitude - from.longitude).degreesToRadians

        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Normalizes an angle in degrees to [0, 360).
    static func normalizeDegrees(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    /// Shortest signed angular difference `to − from`, in (−180, 180].
    static func shortestSignedDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    /// Returns the angle equivalent to `target` (mod 360) that is closest to
    /// `previous` on the continuous number line. Feeding the result back as the
    /// next `previous` yields a continuous rotation value that SwiftUI can animate
    /// without spinning the long way around when crossing 0°/360°.
    static func unwrap(target: Double, previous: Double) -> Double {
        previous + shortestSignedDelta(from: normalizeDegrees(previous), to: normalizeDegrees(target))
    }

    // MARK: - Display quantization

    private static let cardinals16 = [
        "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
    ]

    /// 16-wind compass name for a bearing ("N", "NNE", …).
    static func cardinal16(forBearing bearing: Double) -> String {
        let index = Int((normalizeDegrees(bearing) + 11.25) / 22.5) % 16
        return cardinals16[index]
    }

    /// Direction of the target relative to where the user is facing,
    /// quantized to 8 sectors of 45°. Used for VoiceOver.
    static func relativeDirection(bearing: Double, heading: Double) -> RelativeDirection {
        let relative = normalizeDegrees(bearing - heading)
        let index = Int((relative + 22.5) / 45) % 8
        return RelativeDirection.allCases[index]
    }
}

enum RelativeDirection: CaseIterable {
    case ahead, aheadRight, right, behindRight, behind, behindLeft, left, aheadLeft

    var spoken: String {
        switch self {
        case .ahead: "straight ahead"
        case .aheadRight: "ahead and to your right"
        case .right: "to your right"
        case .behindRight: "behind you, to the right"
        case .behind: "behind you"
        case .behindLeft: "behind you, to the left"
        case .left: "to your left"
        case .aheadLeft: "ahead and to your left"
        }
    }
}

private extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }
}
