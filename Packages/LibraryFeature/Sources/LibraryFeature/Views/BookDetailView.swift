import SwiftUI
import Models
import DesignSystem
import CoreKit
import Persistence
import AIFeature
#if canImport(UIKit)
import UIKit
#endif

/// The book detail screen.
///
/// Shows the hero (cover, title, author, categories), an overall progress ring,
/// a primary Start/Continue action, a depth & tone entry point, and the full
/// chapter list with per-chapter lock/complete/score state.
///
/// All gating is server-authoritative — this view never writes unlock state.
/// Navigation callbacks (`onOpenReader`, `onShowPaywall`) are injected from
/// `AppFeature` and default to no-ops until those features are wired.
public struct BookDetailView: View {
    @State private var model: BookDetailModel
    @State private var showAskSheet = false
    @State private var showPreferencesSheet = false
    @State private var askModel: AskTheBookModel?

    private let aiRepository: (any AIRepository)?
    private let preferences: AppPreferences
    private let store: KeyValueStore
    private let preferencesRepository: (any BookPreferencesRepository)?
    private let automaticallyFetch: Bool

    public init(
        bookId: String,
        repository: any BookDetailRepository,
        aiRepository: (any AIRepository)? = nil,
        preferences: AppPreferences = AppPreferences(),
        store: KeyValueStore = KeyValueStore(),
        preferencesRepository: (any BookPreferencesRepository)? = nil,
        downloadManager: DownloadManager? = nil,
        accountID: String? = nil,
        isGuest: Bool = false,
        analytics: any AnalyticsClient = NoopAnalyticsClient(),
        workPermit: SessionWorkPermit = SessionWorkPermit(),
        onOpenReader: ((String, Int, VariantFamily) -> Void)? = nil,
        onShowPaywall: (() -> Void)? = nil,
        onSignInRequired: ((String, VariantFamily) -> Void)? = nil
    ) {
        let m = BookDetailModel(
            bookId: bookId,
            repository: repository,
            downloadManager: downloadManager,
            accountID: accountID,
            analytics: analytics,
            workPermit: workPermit
        )
        m.isGuest = isGuest
        m.onOpenReader = onOpenReader
        m.onShowPaywall = onShowPaywall
        m.onSignInRequired = onSignInRequired
        _model = State(initialValue: m)
        self.aiRepository = aiRepository
        self.preferences = preferences
        self.store = store
        self.preferencesRepository = preferencesRepository
        self.automaticallyFetch = true
    }

    /// Deterministic render-guard seam for an already-loaded model.
    init(model: BookDetailModel, automaticallyFetch: Bool = false) {
        _model = State(initialValue: model)
        self.aiRepository = nil
        self.preferences = AppPreferences()
        self.store = KeyValueStore()
        self.preferencesRepository = nil
        self.automaticallyFetch = automaticallyFetch
    }

    public var body: some View {
        contentView
            .navigationTitle(model.manifest?.title ?? "")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { askToolbarButton }
            .sheet(isPresented: $showAskSheet) {
                if let askModel {
                    AskTheBookSheet(model: askModel)
                }
            }
            .sheet(isPresented: $showPreferencesSheet) {
                if let variantFamily = model.manifest?.variantFamily {
                    BookPreferencesSheet(
                        model: BookPreferencesModel(
                            bookId: model.bookId,
                            variantFamily: variantFamily,
                            store: store,
                            preferences: preferences,
                            repository: preferencesRepository
                        )
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .task {
                guard automaticallyFetch else { return }
                await model.fetch()
            }
            .task(id: model.bookId) { await model.refreshDownloadState() }
    }

    // MARK: - Content
    @ViewBuilder
    private var contentView: some View {
        switch model.loadState {
        case .idle, .loading where model.manifest == nil:
            loadingView
        case .error(let msg):
            errorView(msg)
        default:
            loadedScrollView
        }
    }

    // MARK: - Loaded
    private var loadedScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                heroSection
                statsSection
                    .padding(.horizontal, .cfSpacing16)
                    .padding(.top, .cfSpacing16)
                privateDataNotice
                    .padding(.horizontal, .cfSpacing16)
                    .padding(.top, .cfSpacing16)
                primaryActionSection
                    .padding(.top, .cfSpacing20)
                if let error = model.startError {
                    inlineErrorNotice(error) {
                        Task { await model.performPrimaryAction() }
                    }
                    .padding(.horizontal, .cfSpacing16)
                    .padding(.top, .cfSpacing12)
                }
                downloadSection
                    .padding(.horizontal, .cfSpacing16)
                    .padding(.top, .cfSpacing12)
                depthToneRow
                    .padding(.top, .cfSpacing16)
                chapterListSection
                    .padding(.top, .cfSpacing8)
            }
            .padding(.bottom, .cfSpacing40)
        }
    }

    // MARK: - Hero
    private var heroSection: some View {
        VStack(alignment: .center, spacing: .cfSpacing12) {
            if let manifest = model.manifest {
                BookCoverView(cover: manifest.cover, size: 120)
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                    .padding(.top, .cfSpacing24)

                Text(manifest.title)
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, .cfSpacing24)

                Text(manifest.author)
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)

                if !manifest.categories.isEmpty {
                    categoryPills(manifest.categories)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, .cfSpacing16)
    }

    private func categoryPills(_ categories: [String]) -> some View {
        HStack(spacing: .cfSpacing8) {
            ForEach(categories, id: \.self) { category in
                Text(category)
                    .font(.cfCaption2)
                    .padding(.horizontal, .cfSpacing8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.cfSecondaryFill))
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        }
    }

    // MARK: - Stats
    private var statsSection: some View {
        HStack(spacing: .cfSpacing20) {
            progressSummary

            Divider().frame(height: 32)

            HStack(spacing: .cfSpacing8) {
                Image(systemName: "clock")
                    .foregroundStyle(Color.cfSecondaryLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.totalReadingMinutes) min")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                    Text("reading time")
                        .font(.cfCaption2)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statsAccessibilityLabel)
    }

    @ViewBuilder
    private var progressSummary: some View {
        if model.hasAuthoritativeProgress {
            HStack(spacing: .cfSpacing8) {
                ProgressRingView(progress: model.progressFraction, size: 36, lineWidth: 3.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.completedChapterCount) of \(model.totalChapters)")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                    Text("chapters")
                        .font(.cfCaption2)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            }
        } else {
            HStack(spacing: .cfSpacing8) {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(progressUnavailableLabel)
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                    Text("reading progress")
                        .font(.cfCaption2)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            }
        }
    }

    private var progressUnavailableLabel: String {
        if case .loading = model.privateState { return "Loading"
        }
        return "Unavailable"
    }

    private var statsAccessibilityLabel: String {
        if model.hasAuthoritativeProgress {
            return "\(model.completedChapterCount) of \(model.totalChapters) chapters completed. " +
                "\(model.totalReadingMinutes) minutes total reading time."
        }
        return "Reading progress \(progressUnavailableLabel.lowercased()). " +
            "\(model.totalReadingMinutes) minutes total reading time."
    }

    // MARK: - Primary action
    private var primaryActionSection: some View {
        Button {
            triggerHaptic()
            Task { await model.performPrimaryAction() }
        } label: {
            HStack {
                if model.isStarting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Text(primaryActionLabel)
                        .font(.cfHeadline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(primaryActionBackground, in: RoundedRectangle(cornerRadius: .cfRadius12, style: .continuous))
            .foregroundStyle(primaryActionForeground)
        }
        .disabled(model.primaryAction == .disabled || model.isStarting)
        .padding(.horizontal, .cfSpacing16)
        .accessibilityLabel(primaryActionLabel)
    }

    private var primaryActionLabel: String {
        switch model.primaryAction {
        case .startReading:    return "Start Reading"
        case .continueReading: return "Continue Reading"
        case .showPaywall:     return "Unlock Book"
        case .signInRequired:  return "Sign in to Read"
        case .disabled:        return disabledPrimaryActionLabel
        }
    }

    private var disabledPrimaryActionLabel: String {
        switch model.privateState {
        case .loading:
            return "Loading Reading Status…"
        case .unavailable, .compatibilityUnknown:
            return "Reading Status Unavailable"
        case .notStarted:
            switch model.entitlementState {
            case .loading:
                return "Checking Access…"
            case .unavailable:
                return "Access Unavailable"
            case .available, .notRequired:
                return "Reading Unavailable"
            }
        case .started:
            return "Reading Unavailable"
        }
    }

    private var primaryActionBackground: some ShapeStyle {
        switch model.primaryAction {
        case .showPaywall:    return AnyShapeStyle(Color.cfAccent.opacity(0.15))
        case .signInRequired: return AnyShapeStyle(Color.cfAccent)
        default:              return AnyShapeStyle(Color.cfAccent)
        }
    }

    private var primaryActionForeground: Color {
        switch model.primaryAction {
        case .showPaywall: return Color.cfAccent
        default:           return Color.white
        }
    }

    // MARK: - Download
    private var downloadSection: some View {
        BookDownloadButton(
            state: model.downloadState,
            canStartDownload: model.hasAuthoritativeStartedState,
            onDownload: { model.startDownload() },
            onCancel: { model.cancelDownload() },
            onDelete: { model.deleteDownload() }
        )
    }

    // MARK: - Private data notice
    @ViewBuilder
    private var privateDataNotice: some View {
        if !model.isGuest {
            switch model.privateState {
            case .unavailable(let error):
                inlineErrorNotice(error) {
                    Task { await model.retryPrivateState() }
                }
            case .compatibilityUnknown:
                inlineErrorNotice(.compatibility) {
                    Task { await model.retryPrivateState() }
                }
            case .notStarted:
                if case .unavailable(let error) = model.entitlementState {
                    inlineErrorNotice(error) {
                        Task { await model.retryEntitlement() }
                    }
                }
            case .loading, .started:
                EmptyView()
            }
        }
    }

    private func inlineErrorNotice(
        _ error: UserFacingError,
        onRetry: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            HStack(alignment: .firstTextBaseline, spacing: .cfSpacing8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .accessibilityHidden(true)
                Text(error.title)
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("book-detail-private-state-heading")
            }

            Text(error.message)
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)

            VStack(alignment: .leading, spacing: .cfSpacing2) {
                Text("Support code: \(error.supportCode.rawValue)")
                if let requestId = error.requestId {
                    Text("Request reference: \(requestId)")
                }
            }
            .font(.cfFootnote.monospaced())
            .foregroundStyle(Color.cfSecondaryLabel)
            .textSelection(.enabled)
            .accessibilityIdentifier("book-detail-private-state-support")

            if error.recovery == .retry {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.cfAccent)
                    .accessibilityHint("Retries only the unavailable account-backed information")
                    .accessibilityIdentifier("book-detail-private-state-retry")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.cfSpacing16)
        .background(Color.cfSecondaryFill, in: RoundedRectangle(cornerRadius: .cfRadius12))
    }

    // MARK: - Depth & Tone entry point
    private var depthToneRow: some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, .cfSpacing16)
            Button {
                triggerSelectionHaptic()
                showPreferencesSheet = true
            } label: {
                HStack {
                    Label("Reading Preferences", systemImage: "slider.horizontal.3")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                    Spacer()
                    if let manifest = model.manifest {
                        Text(manifest.variantFamily.displayName)
                            .font(.cfCaption)
                            .foregroundStyle(Color.cfSecondaryLabel)
                    }
                    Image(systemName: "chevron.right")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfTertiaryLabel)
                }
                .padding(.horizontal, .cfSpacing16)
                .padding(.vertical, .cfSpacing14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open reading preferences")
            Divider().padding(.leading, .cfSpacing16)
        }
    }

    // MARK: - Chapter list
    private var chapterListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chapters")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
                .padding(.horizontal, .cfSpacing16)
                .padding(.bottom, .cfSpacing8)

            if let chapters = model.manifest?.chapters {
                ForEach(chapters) { chapter in
                    Divider().padding(.leading, .cfSpacing16)
                    if model.hasAuthoritativeStartedState {
                        ChapterRowView(
                            chapter: chapter,
                            isUnlocked: model.isUnlocked(chapter),
                            isCompleted: model.isCompleted(chapter),
                            score: model.score(chapter),
                            applicationState: model.applicationState(chapter),
                            lockReason: model.lockReason(chapter),
                            onTap: {
                                triggerSelectionHaptic()
                                model.tapChapter(chapter)
                            }
                        )
                        .padding(.horizontal, .cfSpacing16)
                    } else {
                        chapterOutlineRow(chapter)
                            .padding(.horizontal, .cfSpacing16)
                    }
                }
                Divider().padding(.leading, .cfSpacing16)
            }
        }
    }

    private func chapterOutlineRow(_ chapter: BookManifestChapter) -> some View {
        HStack(alignment: .top, spacing: .cfSpacing12) {
            Text("\(chapter.number)")
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .frame(width: 28, height: 28)
                .background(Color.cfSecondaryFill, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text(chapter.title)
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfLabel)
                    .multilineTextAlignment(.leading)
                Label("\(chapter.readingTimeMinutes) min", systemImage: "clock")
                    .font(.cfCaption2)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, .cfSpacing12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Chapter \(chapter.number): \(chapter.title). " +
            "\(chapter.readingTimeMinutes) minutes. \(chapterOutlineStatus)"
        )
    }

    private var chapterOutlineStatus: String {
        if model.isGuest { return "Sign in to check access." }
        switch model.privateState {
        case .notStarted:
            return "Start this book to check access."
        case .loading:
            return "Reading status is loading."
        case .unavailable, .compatibilityUnknown:
            return "Reading status is unavailable."
        case .started:
            return ""
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: .cfSpacing20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color.cfAccent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(_ error: UserFacingError) -> some View {
        ContentUnavailableView {
            Label(error.title, systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: .cfSpacing8) {
                Text(error.message)
                Text("Support code: \(error.supportCode.rawValue)")
                    .font(.cfFootnote.monospaced())
                if let requestId = error.requestId {
                    Text("Request reference: \(requestId)")
                        .font(.cfFootnote.monospaced())
                }
            }
        } actions: {
            Button("Try Again") { Task { await model.fetch() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.cfAccent)
                .accessibilityHint("Retries loading this book")
        }
    }

    // MARK: - Ask the book toolbar

    @ToolbarContentBuilder
    private var askToolbarButton: some ToolbarContent {
        if aiRepository != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentAskSheet(selectionContext: nil)
                } label: {
                    Label("Ask", systemImage: "sparkles")
                }
                .accessibilityLabel("Ask the book a question")
            }
        }
    }

    private func presentAskSheet(selectionContext: String?) {
        guard let aiRepository else { return }
        let am = AskTheBookModel(
            bookId: model.bookId,
            repository: aiRepository,
            selectionContext: selectionContext
        )
        am.onJumpToChapter = { chapterNumber in
            showAskSheet = false
            model.onOpenReader?(model.bookId, chapterNumber, model.manifest?.variantFamily ?? .emh)
        }
        askModel = am
        showAskSheet = true
    }

}
