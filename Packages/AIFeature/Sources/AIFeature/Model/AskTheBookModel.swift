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
    /// The device has no network connection.
    case offline
}

/// Observable view model for the "Ask the book" chat sheet.
///
/// Owns the in-memory message thread for one book session. Each call to
/// ``sendQuestion()`` fires the live repository and appends the result.
/// The model stays alive as long as the sheet is presented; reopening the
/// sheet within the same app session preserves the thread.
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

    // MARK: - Navigation callback

    /// Called when the user taps a citation chip to jump to that chapter.
    public var onJumpToChapter: ((Int) -> Void)?

    // MARK: - Private

    private let repository: any AIRepository

    // MARK: - Init

    public init(
        bookId: String,
        repository: any AIRepository,
        selectionContext: String? = nil,
        tone: String? = nil
    ) {
        self.bookId = bookId
        self.repository = repository
        self.selectionContext = selectionContext
        self.tone = tone
    }

    // MARK: - Actions

    /// Sends `inputText` as a question to the server and appends the answer.
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
            handleError(appError, question: question)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Dismisses an error or offline state so the user can retry.
    public func retry() {
        phase = .idle
    }

    /// Triggers the chapter-jump callback and dismisses the rate-limit phase
    /// so navigation can complete cleanly.
    public func jumpToChapter(_ number: Int) {
        onJumpToChapter?(number)
    }

    // MARK: - Helpers

    /// Whether a question can currently be submitted.
    public var canSend: Bool {
        phase == .idle && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
