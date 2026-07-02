/// The single place where `(chapter, variant, tone)` is resolved into a flat,
/// display-ready `ResolvedChapter`.
///
/// Every time the reader switches depth or tone, call `resolve(...)` — the result
/// is instant since all variant content is already in memory. No network needed.
///
/// ```swift
/// let resolver = ChapterContentResolver()
/// let resolved = resolver.resolve(
///     chapter: chapter,
///     selectedVariant: prefs.depthVariant,
///     selectedTone: prefs.toneKey
/// )
/// ```
public struct ChapterContentResolver: Sendable {
    public init() {}

    /// Resolves a `Chapter` for the given variant and tone preferences.
    ///
    /// - Parameters:
    ///   - chapter: The fully-loaded chapter with all variant content.
    ///   - selectedVariant: The user's preferred depth. Falls back to
    ///     `chapter.activeVariant`, then `chapter.availableVariants.first`.
    ///   - selectedTone: The user's tone preference.
    /// - Returns: A `ResolvedChapter` with every tone-keyed field collapsed.
    public func resolve(
        chapter: Chapter,
        selectedVariant: VariantKey,
        selectedTone: ToneKey
    ) -> ResolvedChapter {
        let variantKey = resolveVariant(selectedVariant, chapter: chapter)
        let content = chapter.variantContent(for: variantKey)

        let keyTakeaways = (content.keyTakeaways ?? []).map { kt in
            ResolvedKeyTakeaway(
                point: kt.point.resolve(selectedTone),
                moreDetails: kt.moreDetails?.resolve(selectedTone)
            )
        }

        let examples = chapter.examples.map { ex in
            ResolvedExample(
                exampleId: ex.exampleId,
                title: ex.title,
                scenario: ex.scenario.resolve(selectedTone),
                whatToDo: ex.whatToDo.resolve(selectedTone),
                whyItMatters: ex.whyItMatters.resolve(selectedTone),
                contexts: ex.contexts ?? [],
                category: ex.category
            )
        }

        let plan = chapter.implementationPlan.map { ip in
            ResolvedImplementationPlan(
                coreSkill: ip.coreSkill?.resolve(selectedTone),
                concreteAction: ip.concreteAction?.resolve(selectedTone),
                ifThenPlans: (ip.ifThenPlans ?? []).map { p in
                    ResolvedIfThenPlan(context: p.context, plan: p.plan.resolve(selectedTone))
                },
                twentyFourHourChallenge: ip.twentyFourHourChallenge?.resolve(selectedTone),
                weeklyPractice: ip.weeklyPractice?.resolve(selectedTone),
                friction: ip.friction?.resolve(selectedTone),
                checkpoint: ip.checkpoint?.resolve(selectedTone)
            )
        }

        let reviewCards = (chapter.reviewCards ?? []).map { card in
            ResolvedReviewCard(
                cardId: card.cardId,
                front: card.front.resolve(selectedTone),
                back: card.back.resolve(selectedTone),
                difficulty: card.difficulty
            )
        }

        return ResolvedChapter(
            chapterId: chapter.chapterId,
            number: chapter.number,
            title: chapter.title,
            readingTimeMinutes: chapter.readingTimeMinutes,
            chapterBreakdown: content.chapterBreakdown?.resolve(selectedTone),
            keyTakeaways: keyTakeaways,
            oneMinuteRecap: content.oneMinuteRecap?.resolve(selectedTone),
            activationPrompt: content.activationPrompt?.resolve(selectedTone),
            selfCheckPrompts: (content.selfCheckPrompts ?? []).map { $0.resolve(selectedTone) },
            reflectionPrompts: (content.reflectionPrompts ?? []).map { $0.resolve(selectedTone) },
            importantSummary: content.importantSummary,
            summaryBullets: content.summaryBullets ?? [],
            takeaways: content.takeaways ?? [],
            practice: content.practice ?? [],
            examples: examples,
            implementationPlan: plan,
            v21Extras: chapter.v21Extras,
            reviewCards: reviewCards,
            keyTakeawayCard: chapter.keyTakeawayCard?.resolve(selectedTone),
            resolvedVariant: variantKey,
            resolvedTone: selectedTone
        )
    }

    // MARK: - Private

    private func resolveVariant(_ requested: VariantKey, chapter: Chapter) -> VariantKey {
        guard !chapter.availableVariants.isEmpty else { return chapter.activeVariant }
        if chapter.availableVariants.contains(requested) { return requested }
        if chapter.availableVariants.contains(chapter.activeVariant) { return chapter.activeVariant }
        return chapter.availableVariants[0]
    }
}
