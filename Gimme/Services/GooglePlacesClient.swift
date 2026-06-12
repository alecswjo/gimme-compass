import CoreLocation
import Foundation
import os

protocol PlaceSearching: Sendable {
    /// Returns places matching `query` ordered nearest-first relative to `coordinate`.
    func searchNearest(matching query: String, near coordinate: CLLocationCoordinate2D) async throws -> [Place]
}

/// Thin typed client for Google Places API (New) Text Search.
/// REST via URLSession on purpose — no SDK dependency (spec review, rejected
/// proposals). The field mask is deliberately minimal: Places bills per field tier.
struct GooglePlacesClient: PlaceSearching {

    static let endpoint = URL(string: "https://places.googleapis.com/v1/places:searchText")!
    static let fieldMask = "places.id,places.displayName,places.formattedAddress,places.location,places.currentOpeningHours.openNow"
    static let biasRadiusMeters: Double = 50_000 // API max; keeps rural areas working
    static let pageSize = 8

    let apiKey: String
    var session: URLSession = .shared

    private static let logger = Logger(subsystem: "ai.florafauna.gimme", category: "places")

    // MARK: - Wire types

    struct RequestBody: Encodable {
        struct LocationBias: Encodable {
            struct Circle: Encodable {
                struct Center: Encodable {
                    let latitude: Double
                    let longitude: Double
                }
                let center: Center
                let radius: Double
            }
            let circle: Circle
        }

        let textQuery: String
        let pageSize: Int
        let rankPreference: String
        let locationBias: LocationBias
    }

    struct ResponseBody: Decodable {
        struct PlaceDTO: Decodable {
            struct DisplayName: Decodable {
                let text: String
            }
            struct Location: Decodable {
                let latitude: Double
                let longitude: Double
            }
            struct OpeningHours: Decodable {
                let openNow: Bool?
            }

            let id: String
            let displayName: DisplayName
            let formattedAddress: String?
            let location: Location
            let currentOpeningHours: OpeningHours?
        }

        // Absent entirely when there are zero results: `{}` must decode as empty.
        let places: [PlaceDTO]?
    }

    // MARK: - PlaceSearching

    func searchNearest(matching query: String, near coordinate: CLLocationCoordinate2D) async throws -> [Place] {
        let body = RequestBody(
            textQuery: query,
            pageSize: Self.pageSize,
            rankPreference: "DISTANCE",
            locationBias: .init(circle: .init(
                center: .init(latitude: coordinate.latitude, longitude: coordinate.longitude),
                radius: Self.biasRadiusMeters
            ))
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Self.fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            Self.logger.error("Transport failure: \(urlError.code.rawValue)")
            throw GimmeError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw GimmeError.searchFailed
        }
        switch http.statusCode {
        case 200:
            break
        case 400, 403:
            let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
            Self.logger.error("Places rejected request (\(http.statusCode)): \(bodyText, privacy: .public)")
            throw GimmeError.apiKeyInvalid
        case 429:
            throw GimmeError.rateLimited
        default:
            Self.logger.error("Places HTTP \(http.statusCode)")
            throw GimmeError.searchFailed
        }

        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
            Self.logger.error("Places response failed to decode")
            throw GimmeError.searchFailed
        }

        return (decoded.places ?? []).map { dto in
            Place(
                id: dto.id,
                name: dto.displayName.text,
                coordinate: CLLocationCoordinate2D(latitude: dto.location.latitude, longitude: dto.location.longitude),
                address: dto.formattedAddress,
                isOpenNow: dto.currentOpeningHours?.openNow
            )
        }
    }
}
