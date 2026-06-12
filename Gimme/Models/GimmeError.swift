import Foundation

/// Every failure the UI can show. Human copy lives here; transport detail goes
/// to the logger, never to the user (spec §3.6, §7).
enum GimmeError: Error, Equatable {
    case offline
    case apiKeyInvalid
    case rateLimited
    case searchFailed

    var userMessage: String {
        switch self {
        case .offline:
            "Can't reach the internet. Check your connection and try again."
        case .apiKeyInvalid:
            "Search isn't set up correctly. (Places API key was rejected.)"
        case .rateLimited:
            "Too many searches right now. Give it a few seconds."
        case .searchFailed:
            "Something went wrong looking that up. Try again."
        }
    }
}
