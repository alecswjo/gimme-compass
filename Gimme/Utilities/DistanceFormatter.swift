import Foundation

/// Formats straight-line distances for display, respecting the user's
/// measurement system. Thresholds per spec §3.4.
struct DistanceFormatter {

    enum UnitSystem {
        case metric
        case imperial
    }

    let system: UnitSystem
    private let numberFormatter: NumberFormatter

    init(locale: Locale = .current) {
        // .us and .uk both use miles for wayfinding distances.
        self.init(system: locale.measurementSystem == .metric ? .metric : .imperial, locale: locale)
    }

    init(system: UnitSystem, locale: Locale = Locale(identifier: "en_US")) {
        self.system = system
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        self.numberFormatter = formatter
    }

    func string(fromMeters meters: Double) -> String {
        let clamped = max(0, meters)
        switch system {
        case .metric:
            if clamped < 999.5 {
                return "\(roundedToTen(clamped)) m"
            }
            return "\(decimal(clamped / 1000)) km"
        case .imperial:
            let miles = clamped / 1609.344
            if miles < 0.18 {
                let feet = clamped * 3.28084
                return "\(roundedToTen(feet)) ft"
            }
            return "\(decimal(miles)) mi"
        }
    }

    private func roundedToTen(_ value: Double) -> Int {
        Int((value / 10).rounded() * 10)
    }

    private func decimal(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}
