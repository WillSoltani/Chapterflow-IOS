import Foundation
import Models
import Networking
import CoreKit

// MARK: - Commitment preview fixtures

extension Commitment {

    static let preview = Commitment(
        id: "cmt-001",
        bookId: "atomic-habits",
        chapterId: "ch-4",
        ifStatement: "I sit down at my desk at 8 am",
        thenStatement: "I will open my writing app and write for 20 minutes before checking email",
        followUpDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
        status: .active,
        outcome: nil,
        reflection: nil,
        createdAt: Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date()
    )

    static let previewOverdue = Commitment(
        id: "cmt-002",
        bookId: "deep-work",
        chapterId: "ch-2",
        ifStatement: "I feel the urge to check social media during work hours",
        thenStatement: "I will close my browser and put my phone face-down for 25 minutes",
        followUpDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
        status: .active,
        outcome: nil,
        reflection: nil,
        createdAt: Calendar.current.date(byAdding: .day, value: -8, to: Date()) ?? Date()
    )

    static let previewDone = Commitment(
        id: "cmt-003",
        bookId: "atomic-habits",
        chapterId: "ch-2",
        ifStatement: "I make my morning coffee",
        thenStatement: "I will immediately journal for 5 minutes",
        followUpDate: Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date(),
        status: .done,
        outcome: .helped,
        reflection: "It worked really well! The coffee-journal link is now automatic.",
        createdAt: Calendar.current.date(byAdding: .day, value: -17, to: Date()) ?? Date()
    )

    static let previewPartly = Commitment(
        id: "cmt-004",
        bookId: "essentialism",
        chapterId: "ch-7",
        ifStatement: "someone asks me to do something new",
        thenStatement: "I will pause and ask myself if it's essential before saying yes",
        followUpDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date(),
        status: .done,
        outcome: .partly,
        reflection: "I remembered it about half the time. Need more practice.",
        createdAt: Calendar.current.date(byAdding: .day, value: -12, to: Date()) ?? Date()
    )
}

// MARK: - CommitmentRepository preview

extension CommitmentRepository {

    static var preview: CommitmentRepository {
        makePreview(commitments: [.preview, .previewOverdue, .previewDone, .previewPartly])
    }

    static var previewEmpty: CommitmentRepository {
        makePreview(commitments: [])
    }

    private static func makePreview(commitments: [Commitment]) -> CommitmentRepository {
        let client = PreviewCommitmentAPIClient(commitments: commitments)
        return CommitmentRepository(apiClient: client, modelContainer: nil)
    }
}

// MARK: - CommitmentsModel preview

extension CommitmentsModel {

    @MainActor
    static var preview: CommitmentsModel {
        let model = CommitmentsModel(repository: .preview)
        model.loadState = .loaded([.preview, .previewOverdue, .previewDone, .previewPartly])
        return model
    }

    @MainActor
    static var previewEmpty: CommitmentsModel {
        let model = CommitmentsModel(repository: .previewEmpty)
        model.loadState = .loaded([])
        return model
    }
}

// MARK: - Preview API client

/// A minimal `APIClientProtocol` that serves pre-loaded commitment fixtures.
private final class PreviewCommitmentAPIClient: APIClientProtocol, @unchecked Sendable {
    private let commitments: [Commitment]

    init(commitments: [Commitment]) {
        self.commitments = commitments
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data: Data
        switch endpoint.path {
        case "/book/me/commitments" where endpoint.method == .get:
            data = try JSONCoding.encoder.encode(CommitmentsResponse(commitments: commitments))
        case let path where path.hasPrefix("/book/me/commitments/") && endpoint.method == .get:
            let id = String(path.dropFirst("/book/me/commitments/".count))
            guard let found = commitments.first(where: { $0.id == id }) else {
                throw AppError.notFound
            }
            data = try JSONCoding.encoder.encode(CommitmentResponse(commitment: found))
        case let path where path.hasPrefix("/book/me/commitments/") && endpoint.method == .patch:
            let id = String(path.dropFirst("/book/me/commitments/".count))
            guard let existing = commitments.first(where: { $0.id == id }) else {
                throw AppError.notFound
            }
            let updated = Commitment(
                id: existing.id,
                bookId: existing.bookId,
                chapterId: existing.chapterId,
                ifStatement: existing.ifStatement,
                thenStatement: existing.thenStatement,
                followUpDate: existing.followUpDate,
                status: .done,
                outcome: .helped,
                reflection: "Preview reflection",
                createdAt: existing.createdAt
            )
            data = try JSONCoding.encoder.encode(CommitmentResponse(commitment: updated))
        case "/book/me/commitments" where endpoint.method == .post:
            let created = Commitment(
                id: "cmt-new-\(UUID().uuidString.prefix(8))",
                bookId: "preview-book",
                chapterId: "preview-chapter",
                ifStatement: "I start my workday",
                thenStatement: "I will review my top priorities first",
                followUpDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
                status: .active,
                outcome: nil,
                reflection: nil,
                createdAt: Date()
            )
            data = try JSONCoding.encoder.encode(CommitmentResponse(commitment: created))
        default:
            throw AppError.notFound
        }
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }
    }
}
