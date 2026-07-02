import Foundation
import Observation
import Models
import CoreKit
@preconcurrency import Network

/// Observable model driving the Quiz experience.
///
/// Responsibilities:
/// - Load a quiz session from the server.
/// - Track selected answers (one per question).
/// - Submit answers and render the server-graded result.
/// - Enforce the server-authoritative cooldown on failed attempts (countdown
///   is derived from ``QuizAttemptResult/cooldownSeconds``, not the device clock,
///   to avoid skew from wrong device time).
/// - Detect offline connectivity and disable submission with a clear UI hint.
///
/// **Grading contract:** this model never evaluates whether an answer is correct.
/// All correctness data comes from ``QuizAttemptResult/questionResults`` returned
/// by the server after submission.
@Observable
@MainActor
public final class QuizModel {

    // MARK: - Phase

    public enum Phase: Equatable {
        case idle
        case loading
        /// The user is actively answering questions.
        case active
        case submitting
        /// Server has returned a graded result.
        case result
        case error(String)
    }

    // MARK: - Public state

    public private(set) var phase: Phase = .idle
    /// The quiz session returned by the server (questions + choices).
    public private(set) var session: QuizClientSession?
    /// The server-graded result returned after submission.
    public private(set) var result: QuizAttemptResult?
    /// Maps questionId → selected choiceId. Updated by ``selectAnswer(_:for:)``.
    public private(set) var selectedAnswers: [String: String] = [:]
    /// Device time at which the cooldown expires (nil while active or passed).
    /// Derived from ``QuizAttemptResult/cooldownSeconds`` so it's server-authoritative.
    public private(set) var retryEligibleAt: Date?
    /// Whether the device currently has network connectivity.
    public private(set) var isOnline: Bool = true

    // MARK: - Book context

    public let bookId: String
    public let chapterNumber: Int
    public let tone: ToneKey?

    // MARK: - Private

    private let repository: any QuizRepository
    private nonisolated(unsafe) var connectivityMonitor: NWPathMonitor?
    private var connectivityTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        bookId: String,
        chapterNumber: Int,
        tone: ToneKey? = nil,
        repository: any QuizRepository
    ) {
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.tone = tone
        self.repository = repository
    }

    // MARK: - Lifecycle

    /// Begin monitoring network connectivity.
    /// Call this from the quiz view's `.task` modifier and cancel via ``stopConnectivityMonitor()``.
    public func startConnectivityMonitor() {
        let monitor = NWPathMonitor()
        connectivityMonitor = monitor
        let queue = DispatchQueue(label: "com.chapterflow.quiz.connectivity", qos: .utility)
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isOnline = connected
            }
        }
        monitor.start(queue: queue)
    }

    public func stopConnectivityMonitor() {
        connectivityMonitor?.cancel()
        connectivityMonitor = nil
        connectivityTask?.cancel()
        connectivityTask = nil
    }

    // MARK: - Actions

    /// Fetch the quiz session from the server and enter the active phase.
    public func load() async {
        phase = .loading
        selectedAnswers = [:]
        result = nil
        retryEligibleAt = nil
        do {
            let response = try await repository.getQuiz(
                bookId: bookId, n: chapterNumber, tone: tone
            )
            session = response.quiz
            phase = .active
        } catch let e as AppError {
            phase = .error(e.errorDescription ?? e.code)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Record the user's choice for a question.
    /// Has no effect outside the `.active` phase.
    public func selectAnswer(_ choiceId: String, for questionId: String) {
        guard phase == .active else { return }
        selectedAnswers[questionId] = choiceId
    }

    /// Submit all selected answers to the server and transition to the result phase.
    ///
    /// If the device is offline the method returns early; the caller should ensure
    /// ``isOnline`` is true before enabling the submit button.
    public func submit() async {
        guard phase == .active, let session else { return }

        // Collect answers in question order (server may require stable ordering).
        let answers = session.questions.compactMap { q -> QuizAnswerSubmission? in
            guard let choiceId = selectedAnswers[q.questionId] else { return nil }
            return QuizAnswerSubmission(questionId: q.questionId, choiceId: choiceId)
        }

        phase = .submitting
        do {
            let graded = try await repository.submit(
                bookId: bookId, n: chapterNumber, answers: answers
            )

            // Cooldown anchor: use server-authoritative cooldownSeconds from response time.
            // We do NOT compute (nextEligibleAttemptAt - deviceNow) to avoid device clock skew.
            if !graded.passed, graded.cooldownSeconds > 0 {
                retryEligibleAt = Date().addingTimeInterval(TimeInterval(graded.cooldownSeconds))
            } else {
                retryEligibleAt = nil
            }

            result = graded
            phase = .result

            // Fire-and-forget analytics event.
            Task { [weak self] in
                guard let self else { return }
                let event = QuizEventPayload(
                    eventType: graded.passed ? "quiz_passed" : "quiz_failed"
                )
                try? await repository.postEvent(bookId: bookId, n: chapterNumber, event: event)
            }

        } catch AppError.offline {
            // Revert to active — the view shows "connect to submit" when !isOnline.
            isOnline = false
            phase = .active
        } catch let e as AppError {
            phase = .error(e.errorDescription ?? e.code)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Reload the quiz for a retry attempt.
    /// Only valid when ``canRetry`` is true.
    public func retry() async {
        guard canRetry else { return }
        await load()
    }

    // MARK: - Computed

    /// Whether the submit button should be enabled.
    public var canSubmit: Bool {
        phase == .active && allAnswered && isOnline
    }

    /// True when every question has a selected answer.
    public var allAnswered: Bool {
        guard let session else { return false }
        return session.questions.allSatisfy { selectedAnswers[$0.questionId] != nil }
    }

    /// True when a failed attempt has passed its cooldown and can be retried.
    public var canRetry: Bool {
        guard let result, !result.passed else { return false }
        guard let eligibleAt = retryEligibleAt else { return true }
        return Date() >= eligibleAt
    }

    /// Seconds remaining in the retry cooldown (0 when eligible).
    public var cooldownRemaining: TimeInterval {
        guard let eligibleAt = retryEligibleAt else { return 0 }
        return max(0, eligibleAt.timeIntervalSinceNow)
    }

    /// The passing score threshold (defaults to 70 if server omits the field).
    public var passingScorePercent: Int {
        session?.passingScorePercent ?? 70
    }

    /// True if the quiz has been completed and the next chapter was unlocked.
    public var unlockedNextChapter: Bool {
        result?.unlockedNextChapter ?? false
    }
}

// MARK: - Preview support

#if DEBUG
extension QuizModel {
    /// Injects a pre-baked result state for SwiftUI `#Preview` blocks.
    /// Must be in the same file to access `private(set)` setters.
    func injectResultForPreview(
        session: QuizClientSession,
        result: QuizAttemptResult,
        cooldownSeconds: Int = 0
    ) {
        self.session = session
        self.result = result
        self.phase = .result
        if !result.passed, cooldownSeconds > 0 {
            self.retryEligibleAt = Date().addingTimeInterval(TimeInterval(cooldownSeconds))
        }
        self.selectedAnswers = Dictionary(
            uniqueKeysWithValues: result.questionResults.compactMap { qr in
                guard let choiceId = qr.selectedChoiceId else { return nil }
                return (qr.questionId, choiceId)
            }
        )
    }

    /// Injects an active (in-progress) state for SwiftUI `#Preview` blocks.
    func injectActiveForPreview(
        session: QuizClientSession,
        selectedAnswers: [String: String] = [:],
        isOnline: Bool = true
    ) {
        self.session = session
        self.phase = .active
        self.selectedAnswers = selectedAnswers
        self.isOnline = isOnline
    }
}
#endif
