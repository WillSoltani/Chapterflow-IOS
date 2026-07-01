import Foundation
import CoreKit

/// An in-memory ``APIClientProtocol`` for previews and unit tests, so feature
/// packages can be exercised without a live network.
///
/// Configure it by stubbing responses per path (or a single default), then
/// inspect ``recordedEndpoints`` to assert on what a feature requested.
public actor MockAPIClient: APIClientProtocol {
    /// A stubbed outcome for a request.
    public enum Stub: Sendable {
        /// A success body (raw JSON object) to decode into the requested type.
        case success(Data)
        /// A typed failure to throw.
        case failure(AppError)
    }

    private var routes: [String: Stub] = [:]
    private var fallback: Stub?

    /// Every endpoint the mock has been asked to send, in order.
    public private(set) var recordedEndpoints: [Endpoint] = []

    public init() {}

    /// Stubs a raw JSON body for requests to `path`.
    public func setStub(_ stub: Stub, for path: String) {
        routes[path] = stub
    }

    /// Stubs an `Encodable` value (encoded with ``JSONCoding/encoder``) as the
    /// success body for `path`.
    public func setStub<Value: Encodable>(_ value: Value, for path: String) throws {
        routes[path] = .success(try JSONCoding.encoder.encode(value))
    }

    /// Sets the outcome used when no per-path stub matches.
    public func setDefault(_ stub: Stub) {
        fallback = stub
    }

    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        recordedEndpoints.append(endpoint)
        guard let stub = routes[endpoint.path] ?? fallback else {
            throw AppError.notFound
        }
        switch stub {
        case .success(let data):
            do {
                return try JSONCoding.decoder.decode(T.self, from: data)
            } catch {
                throw AppError.decoding(error)
            }
        case .failure(let error):
            throw error
        }
    }
}
