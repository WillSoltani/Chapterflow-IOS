import Models
import CoreKit

/// Data contract for the Book Detail screen.
///
/// Concrete implementations: ``LiveBookDetailRepository`` (production) and
/// ``FakeBookDetailRepository`` (tests + previews).
public protocol BookDetailRepository: Sendable {
    /// Full manifest for a book (title, author, chapters ToC, etc.).
    /// Maps to `GET /book/books/{bookId}`.
    func getBook(id: String) async throws -> BookManifest

    /// Per-chapter reading state and authoritative started status for the current user.
    /// Maps to `GET /book/me/books/{bookId}/state`.
    func getBookState(id: String) async throws -> BookStateGetResponse

    /// Starts (or re-opens) a book for the current user, consuming a free slot.
    /// Maps to `POST /book/me/books/{bookId}/start`.
    func startBook(id: String) async throws -> BookStateResponse

    /// Current entitlement — used for gating.
    /// Maps to `GET /book/me/entitlements`.
    func getEntitlements() async throws -> EntitlementResponse
}
