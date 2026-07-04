import Models

/// Data-layer protocol for syncing per-book reading preferences to the server.
///
/// Server sync is best-effort: the caller does not need to surface errors to the user.
/// Local persistence via ``KeyValueStore`` is handled directly by ``BookPreferencesModel``.
public protocol BookPreferencesRepository: Sendable {
    /// Patches `preferredVariant` on the book's server-side progress record.
    func patchBookPreferredVariant(bookId: String, variantKey: String) async throws
}
