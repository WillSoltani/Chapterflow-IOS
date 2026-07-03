import Testing
import Foundation
@testable import AIFeature
import Models
import Networking
import CoreKit

// MARK: - DepthRecommendation model tests

@Suite("DepthRecommendation")
struct DepthRecommendationTests {

    // MARK: - Confidence threshold

    @Test("isConfident is true when confidence meets the minimum threshold")
    func isConfidentAtThreshold() {
        let rec = DepthRecommendation(recommendedDepth: .medium, confidence: 0.7)
        #expect(rec.isConfident)
    }

    @Test("isConfident is true when confidence exceeds the minimum threshold")
    func isConfidentAboveThreshold() {
        let rec = DepthRecommendation(recommendedDepth: .medium, confidence: 0.85)
        #expect(rec.isConfident)
    }

    @Test("isConfident is false when confidence is below the minimum threshold")
    func isConfidentBelowThreshold() {
        let rec = DepthRecommendation(recommendedDepth: .hard, confidence: 0.4)
        #expect(!rec.isConfident)
    }

    @Test("isConfident is false for zero confidence")
    func isConfidentAtZero() {
        let rec = DepthRecommendation(recommendedDepth: .easy, confidence: 0.0)
        #expect(!rec.isConfident)
    }

    @Test("minimumConfidence is 0.7")
    func minimumConfidenceValue() {
        #expect(DepthRecommendation.minimumConfidence == 0.7)
    }

    // MARK: - Tolerant decoding: unknown recommendedDepth

    @Test("unknown recommendedDepth decodes to nil")
    func unknownDepthDecodesToNil() throws {
        let json = #"{"recommendedDepth":"ultra","confidence":0.9}"#
        let rec = try JSONDecoder().decode(DepthRecommendation.self, from: Data(json.utf8))
        #expect(rec.recommendedDepth == nil)
        #expect(rec.isConfident)
    }

    @Test("missing recommendedDepth decodes to nil")
    func missingDepthDecodesToNil() throws {
        let json = #"{"confidence":0.8}"#
        let rec = try JSONDecoder().decode(DepthRecommendation.self, from: Data(json.utf8))
        #expect(rec.recommendedDepth == nil)
    }

    @Test("null recommendedDepth decodes to nil")
    func nullDepthDecodesToNil() throws {
        let json = #"{"recommendedDepth":null,"confidence":0.75}"#
        let rec = try JSONDecoder().decode(DepthRecommendation.self, from: Data(json.utf8))
        #expect(rec.recommendedDepth == nil)
    }

    @Test("known recommendedDepth decodes correctly")
    func knownDepthDecodesCorrectly() throws {
        let json = #"{"recommendedDepth":"medium","confidence":0.8}"#
        let rec = try JSONDecoder().decode(DepthRecommendation.self, from: Data(json.utf8))
        #expect(rec.recommendedDepth == .medium)
    }

    @Test("all known EMH depths decode correctly")
    func emhDepthsDecode() throws {
        for (raw, expected) in [("easy", VariantKey.easy), ("medium", .medium), ("hard", .hard)] {
            let json = "{\"recommendedDepth\":\"\(raw)\",\"confidence\":0.8}"
            let rec = try JSONDecoder().decode(DepthRecommendation.self, from: Data(json.utf8))
            #expect(rec.recommendedDepth == expected)
        }
    }

    @Test("all known PBC depths decode correctly")
    func pbcDepthsDecode() throws {
        for (raw, expected) in [
            ("precise", VariantKey.precise),
            ("balanced", .balanced),
            ("challenging", .challenging)
        ] {
            let json = "{\"recommendedDepth\":\"\(raw)\",\"confidence\":0.8}"
            let rec = try JSONDecoder().decode(DepthRecommendation.self, from: Data(json.utf8))
            #expect(rec.recommendedDepth == expected)
        }
    }

    // MARK: - Rationale text

    @Test("rationale returns non-empty text for confident EMH recommendations")
    func rationaleNonEmptyForEMH() {
        for variant in [VariantKey.easy, .medium, .hard] {
            let rec = DepthRecommendation(recommendedDepth: variant, confidence: 0.8)
            let text = rec.rationale(variantFamily: .emh)
            #expect(!text.isEmpty, "Expected non-empty rationale for \(variant) in EMH")
        }
    }

    @Test("rationale returns non-empty text for confident PBC recommendations")
    func rationaleNonEmptyForPBC() {
        for variant in [VariantKey.precise, .balanced, .challenging] {
            let rec = DepthRecommendation(recommendedDepth: variant, confidence: 0.8)
            let text = rec.rationale(variantFamily: .pbc)
            #expect(!text.isEmpty, "Expected non-empty rationale for \(variant) in PBC")
        }
    }

    @Test("rationale returns empty string when recommendedDepth is nil")
    func rationaleEmptyForNilDepth() {
        let rec = DepthRecommendation(recommendedDepth: nil, confidence: 0.8)
        #expect(rec.rationale(variantFamily: .emh).isEmpty)
        #expect(rec.rationale(variantFamily: .pbc).isEmpty)
    }

    @Test("rationale for .medium/.emh contains 'engagement' or 'comprehension'")
    func rationaleContentMediumEMH() {
        let rec = DepthRecommendation(recommendedDepth: .medium, confidence: 0.9)
        let text = rec.rationale(variantFamily: .emh).lowercased()
        #expect(text.contains("engagement") || text.contains("comprehension") || text.contains("calibrated"))
    }
}

// MARK: - FakeAIRepository depth tests

@Suite("FakeAIRepository — depth recommendation")
struct FakeAIRepositoryDepthTests {

    @Test("depthRecommendation returns sample data by default")
    func returnsDefaultSampleData() async throws {
        let repo = FakeAIRepository()
        let rec = try await repo.depthRecommendation(bookId: "b-test")
        #expect(rec.recommendedDepth == .medium)
        #expect(rec.confidence == 0.85)
        #expect(rec.isConfident)
    }

    @Test("depthRecommendation throws when configured with an error")
    func throwsOnForcedError() async {
        let repo = FakeAIRepository(error: AppError.offline)
        do {
            _ = try await repo.depthRecommendation(bookId: "b-test")
            Issue.record("Expected throw but succeeded")
        } catch {
            if case AppError.offline = error { } else {
                Issue.record("Expected .offline error, got \(error)")
            }
        }
    }

    @Test("depthRecommendation throws when depth is nil")
    func throwsWhenDepthIsNil() async {
        let repo = FakeAIRepository(depth: nil)
        do {
            _ = try await repo.depthRecommendation(bookId: "b-test")
            Issue.record("Expected throw but succeeded")
        } catch {
            // expected
        }
    }

    @Test("lowConfidenceDepthRecommendation is not confident")
    func lowConfidenceNotConfident() {
        let rec = FakeAIRepository.lowConfidenceDepthRecommendation
        #expect(!rec.isConfident)
    }
}

// MARK: - Endpoint

@Suite("Endpoint.getDepthRecommendation")
struct DepthRecommendationEndpointTests {

    @Test("builds correct path")
    func correctPath() {
        let endpoint = Endpoints.getDepthRecommendation(bookId: "b-atomic-habits")
        #expect(endpoint.path == "/book/me/books/b-atomic-habits/depth-recommendation")
        #expect(endpoint.method == .get)
        #expect(endpoint.requiresAuth == true)
    }
}
