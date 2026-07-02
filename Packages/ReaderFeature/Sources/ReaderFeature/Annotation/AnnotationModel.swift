import Foundation
import Observation
import Persistence

/// Manages all annotation state for a single chapter view.
///
/// Filters which annotations are painted as highlights vs. shown as cross-variant
/// badges based on the reader's active (variant, tone) pair. All mutations are
/// performed optimistically on `annotations` before the repository call returns.
@Observable
@MainActor
public final class AnnotationModel {

    // MARK: - Public state

    /// All annotations for the current chapter (highlights, notes, bookmarks).
    public private(set) var annotations: [LocalAnnotation] = []

    /// Whether the note-editor sheet is visible.
    public var isShowingNoteEditor = false

    /// Whether the full annotations list sheet is visible.
    public var isShowingAnnotationsList = false

    // MARK: - Injected callbacks

    /// Called when the user taps "Ask about this" on a block.
    public var onAskAboutSelection: ((String) -> Void)?

    /// Called when the user taps a cross-variant badge to switch depth/tone.
    public var onSwitchVariantTone: ((String, String) -> Void)?

    // MARK: - Internal configuration

    public let bookId: String
    public let chapterId: String

    /// Raw value of the currently active `VariantKey`.
    public private(set) var currentVariantKey: String
    /// Raw value of the currently active `ToneKey`.
    public private(set) var currentToneKey: String

    @ObservationIgnored private let repository: any AnnotationRepository
    @ObservationIgnored private var pendingNoteAnchor: AnnotationAnchor?

    // MARK: - Init

    public init(
        bookId: String,
        chapterId: String,
        variantKey: String,
        toneKey: String,
        repository: any AnnotationRepository
    ) {
        self.bookId = bookId
        self.chapterId = chapterId
        self.currentVariantKey = variantKey
        self.currentToneKey = toneKey
        self.repository = repository
    }

    // MARK: - Lifecycle

    /// Fetches annotations from the local store. Non-fatal on error.
    public func load() async {
        do {
            annotations = try await repository.loadAnnotations(bookId: bookId, chapterId: chapterId)
        } catch {
            // Annotations are non-essential; silently skip on failure.
        }
    }

    // MARK: - Variant / tone sync

    /// Called whenever the reader switches depth or tone. Updates the filter
    /// used by `activeHighlights(forBlock:)` and `crossVariantInfo(forBlock:)`.
    public func updateVariantTone(variant: String, tone: String) {
        currentVariantKey = variant
        currentToneKey = tone
    }

    // MARK: - Block-level queries

    /// Returns the highlights that should be PAINTED on the given block index
    /// in the current (variant, tone) view.
    public func activeHighlights(forBlock blockIndex: Int) -> [LocalAnnotation] {
        annotations.filter {
            $0.type == "highlight"
                && anchor(for: $0)?.blockIndex == blockIndex
                && anchor(for: $0)?.variantKey == currentVariantKey
                && anchor(for: $0)?.toneKey == currentToneKey
        }
    }

    /// Info about cross-variant highlights on a block, used to render the badge.
    public struct CrossVariantInfo {
        public let count: Int
        public let variantKey: String
        public let toneKey: String
    }

    /// Returns info about highlights on `blockIndex` that live in a DIFFERENT
    /// (variant, tone) pair — used to render the cross-variant badge.
    ///
    /// Returns `nil` when there are no cross-variant highlights for this block.
    public func crossVariantInfo(forBlock blockIndex: Int) -> CrossVariantInfo? {
        let others = annotations.filter {
            $0.type == "highlight"
                && anchor(for: $0)?.blockIndex == blockIndex
                && (anchor(for: $0)?.variantKey != currentVariantKey
                    || anchor(for: $0)?.toneKey != currentToneKey)
        }
        guard let first = others.first, let a = anchor(for: first) else { return nil }
        return CrossVariantInfo(count: others.count, variantKey: a.variantKey, toneKey: a.toneKey)
    }

    /// `true` when the chapter already has a bookmark.
    public var hasBookmark: Bool {
        annotations.contains { $0.type == "bookmark" }
    }

    // MARK: - Mutations

    /// Creates a block-level highlight. Optimistically appends to `annotations`.
    public func createHighlight(
        blockIndex: Int,
        blockText: String,
        blockType: String,
        color: HighlightColor
    ) {
        let anchor = AnnotationAnchor(
            variantKey: currentVariantKey,
            toneKey: currentToneKey,
            blockIndex: blockIndex,
            blockType: blockType,
            startChar: 0,
            endChar: blockText.count,
            snippet: blockText
        )
        Task {
            do {
                let ann = try await repository.addHighlight(
                    bookId: bookId,
                    chapterId: chapterId,
                    anchor: anchor,
                    color: color
                )
                annotations.append(ann)
            } catch {
                // Non-fatal — UI already shows the block normally.
            }
        }
    }

    /// Prepares the note-editor sheet for the given block.
    public func beginAddingNote(blockIndex: Int, blockText: String, blockType: String) {
        pendingNoteAnchor = AnnotationAnchor(
            variantKey: currentVariantKey,
            toneKey: currentToneKey,
            blockIndex: blockIndex,
            blockType: blockType,
            startChar: 0,
            endChar: blockText.count,
            snippet: blockText
        )
        isShowingNoteEditor = true
    }

    /// Saves the note written in the note-editor sheet.
    public func saveNote(content: String) {
        let a = pendingNoteAnchor
        pendingNoteAnchor = nil
        guard !content.isEmpty else { return }
        Task {
            do {
                let ann = try await repository.addNote(
                    bookId: bookId,
                    chapterId: chapterId,
                    anchor: a,
                    content: content
                )
                annotations.append(ann)
            } catch {
                // Non-fatal.
            }
        }
    }

    /// Forwards the passage text to the "Ask about this" handler.
    public func askAbout(_ text: String) {
        onAskAboutSelection?(text)
    }

    /// Deletes an annotation optimistically and queues the server deletion.
    public func deleteAnnotation(_ annotation: LocalAnnotation) {
        annotations.removeAll { $0.annotationId == annotation.annotationId }
        Task {
            try? await repository.deleteAnnotation(annotation)
        }
    }

    /// Toggles the chapter bookmark.
    public func toggleBookmark() {
        Task {
            do {
                let bm = try await repository.toggleBookmark(bookId: bookId, chapterId: chapterId)
                if let bm {
                    annotations.append(bm)
                } else {
                    annotations.removeAll { $0.type == "bookmark" }
                }
            } catch {
                // Non-fatal.
            }
        }
    }

    // MARK: - Private helpers

    private func anchor(for annotation: LocalAnnotation) -> AnnotationAnchor? {
        annotation.anchorJSON.flatMap { AnnotationAnchor.from(json: $0) }
    }
}
