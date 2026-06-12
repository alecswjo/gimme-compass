import CoreLocation
import Foundation

/// A resolved search target. `isOpenNow` is tri-state: nil means Google didn't
/// say, and the UI shows nothing rather than guessing.
struct Place: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let isOpenNow: Bool?

    static func == (lhs: Place, rhs: Place) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.address == rhs.address
            && lhs.isOpenNow == rhs.isOpenNow
    }
}
