import CoreKit
import Foundation
import Networking
import Persistence

extension SessionManager {
    public func currentIdToken() -> String? {
        #if DEBUG
        if currentIdentity == Self.hermeticUITestIdentity,
           Self.isHermeticUITestBypass(environment: ProcessInfo.processInfo.environment) {
            return Self.uitestFakeIDToken
        }
        #endif
        guard let currentIdentity else { return nil }
        do {
            guard let tokens = try tokenStore.load(),
                  UserProfile.from(idToken: tokens.idToken)?.sub == currentIdentity.subject else {
                return nil
            }
            return tokens.idToken
        } catch {
            return nil
        }
    }

    public func validToken() async throws -> String? {
        try await validToken(expectedAccountID: nil)
    }

    private func validToken(expectedAccountID: String?) async throws -> String? {
        #if DEBUG
        if currentIdentity == Self.hermeticUITestIdentity,
           expectedAccountID == nil || expectedAccountID == Self.hermeticUITestIdentity.subject,
           Self.isHermeticUITestBypass(environment: ProcessInfo.processInfo.environment) {
            return Self.uitestFakeIDToken
        }
        #endif

        guard let identity = currentIdentity else { return nil }
        guard expectedAccountID == nil || identity.subject == expectedAccountID else {
            throw AppError.unauthenticated
        }
        let tokens: StoredTokens?
        do {
            tokens = try tokenStore.load()
        } catch {
            return try await performRefresh(expectedAccountID: expectedAccountID).idToken
        }
        guard let tokens else {
            return try await performRefresh(expectedAccountID: expectedAccountID).idToken
        }
        guard UserProfile.from(idToken: tokens.idToken)?.sub == identity.subject else {
            await signOut()
            throw AppError.unauthenticated
        }
        if tokens.isNearlyExpired() {
            return try await performRefresh(expectedAccountID: expectedAccountID).idToken
        }
        return tokens.idToken
    }

    /// Returns a token only when the immutable account scope still matches the
    /// authoritative session at the instant token acquisition begins.
    ///
    /// Account-scoped API clients use this overload so a request authorized for
    /// account A cannot enter the ordinary mutable token path after account B
    /// has become current.
    public func validToken(forAccountID accountID: String) async throws -> String? {
        try await validToken(expectedAccountID: accountID)
    }

    public func refresh() async throws {
        _ = try await performRefresh(expectedAccountID: nil)
    }

    /// Refreshes only while the expected immutable account remains current.
    public func refresh(forAccountID accountID: String) async throws {
        _ = try await performRefresh(expectedAccountID: accountID)
    }

    /// Starts step-up only for the expected immutable account.
    public func stepUp(forAccountID accountID: String) async throws {
        try await stepUp(expectedAccountID: accountID)
    }
}

extension SessionManager: TokenRefreshing, TokenProviding {}
