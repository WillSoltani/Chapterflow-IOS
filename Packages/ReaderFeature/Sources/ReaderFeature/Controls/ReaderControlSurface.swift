import SwiftUI
import Models
import DesignSystem
import Persistence

/// The complete reader experience: content + auto-hiding controls.
///
/// Wraps the chapter content in either a continuous scroll view or a paginated
/// tab view, and overlays `ReaderToolbar` at the bottom. Tapping anywhere on
/// the content toggles the toolbar. In focus mode all chrome is hidden.
///
/// Depth and tone switches are instant — content is re-resolved from in-memory
/// variant data by `ChapterContentResolver`. Scroll position is preserved across
/// every switch using a block-index anchor.
///
/// Selections (depth and tone) are persisted per-book via `BookReadingPreferences`.
///
/// **Host-side chrome removal for focus mode:**
/// This view hides the toolbar and shows a tap-to-exit hint, but cannot reach
/// the navigation bar. Apply `.navigationBarHidden(model.isFocusModeActive)` and
/// `.statusBar(hidden: model.isFocusModeActive)` from the hosting navigation view.
public struct ReaderControlSurface: View {
    @State private var model: ReaderControlsModel
    @State private var scrollPositionID: Int?
    @State private var paginatedPage = 0

    /// Creates the control surface for a chapter.
    ///
    /// - Parameters:
    ///   - chapter: The fully-loaded chapter with all `contentVariants`.
    ///   - bookId: Scopes per-book preference persistence.
    ///   - variantFamily: Determines the depth picker labels (EMH or PBC).
    ///   - preferences: Global reading preferences for appearance.
    ///   - store: Key-value store for per-book persistence.
    @MainActor
    public init(
        chapter: Chapter,
        bookId: String,
        variantFamily: VariantFamily,
        preferences: AppPreferences,
        store: KeyValueStore = KeyValueStore()
    ) {
        _model = State(initialValue: ReaderControlsModel(
            chapter: chapter,
            bookId: bookId,
            variantFamily: variantFamily,
            preferences: preferences,
            store: store
        ))
    }

    /// Creates the control surface from an externally-owned `ReaderControlsModel`.
    ///
    /// Use this initialiser when `ReaderModel` (P2.4d) owns the controls model
    /// and needs to observe `readPercent` / `currentTopBlockIndex` for progress
    /// tracking and position save/restore.
    @MainActor
    public init(model: ReaderControlsModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        @Bindable var m = model
        let appearance = ReadingAppearance(preferences: model.preferences)

        ZStack(alignment: .bottom) {
            contentArea(appearance: appearance)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !model.isFocusModeActive else {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            model.toggleFocusMode()
                        }
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        model.toggleToolbar()
                    }
                }

            toolbarLayer
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: model.selectedVariant) { _, _ in
            if model.readingMode == .paginate { paginatedPage = 0 }
        }
        .onChange(of: model.selectedTone) { _, _ in
            if model.readingMode == .paginate { paginatedPage = 0 }
        }
        .sheet(isPresented: $m.isAppearancePanelPresented) {
            ReadingAppearancePanel(preferences: model.preferences)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private func contentArea(appearance: ReadingAppearance) -> some View {
        switch model.readingMode {
        case .scroll:
            scrollContent(appearance: appearance)
        case .paginate:
#if os(iOS)
            ReaderPaginatedView(
                blocks: model.blocks,
                currentPage: $paginatedPage,
                appearance: appearance
            )
#else
            scrollContent(appearance: appearance)
#endif
        }
    }

    private func scrollContent(appearance: ReadingAppearance) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                ReaderBlockListView(blocks: model.blocks, appearance: appearance)
            }
            .scrollPosition(id: $scrollPositionID)
            .background(appearance.colors.pageBg)
            .readerAppearance(appearance)
            .onChange(of: scrollPositionID) { _, newID in
                // Push topmost-visible block index into the model so that
                // ReaderModel can compute readPercent and save position.
                if let idx = newID {
                    model.currentTopBlockIndex = idx
                }
            }
            .onChange(of: model.pendingScrollAnchor) { _, newAnchor in
                guard let newAnchor else { return }
                withAnimation(.none) {
                    proxy.scrollTo(newAnchor, anchor: .top)
                }
                model.clearPendingAnchor()
            }
        }
    }

    // MARK: - Toolbar layer

    @ViewBuilder
    private var toolbarLayer: some View {
        if model.isFocusModeActive {
            focusModeHint
        } else {
            if model.isToolbarVisible {
                ReaderToolbar(
                    model: model,
                    currentTopIndex: scrollPositionID ?? 0
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Focus mode exit hint

    private var focusModeHint: some View {
        Text("Tap to show controls")
            .font(.cfCaption2)
            .foregroundStyle(Color.cfTertiaryLabel)
            .padding(.bottom, .cfSpacing32)
    }
}
