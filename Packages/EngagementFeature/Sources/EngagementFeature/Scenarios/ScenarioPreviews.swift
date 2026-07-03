import SwiftUI
import Models
import DesignSystem

// MARK: - ScenariosView Previews

#Preview("Scenarios Hub — light", traits: .sizeThatFitsLayout) {
    NavigationStack {
        ScenariosView(model: ScenariosModel.preview)
    }
    .preferredColorScheme(.light)
    .task { ScenariosModel.preview.load() }
}

#Preview("Scenarios Hub — dark", traits: .sizeThatFitsLayout) {
    NavigationStack {
        ScenariosView(model: ScenariosModel.preview)
    }
    .preferredColorScheme(.dark)
    .task { ScenariosModel.preview.load() }
}

#Preview("Scenarios Hub — XXL text", traits: .sizeThatFitsLayout) {
    NavigationStack {
        ScenariosView(model: ScenariosModel.preview)
    }
    .dynamicTypeSize(.accessibility3)
    .task { ScenariosModel.preview.load() }
}

#Preview("Scenarios Hub — empty", traits: .sizeThatFitsLayout) {
    NavigationStack {
        ScenariosView(model: ScenariosModel.previewEmpty)
    }
    .task { ScenariosModel.previewEmpty.load() }
}

// MARK: - ComposeScenarioView Previews

#Preview("Compose — light") {
    ComposeScenarioView(model: ScenariosModel.preview)
        .preferredColorScheme(.light)
}

#Preview("Compose — dark") {
    ComposeScenarioView(model: ScenariosModel.preview)
        .preferredColorScheme(.dark)
}

#Preview("Compose — XXL") {
    ComposeScenarioView(model: ScenariosModel.preview)
        .dynamicTypeSize(.accessibility3)
}

// MARK: - ScenarioDetailView Previews

#Preview("Detail — approved", traits: .sizeThatFitsLayout) {
    NavigationStack {
        ScenarioDetailView(scenario: .previewApproved)
    }
}

#Preview("Detail — pending", traits: .sizeThatFitsLayout) {
    NavigationStack {
        ScenarioDetailView(scenario: .previewPending)
    }
}

#Preview("Detail — rejected", traits: .sizeThatFitsLayout) {
    NavigationStack {
        ScenarioDetailView(scenario: .previewRejected)
    }
}

#Preview("Detail — dark", traits: .sizeThatFitsLayout) {
    NavigationStack {
        ScenarioDetailView(scenario: .previewApproved)
    }
    .preferredColorScheme(.dark)
}

// MARK: - ScenarioStatusBadge Previews

#Preview("Status badges", traits: .sizeThatFitsLayout) {
    VStack(spacing: 12) {
        ScenarioStatusBadge(status: .pending, pointsAwarded: nil)
        ScenarioStatusBadge(status: .approved, pointsAwarded: 50)
        ScenarioStatusBadge(status: .approved, pointsAwarded: nil)
        ScenarioStatusBadge(status: .rejected, pointsAwarded: nil)
    }
    .padding()
}
