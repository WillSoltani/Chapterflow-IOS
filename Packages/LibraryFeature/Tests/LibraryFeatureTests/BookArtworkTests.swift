import CoreGraphics
import Foundation
import ImageIO
import Models
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import LibraryFeature

@Suite("Book artwork loading and rendering", .serialized)
struct BookArtworkTests {
    @Test("URL validation accepts normalized public HTTPS URLs")
    func urlValidationAcceptsNormalizedHTTPS() throws {
        let artworkURL = try #require(BookArtworkURL("HTTPS://COVERS.Example.COM:443"))

        #expect(artworkURL.url.absoluteString == "https://covers.example.com/")
        #expect(BookArtworkURL("https://covers.example.com/books/cover.png") != nil)
    }

    @Test(
        "URL validation rejects non-HTTPS and credential-bearing URLs",
        arguments: [
            "http://covers.example.com/cover.png",
            "https://reader:secret@covers.example.com/cover.png",
            "https://covers.example.com/cover.png?X-Amz-Signature=private",
            "https://covers.example.com/cover.png#private-fragment",
            "https://",
            "covers.example.com/cover.png",
            "not a URL"
        ]
    )
    func urlValidationRejectsUnsafeValues(_ rawURL: String) async {
        ArtworkURLProtocol.state.reset { _ in
            ArtworkStubResponse(data: makePNG())
        }
        let loader = makeLoader()

        #expect(BookArtworkURL(rawURL) == nil)
        #expect(await loader.image(for: rawURL, pixelSize: CGSize(width: 40, height: 56)) == nil)
        #expect(ArtworkURLProtocol.state.requestCount == 0)
    }

    @Test("session configuration is bounded and excludes cookie and credential stores")
    func configurationIsBoundedAndPrivate() throws {
        let configuration = BookArtworkLoader.makeConfiguration()
        let cache = try #require(configuration.urlCache)

        #expect(cache.memoryCapacity == BookArtworkLoader.memoryCapacity)
        #expect(cache.diskCapacity == BookArtworkLoader.diskCapacity)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.httpAdditionalHeaders?["Accept"] as? String == "image/*")
    }

    @Test("successful response decodes and downsamples to the requested pixel bounds")
    func successfulResponseDownsamples() async throws {
        let png = makePNG(width: 200, height: 280)
        ArtworkURLProtocol.state.reset { _ in
            ArtworkStubResponse(data: png)
        }
        let loader = makeLoader()

        let image = try #require(await loader.image(
            for: artworkURL,
            pixelSize: CGSize(width: 40, height: 56)
        ))

        #expect(image.width == 40)
        #expect(image.height == 56)
        #expect(ArtworkURLProtocol.state.requestCount == 1)
    }

    @Test("non-success, invalid, and oversized bodies fail without becoming cache hits")
    func invalidResponsesFailClosed() async {
        ArtworkURLProtocol.state.reset { _ in
            ArtworkStubResponse(statusCode: 404, data: makePNG())
        }
        let statusLoader = makeLoader()
        #expect(await statusLoader.image(for: artworkURL, pixelSize: targetPixelSize) == nil)
        #expect(await statusLoader.image(for: artworkURL, pixelSize: targetPixelSize) == nil)
        #expect(ArtworkURLProtocol.state.requestCount == 2)

        ArtworkURLProtocol.state.reset { _ in
            ArtworkStubResponse(data: Data("not-an-image".utf8))
        }
        let invalidLoader = makeLoader()
        #expect(await invalidLoader.image(for: artworkURL, pixelSize: targetPixelSize) == nil)
        #expect(await invalidLoader.image(for: artworkURL, pixelSize: targetPixelSize) == nil)
        #expect(ArtworkURLProtocol.state.requestCount == 2)

        ArtworkURLProtocol.state.reset { _ in
            ArtworkStubResponse(
                data: Data(repeating: 0xA5, count: BookArtworkLoader.maximumEncodedResponseSize + 1)
            )
        }
        let oversizedLoader = makeLoader()
        #expect(await oversizedLoader.image(for: artworkURL, pixelSize: targetPixelSize) == nil)
        #expect(ArtworkURLProtocol.state.requestCount == 1)
    }

    @Test("simultaneous sizes share one transport and downsample independently")
    func concurrentRequestsCoalesceByURL() async throws {
        let networkGate = AsyncGate()
        let callerGate = AsyncGate()
        let png = makePNG(width: 200, height: 280)
        ArtworkURLProtocol.state.reset { _ in
            await networkGate.suspend()
            return ArtworkStubResponse(data: png)
        }
        let baseLoader = makeLoader()
        let loader = GatedArtworkLoader(base: baseLoader, gate: callerGate)

        let small = Task {
            await loader.image(for: artworkURL, pixelSize: CGSize(width: 20, height: 28))
        }
        let large = Task {
            await loader.image(for: artworkURL, pixelSize: CGSize(width: 40, height: 56))
        }

        await callerGate.waitForArrivals(2)
        await callerGate.open()
        await networkGate.waitForArrivals(1)
        await Task.yield()
        await networkGate.open()

        let smallImage = try #require(await small.value)
        let largeImage = try #require(await large.value)
        #expect(smallImage.width == 20)
        #expect(smallImage.height == 28)
        #expect(largeImage.width == 40)
        #expect(largeImage.height == 56)
        #expect(ArtworkURLProtocol.state.requestCount == 1)
    }

    @Test("a decoded response is reused from the bounded cache")
    func decodedResponseBecomesCacheHit() async throws {
        let png = makePNG(width: 200, height: 280)
        ArtworkURLProtocol.state.reset { _ in
            ArtworkStubResponse(data: png)
        }
        let loader = makeLoader()

        let first = try #require(await loader.image(
            for: artworkURL,
            pixelSize: CGSize(width: 40, height: 56)
        ))
        let second = try #require(await loader.image(
            for: artworkURL,
            pixelSize: CGSize(width: 20, height: 28)
        ))

        #expect(first.width == 40)
        #expect(second.width == 20)
        #expect(ArtworkURLProtocol.state.requestCount == 1)
    }

    @Test("cancelling one waiter does not poison another waiter or the cache")
    func cancellationIsIsolated() async throws {
        let networkGate = AsyncGate()
        let callerGate = AsyncGate()
        let png = makePNG(width: 200, height: 280)
        ArtworkURLProtocol.state.reset { _ in
            await networkGate.suspend()
            return ArtworkStubResponse(data: png)
        }
        let baseLoader = makeLoader()
        let loader = GatedArtworkLoader(base: baseLoader, gate: callerGate)

        let cancelledWaiter = Task {
            await loader.image(for: artworkURL, pixelSize: targetPixelSize)
        }
        let survivingWaiter = Task {
            await loader.image(for: artworkURL, pixelSize: targetPixelSize)
        }

        await callerGate.waitForArrivals(2)
        await callerGate.open()
        await networkGate.waitForArrivals(1)
        await Task.yield()
        cancelledWaiter.cancel()
        await networkGate.open()

        #expect(await cancelledWaiter.value == nil)
        #expect(try #require(await survivingWaiter.value).width == 40)
        #expect(try #require(await baseLoader.image(for: artworkURL, pixelSize: targetPixelSize)).width == 40)
        #expect(ArtworkURLProtocol.state.requestCount == 1)
    }

    @Test("artwork requests never contain authorization or cookie headers")
    func requestOmitsPrivateHeaders() async throws {
        ArtworkURLProtocol.state.reset { _ in
            ArtworkStubResponse(data: makePNG())
        }
        let loader = makeLoader()

        _ = try #require(await loader.image(for: artworkURL, pixelSize: targetPixelSize))
        let request = try #require(ArtworkURLProtocol.state.requests.first)

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "image/*")
    }

    @MainActor
    @Test("newer URL state wins when an older load completes last")
    func staleCompletionCannotPublishWrongArtwork() async throws {
        let oldGate = AsyncGate()
        let oldImage = makeCGImage(width: 20, height: 28, red: 220, green: 40, blue: 40)
        let newImage = makeCGImage(width: 30, height: 42, red: 40, green: 80, blue: 220)
        let oldURL = "https://covers.example.test/old.png"
        let newURL = "https://covers.example.test/new.png"
        let loader = ClosureArtworkLoader { rawURL, _ in
            if rawURL == oldURL {
                await oldGate.suspend()
                return oldImage
            }
            return newImage
        }
        let state = BookArtworkViewState()
        let oldRequest = BookArtworkRequest(rawURL: oldURL, pixelWidth: 20, pixelHeight: 28)
        let newRequest = BookArtworkRequest(rawURL: newURL, pixelWidth: 30, pixelHeight: 42)

        let oldLoad = Task {
            await state.load(request: oldRequest, using: loader)
        }
        await oldGate.waitForArrivals(1)
        await state.load(request: newRequest, using: loader)
        await oldGate.open()
        await oldLoad.value

        let published = try #require(state.image(for: newRequest))
        #expect(published.width == 30)
        #expect(published.height == 42)
        #expect(state.image(for: oldRequest) == nil)
        #expect(state.publishedRequest == newRequest)
    }

    @MainActor
    @Test("loading and failure keep the generated fallback state visible")
    func loadingAndFailureRemainFallback() async throws {
        let failureGate = AsyncGate()
        let request = BookArtworkRequest(rawURL: artworkURL, pixelWidth: 40, pixelHeight: 56)
        let state = BookArtworkViewState()
        state.seed(image: makeCGImage(width: 40, height: 56), for: request)
        let loader = ClosureArtworkLoader { _, _ in
            await failureGate.suspend()
            return nil
        }

        let load = Task {
            await state.load(request: request, using: loader)
        }
        await failureGate.waitForArrivals(1)

        #expect(state.image(for: request) == nil)
        #expect(state.publishedRequest == nil)

        await failureGate.open()
        await load.value
        #expect(state.image(for: request) == nil)
        #expect(state.publishedRequest == nil)
    }

    @MainActor
    @Test("remote cover renders at exact dimensions with transparent rounded corners")
    func remoteArtworkRenderGeometry() throws {
        let size: CGFloat = 50
        let rawURL = artworkURL
        let request = BookArtworkRequest(rawURL: rawURL, pixelWidth: 50, pixelHeight: 70)
        let artwork = makeCGImage(width: 100, height: 140, red: 35, green: 120, blue: 210)
        let state = BookArtworkViewState()
        state.seed(image: artwork, for: request)
        let loader = ClosureArtworkLoader { _, _ in artwork }
        let view = BookCoverView(
            cover: Cover(emoji: "📘", color: "#336699"),
            coverImageURL: rawURL,
            size: size,
            artworkLoader: loader,
            artworkState: state
        )
        .environment(\.displayScale, 1)

        let rendered = try #require(renderCGImage(view))
        #expect(rendered.width == 50)
        #expect(rendered.height == 70)
        #expect(alpha(in: rendered, x: 0, y: 0) == 0)
        #expect(alpha(in: rendered, x: rendered.width / 2, y: rendered.height / 2) > 0)
    }

    @MainActor
    @Test("fallback cover renders in Light, Dark, and AX5 environments")
    func fallbackRenderMatrix() throws {
        let cover = Cover(emoji: "📚", color: "#745B45")
        let loader = ClosureArtworkLoader { _, _ in nil }
        let variants: [(String, AnyView)] = [
            (
                "Light",
                AnyView(BookCoverView(cover: cover, coverImageURL: nil, size: 50, artworkLoader: loader)
                    .environment(\.colorScheme, .light))
            ),
            (
                "Dark",
                AnyView(BookCoverView(cover: cover, coverImageURL: nil, size: 50, artworkLoader: loader)
                    .environment(\.colorScheme, .dark))
            ),
            (
                "AX5",
                AnyView(BookCoverView(cover: cover, coverImageURL: nil, size: 50, artworkLoader: loader)
                    .environment(\.dynamicTypeSize, .accessibility5))
            )
        ]

        for (name, view) in variants {
            let rendered = try #require(renderCGImage(view), "\(name) fallback did not render")
            #expect(rendered.width == 50, "\(name) width changed")
            #expect(rendered.height == 70, "\(name) height changed")
            #expect(alpha(in: rendered, x: rendered.width / 2, y: rendered.height / 2) > 0)
        }
    }
}

private let artworkURL = "https://covers.example.test/books/cover.png"
private let targetPixelSize = CGSize(width: 40, height: 56)

private struct ArtworkStubResponse: Sendable {
    let statusCode: Int
    let data: Data
    let headers: [String: String]

    init(
        statusCode: Int = 200,
        data: Data,
        headers: [String: String] = ["Content-Type": "image/png"]
    ) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }
}

private final class ArtworkURLProtocolState: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> ArtworkStubResponse
    /// The lock protects the mutable handler and captured request log. The handler
    /// is copied while locked, then awaited only after the critical section ends.
    private let lock = NSLock()
    private var handler: Handler?
    private var capturedRequests: [URLRequest] = []
    var requestCount: Int {
        lock.withLock { capturedRequests.count }
    }
    var requests: [URLRequest] {
        lock.withLock { capturedRequests }
    }
    func reset(handler: @escaping Handler) {
        lock.withLock {
            capturedRequests = []
            self.handler = handler
        }
    }
    func response(for request: URLRequest) async throws -> ArtworkStubResponse {
        let currentHandler = lock.withLock {
            capturedRequests.append(request)
            return handler
        }
        guard let currentHandler else {
            throw URLError(.resourceUnavailable)
        }
        return try await currentHandler(request)
    }
}

private final class ArtworkURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = ArtworkURLProtocolState()

    private let taskLock = NSLock()
    private var responseTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let operation = ArtworkURLProtocolOperation(owner: self, request: request)
        let task = Task {
            await operation.run()
        }
        taskLock.withLock {
            responseTask = task
        }
    }

    override func stopLoading() {
        let task = taskLock.withLock {
            let task = responseTask
            responseTask = nil
            return task
        }
        task?.cancel()
    }
}

private final class ArtworkURLProtocolOperation: @unchecked Sendable {
    private let owner: ArtworkURLProtocol
    private let request: URLRequest

    init(owner: ArtworkURLProtocol, request: URLRequest) {
        self.owner = owner
        self.request = request
    }

    func run() async {
        do {
            let stub = try await ArtworkURLProtocol.state.response(for: request)
            try Task.checkCancellation()
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: stub.statusCode,
                      httpVersion: "HTTP/1.1",
                      headerFields: stub.headers
                  ) else {
                throw URLError(.badServerResponse)
            }
            owner.client?.urlProtocol(owner, didReceive: response, cacheStoragePolicy: .notAllowed)
            owner.client?.urlProtocol(owner, didLoad: stub.data)
            owner.client?.urlProtocolDidFinishLoading(owner)
        } catch is CancellationError {
            return
        } catch {
            owner.client?.urlProtocol(owner, didFailWithError: error)
        }
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var arrivals = 0
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func suspend() async {
        arrivals += 1
        resumeSatisfiedArrivalWaiters()
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitForArrivals(_ count: Int) async {
        guard arrivals < count else { return }
        await withCheckedContinuation { continuation in
            arrivalWaiters.append((count, continuation))
        }
    }

    func open() {
        isOpen = true
        let waiters = releaseWaiters
        releaseWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func resumeSatisfiedArrivalWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in arrivalWaiters {
            if arrivals >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        arrivalWaiters = remaining
    }
}

private struct GatedArtworkLoader: BookArtworkLoading {
    let base: BookArtworkLoader
    let gate: AsyncGate

    func image(for rawURL: String, pixelSize: CGSize) async -> CGImage? {
        await gate.suspend()
        return await base.image(for: rawURL, pixelSize: pixelSize)
    }
}

private struct ClosureArtworkLoader: BookArtworkLoading {
    let operation: @Sendable (String, CGSize) async -> CGImage?

    init(operation: @escaping @Sendable (String, CGSize) async -> CGImage?) {
        self.operation = operation
    }

    func image(for rawURL: String, pixelSize: CGSize) async -> CGImage? {
        await operation(rawURL, pixelSize)
    }
}

private func makeLoader() -> BookArtworkLoader {
    let cache = URLCache(
        memoryCapacity: BookArtworkLoader.memoryCapacity,
        diskCapacity: 0
    )
    let configuration = BookArtworkLoader.makeConfiguration(
        cache: cache,
        protocolClasses: [ArtworkURLProtocol.self]
    )
    return BookArtworkLoader(configuration: configuration)
}

private func makePNG(width: Int = 80, height: Int = 112) -> Data {
    let image = makeCGImage(width: width, height: height)
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        Issue.record("Could not create PNG destination")
        return Data()
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        Issue.record("Could not finalize PNG fixture")
        return Data()
    }
    return data as Data
}

private func makeCGImage(
    width: Int,
    height: Int,
    red: UInt8 = 70,
    green: UInt8 = 130,
    blue: UInt8 = 190
) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        fatalError("Could not create image fixture context")
    }
    context.setFillColor(
        red: CGFloat(red) / 255,
        green: CGFloat(green) / 255,
        blue: CGFloat(blue) / 255,
        alpha: 1
    )
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else {
        fatalError("Could not create image fixture")
    }
    return image
}

@MainActor
private func renderCGImage(_ view: some View) -> CGImage? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    return renderer.cgImage
}

private func alpha(in image: CGImage, x: Int, y: Int) -> UInt8 {
    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(
            data: bytes.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )
        context?.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
    }
    return pixels[(y * bytesPerRow) + (x * 4) + 3]
}
