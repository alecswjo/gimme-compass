import Foundation

/// Last few submitted queries, newest first. UserDefaults-backed (declared in
/// PrivacyInfo.xcprivacy under CA92.1).
struct RecentQueriesStore {

    static let storageKey = "gimme.recentQueries"
    static let maxCount = 8

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func all() -> [String] {
        defaults.stringArray(forKey: Self.storageKey) ?? []
    }

    func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var recents = all().filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        recents.insert(trimmed, at: 0)
        defaults.set(Array(recents.prefix(Self.maxCount)), forKey: Self.storageKey)
    }
}
