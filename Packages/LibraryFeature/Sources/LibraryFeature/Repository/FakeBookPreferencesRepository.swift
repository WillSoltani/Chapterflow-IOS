import Models

/// In-memory ``BookPreferencesRepository`` for unit tests and SwiftUI previews.
public actor FakeBookPreferencesRepository: BookPreferencesRepository {
    /// The most recently patched variant key; `nil` if not yet called.
    public private(set) var lastPatchedVariantKey: String?
    /// When non-nil, `patchBookPreferredVariant` throws this error.
    private let forcedError: Error?

    public init(error: Error? = nil) {
        self.forcedError = error
    }

    public func patchBookPreferredVariant(bookId: String, variantKey: String) async throws {
        if let error = forcedError { throw error }
        lastPatchedVariantKey = variantKey
    }
}
