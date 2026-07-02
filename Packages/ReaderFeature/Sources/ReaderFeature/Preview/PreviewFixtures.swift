#if DEBUG
import Foundation
import Models

// MARK: - Raw Chapter fixture for ReaderControlSurface previews

/// A minimal raw `Chapter` with three EMH depth variants for previewing the control surface.
/// Created via JSON decoding so `ChapterVariantContent`'s internal init is not needed.
let previewChapterRaw: Chapter = {
    let json = """
    {
        "chapterId": "ch-ah-1",
        "number": 1,
        "title": "The Surprising Power of Atomic Habits",
        "readingTimeMinutes": 12,
        "activeVariant": "medium",
        "availableVariants": ["easy", "medium", "hard"],
        "content": {
            "chapterBreakdown": {
                "gentle": "Small habits might seem insignificant at first, but tiny **1% improvements** compound into extraordinary results over time.",
                "direct": "1% better every day = 37x better in a year. Stop waiting for dramatic change. Start tiny.",
                "competitive": "Your competitors are sleeping. You can outperform them with 1% gains compounding daily."
            },
            "keyTakeaways": [
                {
                    "point": {
                        "gentle": "Tiny improvements each day create extraordinary long-term results.",
                        "direct": "Small consistent action beats big sporadic effort. Every time.",
                        "competitive": "Compound your edge daily. The scoreboard rewards systems, not intentions."
                    },
                    "moreDetails": null
                }
            ]
        },
        "contentVariants": {
            "easy": {
                "chapterBreakdown": {
                    "gentle": "Small habits are the key. Even tiny 1% improvements add up over time.",
                    "direct": "1% better daily. That's all it takes. Simple.",
                    "competitive": "Get ahead with tiny daily wins. They add up faster than you think."
                }
            },
            "medium": {
                "chapterBreakdown": {
                    "gentle": "Small habits might seem insignificant at first, but tiny **1% improvements** compound into extraordinary results over time.",
                    "direct": "1% better every day = 37x better in a year. Stop waiting for dramatic change. Start tiny.",
                    "competitive": "Your competitors are sleeping. You can outperform them with 1% gains compounding daily."
                },
                "keyTakeaways": [
                    {
                        "point": {
                            "gentle": "Tiny improvements each day create extraordinary long-term results.",
                            "direct": "Small consistent action beats big sporadic effort. Every time.",
                            "competitive": "Compound your edge daily. The scoreboard rewards systems, not intentions."
                        },
                        "moreDetails": null
                    }
                ]
            },
            "hard": {
                "chapterBreakdown": {
                    "gentle": "The mathematics of marginal gains reveals a counterintuitive truth: a 1% improvement each day yields a 37.78x performance increase over a year.",
                    "direct": "Marginal gains compound exponentially. 1% daily = 3,778% annual improvement. Most people overestimate what they can do in a day and underestimate what they can do in a year.",
                    "competitive": "Elite performers understand that the gap between good and exceptional isn't talent — it's the relentless accumulation of marginal gains. 1% daily improvement creates a 37.78x annual multiplier."
                },
                "keyTakeaways": [
                    {
                        "point": {
                            "gentle": "The aggregation of marginal gains: many small improvements compound into transformative change.",
                            "direct": "Systems beat goals. Your daily habits are the actual strategy. The goal is irrelevant.",
                            "competitive": "Identity-based habits create permanent change. You don't adopt habits; you become the person who does them."
                        },
                        "moreDetails": null
                    },
                    {
                        "point": {
                            "gentle": "Your outcomes are a lagging indicator of your habits.",
                            "direct": "Focus on the system. Results follow.",
                            "competitive": "Outcomes are lagging indicators. Lead with process metrics."
                        },
                        "moreDetails": null
                    }
                ]
            }
        },
        "examples": [
            {
                "exampleId": "ex-ah-1-1",
                "title": "The Exercise Habit",
                "scenario": "You've been trying to go to the gym for years but always fall off after a few weeks.",
                "whatToDo": ["Start with just 2 minutes of exercise per day", "Set your gym clothes out the night before"],
                "whyItMatters": "Starting small removes the mental barrier.",
                "contexts": ["fitness"],
                "category": "health"
            }
        ]
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder.chapterFlow.decode(Chapter.self, from: Data(json.utf8))
}()

// MARK: - EMH fixture (with v21Extras)

/// "The Surprising Power of Atomic Habits" — EMH family, with full v21Extras.
let previewChapterEMH: ResolvedChapter = ResolvedChapter(
    chapterId: "ch-ah-1",
    number: 1,
    title: "The Surprising Power of Atomic Habits",
    readingTimeMinutes: 12,
    chapterBreakdown: "Small habits might seem insignificant at first, but tiny **1% improvements** compound into remarkable results over time. Think of it as interest on a savings account — the gains are invisible day to day, but transformative over years.",
    keyTakeaways: [
        ResolvedKeyTakeaway(
            point: "Tiny improvements each day create extraordinary long-term results through the magic of compounding.",
            moreDetails: "The challenge is that the impact of your habits is often invisible in the short term. You need to trust the process even when results aren't visible yet."
        ),
        ResolvedKeyTakeaway(
            point: "Your outcomes are a lagging indicator of your habits — focus on the _process_, not the results.",
            moreDetails: nil
        ),
    ],
    oneMinuteRecap: ResolvedOneMinuteRecap(
        text: "Small changes feel insignificant day to day, but through compounding they produce extraordinary results. Your habits are your future self — invest in **1% improvements** and trust the process.",
        retrieve: nil,
        connect: nil,
        preview: nil
    ),
    activationPrompt: "Think about one tiny habit you could improve by just 1% this week — something so small it almost seems silly.",
    selfCheckPrompts: [
        "Can you describe the compounding effect of habits in your own words?",
    ],
    reflectionPrompts: [
        "Which area of your life would benefit most from a series of tiny 1% improvements?",
    ],
    importantSummary: nil,
    summaryBullets: [],
    takeaways: [],
    practice: [],
    examples: [
        ResolvedExample(
            exampleId: "ex-ah-1-1",
            title: "The Exercise Habit",
            scenario: "You've been trying to go to the gym for years but always seem to fall off after a few weeks.",
            whatToDo: [
                "Start with just 2 minutes of exercise per day",
                "Set your gym clothes out the night before",
                "Link the habit to an existing routine (e.g. after morning coffee)",
            ],
            whyItMatters: "Starting small removes the mental barrier. Once you establish the identity of 'someone who exercises,' bigger changes naturally follow.",
            contexts: ["fitness", "health"],
            category: "health"
        ),
        ResolvedExample(
            exampleId: "ex-ah-1-2",
            title: "Learning a New Skill",
            scenario: "You want to learn to play guitar but the thought of years of practice feels overwhelming.",
            whatToDo: ["Just pick up the guitar for 2 minutes after dinner."],
            whyItMatters: "The goal isn't to practice guitar. The goal is to become the kind of person who practices guitar daily.",
            contexts: ["learning"],
            category: "learning"
        ),
    ],
    implementationPlan: ResolvedImplementationPlan(
        coreSkill: "Designing tiny, consistent habits that build on each other over time.",
        concreteAction: "Choose one habit you want to build. Make it so small it seems almost too easy. Do it every day this week.",
        ifThenPlans: [
            ResolvedIfThenPlan(
                context: "When I finish my morning coffee",
                plan: "I will spend 2 minutes on the habit I'm building, even if it's just setting up."
            ),
        ],
        twentyFourHourChallenge: "Choose one tiny habit to start today. Do the 2-minute version. Just show up once.",
        weeklyPractice: "Each day this week, do the 2-minute version of your chosen habit. Notice how you feel after day 7.",
        friction: "It feels too small to make a difference — but that's actually the point.",
        checkpoint: "After one week: Are you showing up every day? That's the only success metric right now."
    ),
    v21Extras: V21ChapterExtras(
        hook: "What if the key to getting **37 times better** at anything in a year required only a 1% improvement each day?",
        counterintuition: "Most people think success requires dramatic transformations. But the science shows it's the opposite — tiny, consistent improvements beat big, inconsistent efforts every time.",
        tryThisNow: "Right now, think of one habit you want to build. Write down the 2-minute version of it. That's your atomic habit.",
        keyTakeaway: "You don't rise to the level of your goals; you _fall to the level of your systems_.",
        memorableLines: [
            MemorableLine(
                text: "You do not rise to the level of your goals. You fall to the level of your systems.",
                location: "Chapter 1",
                why: nil
            ),
            MemorableLine(
                text: "Every action you take is a vote for the type of person you wish to become.",
                location: "Chapter 1",
                why: nil
            ),
        ],
        experiencePlan: V21ExperiencePlan(
            failureRecovery: FailureRecovery(
                normalizingLine: "It happens to almost everyone — you start strong, then life intervenes and the habit disappears for a few days.",
                cueQuestion: "When you notice you've broken the streak, which of these sounds most like your situation?",
                options: [
                    "I forgot and it slipped past me without noticing.",
                    "I tried but the habit felt too big that day.",
                    "I was dealing with something stressful and deprioritised it.",
                    "I got it done but told myself it didn't count because it wasn't 'real' effort.",
                ],
                repairLine: "Miss once — never twice. One missed day is an accident. Two is the start of a new habit."
            ),
            transferPrompt: TransferPrompt(
                prompt: "You've applied this to building a habit — where else in your life does the 1% principle apply?",
                contexts: ["Learning a language", "Building a writing practice", "Career growth", "Fitness", "Relationships"]
            ),
            behaviorLoop: BehaviorLoop(readerPatterns: [
                ReaderPattern(
                    id: "the-planner",
                    label: "The Planner",
                    mapsToPlanIndex: 0,
                    mapsToExampleIndex: nil
                ),
                ReaderPattern(
                    id: "the-doer",
                    label: "The Doer",
                    mapsToPlanIndex: nil,
                    mapsToExampleIndex: 0
                ),
                ReaderPattern(
                    id: "the-doubter",
                    label: "The Doubter",
                    mapsToPlanIndex: nil,
                    mapsToExampleIndex: 1
                ),
            ])
        )
    ),
    reviewCards: [],
    keyTakeawayCard: "Tiny habits compound into remarkable results.",
    resolvedVariant: .medium,
    resolvedTone: .gentle
)

// MARK: - PBC fixture (without v21Extras)

/// "Deep Work: The New Superpower" — PBC family, no v21Extras, structured recap.
let previewChapterPBC: ResolvedChapter = ResolvedChapter(
    chapterId: "ch-dw-1",
    number: 1,
    title: "Deep Work: The New Superpower",
    readingTimeMinutes: 15,
    chapterBreakdown: "In our distracted world, the ability to focus deeply on cognitively demanding work has become both **increasingly rare** and increasingly valuable. Deep work — the ability to focus without distraction — is the skill that will separate those who thrive from those who struggle.",
    keyTakeaways: [
        ResolvedKeyTakeaway(
            point: "Deep work — focusing intensely without distraction — is becoming both rarer and more valuable in our distracted world.",
            moreDetails: "Many knowledge workers spend their days doing 'shallow work' — emails, meetings, social media — that feels busy but produces little real value."
        ),
    ],
    oneMinuteRecap: ResolvedOneMinuteRecap(
        text: nil,
        retrieve: "Deep work is rare and valuable. Knowledge economy rewards complex cognitive output.",
        connect: "Think of a skill in your life where you've seen the benefits of sustained focus. How can you apply that to your work?",
        preview: "Next we'll explore deep work philosophies — how to schedule and protect deep work sessions."
    ),
    activationPrompt: "Think about your typical workday. How many hours do you spend in truly focused, uninterrupted work versus reactive tasks?",
    selfCheckPrompts: [
        "Can you explain what makes deep work different from regular hard work?",
    ],
    reflectionPrompts: [
        "When do you feel most 'in the zone' with your work? What conditions make that possible?",
    ],
    importantSummary: nil,
    summaryBullets: [],
    takeaways: [],
    practice: [],
    examples: [
        ResolvedExample(
            exampleId: nil,
            title: "The Research Session",
            scenario: "You sit down to write a research paper but find yourself constantly switching to email and Slack.",
            whatToDo: [
                "Block 2 hours on your calendar with no meetings",
                "Put your phone in another room",
                "Close all browser tabs except your research tools",
            ],
            whyItMatters: "A 2-hour uninterrupted session produces more high-quality output than a full day of fragmented attention.",
            contexts: ["knowledge work", "writing"],
            category: "productivity"
        ),
    ],
    implementationPlan: ResolvedImplementationPlan(
        coreSkill: "Scheduling and protecting dedicated deep work sessions.",
        concreteAction: "Block one 90-minute deep work session in your calendar for tomorrow.",
        ifThenPlans: [
            ResolvedIfThenPlan(
                context: "When a notification pops up during deep work",
                plan: "I will acknowledge it mentally and return to it after the session ends — not immediately."
            ),
        ],
        twentyFourHourChallenge: "Schedule and complete one 90-minute deep work block today. No phone, no notifications.",
        weeklyPractice: nil,
        friction: nil,
        checkpoint: nil
    ),
    v21Extras: nil,
    reviewCards: [],
    keyTakeawayCard: nil,
    resolvedVariant: .balanced,
    resolvedTone: .direct
)
#endif
