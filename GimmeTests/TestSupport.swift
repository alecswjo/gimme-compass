import CoreLocation
import Foundation
@testable import Gimme

// MARK: - Location

final class MockLocationProvider: LocationProviding {
    let events: AsyncStream<LocationEvent>
    let continuation: AsyncStream<LocationEvent>.Continuation

    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var isHeadingAvailable = true
    var isReducedAccuracy = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var requestCount = 0

    init() {
        (events, continuation) = AsyncStream.makeStream(of: LocationEvent.self)
    }

    func requestWhenInUseAuthorization() { requestCount += 1 }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

// MARK: - Search

final class MockSearcher: PlaceSearching, @unchecked Sendable {
    /// Receives (1-based call index, query). Configure per test.
    var onSearch: @Sendable (Int, String) async throws -> [Place] = { _, _ in [] }

    private let lock = NSLock()
    private var _queries: [String] = []

    var queries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _queries
    }

    func searchNearest(matching query: String, near coordinate: CLLocationCoordinate2D) async throws -> [Place] {
        lock.lock()
        _queries.append(query)
        let call = _queries.count
        lock.unlock()
        return try await onSearch(call, query)
    }
}

// MARK: - Fixtures

enum Fixtures {
    static let userCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

    static func place(id: String = "p1", name: String = "7-Eleven", at coordinate: CLLocationCoordinate2D) -> Place {
        Place(id: id, name: name, coordinate: coordinate, address: "1 Test St", isOpenNow: true)
    }

    /// A CLLocation a given number of meters due north of a coordinate.
    static func location(metersNorthOf coordinate: CLLocationCoordinate2D, _ meters: Double) -> CLLocation {
        CLLocation(latitude: coordinate.latitude + meters / 111_195.0, longitude: coordinate.longitude)
    }
}

// MARK: - URLProtocol stub

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// URLSession hands URLProtocol the body as a stream, not `httpBody`.
    var bodyBytes: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
