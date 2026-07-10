import Foundation
import Testing

/// Waits until `condition` holds (or `timeout` elapses), suspending — and thus
/// releasing the main actor — between checks.
///
/// These model tests drive a fire-and-forget `load()` (it spawns an internal
/// `Task`) and then need to observe the *settled* state. The previous
/// `try await Task.sleep(for: .milliseconds(100))` assumed the async load
/// finished within a fixed window — a timing assumption that fails the moment
/// anything else contends for the main actor under swift-testing's parallel
/// execution (a heavy sibling test, a busy CI runner). Polling the model's own
/// `loadState` with a generous timeout removes the assumption entirely: the
/// wait ends the instant the load actually completes and the subsequent
/// assertions are unchanged, so this strengthens the tests without weakening
/// any expectation.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: () -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(2))
    }
}
