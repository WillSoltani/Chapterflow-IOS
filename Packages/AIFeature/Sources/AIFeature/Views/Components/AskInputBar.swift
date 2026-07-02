import SwiftUI
import DesignSystem

/// The text-entry bar at the bottom of the Ask the Book sheet.
///
/// Shows a multi-line text field and a send button. The send button is
/// disabled while a question is in flight or the text field is empty.
struct AskInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let canSend: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: .cfSpacing8) {
            TextField("Ask a question…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit {
                    if canSend { onSend() }
                }
                .accessibilityLabel("Question input field")

            sendButton
        }
        .padding(.horizontal, .cfSpacing12)
        .padding(.vertical, .cfSpacing8)
        .background(inputBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))
        .padding(.horizontal, .cfSpacing16)
        .padding(.bottom, .cfSpacing8)
        .onAppear { isFocused = true }
    }

    private var sendButton: some View {
        Button {
            triggerHaptic()
            onSend()
        } label: {
            Group {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .frame(width: 32, height: 32)
            .background(canSend ? Color.cfAccent : Color.cfSecondaryFill, in: Circle())
            .foregroundStyle(canSend ? Color.white : Color.cfTertiaryLabel)
        }
        .disabled(!canSend || isSending)
        .animation(.easeInOut(duration: 0.15), value: canSend)
        .accessibilityLabel("Send question")
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var inputBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color.cfSecondaryBackground)
            : AnyShapeStyle(.regularMaterial)
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
