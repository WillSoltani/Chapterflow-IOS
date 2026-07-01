import SwiftUI

/// Full-screen blur shown while waiting for Face ID / Touch ID to unlock the app.
public struct AppLockView: View {
    let manager: AppLockManager

    public init(manager: AppLockManager) {
        self.manager = manager
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("ChapterFlow is Locked")
                    .font(.title3.weight(.semibold))

                Button {
                    Task { await manager.authenticate() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .frame(minWidth: 160)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Unlock app with Face ID or Touch ID")
            }
        }
    }
}

#Preview("App Lock") {
    AppLockView(manager: AppLockManager())
}
