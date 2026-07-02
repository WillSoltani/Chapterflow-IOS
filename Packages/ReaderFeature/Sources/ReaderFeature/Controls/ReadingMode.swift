/// The reader's content-presentation mode.
public enum ReadingMode: String, Sendable, CaseIterable {
    /// Continuous vertical scroll through the chapter content.
    case scroll
    /// Page-by-page presentation, swiping left/right between sections.
    case paginate
}
