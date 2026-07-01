#if os(iOS)
import SwiftUI

// MARK: - AuthTextField

public struct AuthTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences

    public init(
        _ label: String,
        placeholder: String = "",
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: TextInputAutocapitalization = .sentences
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.autocapitalization = autocapitalization
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .textContentType(textContentType)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .accessibilityLabel(label)
    }
}

// MARK: - AuthSecureField

public struct AuthSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var textContentType: UITextContentType? = .password

    @State private var isVisible = false

    public init(
        _ label: String,
        placeholder: String = "",
        text: Binding<String>,
        textContentType: UITextContentType? = .password
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.textContentType = textContentType
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack {
                Group {
                    if isVisible {
                        TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                            .textContentType(textContentType)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField(placeholder.isEmpty ? label : placeholder, text: $text)
                            .textContentType(textContentType)
                    }
                }
                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel(isVisible ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .accessibilityLabel(label)
    }
}

// MARK: - PasswordStrengthBar

public struct PasswordStrengthBar: View {
    let strength: PasswordStrength

    public init(_ strength: PasswordStrength) {
        self.strength = strength
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(strength.color)
                    .frame(width: geo.size.width * strength.fraction, height: 4)
                    .animation(.spring(response: 0.3), value: strength)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Password strength: \(strength.label)")
    }
}

// MARK: - CFPrimaryButton

public struct CFPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    public init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title).fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}

// MARK: - CFTextButton

public struct CFTextButton: View {
    let title: String
    let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline)
        }
        .accessibilityLabel(title)
    }
}

// MARK: - VerificationCodeField

/// A row of 6 digit boxes for one-time code entry.
public struct VerificationCodeField: View {
    @Binding var code: String
    @FocusState private var isFocused: Bool

    public init(code: Binding<String>) {
        self._code = code
    }

    public var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .opacity(0)
                .frame(width: 1, height: 1)
                .focused($isFocused)
                .onChange(of: code) {
                    code = String(code.filter(\.isNumber).prefix(6))
                }

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let digit: String = i < code.count
                        ? String(code[code.index(code.startIndex, offsetBy: i)])
                        : ""
                    Text(digit)
                        .font(.title2.monospaced())
                        .frame(width: 44, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    i < code.count ? Color.accentColor : Color(uiColor: .tertiaryLabel),
                                    lineWidth: i < code.count ? 1.5 : 0.5
                                )
                        )
                }
            }
            .onTapGesture { isFocused = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verification code, \(code.count) of 6 digits entered")
        .onAppear { isFocused = true }
    }
}

// MARK: - CFToast / cfToast modifier

/// Transient message banner shown at the bottom of the screen.
public struct CFToast: View {
    let message: String
    let isError: Bool

    public init(_ message: String, isError: Bool = false) {
        self.message = message
        self.isError = isError
    }

    public var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(isError ? .white : Color.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(isError ? Color.red : Color(uiColor: .secondarySystemBackground))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            )
            .accessibilityLabel(isError ? "Error: \(message)" : message)
    }
}

private struct CFToastModifier: ViewModifier {
    let message: String?
    let isError: Bool

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let message {
                CFToast(message, isError: isError)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4), value: message)
    }
}

public extension View {
    func cfToast(message: String?, isError: Bool = false) -> some View {
        modifier(CFToastModifier(message: message, isError: isError))
    }
}

#endif // os(iOS)
