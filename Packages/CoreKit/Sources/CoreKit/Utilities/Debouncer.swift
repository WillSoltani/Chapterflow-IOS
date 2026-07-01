import Foundation

/// Coalesces rapid calls into a single trailing invocation.
///
/// Each `call(_:)` cancels any pending action and schedules a new one `interval`
/// later, so only the last call in a burst runs — useful for search-as-you-type,
/// auto-save, and progress-sync. `@MainActor` so the scheduled action can safely
/// touch UI state.
@MainActor
public final class Debouncer {
    private let interval: Duration
    private var task: Task<Void, Never>?

    public init(interval: Duration) {
        self.interval = interval
    }

    /// Schedules `action` to run after `interval`, cancelling any pending one.
    public func call(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [interval] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return // cancelled
            }
            action()
        }
    }

    /// Cancels any pending action without running it.
    public func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
