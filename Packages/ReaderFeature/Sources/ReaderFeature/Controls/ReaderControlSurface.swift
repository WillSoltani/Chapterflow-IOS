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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// When non-nil, highlights, notes, and bookmarks are enabled for this chapter.
    var annotationModel: AnnotationModel?

    /// When non-nil, enables the in-reader ToC and prev/next navigation.
    var navModel: ChapterNavModel?

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
    /// Use this initialiser when `ReaderModel` owns the controls model and needs
    /// to observe `readPercent` / `currentTopBlockIndex` for progress tracking.
    ///
    /// - Parameters:
    ///   - model: The externally-owned controls model.
    ///   - annotationModel: Optional annotation model. When non-nil, all blocks
    ///     support long-press highlights, notes, and bookmarks.
    ///   - navModel: Optional navigation model. When non-nil, enables the ToC and
    ///     prev/next chapter controls in the toolbar.
    @MainActor
    public init(
        model: ReaderControlsModel,
        annotationModel: AnnotationModel? = nil,
        navModel: ChapterNavModel? = nil
    ) {
        _model = State(initialValue: model)
        self.annotationModel = annotationModel
        self.navModel = navModel
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
        .sheet(
            isPresented: Binding(
                get: { annotationModel?.isShowingNoteEditor ?? false },
                set: { annotationModel?.isShowingNoteEditor = $0 }
            )
        ) {
            if let ann = annotationModel {
                NoteEditorView(model: ann)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { annotationModel?.isShowingAnnotationsList ?? false },
                set: { annotationModel?.isShowingAnnotationsList = $0 }
            )
        ) {
            if let ann = annotationModel {
                AnnotationsListView(model: ann, onJumpToBlock: { blockIndex in
                    model.pendingScrollAnchor = blockIndex
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        // ToC sheet: shown on compact (iPhone). On regular (iPad) the sidebar in ReaderView shows instead.
        .sheet(
            isPresented: Binding(
                get: { (navModel?.isToCPresented ?? false) && horizontalSizeClass != .regular },
                set: { navModel?.isToCPresented = $0 }
            )
        ) {
            if let nav = navModel {
                TableOfContentsView(
                    model: nav,
                    currentReadPercent: model.readPercent,
                    isSheet: true
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
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
        let currentVariant = model.selectedVariant.rawValue
        let currentTone = model.selectedTone.rawValue

        return ScrollViewReader { proxy in
            ScrollView {
                ReaderBlockListView(
                    blocks: model.blocks,
                    appearance: appearance,
                    annotationModel: annotationModel,
                    switchToVariantTone: { [model] vk, tk in
                        model.switchVariant(VariantKey(rawValue: vk), currentTopIndex: model.currentTopBlockIndex)
                        model.switchTone(ToneKey(rawValue: tk), currentTopIndex: model.currentTopBlockIndex)
                    }
                )
            }
            .scrollPosition(id: $scrollPositionID)
            .background(appearance.colors.pageBg)
            .readerAppearance(appearance)
            .onChange(of: scrollPositionID) { _, newID in
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
            .onChange(of: currentVariant) { _, vk in
                annotationModel?.updateVariantTone(variant: vk, tone: currentTone)
            }
            .onChange(of: currentTone) { _, tk in
                annotationModel?.updateVariantTone(variant: currentVariant, tone: tk)
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
                    currentTopIndex: scrollPositionID ?? 0,
                    navModel: navModel
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
