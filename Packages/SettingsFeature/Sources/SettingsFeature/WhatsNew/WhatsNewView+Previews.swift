import SwiftUI

#if DEBUG

/// Sample release used to drive the What's New previews without touching the
/// bundle or persistence.
private let sampleWhatsNewRelease = WhatsNewRelease(
    version: "1.0",
    title: "Welcome to ChapterFlow",
    highlights: [
        WhatsNewHighlight(
            id: "offline-reading",
            symbolName: "arrow.down.circle",
            title: "Read Anywhere, Offline",
            detail: "Download books and chapters to read without a connection."
        ),
        WhatsNewHighlight(
            id: "audio-narration",
            symbolName: "headphones",
            title: "Listen on the Go",
            detail: "Every chapter can be narrated aloud, with adjustable speed."
        ),
        WhatsNewHighlight(
            id: "premium-typography",
            symbolName: "textformat.size",
            title: "Beautiful, Adjustable Type",
            detail: "Premium typography with reader themes and full Dynamic Type support."
        ),
        WhatsNewHighlight(
            id: "widgets",
            symbolName: "square.grid.2x2",
            title: "Home Screen Widgets",
            detail: "Track your streak and jump back into your current chapter."
        )
    ]
)

#Preview("What's New — Light") {
    WhatsNewView(release: sampleWhatsNewRelease)
        .preferredColorScheme(.light)
}

#Preview("What's New — Dark") {
    WhatsNewView(release: sampleWhatsNewRelease)
        .preferredColorScheme(.dark)
}

#Preview("What's New — XXL text") {
    WhatsNewView(release: sampleWhatsNewRelease)
        .dynamicTypeSize(.accessibility3)
}

#endif
