import Testing
import Foundation
import Models
import CoreKit
@testable import SocialFeature

// MARK: - PrivacySettings model tests

@Suite("PrivacySettings")
struct PrivacySettingsTests {

    @Test("default settings are all private-friendly")
    func defaultsArePrivate() {
        let settings = PrivacySettings.default
        #expect(!settings.showStreak)
        #expect(!settings.showBooksFinished)
        #expect(!settings.showProgress)
        #expect(settings.useDisplayName)       // display name = privacy-respecting
        #expect(!settings.leaderboardOptIn)
        #expect(!settings.discoverabilityOptIn)
    }

    @Test("PrivacySettings encodes and decodes round-trip")
    func codableRoundTrip() throws {
        let original = PrivacySettings(
            showStreak: true,
            showBooksFinished: false,
            showProgress: true,
            useDisplayName: true,
            leaderboardOptIn: false,
            discoverabilityOptIn: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PrivacySettings.self, from: data)
        #expect(decoded == original)
    }

    @Test("PrivacySettings decodes with extra unknown keys (forward compatibility)")
    func forwardCompatibleDecoding() throws {
        let json = """
        {"showStreak":true,"showBooksFinished":false,"showProgress":false,
         "useDisplayName":true,"leaderboardOptIn":false,"discoverabilityOptIn":false,
         "futureUnknownKey":"someValue"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PrivacySettings.self, from: json)
        #expect(decoded.showStreak)
        #expect(!decoded.showBooksFinished)
    }
}

// MARK: - PublicProfile visibility-helper tests (P7.8 client-side enforcement)

@Suite("PublicProfile.visibilityHelpers")
struct PublicProfileVisibilityTests {

    private func makeProfile(streak: Int? = 7, books: Int? = 12) -> PublicProfile {
        PublicProfile(
            userId: "u1",
            displayName: "Test Partner",
            avatarUrl: nil,
            avatarEmoji: nil,
            tier: .analyst,
            currentStreak: streak,
            booksFinished: books,
            equippedFrame: nil,
            equippedTheme: nil,
            badgeCount: 3,
            joinedAt: nil
        )
    }

    // MARK: Server-truth mode (privacySettings == nil)

    @Test("visibleStreak returns server value when no settings provided")
    func streakPassThroughNoSettings() {
        let profile = makeProfile(streak: 7)
        #expect(profile.visibleStreak(honoring: nil) == 7)
    }

    @Test("visibleStreak returns nil when server already hid it (nil value, no settings)")
    func streakNilFromServer() {
        let profile = makeProfile(streak: nil)
        #expect(profile.visibleStreak(honoring: nil) == nil)
    }

    @Test("visibleBooksFinished returns server value when no settings provided")
    func booksPassThroughNoSettings() {
        let profile = makeProfile(books: 12)
        #expect(profile.visibleBooksFinished(honoring: nil) == 12)
    }

    // MARK: Client-side enforcement (privacySettings != nil)

    @Test("hidden streak is nil even when server returned a value")
    func streakHiddenByPrivacySettings() {
        let profile = makeProfile(streak: 7)
        let settings = PrivacySettings(showStreak: false)
        // Server returned 7 but user hid it — must be nil.
        #expect(profile.visibleStreak(honoring: settings) == nil)
    }

    @Test("visible streak is returned when settings allow sharing")
    func streakVisibleWhenAllowed() {
        let profile = makeProfile(streak: 7)
        let settings = PrivacySettings(showStreak: true)
        #expect(profile.visibleStreak(honoring: settings) == 7)
    }

    @Test("hidden books-finished is nil even when server returned a value")
    func booksHiddenByPrivacySettings() {
        let profile = makeProfile(books: 12)
        let settings = PrivacySettings(showBooksFinished: false)
        // Server returned 12 but user hid it — must be nil.
        #expect(profile.visibleBooksFinished(honoring: settings) == nil)
    }

    @Test("visible books-finished returned when settings allow sharing")
    func booksVisibleWhenAllowed() {
        let profile = makeProfile(books: 12)
        let settings = PrivacySettings(showBooksFinished: true)
        #expect(profile.visibleBooksFinished(honoring: settings) == 12)
    }

    @Test("streak hidden when server returns nil AND settings disallow — stays nil")
    func streakNilBothServerAndSettings() {
        let profile = makeProfile(streak: nil)
        let settings = PrivacySettings(showStreak: false)
        #expect(profile.visibleStreak(honoring: settings) == nil)
    }

    @Test("streak nil from server even when settings say show — server truth wins")
    func serverNilDominatesEvenWhenSettingsAllow() {
        let profile = makeProfile(streak: nil)
        let settings = PrivacySettings(showStreak: true)
        // Server hid it (nil); client settings say show — nil still wins (server truth).
        #expect(profile.visibleStreak(honoring: settings) == nil)
    }
}

// MARK: - FakeSocialRepository privacy tests

@Suite("FakeSocialRepository.privacy")
struct FakeSocialRepositoryPrivacyTests {

    @Test("updateSettings with privacySettings persists them on the profile")
    func privacySettingsPersisted() async throws {
        let repo = FakeSocialRepository(profile: .preview)
        let newPrivacy = PrivacySettings(showStreak: true, showBooksFinished: true)
        let updated = try await repo.updateSettings(
            UpdateSettingsBody(privacySettings: newPrivacy)
        )
        #expect(updated.privacySettings?.showStreak == true)
        #expect(updated.privacySettings?.showBooksFinished == true)
        // Subsequent fetch reflects the mutation.
        let refetched = try await repo.getMyProfile()
        #expect(refetched.privacySettings?.showStreak == true)
    }

    @Test("updateSettings without privacySettings leaves them unchanged")
    func privacySettingsUnchangedWhenOmitted() async throws {
        let initial = PrivacySettings(showStreak: true, leaderboardOptIn: true)
        let profile = OwnProfile(
            userId: "u1", displayName: "Test", avatarUrl: nil, avatarEmoji: nil,
            tier: .reader, tierProgress: nil, currentStreak: 0, longestStreak: 0,
            booksFinished: 0, flowPoints: 0, equippedFrame: nil, equippedTheme: nil,
            badgeCount: 0, joinedAt: nil, privacySettings: initial
        )
        let repo = FakeSocialRepository(profile: profile)
        // PATCH only display name — privacy should be untouched.
        let updated = try await repo.updateSettings(
            UpdateSettingsBody(displayName: "New Name")
        )
        #expect(updated.privacySettings?.showStreak == true)
        #expect(updated.privacySettings?.leaderboardOptIn == true)
    }

    @Test("UpdateSettingsBody encodes privacySettings when present")
    func updateBodyEncodesPrivacy() throws {
        let settings = PrivacySettings(showStreak: true, leaderboardOptIn: true)
        let body = UpdateSettingsBody(privacySettings: settings)
        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let privacyDict = json?["privacySettings"] as? [String: Any]
        #expect(privacyDict?["showStreak"] as? Bool == true)
        #expect(privacyDict?["leaderboardOptIn"] as? Bool == true)
    }

    @Test("UpdateSettingsBody omits privacySettings key when nil")
    func updateBodyOmitsPrivacyWhenNil() throws {
        let body = UpdateSettingsBody(displayName: "Alice")
        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["privacySettings"] == nil)
    }
}
