import Foundation

/// Build-time configuration, injected via Config/Gimme.xcconfig → Info.plist.
/// Missing values produce the Setup-required state rather than a broken app.
struct AppConfig {
    let placesAPIKey: String
    let proxyURL: URL?
    let proxyAuthToken: String?

    var isConfigured: Bool { !placesAPIKey.isEmpty }

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfig {
        func value(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return AppConfig(
            placesAPIKey: value("GooglePlacesAPIKey") ?? "",
            proxyURL: value("GimmeProxyURL").flatMap(URL.init(string:)),
            proxyAuthToken: value("GimmeProxyAuthToken")
        )
    }
}
