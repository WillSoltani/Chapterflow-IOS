#if DEBUG
import SwiftUI

#Preview("EMH — Light (with v21Extras)") {
    ReaderContentView(chapter: previewChapterEMH)
}

#Preview("PBC — Dark (no v21Extras)") {
    ReaderContentView(chapter: previewChapterPBC)
        .preferredColorScheme(.dark)
}

#Preview("EMH — Accessibility XXL") {
    ReaderContentView(chapter: previewChapterEMH)
        .dynamicTypeSize(.accessibility3)
}
#endif
