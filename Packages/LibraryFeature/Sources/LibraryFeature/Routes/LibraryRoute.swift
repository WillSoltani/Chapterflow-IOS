import CoreKit

/// Navigation destinations for the Library and Home tabs.
public enum LibraryRoute: Routed {
    case bookDetail(bookId: String)
    case globalSearch
    /// Browse all books in a single category.
    case categoryDetail(category: String)
}
