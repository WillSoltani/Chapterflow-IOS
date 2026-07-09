import Foundation
import Observation
import CoreKit

/// The phase the "Ask the book" sheet is in.
public enum AskPhase: Equatable {
    /// Ready for input.
    case idle
    /// A question is in flight.
    case asking
    /// The server returned HTTP 429 — daily quota exhausted.
    /// `resetsAt` is the optional reset time derived from `Retry-After`.
    case rateLimited(resetsAt: Date?)
    /// A recoverable error occurred; `message` is user-facing.
    case error(String)
    /// The device has no network connection and on-device AI is unavailable.
    case offline
}

/// Observable view model for the "Ask the book" chat sheet.
///
/// Owns the in-memory message thread for one book session. Each call to
/// ``sendQuestion()`` fires the live repository and appends the result.
/// The model stays alive as long as the sheet is presented; reopening the
/// sheet within the same app session preserves the thread.
///
/// **Offline fallback (P6.5):** When the network is unavailable and an
/// ``OnDeviceAIProviding`` service is supplied together with ``chapterText``,
/// the model automatically answers using the on-device model — no user action
/// required. Answers generated this way carry `isOnDeviceAnswer = true`.
@Observable
@MainActor
public final class AskTheBookModel {

    // MARK: - State

    /// Current UI phase (loading / rate-limited / error / offline / idle).
    public private(set) var phase: AskPhase = .idle

    /// The conversation thread for this book in the current session.
    public private(set) var messages: [AskMessage] = []

    /// How many questions the user may still ask today (nil = unknown).
    public private(set) var remainingQuota: Int?

    /// The text currently in the input field.
    public var inputText: String = ""

    // MARK: - Configuration

    /// The book this model is asking about.
    public let bookId: String

    /// Optional highlighted passage shown as a context chip; sent with every request.
    public let selectionContext: String?

    /// The reader's tone preference; forwarded to the API for grounded answers.
    public let tone: String?

    /// Pre-extracted plain text of the current chapter used as grounding context
    /// for the on-device offline fallback. Truncated internally before use.
    public let chapterText: String?

    // MARK: - Navigation callback

    /// Called when the user taps a citation chip to jump to that chapter.
    public var onJumpToChapter: ((Int) -> Void)?

    // MARK: - Private

    private let repository: any AIRepository
    private let onDeviceService: (any OnDeviceAIProviding)?

    // MARK: - Init

    public init(
        bookId: String,
        repository: any AIRepository,
        selectionContext: String? = nil,
        tone: String? = nil,
        chapterText: String? = nil,
        onDeviceService: (any OnDeviceAIProviding)? = nil
    ) {
        self.bookId = bookId
        self.repository = repository
        self.selectionContext = selectionContext
        self.tone = tone
        self.chapterText = chapterText
        self.onDeviceService = onDeviceService
    }

    // MARK: - Actions

    /// Sends `inputText` as a question to the server and appends the answer.
    ///
    /// When the network is unavailable and an on-device service + chapter text
    /// were provided, falls back to an on-device answer automatically.
    public func sendQuestion() async {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, phase != .asking else { return }

        inputText = ""
        phase = .asking

        do {
            let response = try await repository.askBook(
                bookId: bookId,
                question: question,
                selectionContext: selectionContext,
                tone: tone
            )
            messages.append(AskMessage(
                question: question,
                selectionContext: selectionContext,
                answer: response.answer,
                citations: response.citations
            ))
            if let quota = response.remainingQuestions {
                remainingQuota = quota
            }
            phase = .idle
        } catch let appError as AppError {
            if case .offline = appError, let service = onDeviceService {
                await handleOfflineWithOnDevice(question: question, service: service)
            } else {
                handleError(appError, question: question)
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Dismisses an error or offline state so the user can retry.
    public func retry() {
        phase = .idle
    }

    /// Triggers the chapter-jump callback.
    public func jumpToChapter(_ number: Int) {
        onJumpToChapter?(number)
    }

    // MARK: - Helpers

    /// Whether a question can currently be submitted.
    public var canSend: Bool {
        phase == .idle && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when the on-device service and chapter text are both injected.
    ///
    /// Use this synchronous check to show/hide entry points and the privacy note
    /// without awaiting the async availability check.
    public var isOnDeviceWired: Bool {
        onDeviceService != nil && !(chapterText ?? "").isEmpty
    }

    /// True when on-device offline answering is wired up and available.
    ///
    /// Views use this to decide whether to show the privacy note / on-device badge.
    public var isOnDeviceAvailable: Bool {
        get async {
            guard let service = onDeviceService,
                  let text = chapterText, !text.isEmpty else { return false }
            return await service.availability.isAvailable && !text.isEmpty
        }
    }

    // MARK: - Private helpers

    /// Attempts an on-device answer when the network is offline.
    /// Falls back to `.offline` phase if unavailable or the generation fails.
    private func handleOfflineWithOnDevice(question: String, service: any OnDeviceAIProviding) async {
        let state = await service.availability
        guard state.isAvailable, let text = chapterText, !text.isEmpty else {
            phase = .offline
            return
        }
        // phase is already .asking from sendQuestion — keep the "Thinking..." indicator
        do {
            let answer = try await service.answerQuestion(
                question,
                chapterText: text,
                selectionContext: selectionContext
            )
            messages.append(AskMessage(
                question: question,
                selectionContext: selectionContext,
                answer: answer,
                citations: [],
                isOnDeviceAnswer: true
            ))
            phase = .idle
        } catch {
            phase = .offline
        }
    }

    private func handleError(_ error: AppError, question: String) {
        switch error {
        case .rateLimited(let retryAfter):
            let resetDate = retryAfter.map { Date().addingTimeInterval($0) }
            phase = .rateLimited(resetsAt: resetDate)
        case .offline:
            phase = .offline
        default:
            phase = .error(error.errorDescription ?? "Something went wrong. Please try again.")
        }
    }
}
