import Foundation
import os

#if canImport(UIKit)
import UIKit
#endif

/// Closed, value-free categories that may stop required storage bootstrap.
public enum AppBootstrapStorageFailureCategory: Equatable, Sendable {
    case protectedDataUnavailable
    case persistentStoreOpenOrMigration
    case requiredFileStore
    case unavailable
}

/// Stable support identifiers for storage bootstrap failures. They carry no
/// path, account, book, schema, or underlying-error data.
public enum AppBootstrapStorageSupportCode: String, Equatable, Sendable {
    case protectedDataUnavailable = "CF-BOOT-STORAGE-PROTECTED-001"
    case persistentStoreOpenOrMigration = "CF-BOOT-STORAGE-STORE-001"
    case requiredFileStore = "CF-BOOT-STORAGE-FILES-001"
    case unavailable = "CF-BOOT-STORAGE-UNAVAILABLE-001"
}

/// A privacy-safe storage bootstrap failure. Raw persistence and filesystem
/// errors are intentionally neither retained nor reflected into the UI.
public struct AppBootstrapStorageFailure: Equatable, Sendable {
    public let category: AppBootstrapStorageFailureCategory
    public let supportCode: AppBootstrapStorageSupportCode
    public let isRetryMeaningful: Bool

    public init(category: AppBootstrapStorageFailureCategory) {
        self.category = category
        switch category {
        case .protectedDataUnavailable:
            supportCode = .protectedDataUnavailable
            isRetryMeaningful = false
        case .persistentStoreOpenOrMigration:
            supportCode = .persistentStoreOpenOrMigration
            isRetryMeaningful = true
        case .requiredFileStore:
            supportCode = .requiredFileStore
            isRetryMeaningful = true
        case .unavailable:
            supportCode = .unavailable
            isRetryMeaningful = true
        }
    }
}

/// Closed startup milestones emitted without dynamic metadata. Their timestamps
/// provide launch timing in Instruments while keeping storage and user data out
/// of logs and signposts.
public enum AppBootstrapPhase: Equatable, Sendable {
    case bootstrapStarted
    case firstLaunchViewAvailable
    case protectedDataWaiting
    case protectedDataBecameAvailable
    case persistenceOpenStarted
    case persistenceOpenCompleted
    case requiredSessionSetupStarted
    case requiredSessionSetupCompleted
    case readyPublished
    case invalidConfigurationFailed
    case persistentStoreOpenOrMigrationFailed
    case requiredFileStoreFailed
    case storageUnavailableFailed
    case requiredSessionSetupFailed
}

@MainActor
protocol AppBootstrapPhaseRecording: Sendable {
    func record(_ phase: AppBootstrapPhase) throws
}

struct NoopAppBootstrapPhaseRecorder: AppBootstrapPhaseRecording {
    func record(_ phase: AppBootstrapPhase) throws {}
}

/// Instruments recorder using fixed event names and no interpolated metadata.
/// Signpost emission is best effort at the coordinator boundary.
struct SignpostAppBootstrapPhaseRecorder: AppBootstrapPhaseRecording {
    private let signposter = OSSignposter(
        subsystem: "com.chapterflow.ios",
        category: "Bootstrap"
    )

    func record(_ phase: AppBootstrapPhase) throws {
        switch phase {
        case .bootstrapStarted:
            signposter.emitEvent("BootstrapStarted")
        case .firstLaunchViewAvailable:
            signposter.emitEvent("FirstLaunchViewAvailable")
        case .protectedDataWaiting:
            signposter.emitEvent("ProtectedDataWaiting")
        case .protectedDataBecameAvailable:
            signposter.emitEvent("ProtectedDataBecameAvailable")
        case .persistenceOpenStarted:
            signposter.emitEvent("PersistenceOpenStarted")
        case .persistenceOpenCompleted:
            signposter.emitEvent("PersistenceOpenCompleted")
        case .requiredSessionSetupStarted:
            signposter.emitEvent("RequiredSessionSetupStarted")
        case .requiredSessionSetupCompleted:
            signposter.emitEvent("RequiredSessionSetupCompleted")
        case .readyPublished:
            signposter.emitEvent("ReadyPublished")
        case .invalidConfigurationFailed:
            signposter.emitEvent("InvalidConfigurationFailed")
        case .persistentStoreOpenOrMigrationFailed:
            signposter.emitEvent("PersistentStoreOpenOrMigrationFailed")
        case .requiredFileStoreFailed:
            signposter.emitEvent("RequiredFileStoreFailed")
        case .storageUnavailableFailed:
            signposter.emitEvent("StorageUnavailableFailed")
        case .requiredSessionSetupFailed:
            signposter.emitEvent("RequiredSessionSetupFailed")
        }
    }
}

@MainActor
protocol ProtectedDataAvailabilityProviding: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func waitUntilAvailable() async
}

#if canImport(UIKit)
@MainActor
final class SystemProtectedDataAvailabilityProvider: ProtectedDataAvailabilityProviding {
    var isAvailable: Bool {
        UIApplication.shared.isProtectedDataAvailable
    }

    func waitUntilAvailable() async {
        let registration = ProtectedDataWaitRegistration()
        await registration.wait()
    }
}

@MainActor
private final class ProtectedDataWaitRegistration {
    private var continuation: CheckedContinuation<Void, Never>?
    private var token: (any NSObjectProtocol)?

    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                token = NotificationCenter.default.addObserver(
                    forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.finish()
                    }
                }

                // Register first, then recheck, closing the unlock race without
                // polling. Cancellation also consumes this one-shot observer.
                if UIApplication.shared.isProtectedDataAvailable || Task.isCancelled {
                    finish()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish()
            }
        }
    }

    private func finish() {
        if let token {
            NotificationCenter.default.removeObserver(token)
            self.token = nil
        }
        continuation?.resume()
        continuation = nil
    }
}
#else
@MainActor
final class SystemProtectedDataAvailabilityProvider: ProtectedDataAvailabilityProviding {
    /// Host-only package builds do not model iOS data protection. Device and
    /// Simulator evidence is required for the live UIKit source.
    var isAvailable: Bool { true }

    func waitUntilAvailable() async {}
}
#endif
