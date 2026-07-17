import CoreGraphics
import Foundation
import ImageIO

protocol BookArtworkLoading: Sendable {
    func image(for rawURL: String, pixelSize: CGSize) async -> CGImage?
}

struct BookArtworkURL: Hashable, Sendable {
    let url: URL

    init?(_ rawValue: String) {
        guard var components = URLComponents(string: rawValue),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }

        components.scheme = "https"
        components.host = host
        if components.port == 443 {
            components.port = nil
        }
        if components.path.isEmpty {
            components.path = "/"
        }

        guard let normalizedURL = components.url else { return nil }
        url = normalizedURL
    }
}

actor BookArtworkLoader: BookArtworkLoading {
    static let memoryCapacity = 24 * 1_024 * 1_024
    static let diskCapacity = 128 * 1_024 * 1_024
    static let maximumEncodedResponseSize = 8 * 1_024 * 1_024
    static let shared = BookArtworkLoader()

    private struct InFlight: Sendable {
        let id: UUID
        let task: Task<BookArtworkPayload, Error>
    }

    private let cache: URLCache
    private let transport: BookArtworkTransport
    private var inFlight: [BookArtworkURL: InFlight] = [:]

    init(configuration: URLSessionConfiguration? = nil) {
        let resolvedConfiguration = configuration ?? Self.makeConfiguration()
        let resolvedCache = resolvedConfiguration.urlCache ?? URLCache(
            memoryCapacity: Self.memoryCapacity,
            diskCapacity: Self.diskCapacity
        )
        resolvedConfiguration.urlCache = resolvedCache
        cache = resolvedCache
        transport = BookArtworkTransport(
            configuration: resolvedConfiguration,
            maximumResponseSize: Self.maximumEncodedResponseSize
        )
    }

    func image(for rawURL: String, pixelSize: CGSize) async -> CGImage? {
        guard let artworkURL = BookArtworkURL(rawURL),
              pixelSize.width > 0,
              pixelSize.height > 0 else {
            return nil
        }

        let request = Self.makeRequest(for: artworkURL.url)

        if let cachedResponse = cache.cachedResponse(for: request) {
            if let image = Self.downsample(cachedResponse.data, to: pixelSize) {
                return image
            }
            cache.removeCachedResponse(for: request)
        }

        let flight: InFlight
        if let existing = inFlight[artworkURL] {
            flight = existing
        } else {
            let task = Task { [transport] in
                try await transport.payload(for: request)
            }
            flight = InFlight(id: UUID(), task: task)
            inFlight[artworkURL] = flight
        }

        do {
            let payload = try await flight.task.value
            if inFlight[artworkURL]?.id == flight.id {
                inFlight[artworkURL] = nil
            }
            try Task.checkCancellation()

            guard let image = Self.downsample(payload.data, to: pixelSize) else {
                return nil
            }

            cache.storeCachedResponse(
                CachedURLResponse(
                    response: payload.response,
                    data: payload.data,
                    storagePolicy: .allowed
                ),
                for: request
            )
            return image
        } catch {
            if inFlight[artworkURL]?.id == flight.id,
               flight.task.isCancelled || !Task.isCancelled {
                inFlight[artworkURL] = nil
            }
            return nil
        }
    }

    static func makeConfiguration(
        cache: URLCache? = nil,
        protocolClasses: [AnyClass]? = nil
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache ?? URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity
        )
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = ["Accept": "image/*"]
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        var resolvedProtocolClasses = protocolClasses
        #if DEBUG
        if resolvedProtocolClasses == nil,
           ProcessInfo.processInfo.environment["CF_STUB_SERVER"] == "1",
           let stubProtocolClass = NSClassFromString("CFStubURLProtocol") {
            // Global URLProtocol registration does not propagate to newly
            // constructed URLSession instances on current Foundation releases.
            resolvedProtocolClasses = [stubProtocolClass]
        }
        #endif
        if let resolvedProtocolClasses {
            configuration.protocolClasses = resolvedProtocolClasses
        }
        return configuration
    }

    private static func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        request.setValue(nil, forHTTPHeaderField: "Cookie")
        return request
    }

    private static func downsample(_ data: Data, to pixelSize: CGSize) -> CGImage? {
        guard !data.isEmpty,
              data.count <= maximumEncodedResponseSize,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let maximumPixelDimension = max(1, Int(ceil(max(pixelSize.width, pixelSize.height))))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

private struct BookArtworkPayload: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

private enum BookArtworkTransportError: Error {
    case invalidResponse
    case responseTooLarge
    case unacceptableStatus
    case unsafeRedirect
}

private final class BookArtworkTransport: NSObject, @unchecked Sendable {
    private let delegate: BookArtworkSessionDelegate
    private let session: URLSession

    init(configuration: URLSessionConfiguration, maximumResponseSize: Int) {
        let delegate = BookArtworkSessionDelegate(maximumResponseSize: maximumResponseSize)
        self.delegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        super.init()
    }

    func payload(for request: URLRequest) async throws -> BookArtworkPayload {
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.register(task, continuation: continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

private final class BookArtworkSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Pending {
        var data = Data()
        var response: HTTPURLResponse?
        let continuation: CheckedContinuation<BookArtworkPayload, Error>
    }

    /// All access to `pending` is serialized by `lock`; continuations are removed
    /// exactly once and resumed only after the lock has been released.
    private let lock = NSLock()
    private let maximumResponseSize: Int
    private var pending: [Int: Pending] = [:]

    init(maximumResponseSize: Int) {
        self.maximumResponseSize = maximumResponseSize
    }

    func register(
        _ task: URLSessionDataTask,
        continuation: CheckedContinuation<BookArtworkPayload, Error>
    ) {
        lock.withLock {
            pending[task.taskIdentifier] = Pending(continuation: continuation)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let finalURL = httpResponse.url,
              BookArtworkURL(finalURL.absoluteString) != nil else {
            finish(
                taskIdentifier: dataTask.taskIdentifier,
                result: .failure(
                    (response as? HTTPURLResponse).map { _ in
                        BookArtworkTransportError.unacceptableStatus
                    } ?? BookArtworkTransportError.invalidResponse
                )
            )
            completionHandler(.cancel)
            return
        }

        if httpResponse.expectedContentLength > Int64(maximumResponseSize) {
            finish(
                taskIdentifier: dataTask.taskIdentifier,
                result: .failure(BookArtworkTransportError.responseTooLarge)
            )
            completionHandler(.cancel)
            return
        }

        lock.withLock {
            pending[dataTask.taskIdentifier]?.response = httpResponse
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var failure: Pending?
        lock.withLock {
            guard var value = pending[dataTask.taskIdentifier] else { return }
            guard value.data.count <= maximumResponseSize - data.count else {
                failure = pending.removeValue(forKey: dataTask.taskIdentifier)
                return
            }
            value.data.append(data)
            pending[dataTask.taskIdentifier] = value
        }

        if let failure {
            failure.continuation.resume(throwing: BookArtworkTransportError.responseTooLarge)
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        let value = lock.withLock {
            pending.removeValue(forKey: task.taskIdentifier)
        }
        guard let value else { return }

        if let error {
            value.continuation.resume(throwing: error)
        } else if let response = value.response {
            value.continuation.resume(returning: BookArtworkPayload(data: value.data, response: response))
        } else {
            value.continuation.resume(throwing: BookArtworkTransportError.invalidResponse)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let rawURL = request.url?.absoluteString,
              BookArtworkURL(rawURL) != nil else {
            finish(
                taskIdentifier: task.taskIdentifier,
                result: .failure(BookArtworkTransportError.unsafeRedirect)
            )
            completionHandler(nil)
            return
        }

        var sanitizedRequest = request
        sanitizedRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        sanitizedRequest.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(sanitizedRequest)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        willCacheResponse proposedResponse: CachedURLResponse,
        completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func finish(taskIdentifier: Int, result: Result<BookArtworkPayload, Error>) {
        let value = lock.withLock {
            pending.removeValue(forKey: taskIdentifier)
        }
        guard let value else { return }

        switch result {
        case .success(let payload):
            value.continuation.resume(returning: payload)
        case .failure(let error):
            value.continuation.resume(throwing: error)
        }
    }
}
