import Testing
import Foundation
@testable import Models

// MARK: - Helpers

private func json(_ string: String) -> Data {
    Data(string.utf8)
}

// MARK: - CommitmentOutcome tolerance

@Suite("CommitmentOutcome server evolution")
struct CommitmentOutcomeEvolutionTests {

    @Test("unknown raw value decodes to .unknown, not throws")
    func unknownOutcome() throws {
        let data = json(#""future_outcome""#)
        let outcome = try JSONDecoder.chapterFlow.decode(CommitmentOutcome.self, from: data)
        if case .unknown(let raw) = outcome {
            #expect(raw == "future_outcome")
        } else {
            Issue.record("Expected .unknown outcome")
        }
    }

    @Test("known values decode correctly")
    func knownOutcomes() throws {
        let helped = try JSONDecoder.chapterFlow.decode(CommitmentOutcome.self, from: json(#""helped""#))
        let partly = try JSONDecoder.chapterFlow.decode(CommitmentOutcome.self, from: json(#""partly""#))
        let didnt  = try JSONDecoder.chapterFlow.decode(CommitmentOutcome.self, from: json(#""didnt""#))
        #expect(helped == .helped)
        #expect(partly == .partly)
        #expect(didnt  == .didnt)
    }

    @Test("allCases excludes .unknown")
    func allCasesKnownOnly() {
        let hasUnknown = CommitmentOutcome.allCases.contains {
            if case .unknown = $0 { return true }
            return false
        }
        #expect(!hasUnknown)
        #expect(CommitmentOutcome.allCases.count == 3)
    }
}

// MARK: - CommitmentStatus tolerance

@Suite("CommitmentStatus server evolution")
struct CommitmentStatusEvolutionTests {

    @Test("unknown raw value decodes to .unknown, not throws")
    func unknownStatus() throws {
        let data = json(#""archived""#)
        let status = try JSONDecoder.chapterFlow.decode(CommitmentStatus.self, from: data)
        if case .unknown(let raw) = status {
            #expect(raw == "archived")
        } else {
            Issue.record("Expected .unknown status")
        }
    }

    @Test("known statuses decode correctly")
    func knownStatuses() throws {
        let active = try JSONDecoder.chapterFlow.decode(CommitmentStatus.self, from: json(#""active""#))
        let done   = try JSONDecoder.chapterFlow.decode(CommitmentStatus.self, from: json(#""done""#))
        #expect(active == .active)
        #expect(done   == .done)
    }
}

// MARK: - CommitmentsResponse lossy decoding

@Suite("CommitmentsResponse lossy decoding")
struct CommitmentsResponseEvolutionTests {

    private let validJSON = """
    {
        "commitments": [
            {
                "id": "cmt-1",
                "bookId": "book-a",
                "chapterId": "ch-1",
                "ifStatement": "I wake up",
                "thenStatement": "I will read",
                "followUpDate": "2026-07-10T09:00:00Z",
                "status": "active",
                "createdAt": "2026-07-03T08:00:00Z"
            },
            null,
            {
                "id": "cmt-2",
                "bookId": "book-b",
                "chapterId": "ch-2",
                "ifStatement": "I sit down",
                "thenStatement": "I will write",
                "followUpDate": "2026-07-17T09:00:00Z",
                "status": "done",
                "outcome": "helped",
                "reflection": "Worked!",
                "createdAt": "2026-07-01T08:00:00Z"
            }
        ]
    }
    """

    @Test("null element is dropped; valid elements survive")
    func lossyDecode() throws {
        let resp = try JSONDecoder.chapterFlow.decode(CommitmentsResponse.self, from: Data(validJSON.utf8))
        #expect(resp.commitments.count == 2)
        #expect(resp.commitments[0].id == "cmt-1")
        #expect(resp.commitments[1].id == "cmt-2")
    }

    @Test("commitment with unknown outcome decodes without crashing")
    func unknownOutcomeInCommitment() throws {
        let raw = """
        {
            "commitments": [{
                "id": "cmt-x",
                "bookId": "bk",
                "chapterId": "ch",
                "ifStatement": "If",
                "thenStatement": "Then",
                "followUpDate": "2026-08-01T09:00:00Z",
                "status": "done",
                "outcome": "super_helped",
                "createdAt": "2026-07-01T00:00:00Z"
            }]
        }
        """
        let resp = try JSONDecoder.chapterFlow.decode(CommitmentsResponse.self, from: Data(raw.utf8))
        #expect(resp.commitments.count == 1)
        if case .unknown(let raw) = resp.commitments[0].outcome {
            #expect(raw == "super_helped")
        } else {
            Issue.record("Expected .unknown outcome")
        }
    }
}
