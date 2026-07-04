import Foundation
import CoreKit
import Networking

// MARK: - Protocol

/// Registers and unregisters APNs device tokens with the ChapterFlow backend
/// (POST /book/me/devices/register and /book/me/devices/unregister).
///
/// Implementations must be `Sendable` so they can be called from any actor context.
public protocol DeviceRegistrationRepository: Sendable {
    /// Registers an APNs device token with the backend.
    /// Safe to call repeatedly — the server upserts by (userId, token).
    func register(apnsToken: String) async
    /// Removes an APNs device token from the backend.
    /// Safe to call even if the token was never registered.
    func unregister(apnsToken: String) async
}

// MARK: - Live implementation

/// Production implementation backed by `APIClient`.
public struct LiveDeviceRegistrationRepository: DeviceRegistrationRepository {

    private let apiClient: any APIClientProtocol
    private let log = AppLog(category: .notifications)

    public init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    public func register(apnsToken: String) async {
        do {
            let endpoint = try Endpoints.registerDevice(
                apnsToken: apnsToken,
                bundleId: Bundle.main.bundleIdentifier ?? "com.chapterflow.ios",
                locale: Locale.current.identifier,
                timeZone: TimeZone.current.identifier
            )
            let _: DeviceRegistrationResponse = try await apiClient.send(endpoint)
            log.info("APNs token registered with backend")
        } catch {
            log.error("APNs token registration failed: \(error.localizedDescription)")
        }
    }

    public func unregister(apnsToken: String) async {
        do {
            let endpoint = try Endpoints.unregisterDevice(apnsToken: apnsToken)
            let _: DeviceRegistrationResponse = try await apiClient.send(endpoint)
            log.info("APNs token unregistered from backend")
        } catch {
            log.error("APNs token unregistration failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Fake (for tests / previews)

/// In-memory fake for unit tests and SwiftUI previews.
public final class FakeDeviceRegistrationRepository: DeviceRegistrationRepository, @unchecked Sendable {
    public private(set) var registeredTokens: [String] = []
    public private(set) var unregisteredTokens: [String] = []

    public init() {}

    public func register(apnsToken: String) async {
        registeredTokens.append(apnsToken)
    }

    public func unregister(apnsToken: String) async {
        unregisteredTokens.append(apnsToken)
    }
}

// MARK: - Wire response

/// The server returns a minimal acknowledgement; we decode it leniently.
private struct DeviceRegistrationResponse: Decodable, Sendable {}
