import AuthKit
import CoreKit
import Foundation
import Networking

/// Binds every token, refresh, step-up, and error-report operation to one
/// immutable account scope before the underlying API client builds a request.
///
/// The API client receives this provider instead of the process-long mutable
/// `SessionManager`, preventing an A endpoint from acquiring B's bearer token
/// in the gap between wrapper authorization and request construction.
struct AccountBoundSessionTokenProvider: TokenProviding {
    let context: AccountContext
    let session: SessionManager
    let permit: SessionWorkPermit
    var accountCheckHook: (@Sendable () async -> Void)? = nil

    func validToken() async throws -> String? {
        let ticket = try await authorizeStart()
        let token = try await session.validToken(forAccountID: context.accountID)
        try await authorizeCompletion(ticket)
        return token
    }

    func refresh() async throws {
        let ticket = try await authorizeStart()
        try await session.refresh(forAccountID: context.accountID)
        try await authorizeCompletion(ticket)
    }

    func stepUp() async throws {
        let ticket = try await authorizeStart()
        try await session.stepUp(forAccountID: context.accountID)
        try await authorizeCompletion(ticket)
    }

    func reportSessionError(_ error: AppError) async {
        guard let ticket = try? await authorizeStart() else { return }
        await session.reportSessionError(error, forAccountID: context.accountID)
        _ = try? await authorizeCompletion(ticket)
    }

    private func authorizeStart() async throws -> UInt64 {
        try Task.checkCancellation()
        let ticket = try permit.begin()
        try await requireCurrentAccount()
        try permit.validate(ticket)
        try Task.checkCancellation()
        return ticket
    }

    private func authorizeCompletion(_ ticket: UInt64) async throws {
        try Task.checkCancellation()
        try permit.validate(ticket)
        try await requireCurrentAccount()
        try permit.validate(ticket)
        try Task.checkCancellation()
    }

    private func requireCurrentAccount() async throws {
        await accountCheckHook?()
        let currentIdentity = await MainActor.run { session.currentIdentity }
        guard currentIdentity?.subject == context.accountID else {
            throw AppError.unauthenticated
        }
    }
}

/// Rejects work unless both the scope permit and the authoritative session
/// still belong to the immutable account context before and after transport.
struct SessionScopedAPIClient: APIClientProtocol {
    let base: any APIClientProtocol
    let context: AccountContext
    let session: SessionManager
    let permit: SessionWorkPermit
    var accountCheckHook: (@Sendable () async -> Void)? = nil

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let ticket = try await authorizeStart()
        let value: T = try await base.send(endpoint)
        try await authorizeCompletion(ticket)
        return value
    }

    func sendWithServerDate<T: Decodable & Sendable>(
        _ endpoint: Endpoint
    ) async throws -> (T, Date?) {
        let ticket = try await authorizeStart()
        let value: (T, Date?) = try await base.sendWithServerDate(endpoint)
        try await authorizeCompletion(ticket)
        return value
    }

    func sendData(_ endpoint: Endpoint) async throws -> Data {
        let ticket = try await authorizeStart()
        let value = try await base.sendData(endpoint)
        try await authorizeCompletion(ticket)
        return value
    }

    private func authorizeStart() async throws -> UInt64 {
        try Task.checkCancellation()
        let ticket = try permit.begin()
        try await requireCurrentAccount()
        try permit.validate(ticket)
        try Task.checkCancellation()
        return ticket
    }

    private func authorizeCompletion(_ ticket: UInt64) async throws {
        try Task.checkCancellation()
        try permit.validate(ticket)
        try await requireCurrentAccount()
        try permit.validate(ticket)
        try Task.checkCancellation()
    }

    private func requireCurrentAccount() async throws {
        await accountCheckHook?()
        let currentIdentity = await MainActor.run { session.currentIdentity }
        guard currentIdentity?.subject == context.accountID else {
            throw AppError.unauthenticated
        }
    }
}
