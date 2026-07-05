import Testing

/// Polls `condition` every 5 ms on the main actor until it returns `true`.
/// Records a test failure if `timeout` elapses before the condition is satisfied.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () async -> Bool
) async {
    let deadline = ContinuousClock().now + timeout
    while !(await condition()) {
        if ContinuousClock().now >= deadline {
            Issue.record("waitUntil timed out after \(timeout)")
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}
