/// LibraryFeature — Home + Library tabs for ChapterFlow.
///
/// Public surface:
/// - ``LibraryRepository`` protocol + ``LiveLibraryRepository`` + ``FakeLibraryRepository``
/// - ``HomeView`` / ``LibraryView`` — the two tab-root views
/// - ``BookCoverView``, ``ProgressRingView``, ``BookCardView`` — reusable components
/// - ``LibraryRoute`` — navigation destinations
public enum LibraryFeature {
    /// Module name for smoke-test assertions.
    public static let moduleName = "LibraryFeature"
}
