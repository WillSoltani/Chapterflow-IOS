import SwiftUI
import DesignSystem

/// Bottom sheet for choosing the sleep timer option.
struct SleepTimerSheet: View {
    @Binding var selected: SleepTimerOption
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            HStack {
                Text("Sleep Timer")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)
                Spacer()
                Button("Done", action: onDismiss)
                    .font(.cfCallout)
                    .foregroundStyle(Color.cfAccent)
                    .accessibilityLabel("Close sleep timer")
            }
            .padding(.horizontal, .cfSpacing20)
            .padding(.top, .cfSpacing20)
            .padding(.bottom, .cfSpacing8)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(SleepTimerOption.allCases, id: \.displayName) { option in
                        Button {
                            selected = option
                        } label: {
                            HStack {
                                Text(option.displayName)
                                    .font(.cfBody)
                                    .foregroundStyle(Color.cfLabel)
                                Spacer()
                                if selected == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.cfAccent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(.horizontal, .cfSpacing20)
                            .padding(.vertical, .cfSpacing16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.displayName)
                        .accessibilityAddTraits(selected == option ? .isSelected : [])

                        Divider()
                            .padding(.leading, .cfSpacing20)
                    }
                }
            }
        }
        .background(Color.cfBackground)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview("Sleep timer sheet") {
    Text("Content")
        .sheet(isPresented: .constant(true)) {
            SleepTimerSheet(selected: .constant(.off))
        }
}
