import SwiftUI
import Models
import DesignSystem
import CoreKit
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

    public init(
        bookId: String,
        repository: any BookDetailRepository,
        onOpenReader: ((String, Int) -> Void)? = nil,
        onShowPaywall: (() -> Void)? = nil
    ) {
        let m = BookDetailModel(bookId: bookId, repository: repository)
        m.onOpenReader = onOpenReader
        m.onShowPaywall = onShowPaywall
        _model = State(initialValue: m)
    }

    public var body: some View {
        contentView
            .navigationTitle(model.manifest?.title ?? "")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await model.fetch() }
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
                primaryActionSection
                    .padding(.top, .cfSpacing20)
                if let error = model.startError {
                    Text(error)
                        .font(.cfCaption)
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, .cfSpacing16)
                        .padding(.top, .cfSpacing8)
                }
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
            // Progress ring + fraction
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

            Divider().frame(height: 32)

            // Total reading time
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

    private var statsAccessibilityLabel: String {
        "\(model.completedChapterCount) of \(model.totalChapters) chapters completed. " +
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
            .frame(height: 50)
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
        case .disabled:        return "Loading…"
        }
    }

    private var primaryActionBackground: some ShapeStyle {
        switch model.primaryAction {
        case .showPaywall: return AnyShapeStyle(Color.cfAccent.opacity(0.15))
        default:           return AnyShapeStyle(Color.cfAccent)
        }
    }

    private var primaryActionForeground: Color {
        switch model.primaryAction {
        case .showPaywall: return Color.cfAccent
        default:           return Color.white
        }
    }

    // MARK: - Depth & Tone entry point

    private var depthToneRow: some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, .cfSpacing16)
            Button {
                // Depth/tone sheet — wired in a later prompt.
            } label: {
                HStack {
                    Label("Depth & Tone", systemImage: "slider.horizontal.3")
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
                }
                Divider().padding(.leading, .cfSpacing16)
            }
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

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await model.fetch() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.cfAccent)
        }
    }

    // MARK: - Haptics

    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    private func triggerSelectionHaptic() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}

// MARK: - VariantFamily display

private extension VariantFamily {
    var displayName: String {
        switch self {
        case .emh: return "Easy · Medium · Hard"
        case .pbc: return "Precise · Balanced · Challenging"
        case .unknown: return "Custom"
        }
    }
}

// MARK: - cfSpacing14 helper

private extension CGFloat {
    static let cfSpacing14: CGFloat = 14
}

// MARK: - Previews

#if DEBUG
#Preview("Free — locked (paywall)") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailFreeLocked
        )
    }
}

#Preview("In-progress") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailInProgress
        )
    }
}

#Preview("Completed") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailCompleted
        )
    }
}

#Preview("Dark mode — in-progress") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailInProgress
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("XXL text") {
    NavigationStack {
        BookDetailView(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailInProgress
        )
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
