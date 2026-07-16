import Foundation
import Observation
import Models
import CoreKit
@preconcurrency import Network

/// Observable model driving the server-authoritative quiz experience.
@Observable
@MainActor
public final class QuizModel {

    public enum Phase: Equatable {
        case idle
        case loading
        case active
        case submitting
        case result
        case error(String)
    }

    public enum DraftState: Equatable {
        case none
        case saving
        case saved
        case savedRequiresConnection
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var session: QuizClientSession?
    public private(set) var result: QuizAttemptResult?
    public private(set) var selectedAnswers: [String: String] = [:]
    public private(set) var retryEligibleAt: Date?
    public private(set) var isOnline: Bool = true
    public private(set) var draftState: DraftState = .none
    public private(set) var submissionMessage: String?

    public let bookId: String
    public let chapterNumber: Int
    public let tone: ToneKey?

    private let repository: any QuizRepository
    private let analytics: any AnalyticsClient
    private let workPermit: SessionWorkPermit
    @ObservationIgnored private var connectivityMonitor: NWPathMonitor?
    @ObservationIgnored private var draftSaveTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var draftRevision = 0

    public init(
        bookId: String,
        chapterNumber: Int,
        tone: ToneKey? = nil,
        repository: any QuizRepository,
        workPermit: SessionWorkPermit = SessionWorkPermit(),
        analytics: any AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.tone = tone
        self.repository = repository
        self.workPermit = workPermit
        self.analytics = analytics
    }

    // MARK: - Lifecycle

    public func startConnectivityMonitor() {
        let monitor = NWPathMonitor()
        connectivityMonitor = monitor
        let queue = DispatchQueue(label: "com.chapterflow.quiz.connectivity", qos: .utility)
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, let ticket = try? self.workPermit.begin() else { return }
                try? self.workPermit.commit(ticket) {
                    self.isOnline = connected
                }
            }
        }
        monitor.start(queue: queue)
    }

    public func stopConnectivityMonitor() {
        connectivityMonitor?.cancel()
        connectivityMonitor = nil
        eventTask?.cancel()
        eventTask = nil
    }

    // MARK: - Actions

    public func load() async {
        guard let ticket = try? workPermit.begin() else { return }
        draftRevision += 1
        draftSaveTask?.cancel()
        draftSaveTask = nil
        try? workPermit.commit(ticket) {
            phase = .loading
            selectedAnswers = [:]
            result = nil
            retryEligibleAt = nil
            draftState = .none
            submissionMessage = nil
        }
        do {
            let loaded = try await repository.loadQuiz(
                bookId: bookId,
                n: chapterNumber,
                tone: tone
            )
            try workPermit.commit(ticket) {
                session = loaded.response.quiz
                selectedAnswers = loaded.selectedAnswers
                draftState = loaded.selectedAnswers.isEmpty ? .none : .saved
                phase = .active
            }
        } catch is CancellationError {
            try? workPermit.commit(ticket) { phase = .idle }
        } catch let error as AppError {
            try? workPermit.commit(ticket) {
                phase = .error(error.errorDescription ?? error.code)
            }
        } catch {
            try? workPermit.commit(ticket) {
                phase = .error(error.localizedDescription)
            }
        }
    }

    public func selectAnswer(_ choiceId: String, for questionId: String) {
        guard phase == .active,
              let session,
              let question = session.questions.first(where: { $0.questionId == questionId }),
              question.choices.contains(where: { $0.choiceId == choiceId }),
              let ticket = try? workPermit.begin() else {
            return
        }
        try? workPermit.commit(ticket) {
            selectedAnswers[questionId] = choiceId
            submissionMessage = nil
        }
        scheduleDraftSave(session: session, ticket: ticket)
    }

    private func scheduleDraftSave(session: QuizClientSession, ticket: UInt64) {
        draftRevision += 1
        let revision = draftRevision
        let answers = selectedAnswers
        let repository = repository
        let bookId = bookId
        let chapterNumber = chapterNumber

        draftSaveTask?.cancel()
        draftState = .saving
        draftSaveTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                try await repository.saveDraft(
                    bookId: bookId,
                    n: chapterNumber,
                    session: session,
                    selectedAnswers: answers
                )
                try Task.checkCancellation()
                guard let self, self.draftRevision == revision else { return }
                try self.workPermit.commit(ticket) {
                    self.draftState = .saved
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.draftRevision == revision else { return }
                try? self.workPermit.commit(ticket) {
                    self.draftState = .failed(error.localizedDescription)
                }
            }
        }
    }

    public func submit() async {
        guard phase == .active, canSubmit, let session else { return }
        guard let ticket = try? workPermit.begin() else { return }

        draftRevision += 1
        let pendingDraftSave = draftSaveTask
        pendingDraftSave?.cancel()
        draftSaveTask = nil

        let responses = orderedResponses(for: session)

        try? workPermit.commit(ticket) {
            phase = .submitting
            draftState = .saving
            submissionMessage = nil
        }
        await pendingDraftSave?.value
        if Task.isCancelled {
            try? workPermit.commit(ticket) { phase = .active }
            return
        }
        do {
            let outcome = try await repository.submitAttempt(
                bookId: bookId,
                n: chapterNumber,
                session: session,
                responses: responses
            )
            switch outcome {
            case .graded(let graded, let draftCleared):
                try workPermit.commit(ticket) {
                    if !graded.passed, graded.cooldownSeconds > 0 {
                        retryEligibleAt = Date().addingTimeInterval(
                            TimeInterval(graded.cooldownSeconds)
                        )
                    } else {
                        retryEligibleAt = nil
                    }
                    result = graded
                    draftState = draftCleared
                        ? .none
                        : .failed("The server graded this quiz, but the local draft still needs cleanup.")
                    phase = .result
                }
                recordServerResult(graded, ticket: ticket)

            case .draftSavedRequiresConnection:
                try workPermit.commit(ticket) {
                    draftState = .savedRequiresConnection
                    phase = .active
                }

            case .refreshedAfterStale(let loaded):
                try workPermit.commit(ticket) {
                    self.session = loaded.response.quiz
                    selectedAnswers = loaded.selectedAnswers
                    draftState = loaded.selectedAnswers.isEmpty ? .none : .saved
                    submissionMessage = "The quiz changed on the server. Review it before submitting again."
                    result = nil
                    retryEligibleAt = nil
                    phase = .active
                }
            }
        } catch is CancellationError {
            try? workPermit.commit(ticket) { phase = .active }
        } catch let error as QuizDraftError {
            try? workPermit.commit(ticket) {
                draftState = .failed(error.errorDescription ?? "The draft could not be saved.")
                submissionMessage = error.errorDescription
                phase = .active
            }
        } catch let error as AppError {
            try? workPermit.commit(ticket) {
                draftState = .saved
                submissionMessage = error.errorDescription ?? error.code
                phase = .active
            }
        } catch {
            try? workPermit.commit(ticket) {
                draftState = .saved
                submissionMessage = error.localizedDescription
                phase = .active
            }
        }
    }

    private func orderedResponses(for session: QuizClientSession) -> [QuizAnswerSubmission] {
        session.questions.compactMap { question in
            selectedAnswers[question.questionId].map {
                QuizAnswerSubmission(questionId: question.questionId, selectedChoiceId: $0)
            }
        }
    }

    private func recordServerResult(_ graded: QuizAttemptResult, ticket: UInt64) {
        let score = graded.scorePercent
        analytics.track(.quizSubmitted(bookId: bookId, chapter: chapterNumber, score: score))
        if graded.passed {
            analytics.track(.custom(name: "quiz_passed", properties: [
                "bookId": bookId,
                "chapter": String(chapterNumber),
                "score": String(score),
            ]))
        }

        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self,
                  (try? self.workPermit.validate(ticket)) != nil else {
                return
            }
            let event = QuizEventPayload(
                eventType: graded.passed ? "quiz_passed" : "quiz_failed"
            )
            try? await self.repository.postEvent(
                bookId: self.bookId,
                n: self.chapterNumber,
                event: event
            )
        }
    }

    public func retry() async {
        guard canRetry else { return }
        await load()
    }

    /// Test synchronization point for the retained draft task.
    func waitForDraftSave() async {
        await draftSaveTask?.value
    }

    // MARK: - Computed state

    public var canSubmit: Bool {
        phase == .active && sessionCanSubmit && allAnswered
    }

    public var requiresSessionRefresh: Bool {
        session != nil && !sessionCanSubmit
    }

    private var sessionCanSubmit: Bool {
        guard let session,
              let attemptNumber = session.attemptNumber,
              attemptNumber > 0,
              session.status == .ready else {
            return false
        }
        return session.nextAttemptNumber == attemptNumber
    }

    public var allAnswered: Bool {
        guard let session else { return false }
        return session.questions.allSatisfy { selectedAnswers[$0.questionId] != nil }
    }

    public var canRetry: Bool {
        guard let result, !result.passed else { return false }
        guard let eligibleAt = retryEligibleAt else { return true }
        return Date() >= eligibleAt
    }

    public var cooldownRemaining: TimeInterval {
        guard let eligibleAt = retryEligibleAt else { return 0 }
        return max(0, eligibleAt.timeIntervalSinceNow)
    }

    public var passingScorePercent: Int {
        session?.passingScorePercent ?? 70
    }

    public var unlockedNextChapter: Bool {
        result?.unlockedNextChapter ?? false
    }
}

#if DEBUG
extension QuizModel {
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
            uniqueKeysWithValues: result.questionResults.compactMap { questionResult in
                guard let choiceId = questionResult.selectedChoiceId else { return nil }
                return (questionResult.questionId, choiceId)
            }
        )
    }

    func injectActiveForPreview(
        session: QuizClientSession,
        selectedAnswers: [String: String] = [:],
        isOnline: Bool = true
    ) {
        self.session = session
        self.phase = .active
        self.selectedAnswers = selectedAnswers
        self.isOnline = isOnline
        self.draftState = selectedAnswers.isEmpty ? .none : .saved
    }
}
#endif
