#if DEBUG
import Foundation

/// A ``URLProtocol`` subclass that intercepts ALL HTTP/HTTPS requests during
/// XCUITest runs and serves deterministic, fixture-backed responses.
///
/// Registered at app launch when ``CF_STUB_SERVER=1`` is set in the
/// test's ``launchEnvironment``. Never compiled into release builds.
final class CFStubURLProtocol: URLProtocol, @unchecked Sendable {

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path   = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        if let (status, body) = CFStubRoutes.response(for: path, method: method) {
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            // Unknown path → 404
            let notFound = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = #"{"error":{"code":"not_found","message":"Stub: no route for \#(path)"}}"#
            client?.urlProtocol(self, didReceive: notFound, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body.data(using: .utf8) ?? Data())
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
#endif
