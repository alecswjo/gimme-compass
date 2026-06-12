import CoreLocation
import XCTest
@testable import Gimme

final class GooglePlacesClientTests: XCTestCase {

    private var client: GooglePlacesClient!

    override func setUp() {
        super.setUp()
        client = GooglePlacesClient(apiKey: "test-key", session: StubURLProtocol.makeSession())
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func respond(status: Int, body: String) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
    }

    private static let fixture = """
    {
      "places": [
        {
          "id": "ChIJabc123",
          "displayName": { "text": "7-Eleven", "languageCode": "en" },
          "formattedAddress": "1601 Divisadero St, San Francisco, CA 94115",
          "location": { "latitude": 37.7842, "longitude": -122.4395 },
          "currentOpeningHours": { "openNow": true }
        },
        {
          "id": "ChIJdef456",
          "displayName": { "text": "Quick Stop" },
          "location": { "latitude": 37.79, "longitude": -122.44 }
        }
      ]
    }
    """

    // MARK: - Decoding

    func testDecodesPlacesFromFixture() async throws {
        respond(status: 200, body: Self.fixture)

        let places = try await client.searchNearest(matching: "convenience store", near: Fixtures.userCoordinate)

        XCTAssertEqual(places.count, 2)
        XCTAssertEqual(places[0].id, "ChIJabc123")
        XCTAssertEqual(places[0].name, "7-Eleven")
        XCTAssertEqual(places[0].address, "1601 Divisadero St, San Francisco, CA 94115")
        XCTAssertEqual(places[0].coordinate.latitude, 37.7842, accuracy: 0.0001)
        XCTAssertEqual(places[0].coordinate.longitude, -122.4395, accuracy: 0.0001)
        XCTAssertEqual(places[0].isOpenNow, true)
        // Optional fields really are optional:
        XCTAssertNil(places[1].address)
        XCTAssertNil(places[1].isOpenNow)
    }

    func testEmptyObjectDecodesAsNoResults() async throws {
        respond(status: 200, body: "{}")
        let places = try await client.searchNearest(matching: "zorbblefruit", near: Fixtures.userCoordinate)
        XCTAssertTrue(places.isEmpty)
    }

    // MARK: - Error mapping

    func testForbiddenMapsToAPIKeyInvalid() async {
        respond(status: 403, body: #"{"error": {"status": "PERMISSION_DENIED"}}"#)
        await assertThrows(.apiKeyInvalid)
    }

    func testBadRequestMapsToAPIKeyInvalid() async {
        respond(status: 400, body: "{}")
        await assertThrows(.apiKeyInvalid)
    }

    func testRateLimitMaps() async {
        respond(status: 429, body: "{}")
        await assertThrows(.rateLimited)
    }

    func testServerErrorMapsToSearchFailed() async {
        respond(status: 500, body: "{}")
        await assertThrows(.searchFailed)
    }

    func testTransportErrorMapsToOffline() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertThrows(.offline)
    }

    func testGarbageBodyMapsToSearchFailed() async {
        respond(status: 200, body: "not json")
        await assertThrows(.searchFailed)
    }

    private func assertThrows(_ expected: GimmeError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await client.searchNearest(matching: "x", near: Fixtures.userCoordinate)
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GimmeError, expected, file: file, line: line)
        }
    }

    // MARK: - Request shape (spec §4.3: endpoint, headers, minimal field mask, body)

    func testRequestShape() async throws {
        let captured = CapturedRequest()
        StubURLProtocol.handler = { request in
            captured.request = request
            captured.body = request.bodyBytes
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        _ = try await client.searchNearest(matching: "gas station", near: Fixtures.userCoordinate)

        let request = try XCTUnwrap(captured.request)
        XCTAssertEqual(request.url, GooglePlacesClient.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Api-Key"), "test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-FieldMask"), GooglePlacesClient.fieldMask)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let bodyData = try XCTUnwrap(captured.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(json["textQuery"] as? String, "gas station")
        XCTAssertEqual(json["rankPreference"] as? String, "DISTANCE")
        XCTAssertEqual(json["pageSize"] as? Int, GooglePlacesClient.pageSize)

        let bias = try XCTUnwrap(json["locationBias"] as? [String: Any])
        let circle = try XCTUnwrap(bias["circle"] as? [String: Any])
        XCTAssertEqual(circle["radius"] as? Double, GooglePlacesClient.biasRadiusMeters)
        let center = try XCTUnwrap(circle["center"] as? [String: Any])
        XCTAssertEqual(center["latitude"] as! Double, Fixtures.userCoordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(center["longitude"] as! Double, Fixtures.userCoordinate.longitude, accuracy: 0.0001)
    }
}

/// Reference box so the URLProtocol closure can hand the request back out.
private final class CapturedRequest: @unchecked Sendable {
    var request: URLRequest?
    var body: Data?
}
