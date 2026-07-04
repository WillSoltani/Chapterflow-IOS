/// LibraryFeature — Home, Library, and Discover tabs for ChapterFlow.
///
/// Public surface:
/// - ``LibraryRepository`` protocol + ``LiveLibraryRepository`` + ``FakeLibraryRepository``
/// - ``HomeView`` / ``LibraryView`` / ``DiscoverView`` — tab-root views
/// - ``CategoryDetailView`` — books in a single category
/// - ``BookCoverView``, ``ProgressRingView``, ``BookCardView``, ``ShelfCoverCard``,
///   ``BookShelfView`` — reusable components
/// - ``DiscoverModel`` — observable model for the Discover screen
/// - ``LibraryRoute`` — navigation destinations (`.bookDetail`, `.categoryDetail`)
public enum LibraryFeature {
    /// Module name for smoke-test assertions.
    public static let moduleName = "LibraryFeature"
}
