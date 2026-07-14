import AuthKit
import CoreKit
import Persistence
@testable import AppFeature

actor ControlledPersistenceLoader: AppPersistenceLoading {
    private struct Waiter {
        let target: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var pending: [Int: CheckedContinuation<AppPersistenceResources, any Error>] = [:]
    private var waiters: [Waiter] = []
    private(set) var callCount = 0

    func load() async throws -> AppPersistenceResources {
        callCount += 1
        let call = callCount
        resumeSatisfiedWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            pending[call] = continuation
        }
    }

    func waitForCallCount(_ target: Int) async {
        guard callCount < target else { return }
        await withCheckedContinuation { continuation in
            waiters.append(Waiter(target: target, continuation: continuation))
        }
    }

    func succeed(call: Int, with resources: AppPersistenceResources) {
        pending.removeValue(forKey: call)?.resume(returning: resources)
    }

    func fail(call: Int, with error: any Error & Sendable) {
        pending.removeValue(forKey: call)?.resume(throwing: error)
    }

    private func resumeSatisfiedWaiters() {
        while let index = waiters.firstIndex(where: { $0.target <= callCount }) {
            waiters.remove(at: index).continuation.resume()
        }
    }
}

@MainActor
final class RecordingGraphFactory: AppGraphFactory {
    private let shouldFail: Bool
    private(set) var attemptCount = 0
    private(set) var models: [AppModel] = []
    private(set) var receivedContainer: AnyObject?

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func makeConfiguredGraph(
        config: ValidatedAppConfig,
        persistence: AppPersistenceResources
    ) throws -> AppModel {
        attemptCount += 1
        receivedContainer = persistence.controller.container
        if shouldFail {
            throw ControlledBootstrapError()
        }

        let authService = AuthService(config: config.value)
        let model = AppModel(
            config: config,
            persistence: persistence,
            authService: authService,
            session: SessionManager(authService: authService)
        )
        models.append(model)
        return model
    }
}

struct ControlledBootstrapError: Error, Sendable {}

final class WeakReference<Value: AnyObject> {
    private(set) weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

@MainActor
final class ControlledProtectedDataAvailability: ProtectedDataAvailabilityProviding {
    private struct Waiter {
        let target: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var waiters: [Waiter] = []
    private(set) var waitCallCount = 0
    private(set) var isAvailable: Bool

    init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }

    func waitUntilAvailable() async {
        waitCallCount += 1
        let call = waitCallCount
        resumeSatisfiedWaiters()
        await withCheckedContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func waitForCallCount(_ target: Int) async {
        guard waitCallCount < target else { return }
        await withCheckedContinuation { continuation in
            waiters.append(Waiter(target: target, continuation: continuation))
        }
    }

    func setAvailable(_ available: Bool) {
        isAvailable = available
    }

    func resume(call: Int, makingAvailable available: Bool) {
        isAvailable = available
        continuations.removeValue(forKey: call)?.resume()
    }

    private func resumeSatisfiedWaiters() {
        while let index = waiters.firstIndex(where: { $0.target <= waitCallCount }) {
            waiters.remove(at: index).continuation.resume()
        }
    }
}

@MainActor
final class CancellationTrackingAvailability: ProtectedDataAvailabilityProviding {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var cancellationCount = 0
    private var didStart = false

    var isAvailable: Bool { false }

    func waitUntilAvailable() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                didStart = true
                startWaiters.forEach { $0.resume() }
                startWaiters.removeAll()
                if Task.isCancelled {
                    finishCancellation()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishCancellation()
            }
        }
    }

    func waitForStart() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitForCancellation() async {
        guard cancellationCount == 0 else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }

    private func finishCancellation() {
        guard let continuation else { return }
        self.continuation = nil
        cancellationCount += 1
        continuation.resume()
        cancellationWaiters.forEach { $0.resume() }
        cancellationWaiters.removeAll()
    }
}

@MainActor
final class RecordingBootstrapPhaseRecorder: AppBootstrapPhaseRecording {
    private let shouldThrow: Bool
    private(set) var phases: [AppBootstrapPhase] = []

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func record(_ phase: AppBootstrapPhase) throws {
        phases.append(phase)
        if shouldThrow {
            throw ControlledBootstrapError()
        }
    }
}

struct ThrowingDiagnosticsRecorder: AppConfigurationDiagnosticsRecording {
    func record(_ record: AppConfigurationDiagnosticRecord) throws {
        throw ControlledBootstrapError()
    }
}
