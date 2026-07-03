import CoreKit

/// Navigation destinations for the Library and Home tabs.
public enum LibraryRoute: Routed {
    case bookDetail(bookId: String)
    case globalSearch
}
