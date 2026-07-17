#if DEBUG
import Foundation

/// A ``URLProtocol`` subclass that intercepts ALL HTTP/HTTPS requests during
/// XCUITest runs and serves deterministic, fixture-backed responses.
///
/// Registered at app launch when ``CF_STUB_SERVER=1`` is set in the
/// test's ``launchEnvironment``. Never compiled into release builds.
@objc(CFStubURLProtocol)
nonisolated final class CFStubURLProtocol: URLProtocol, @unchecked Sendable {

    private enum Lifecycle {
        case pending
        case delivering
        case stopped
    }

    private final class DelayedDeliveryOperation: @unchecked Sendable {
        private weak var owner: CFStubURLProtocol?
        private let response: CFStubRoutes.Response
        private let delayMilliseconds: Int

        init(
            owner: CFStubURLProtocol,
            response: CFStubRoutes.Response,
            delayMilliseconds: Int
        ) {
            self.owner = owner
            self.response = response
            self.delayMilliseconds = delayMilliseconds
        }

        func run() async {
            do {
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            owner?.deliver(response)
        }
    }

    /// `URLProtocol` may invoke lifecycle callbacks from different threads. The
    /// lock is the synchronization invariant for the mutable task/lifecycle pair.
    private let stateLock = NSLock()
    private var lifecycle = Lifecycle.pending
    private var delayedDelivery: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path   = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        if let response = CFStubRoutes.response(for: path, method: method) {
            let delay = response.contentType == "image/png" ? artworkDelayMilliseconds : 0
            guard delay > 0 else {
                deliver(response)
                return
            }

            let operation = DelayedDeliveryOperation(
                owner: self,
                response: response,
                delayMilliseconds: delay
            )
            let task = Task {
                await operation.run()
            }
            stateLock.lock()
            let shouldKeepTask = lifecycle == .pending
            if shouldKeepTask {
                delayedDelivery = task
            }
            stateLock.unlock()
            if !shouldKeepTask {
                task.cancel()
            }
        } else {
            let body = #"{"error":{"code":"not_found","message":"Stub: no route for \#(path)"}}"#
            deliver(CFStubRoutes.Response(
                statusCode: 404,
                body: body.data(using: .utf8) ?? Data(),
                contentType: "application/json",
                cachePolicy: .notAllowed
            ))
        }
    }

    override func stopLoading() {
        stateLock.lock()
        if lifecycle == .pending {
            lifecycle = .stopped
        }
        let task = delayedDelivery
        delayedDelivery = nil
        stateLock.unlock()
        task?.cancel()
    }

    private var artworkDelayMilliseconds: Int {
        let rawValue = ProcessInfo.processInfo.environment["CF_STUB_ARTWORK_DELAY_MS"] ?? "0"
        return min(max(Int(rawValue) ?? 0, 0), 60_000)
    }

    private func deliver(_ response: CFStubRoutes.Response) {
        stateLock.lock()
        guard lifecycle == .pending else {
            stateLock.unlock()
            return
        }
        lifecycle = .delivering
        delayedDelivery = nil
        stateLock.unlock()

        guard let url = request.url,
              let httpResponse = HTTPURLResponse(
                  url: url,
                  statusCode: response.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: [
                      "Content-Type": response.contentType,
                      "Content-Length": String(response.body.count),
                      "Cache-Control": response.cachePolicy == .allowed
                          ? "public, max-age=3600"
                          : "no-store",
                  ]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let storagePolicy: URLCache.StoragePolicy = response.cachePolicy == .allowed
            ? .allowed
            : .notAllowed
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: storagePolicy)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
#endif
