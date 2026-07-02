import SwiftUI

/// A floating notification pill anchored as an overlay (`.top` or `.bottom`).
///
/// On iOS/macOS 26+ uses Liquid Glass (`glassEffect(in: Capsule())`).
/// On older OS or when Reduce Transparency is enabled falls back to
/// a `.regularMaterial` or solid capsule.
public struct CFToast: View {
    public let message: String
    public let systemImage: String?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(_ message: String, systemImage: String? = nil) {
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        Group {
            if #available(iOS 26, macOS 26, *) {
                label
                    .glassEffect(in: Capsule())
            } else {
                label
                    .background(
                        Capsule().fill(
                            reduceTransparency
                                ? AnyShapeStyle(Color.cfSecondaryBackground)
                                : AnyShapeStyle(.regularMaterial)
                        )
                    )
            }
        }
    }

    private var label: some View {
        HStack(spacing: .cfSpacing8) {
            if let icon = systemImage {
                Image(systemName: icon)
                    .font(.cfCaption)
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(.cfFootnote)
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing8)
    }
}

// MARK: - View modifier helper

public extension View {
    /// Presents a `CFToast` as a top overlay with an entrance/exit transition.
    func cfToast(
        _ message: String,
        systemImage: String? = nil,
        isPresented: Bool
    ) -> some View {
        overlay(alignment: .top) {
            if isPresented {
                CFToast(message, systemImage: systemImage)
                    .padding(.top, .cfSpacing8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
    }
}

// MARK: - Preview

#Preview("CFToast") {
    VStack(spacing: .cfSpacing24) {
        CFToast("Chapter saved to library", systemImage: "checkmark.circle.fill")
        CFToast("No internet connection", systemImage: "wifi.slash")
        CFToast("Syncing…")
    }
    .padding(.cfSpacing24)
}

#Preview("CFToast overlay") {
    @Previewable @State var show = false
    ZStack {
        Color.cfBackground.ignoresSafeArea()
        Button("Toggle Toast") { show.toggle() }
    }
    .cfToast("Reading progress saved", systemImage: "checkmark", isPresented: show)
}
