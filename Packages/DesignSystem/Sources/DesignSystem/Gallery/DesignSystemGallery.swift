import SwiftUI

/// A scrollable catalogue of all DesignSystem tokens and components.
///
/// Use this view inside Xcode Previews or a debug build to verify that
/// every token and component looks correct in light/dark mode and at
/// every Dynamic Type size.
public struct DesignSystemGallery: View {
    @State private var toastVisible = false
    @State private var ringProgress: Double = 0.6
    @State private var colorScheme: ColorScheme? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                colorTokensSection
                typographySection
                spacingSection
                componentsSection
                buttonsSection
            }
            .navigationTitle("Design System")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Light") { colorScheme = .light }
                        Button("Dark")  { colorScheme = .dark }
                        Button("System") { colorScheme = nil }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                }
            }
        }
        .preferredColorScheme(colorScheme)
        .cfToast("Toast preview", systemImage: "checkmark.circle.fill", isPresented: toastVisible)
    }

    // MARK: - Color tokens

    private var colorTokensSection: some View {
        Section("Color Tokens") {
            colorRow("cfAccent", color: .cfAccent)
            colorRow("cfLabel", color: .cfLabel)
            colorRow("cfSecondaryLabel", color: .cfSecondaryLabel)
            colorRow("cfBackground", color: .cfBackground)
            colorRow("cfSecondaryBackground", color: .cfSecondaryBackground)
            colorRow("cfGroupedBackground", color: .cfGroupedBackground)
            colorRow("cfFill", color: .cfFill)
            colorRow("cfSeparator", color: .cfSeparator)
        }
    }

    private func colorRow(_ name: String, color: Color) -> some View {
        HStack(spacing: .cfSpacing12) {
            RoundedRectangle(cornerRadius: .cfRadius8)
                .fill(color)
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: .cfRadius8)
                        .stroke(Color.cfSeparator, lineWidth: 0.5)
                )
            Text(name)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
        }
    }

    // MARK: - Typography

    private var typographySection: some View {
        Section("Typography") {
            Group {
                typeRow("cfLargeTitle",  font: .cfLargeTitle)
                typeRow("cfTitle1",      font: .cfTitle1)
                typeRow("cfTitle2",      font: .cfTitle2)
                typeRow("cfTitle3",      font: .cfTitle3)
                typeRow("cfHeadline",    font: .cfHeadline)
                typeRow("cfSubheadline", font: .cfSubheadline)
                typeRow("cfBody",        font: .cfBody)
                typeRow("cfCallout",     font: .cfCallout)
                typeRow("cfFootnote",    font: .cfFootnote)
                typeRow("cfCaption",     font: .cfCaption)
            }
        }
    }

    private func typeRow(_ name: String, font: Font) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(name)
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
            Text("The quick brown fox")
                .font(font)
        }
        .padding(.vertical, .cfSpacing4)
    }

    // MARK: - Spacing / Radius

    private var spacingSection: some View {
        Section("Spacing & Radius") {
            Group {
                spacingRow("cfRadius8",  value: .cfRadius8)
                spacingRow("cfRadius12", value: .cfRadius12)
                spacingRow("cfRadius16", value: .cfRadius16)
                spacingRow("cfRadius20", value: .cfRadius20)
                spacingRow("cfRadius24", value: .cfRadius24)
            }
        }
    }

    private func spacingRow(_ name: String, value: CGFloat) -> some View {
        HStack(spacing: .cfSpacing12) {
            RoundedRectangle(cornerRadius: value)
                .fill(Color.cfAccent.opacity(0.2))
                .frame(width: value * 2.5, height: value * 2.5)
            VStack(alignment: .leading, spacing: .cfSpacing2) {
                Text(name).font(.cfCaption).foregroundStyle(Color.cfSecondaryLabel)
                Text("\(Int(value)) pt").font(.cfFootnote)
            }
        }
        .padding(.vertical, .cfSpacing4)
    }

    // MARK: - Components

    private var componentsSection: some View {
        Section("Components") {
            // CFCard
            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text("CFCard").font(.cfCaption).foregroundStyle(Color.cfSecondaryLabel)
                CFCard {
                    HStack(spacing: .cfSpacing12) {
                        Image(systemName: "book.fill")
                            .font(.cfTitle2)
                            .foregroundStyle(Color.cfAccent)
                        VStack(alignment: .leading, spacing: .cfSpacing4) {
                            Text("Atomic Habits")
                                .font(.cfSubheadline)
                            Text("James Clear · Chapter 4")
                                .font(.cfCaption)
                                .foregroundStyle(Color.cfSecondaryLabel)
                        }
                        Spacer()
                        CFProgressRing(progress: 0.4)
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .padding(.vertical, .cfSpacing4)

            // CFToast
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                Text("CFToast").font(.cfCaption).foregroundStyle(Color.cfSecondaryLabel)
                CFToast("Chapter saved", systemImage: "checkmark.circle.fill")
                CFToast("No connection", systemImage: "wifi.slash")
                Button("Toggle overlay toast") {
                    withAnimation { toastVisible.toggle() }
                }
                .font(.cfFootnote)
                .foregroundStyle(Color.cfAccent)
            }
            .padding(.vertical, .cfSpacing4)

            // CFProgressRing
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                Text("CFProgressRing").font(.cfCaption).foregroundStyle(Color.cfSecondaryLabel)
                HStack(spacing: .cfSpacing24) {
                    ForEach([0.0, 0.25, 0.6, 1.0], id: \.self) { p in
                        VStack(spacing: .cfSpacing4) {
                            CFProgressRing(progress: p)
                                .frame(width: 44, height: 44)
                            Text("\(Int(p * 100))%")
                                .font(.cfCaption2)
                                .foregroundStyle(Color.cfSecondaryLabel)
                        }
                    }
                }
            }
            .padding(.vertical, .cfSpacing4)

            // CFSkeleton
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                Text("CFSkeleton").font(.cfCaption).foregroundStyle(Color.cfSecondaryLabel)
                CFSkeleton().frame(height: 18).frame(maxWidth: 200)
                CFSkeleton().frame(height: 14).frame(maxWidth: 260)
                CFSkeleton().frame(height: 14).frame(maxWidth: 180)
            }
            .padding(.vertical, .cfSpacing4)

            // CFEmptyState
            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text("CFEmptyState").font(.cfCaption).foregroundStyle(Color.cfSecondaryLabel)
                CFEmptyState(
                    systemImage: "books.vertical",
                    title: "No Books Yet",
                    description: "Add books to your library.",
                    actionLabel: "Browse"
                ) {}
                .frame(height: 220)
            }
            .padding(.vertical, .cfSpacing4)
        }
    }

    // MARK: - Buttons

    private var buttonsSection: some View {
        Section("Buttons") {
            VStack(spacing: .cfSpacing12) {
                Group {
                    if #available(iOS 26, macOS 26, *) {
                        Button("Glass Button") {}
                            .buttonStyle(.glass)
                        Button("Glass Prominent") {}
                            .buttonStyle(.glassProminent)
                    } else {
                        Button("Bordered Button") {}
                            .buttonStyle(.bordered)
                            .tint(.cfAccent)
                        Button("Bordered Prominent") {}
                            .buttonStyle(.borderedProminent)
                            .tint(.cfAccent)
                    }
                }
                Button("Destructive", role: .destructive) {}
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, .cfSpacing8)
        }
    }
}

// MARK: - Preview

#Preview("Gallery — light") {
    DesignSystemGallery()
}

#Preview("Gallery — dark") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}

#Preview("Gallery — XXL text") {
    DesignSystemGallery()
        .dynamicTypeSize(.accessibility3)
}
