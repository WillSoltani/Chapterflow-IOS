#if DEBUG && canImport(UIKit)
import SwiftUI
import UIKit
import Models
import Persistence

// MARK: - Helpers

@MainActor
private func appearance(theme: ReadingTheme = .system) -> ReadingAppearance {
    ReadingAppearance(
        colors: .tokens(for: theme),
        fontScale: 1.0,
        lineSpacing: 6,
        colorSchemeOverride: theme == .dark ? .dark : (theme == .system ? nil : .light)
    )
}

private var sampleHook: String {
    "What if the key to getting **37 times better** at anything in a year required only a 1% improvement each day?"
}

private var sampleCounterIntuition: String {
    "Most people think success requires dramatic transformations. But the science shows it's the opposite — tiny, consistent improvements beat big, inconsistent efforts every time."
}

private var sampleTryThisNow: String {
    "Right now, think of one habit you want to build. Write down the 2-minute version of it. That's your atomic habit."
}

private var sampleKeyTakeaway: String {
    "You don't rise to the level of your goals; you _fall to the level of your systems_."
}

private var sampleFailureRecovery: FailureRecovery {
    FailureRecovery(
        normalizingLine: "It happens to almost everyone — you start strong, then life intervenes and the habit disappears for a few days.",
        cueQuestion: "When you notice you've broken the streak, which of these sounds most like your situation?",
        options: [
            "I forgot and it slipped past me without noticing.",
            "I tried but the habit felt too big that day.",
            "I was dealing with something stressful and deprioritised it.",
        ],
        repairLine: "Miss once — never twice. One missed day is an accident. Two is the start of a new habit."
    )
}

private var sampleTransferPrompt: TransferPrompt {
    TransferPrompt(
        prompt: "You've applied this to building a habit — where else in your life does the 1% principle apply?",
        contexts: ["Learning a language", "Writing practice", "Career growth", "Fitness", "Relationships"]
    )
}

private var sampleBehaviorLoop: BehaviorLoop {
    BehaviorLoop(readerPatterns: [
        ReaderPattern(id: "planner", label: "The Planner", mapsToPlanIndex: 0, mapsToExampleIndex: nil),
        ReaderPattern(id: "doer", label: "The Doer", mapsToPlanIndex: nil, mapsToExampleIndex: 0),
        ReaderPattern(id: "doubter", label: "The Doubter", mapsToPlanIndex: nil, mapsToExampleIndex: 1),
    ])
}

private var sampleExamples: [ResolvedExample] {
    [
        ResolvedExample(
            exampleId: "ex-1",
            title: "The Exercise Habit",
            scenario: "You've been trying to go to the gym for years but always fall off after a few weeks.",
            whatToDo: ["Start with just 2 minutes", "Set clothes out the night before"],
            whyItMatters: "Starting small removes the mental barrier.",
            contexts: ["fitness"],
            category: "health"
        ),
        ResolvedExample(
            exampleId: "ex-2",
            title: "Learning Guitar",
            scenario: "You want to learn guitar but years of practice feels overwhelming.",
            whatToDo: ["Pick up the guitar for 2 minutes after dinner"],
            whyItMatters: "The goal is to become someone who practices daily.",
            contexts: ["learning"],
            category: "learning"
        ),
    ]
}

private var sampleIfThenPlans: [ResolvedIfThenPlan] {
    [
        ResolvedIfThenPlan(
            context: "When I finish my morning coffee",
            plan: "I will spend 2 minutes on the habit I'm building, even if it's just setting up."
        ),
    ]
}

// MARK: - HookBannerView previews

#Preview("Hook — Light") {
    ScrollView {
        HookBannerView(text: sampleHook)
            .padding(.horizontal, 24)
    }
    .background(Color(UIColor.systemBackground))
    .readerAppearance(appearance())
}

#Preview("Hook — Dark") {
    ScrollView {
        HookBannerView(text: sampleHook)
            .padding(.horizontal, 24)
    }
    .background(Color.black)
    .readerAppearance(appearance(theme: .dark))
}

#Preview("Hook — Sepia XXL") {
    ScrollView {
        HookBannerView(text: sampleHook)
            .padding(.horizontal, 24)
    }
    .background(Color(red: 0.961, green: 0.941, blue: 0.898))
    .readerAppearance(appearance(theme: .sepia))
    .dynamicTypeSize(.accessibility3)
}

// MARK: - CounterIntuitionView previews

#Preview("Counterintuition — Light") {
    ScrollView {
        CounterIntuitionView(text: sampleCounterIntuition)
            .padding(.horizontal, 24)
    }
    .background(Color(UIColor.systemBackground))
    .readerAppearance(appearance())
}

#Preview("Counterintuition — Dark") {
    ScrollView {
        CounterIntuitionView(text: sampleCounterIntuition)
            .padding(.horizontal, 24)
    }
    .background(Color.black)
    .readerAppearance(appearance(theme: .dark))
}

// MARK: - TryThisNowView previews

#Preview("Try This Now — Light") {
    ScrollView {
        TryThisNowView(text: sampleTryThisNow)
            .padding(.horizontal, 24)
    }
    .background(Color(UIColor.systemBackground))
    .readerAppearance(appearance())
}

#Preview("Try This Now — Dark") {
    ScrollView {
        TryThisNowView(text: sampleTryThisNow)
            .padding(.horizontal, 24)
    }
    .background(Color.black)
    .readerAppearance(appearance(theme: .dark))
}

// MARK: - V21KeyTakeawayView previews

#Preview("v21 Key Takeaway — Light") {
    ScrollView {
        V21KeyTakeawayView(text: sampleKeyTakeaway)
            .padding(.horizontal, 24)
    }
    .background(Color(UIColor.systemBackground))
    .readerAppearance(appearance())
}

#Preview("v21 Key Takeaway — Sepia") {
    ScrollView {
        V21KeyTakeawayView(text: sampleKeyTakeaway)
            .padding(.horizontal, 24)
    }
    .background(Color(red: 0.961, green: 0.941, blue: 0.898))
    .readerAppearance(appearance(theme: .sepia))
}

// MARK: - FailureRecoveryView previews

#Preview("Failure Recovery — Light") {
    ScrollView {
        FailureRecoveryView(recovery: sampleFailureRecovery)
            .padding(.horizontal, 24)
    }
    .background(Color(UIColor.systemBackground))
    .readerAppearance(appearance())
}

#Preview("Failure Recovery — Dark XXL") {
    ScrollView {
        FailureRecoveryView(recovery: sampleFailureRecovery)
            .padding(.horizontal, 24)
    }
    .background(Color.black)
    .readerAppearance(appearance(theme: .dark))
    .dynamicTypeSize(.accessibility3)
}

// MARK: - TransferPromptView previews

#Preview("Transfer Prompt — Light") {
    ScrollView {
        TransferPromptView(transfer: sampleTransferPrompt)
            .padding(.horizontal, 24)
    }
    .background(Color(UIColor.systemBackground))
    .readerAppearance(appearance())
}

#Preview("Transfer Prompt — Dark") {
    ScrollView {
        TransferPromptView(transfer: sampleTransferPrompt)
            .padding(.horizontal, 24)
    }
    .background(Color.black)
    .readerAppearance(appearance(theme: .dark))
}

// MARK: - BehaviorLoopView previews

#Preview("Behavior Loop — Light") {
    ScrollView {
        BehaviorLoopView(
            loop: sampleBehaviorLoop,
            examples: sampleExamples,
            ifThenPlans: sampleIfThenPlans
        )
        .padding(.horizontal, 24)
    }
    .background(Color(UIColor.systemBackground))
    .readerAppearance(appearance())
}

#Preview("Behavior Loop — Dark") {
    ScrollView {
        BehaviorLoopView(
            loop: sampleBehaviorLoop,
            examples: sampleExamples,
            ifThenPlans: sampleIfThenPlans
        )
        .padding(.horizontal, 24)
    }
    .background(Color.black)
    .readerAppearance(appearance(theme: .dark))
}

#Preview("Behavior Loop — Sepia XXL") {
    ScrollView {
        BehaviorLoopView(
            loop: sampleBehaviorLoop,
            examples: sampleExamples,
            ifThenPlans: sampleIfThenPlans
        )
        .padding(.horizontal, 24)
    }
    .background(Color(red: 0.961, green: 0.941, blue: 0.898))
    .readerAppearance(appearance(theme: .sepia))
    .dynamicTypeSize(.accessibility3)
}

// MARK: - Full chapter with v21Extras present

#Preview("Full chapter — v21Extras present (Light)") {
    ReaderContentView(
        chapter: previewChapterEMH,
        preferences: {
            let p = AppPreferences(defaults: UserDefaults(suiteName: "v21.preview.light"))
            p.readerTheme = .light
            return p
        }()
    )
}

#Preview("Full chapter — v21Extras present (Dark)") {
    ReaderContentView(
        chapter: previewChapterEMH,
        preferences: {
            let p = AppPreferences(defaults: UserDefaults(suiteName: "v21.preview.dark"))
            p.readerTheme = .dark
            return p
        }()
    )
}

#Preview("Full chapter — v21Extras present (Sepia XXL)") {
    ReaderContentView(
        chapter: previewChapterEMH,
        preferences: {
            let p = AppPreferences(defaults: UserDefaults(suiteName: "v21.preview.sepia"))
            p.readerTheme = .sepia
            return p
        }()
    )
    .dynamicTypeSize(.accessibility3)
}

// MARK: - Full chapter without v21Extras (degrades cleanly)

#Preview("Full chapter — no v21Extras (Light)") {
    ReaderContentView(
        chapter: previewChapterPBC,
        preferences: {
            let p = AppPreferences(defaults: UserDefaults(suiteName: "v21.preview.pbc.light"))
            p.readerTheme = .light
            return p
        }()
    )
}

#Preview("Full chapter — no v21Extras (Dark)") {
    ReaderContentView(
        chapter: previewChapterPBC,
        preferences: {
            let p = AppPreferences(defaults: UserDefaults(suiteName: "v21.preview.pbc.dark"))
            p.readerTheme = .dark
            return p
        }()
    )
}
#endif
