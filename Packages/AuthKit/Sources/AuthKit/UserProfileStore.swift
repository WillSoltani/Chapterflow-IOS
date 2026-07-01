import Foundation

/// Persists a minimal `UserProfile` in `UserDefaults` so the app can show
/// the user's name instantly on relaunch before the session refresh completes.
public final class UserProfileStore: @unchecked Sendable {
    public static let shared = UserProfileStore()

    private let defaults: UserDefaults
    private let key = "com.chapterflow.ios.userProfile"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> UserProfile? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    public func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
