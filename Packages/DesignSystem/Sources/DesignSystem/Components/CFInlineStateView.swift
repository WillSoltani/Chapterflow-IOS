import SwiftUI

/// Explicit presentation state for a compact inline content region.
///
/// Copy is supplied by the caller and the value deliberately stores no raw
/// `Error`, transport payload, or retry closure.
public struct CFInlineState: Equatable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case loading
        case empty
        case error
        case offline

        var indicatorName: String {
            switch self {
            case .loading:
                "hourglass"
            case .empty:
                "tray"
            case .error:
                "exclamationmark.triangle"
            case .offline:
                "wifi.slash"
            }
        }

        var supportsRetry: Bool {
            self == .error || self == .offline
        }
    }

    public let kind: Kind
    public let title: String
    public let message: String?

    public init(kind: Kind, title: String, message: String? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
    }
}

/// A paired retry label and action for recoverable inline states.
public struct CFInlineRetryAction {
    public let title: String
    let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

/// Compact loading, empty, error, and offline feedback for an inline region.
///
/// State is communicated through distinct symbols and caller-approved
/// copy, never color alone. VoiceOver traverses heading, message, then retry.
public struct CFInlineStateView: View {
    let state: CFInlineState
    let retryAction: CFInlineRetryAction?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let minimumActionTarget = CGFloat.cfIconLarge

    public init(
        state: CFInlineState,
        retryAction: CFInlineRetryAction? = nil
    ) {
        self.state = state
        self.retryAction = state.kind.supportsRetry ? retryAction : nil
    }

    public var body: some View {
        content
            .id(state)
            .transition(.opacity)
            .animation(
                Self.animatesStateChanges(reduceMotion: reduceMotion)
                    ? .easeInOut(duration: 0.2)
                    : nil,
                value: state
            )
    }

    static func animatesStateChanges(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    var accessibilityOrder: [String] {
        var elements = [state.title]
        if let message = state.message {
            elements.append(message)
        }
        if let retryAction {
            elements.append(retryAction.title)
        }
        return elements
    }

    var showsRetry: Bool {
        retryAction != nil
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            HStack(alignment: .top, spacing: .cfSpacing12) {
                indicator
                    .frame(minWidth: .cfIconSmall)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text(state.title)
                        .cfEditorialTextStyle(.metadata)
                        .foregroundStyle(Color.cfLabel)
                        .accessibilityAddTraits(.isHeader)

                    if let message = state.message {
                        Text(message)
                            .cfEditorialTextStyle(.caption)
                            .foregroundStyle(Color.cfSecondaryLabel)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let retryAction {
                Button(retryAction.title, action: retryAction.action)
                    .buttonStyle(.bordered)
                    .tint(Color.cfAccent)
                    .frame(
                        minWidth: Self.minimumActionTarget,
                        minHeight: Self.minimumActionTarget
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.cfSecondaryBackground,
            in: RoundedRectangle(cornerRadius: .cfRadius12)
        )
        .accessibilityElement(children: .contain)
    }

    private var indicator: some View {
        Image(systemName: state.kind.indicatorName)
            .font(.cfBody)
            .symbolRenderingMode(.hierarchical)
    }
}

#Preview("Inline editorial states") {
    VStack(spacing: .cfSpacing12) {
        CFInlineStateView(
            state: CFInlineState(
                kind: .loading,
                title: "Loading your highlights",
                message: "This should only take a moment."
            )
        )
        CFInlineStateView(
            state: CFInlineState(
                kind: .empty,
                title: "No highlights yet",
                message: "Select a passage while reading to keep it here."
            )
        )
        CFInlineStateView(
            state: CFInlineState(
                kind: .error,
                title: "Highlights could not load",
                message: "Your saved highlights are still safe."
            ),
            retryAction: CFInlineRetryAction("Try Again") {}
        )
        CFInlineStateView(
            state: CFInlineState(
                kind: .offline,
                title: "You're offline",
                message: "Reconnect to refresh this section."
            ),
            retryAction: CFInlineRetryAction("Retry") {}
        )
    }
    .padding(.cfSpacing16)
    .background(Color.cfGroupedBackground)
}
