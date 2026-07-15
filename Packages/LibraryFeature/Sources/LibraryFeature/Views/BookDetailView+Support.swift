import SwiftUI
import Models
#if canImport(UIKit)
import UIKit
#endif

@MainActor
func triggerHaptic() {
    #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    #endif
}

@MainActor
func triggerSelectionHaptic() {
    #if canImport(UIKit)
    UISelectionFeedbackGenerator().selectionChanged()
    #endif
}

extension VariantFamily {
    var displayName: String {
        switch self {
        case .emh: return "Easy · Medium · Hard"
        case .pbc: return "Precise · Balanced · Challenging"
        case .unknown: return "Custom"
        }
    }
}

extension CGFloat {
    static let cfSpacing14: CGFloat = 14
}

#if DEBUG
#Preview("Guest — browsing (sign in to read)") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailFreeLocked,
            isGuest: true
        )
    }
}

#Preview("Guest — dark mode") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailFreeLocked,
            isGuest: true
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Guest — XXL text") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailFreeLocked,
            isGuest: true
        )
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Free — locked (paywall)") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailFreeLocked
        )
    }
}

#Preview("In-progress") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailInProgress
        )
    }
}

#Preview("Completed") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailCompleted
        )
    }
}

#Preview("Private reading status unavailable") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailStateUnavailable
        )
    }
}

#Preview("Compatibility-unknown reading status") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailCompatibilityUnknown
        )
    }
}

#Preview("Dark mode — in-progress") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailInProgress
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("XXL text") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailInProgress
        )
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
