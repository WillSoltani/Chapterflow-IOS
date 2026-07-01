import Foundation
import Observation
import LocalAuthentication

/// Manages optional Face ID / Touch ID app lock.
///
/// When enabled (via `UserDefaults` key `"appLockEnabled"`), the user must
/// authenticate each time the app comes from the background. A full-screen
/// overlay hides content until the challenge succeeds.
@Observable
@MainActor
public final class AppLockManager {

    public var isLocked = false

    private var requiresBiometrics: Bool {
        UserDefaults.standard.bool(forKey: "appLockEnabled")
    }

    public init() {}

    /// Call when `ScenePhase` transitions to `.active`.
    public func handleForeground() {
        guard requiresBiometrics else { return }
        isLocked = true
        Task { await authenticate() }
    }

    /// Presents the biometric challenge and unlocks on success.
    public func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock ChapterFlow"
            )
            if success { isLocked = false }
        } catch let laError as LAError where laError.code == .userCancel {
            // User cancelled — keep locked; they can retry with the button.
        } catch {
            isLocked = false
        }
    }
}
