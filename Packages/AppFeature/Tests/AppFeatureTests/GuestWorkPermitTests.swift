import AuthKit
import CoreKit
import Foundation
import Observation
import os
import Persistence
import Testing
@testable import AppFeature

@Suite("Guest public work permit")
@MainActor
struct GuestWorkPermitTests {
    @Test("settled signed-out reconciliation does not start account teardown")
    func settledSignedOutReconciliationIsNoOp() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        let probe = GuestScopeProbe()
        let model = makeModel(session: session, probe: probe)
        let phaseDidChange = OSAllocatedUnfairLock(initialState: false)

        #expect(model.canPresentSignedOutEntry)
        #expect(model.sessionScopePhase == .none)
        #expect(model.activeSessionScope == nil)

        withObservationTracking {
            _ = model.sessionScopePhase
        } onChange: {
            phaseDidChange.withLock { $0 = true }
        }

        await model.reconcileCurrentSession()

        #expect(!phaseDidChange.withLock { $0 })
        #expect(model.sessionScopePhase == .none)
        #expect(model.activeSessionScope == nil)
        #expect(model.canPresentSignedOutEntry)
        #expect(await probe.constructedAccounts.isEmpty)
    }

    @Test("guest mode exposes an active public permit without constructing a private scope")
    func guestModeExposesPublicPermit() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        let probe = GuestScopeProbe()
        let model = makeModel(session: session, probe: probe)
        let permit = model.guestWorkPermit

        #expect(session.currentIdentity == nil)
        model.enterGuestMode()
        await model.reconcileCurrentSession()

        #expect(session.currentIdentity == nil)
        #expect(model.isGuestMode)
        #expect(model.guestWorkPermit === permit)
        #expect(permit.currentState() == .active)
        #expect(model.activeSessionScope == nil)
        #expect(await probe.constructedAccounts.isEmpty)
    }

    @Test("guest permit remains distinct from and active after account A permit teardown")
    func guestPermitIsNotAccountPermit() async throws {
        let session = try guestSignedInSession(subject: "account-a")
        let probe = GuestScopeProbe()
        let model = makeModel(session: session, probe: probe)
        let guestPermit = model.guestWorkPermit

        await model.reconcileCurrentSession()
        let accountPermit = try #require(model.activeSessionScope?.permit)
        let accountTicket = try accountPermit.begin()

        #expect(guestPermit !== accountPermit)
        #expect(accountPermit.currentState() == .active)

        await model.signOut()

        #expect(accountPermit.currentState() == .invalidated)
        #expect(throws: CancellationError.self) {
            _ = try accountPermit.begin()
        }
        #expect(throws: CancellationError.self) {
            try accountPermit.validate(accountTicket)
        }
        #expect(guestPermit.currentState() == .active)
    }

    @Test("guest Home composition is repeatable without private graph construction")
    func guestHomeCompositionIsPublic() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        let probe = GuestScopeProbe()
        let model = makeModel(session: session, probe: probe)
        model.enterGuestMode()
        await model.reconcileCurrentSession()
        let root = AppRootView(model: model)

        for _ in 0..<25 {
            _ = root.guestTabContent(for: .home)
        }

        #expect(model.activeSessionScope == nil)
        #expect(await probe.constructedAccounts.isEmpty)
    }

    @Test("guest Library composition is repeatable without private graph construction")
    func guestLibraryCompositionIsPublic() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        let probe = GuestScopeProbe()
        let model = makeModel(session: session, probe: probe)
        model.enterGuestMode()
        await model.reconcileCurrentSession()
        let root = AppRootView(model: model)

        for _ in 0..<25 {
            _ = root.guestTabContent(for: .library)
        }

        #expect(model.activeSessionScope == nil)
        #expect(await probe.constructedAccounts.isEmpty)
    }

    @Test("private work-permit access fails closed without a matching account scope")
    func privatePermitWithoutMatchingScopeFailsClosed() async {
        let result = await #expect(
            processExitsWith: .failure,
            observing: [\.standardErrorContent]
        ) {
            await MainActor.run {
                let session = SessionManager(tokenStore: InMemoryTokenStore())
                let model = makeTestAppModel(session: session)

                _ = model.workPermit
            }
        }
        let standardError = result.flatMap {
            String(bytes: $0.standardErrorContent, encoding: .utf8)
        } ?? ""

        #expect(standardError.contains(
            "Account-private dependency requested without an active matching session scope"
        ))
    }

    private func makeModel(
        session: SessionManager,
        probe: GuestScopeProbe
    ) -> AppModel {
        makeTestAppModel(session: session) { context in
            await probe.record(context.accountID)
            return SessionScope(context: context)
        }
    }
}

private actor GuestScopeProbe {
    private(set) var constructedAccounts: [String] = []

    func record(_ accountID: String) {
        constructedAccounts.append(accountID)
    }
}

@MainActor
private func guestSignedInSession(subject: String) throws -> SessionManager {
    SessionManager(
        tokenStore: InMemoryTokenStore(tokens: guestTokens(marker: subject)),
        refresher: StubTokenRefresher(),
        hermeticIdentity: try guestIdentity(subject: subject)
    )
}

private func guestIdentity(subject: String) throws -> SessionIdentity {
    try #require(SessionIdentity(
        subject: subject,
        username: "Reader",
        email: nil,
        source: .cognitoUserPool
    ))
}

private func guestTokens(marker: String) -> StoredTokens {
    StoredTokens(
        idToken: "id-\(marker)",
        accessToken: "access-\(marker)",
        refreshToken: "refresh-\(marker)",
        expiresAt: Date().addingTimeInterval(3_600)
    )
}
