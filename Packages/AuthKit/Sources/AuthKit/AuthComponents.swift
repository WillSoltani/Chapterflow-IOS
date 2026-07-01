import SwiftUI
import DesignSystem

// MARK: - AuthTextField

/// A labeled, styled text input for auth forms.
///
/// On iOS, full UIKit integration (keyboard type, content type,
/// autocapitalization) is available. On macOS the component renders a plain
/// labeled text field suitable for host-toolchain unit-test builds.
public struct AuthTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    // UIKit-specific storage — only allocated on iOS
#if canImport(UIKit)
    private let keyboardType: UIKeyboardType
    private let textContentType: UITextContentType?
    private let autocapitalization: TextInputAutocapitalization
#endif

    // MARK: Init

#if canImport(UIKit)
    public init(
        label: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: TextInputAutocapitalization = .never
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.autocapitalization = autocapitalization
    }
#else
    public init(
        label: String,
        placeholder: String,
        text: Binding<String>
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
    }
#endif

    // MARK: Body

    public var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(label)
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .accessibilityHidden(true)
            inputField
                .padding(.cfSpacing12)
                .background(Color.cfSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
                .font(.cfBody)
                .accessibilityLabel(label)
        }
    }

    @ViewBuilder
    private var inputField: some View {
#if canImport(UIKit)
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled()
#else
        TextField(placeholder, text: $text)
            .autocorrectionDisabled()
#endif
    }
}

// MARK: - AuthSecureField

/// A labeled secure text field with a show/hide password toggle.
public struct AuthSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

#if canImport(UIKit)
    private let textContentType: UITextContentType?

    public init(
        label: String,
        placeholder: String,
        text: Binding<String>,
        textContentType: UITextContentType? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.textContentType = textContentType
    }
#else
    public init(
        label: String,
        placeholder: String,
        text: Binding<String>
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
    }
#endif

    @State private var isVisible: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(label)
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .accessibilityHidden(true)
            HStack {
                inputField
                    .font(.cfBody)
                    .accessibilityLabel(label)

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isVisible ? "Hide password" : "Show password")
            }
            .padding(.leading, .cfSpacing12)
            .padding(.trailing, .cfSpacing4)
            .background(Color.cfSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        }
    }

    @ViewBuilder
    private var inputField: some View {
#if canImport(UIKit)
        if isVisible {
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(textContentType)
        } else {
            SecureField(placeholder, text: $text)
                .textContentType(textContentType)
        }
#else
        if isVisible {
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
        } else {
            SecureField(placeholder, text: $text)
        }
#endif
    }
}

// MARK: - PasswordStrengthBar

/// Segmented bar visualizing password strength with a strength label.
public struct PasswordStrengthBar: View {
    let strength: PasswordStrength

    public init(strength: PasswordStrength) {
        self.strength = strength
    }

    public var body: some View {
        HStack(spacing: .cfSpacing4) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: .cfRadius4)
                    .fill(index < strength.score ? strength.color : Color.cfSecondaryBackground)
                    .frame(height: 4)
            }
            Text(strength.label)
                .font(.cfCaption)
                .foregroundStyle(strength.score == 0 ? Color.cfSecondaryLabel : strength.color)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .animation(.easeInOut(duration: 0.2), value: strength.score)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Password strength: \(strength.label)")
    }
}

// MARK: - CFToast

/// A toast notification shown at the bottom of the screen.
public struct CFToast: View {
    let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text(message)
                .font(.cfSubheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing12)
        .background(
            RoundedRectangle(cornerRadius: .cfRadius16)
                .fill(Color.black.opacity(0.85))
        )
        .padding(.horizontal, .cfSpacing24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - CFPrimaryButton

/// Full-width primary action button with loading state.
public struct CFPrimaryButton: View {
    let label: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    public init(
        label: String,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    private var effectivelyEnabled: Bool { isEnabled && !isLoading }

    public var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: .cfRadius16)
                    .fill(effectivelyEnabled ? Color.cfAccent : Color.cfAccent.opacity(0.4))
                    .frame(height: 52)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(label)
                        .font(.cfHeadline)
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(!effectivelyEnabled)
        .accessibilityLabel(label)
        .accessibilityHint(isLoading ? "Loading, please wait." : "")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - CFTextButton

/// A minimal text-only button for secondary actions.
public struct CFTextButton: View {
    let label: String
    var isEnabled: Bool = true
    let action: () -> Void

    public init(
        label: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.cfSubheadline)
                .foregroundStyle(isEnabled ? Color.cfAccent : Color.cfSecondaryLabel)
                .frame(minHeight: 44)
        }
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - VerificationCodeField

/// A 6-digit OTP entry field with visual character boxes.
public struct VerificationCodeField: View {
    @Binding var code: String
    var onComplete: ((String) -> Void)? = nil

    @FocusState private var isFieldFocused: Bool

    public init(code: Binding<String>, onComplete: ((String) -> Void)? = nil) {
        self._code = code
        self.onComplete = onComplete
    }

    private let boxCount = 6

    public var body: some View {
        ZStack {
            hiddenInput

            HStack(spacing: .cfSpacing8) {
                ForEach(0..<boxCount, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .onTapGesture {
                isFieldFocused = true
            }
        }
        .onAppear { isFieldFocused = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verification code entry, \(code.count) of \(boxCount) digits entered")
    }

    @ViewBuilder
    private var hiddenInput: some View {
        TextField("", text: $code)
#if canImport(UIKit)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
#endif
            .focused($isFieldFocused)
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .accessibilityHidden(true)
            .onChange(of: code) { _, newValue in
                let filtered = String(newValue.filter { $0.isNumber }.prefix(boxCount))
                if filtered != newValue { code = filtered }
                if filtered.count == boxCount {
                    onComplete?(filtered)
                }
            }
    }

    @ViewBuilder
    private func digitBox(at index: Int) -> some View {
        let chars = Array(code)
        let isFilled = index < chars.count
        let isActive = index == chars.count && isFieldFocused

        ZStack {
            RoundedRectangle(cornerRadius: .cfRadius12)
                .fill(Color.cfSecondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: .cfRadius12)
                        .strokeBorder(
                            isActive ? Color.cfAccent : Color.cfSeparator,
                            lineWidth: isActive ? 2 : 1
                        )
                )
                .frame(width: 44, height: 52)

            if isFilled {
                Text(String(chars[index]))
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)
            } else if isActive {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.cfAccent)
                    .frame(width: 2, height: 24)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

// MARK: - ToastOverlay view modifier

struct ToastOverlayModifier: ViewModifier {
    let message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                CFToast(message: message)
                    .padding(.bottom, .cfSpacing32)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .animation(.spring(duration: 0.35), value: message != nil)
    }
}

public extension View {
    /// Attaches a bottom-anchored toast overlay driven by an optional message string.
    func cfToast(_ message: String?) -> some View {
        modifier(ToastOverlayModifier(message: message))
    }
}
