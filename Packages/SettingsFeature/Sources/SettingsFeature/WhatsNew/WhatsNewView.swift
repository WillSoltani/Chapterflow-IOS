import SwiftUI
import DesignSystem

// MARK: - WhatsNewView

/// A tasteful, Apple-"Pro"-restraint release-notes screen: a large title, a list
/// of feature highlights, and a single prominent action to dismiss.
///
/// Presented automatically once after an app update, and always reachable from
/// Settings ▸ About. Skippable and fully accessible (Dynamic Type, combined
/// accessibility elements, Reduce Motion friendly).
public struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let release: WhatsNewRelease
    private let onContinue: (() -> Void)?

    /// - Parameters:
    ///   - release: The release notes to display.
    ///   - onContinue: Called when the user dismisses via the primary action or
    ///     the close button (before the view dismisses itself).
    public init(release: WhatsNewRelease, onContinue: (() -> Void)? = nil) {
        self.release = release
        self.onContinue = onContinue
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: .cfSpacing32) {
                    header
                    highlights
                }
                .padding(.horizontal, .cfSpacing24)
                .padding(.top, .cfSpacing32)
                .padding(.bottom, .cfSpacing24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.cfGroupedBackground)
            .safeAreaInset(edge: .bottom) { continueBar }
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        finish()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.cfTertiaryLabel)
                    }
                    .accessibilityLabel("Close What's New")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Text(release.title)
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfLabel)
                .fixedSize(horizontal: false, vertical: true)
            Text("Version \(release.version)")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(release.title). Version \(release.version)")
    }

    // MARK: - Highlights

    private var highlights: some View {
        VStack(alignment: .leading, spacing: .cfSpacing24) {
            ForEach(release.highlights) { highlight in
                HighlightRow(highlight: highlight)
            }
        }
    }

    // MARK: - Continue bar

    private var continueBar: some View {
        VStack(spacing: 0) {
            Button {
                finish()
            } label: {
                Text("Continue")
                    .font(.cfHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .cfSpacing12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cfAccent)
            .padding(.horizontal, .cfSpacing24)
            .padding(.vertical, .cfSpacing16)
            .accessibilityLabel("Continue")
            .accessibilityHint("Dismisses What's New")
        }
        .background(.bar)
    }

    // MARK: - Actions

    private func finish() {
        onContinue?()
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dismiss() }
        } else {
            dismiss()
        }
    }
}

// MARK: - HighlightRow

private struct HighlightRow: View {
    let highlight: WhatsNewHighlight

    var body: some View {
        HStack(alignment: .top, spacing: .cfSpacing16) {
            Image(systemName: highlight.symbolName)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Color.cfAccent)
                .frame(width: .cfIconLarge, height: .cfIconLarge)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text(highlight.title)
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Text(highlight.detail)
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(highlight.title). \(highlight.detail)")
    }
}
