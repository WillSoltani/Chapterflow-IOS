import SwiftUI

/// App-wide SwiftUI environment key for the signed-in user.
///
/// Injected at the composition root (`AppRootView`) so every feature view can
/// read the current identity via `@Environment(\.currentUser) var currentUser`.
public extension EnvironmentValues {
    @Entry var currentUser: UserProfile? = nil
}
