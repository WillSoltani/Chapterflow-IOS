import Foundation
import CoreKit

// Type-safe navigation destinations, one enum per tab. Each conforms to
// `CoreKit.Routed` (Hashable + Sendable) so it can be pushed onto a
// `NavigationPath` and matched in a `navigationDestination`. Cases are the
// destinations reachable today (deep links + placeholders); feature packages
// extend these as real screens land.

/// Destinations within the Home tab.
public enum HomeRoute: Routed {
    /// The "continue reading" jump-back-in destination.
    case continueReading(bookId: String)
}

/// Destinations within the Library tab.
public enum LibraryRoute: Routed {
    /// A book's detail page.
    case book(id: String)
    /// A specific chapter of a book (opens the reader).
    case chapter(bookId: String, chapter: Int)
}

/// Destinations within the Reviews tab.
public enum ReviewsRoute: Routed {
    /// A single spaced-repetition review card.
    case card(id: String)
}

/// Destinations within the Profile tab.
public enum ProfileRoute: Routed {
    /// Accepting a reading-pair invite by code.
    case pairAccept(code: String)
    /// Claiming a gifted subscription by code.
    case gift(code: String)
}

/// Destinations within the Settings tab.
public enum SettingsRoute: Routed {
    /// The about / acknowledgements screen.
    case about
}
