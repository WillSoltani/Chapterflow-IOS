import Synchronization

/// Thread-safe ownership for a lifecycle task that must be cancelled from
/// `deinit` without reading mutable actor-isolated state.
final class TaskCancellationHandle: Sendable {
    private let task = Mutex<Task<Void, Never>?>(nil)

    @discardableResult
    func installIfEmpty(_ nextTask: Task<Void, Never>) -> Bool {
        let installed = task.withLock { currentTask in
            guard currentTask == nil else { return false }
            currentTask = nextTask
            return true
        }
        if !installed {
            nextTask.cancel()
        }
        return installed
    }

    func replace(with nextTask: Task<Void, Never>) {
        let previousTask = task.withLock { currentTask in
            let previousTask = currentTask
            currentTask = nextTask
            return previousTask
        }
        previousTask?.cancel()
    }

    func cancel() {
        let previousTask = task.withLock { currentTask in
            let previousTask = currentTask
            currentTask = nil
            return previousTask
        }
        previousTask?.cancel()
    }
}
