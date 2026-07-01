import Foundation

public extension Result where Failure == Error {
    /// Builds a `Result` by awaiting a throwing async operation, capturing any
    /// error as `.failure`.
    init(catchingAsync operation: () async throws -> Success) async {
        do {
            self = .success(try await operation())
        } catch {
            self = .failure(error)
        }
    }
}

public extension Result {
    /// The success value, or `nil` if this is a failure.
    var value: Success? {
        if case .success(let value) = self { return value }
        return nil
    }

    /// The error, or `nil` if this is a success.
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }

    /// Runs `body` with the success value (if any), returning `self` for chaining.
    @discardableResult
    func onSuccess(_ body: (Success) -> Void) -> Self {
        if case .success(let value) = self { body(value) }
        return self
    }

    /// Runs `body` with the error (if any), returning `self` for chaining.
    @discardableResult
    func onFailure(_ body: (Failure) -> Void) -> Self {
        if case .failure(let error) = self { body(error) }
        return self
    }
}

/// Awaits a throwing async operation and returns its outcome as a `Result`,
/// never throwing.
public func asyncResult<T>(
    _ operation: () async throws -> T
) async -> Result<T, Error> {
    await Result(catchingAsync: operation)
}
