import Models

extension Fixtures {

    // MARK: - Catalog

    /// Full book catalog: Atomic Habits (EMH) + Deep Work (PBC) + Thinking Fast and Slow (EMH).
    public static let catalog: CatalogResponse = load("catalog")

    /// Convenience: the three books as a flat array.
    public static let books: [BookCatalogItem] = catalog.books

    /// Atomic Habits catalog entry (EMH variant family).
    public static var atomicHabits: BookCatalogItem { books[0] }

    /// Deep Work catalog entry (PBC variant family).
    public static var deepWork: BookCatalogItem { books[1] }

    /// Thinking, Fast and Slow catalog entry (EMH variant family).
    public static var thinkingFastAndSlow: BookCatalogItem { books[2] }

    // MARK: - Book manifest

    /// Full book manifest for Atomic Habits (5 chapters with ToC).
    public static let bookManifest: BookManifest = load("book_manifest")
}
