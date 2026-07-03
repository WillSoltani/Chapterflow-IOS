/// Server-returned adaptive reading-depth recommendation for a user/book pair.
///
/// Decoded from `GET /book/me/books/{bookId}/depth-recommendation`.
///
/// **Tolerant decoding contract (RF2):**
/// - A missing `recommendedDepth` key → `nil` (hides the recommendation)
/// - An unrecognised `recommendedDepth` string → `nil` (hides, never crashes)
/// - An absent `confidence` key → decoding throws (field is required by the API)
public struct DepthRecommendation: Codable, Sendable {

    // MARK: - Properties

    /// The server-recommended reading depth.
    ///
    /// `nil` when the field is absent or contains an unrecognised variant string.
    /// Views must treat `nil` as "hide the recommendation".
    public let recommendedDepth: VariantKey?

    /// Server-reported confidence in the recommendation (0–1).
    public let confidence: Double

    // MARK: - Threshold

    /// Minimum confidence required to surface the recommendation to the user.
    public static let minimumConfidence: Double = 0.7

    /// `true` when the recommendation is confident enough to show.
    ///
    /// Low-confidence recommendations are hidden entirely — no badge, no rationale.
    public var isConfident: Bool { confidence >= Self.minimumConfidence }

    // MARK: - Init

    public init(recommendedDepth: VariantKey?, confidence: Double) {
        self.recommendedDepth = recommendedDepth
        self.confidence = confidence
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case recommendedDepth
        case confidence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Tolerant depth decoding: missing or unknown → nil (hide, don't crash).
        if let rawDepth = try container.decodeIfPresent(String.self, forKey: .recommendedDepth) {
            let variant = VariantKey(rawValue: rawDepth)
            switch variant {
            case .unknown:
                // Unknown server value — hide the recommendation.
                recommendedDepth = nil
            default:
                recommendedDepth = variant
            }
        } else {
            recommendedDepth = nil
        }

        confidence = (try? container.decode(Double.self, forKey: .confidence)) ?? 0
    }
}

// MARK: - Rationale

extension DepthRecommendation {

    /// A one-line "why" rationale string for displaying alongside the recommendation.
    ///
    /// Generated client-side from the variant and family — the server does not provide
    /// rationale text. Returns an empty string when `recommendedDepth` is `nil`.
    ///
    /// - Parameter variantFamily: The book's variant family, used to pick appropriate copy.
    public func rationale(variantFamily: VariantFamily) -> String {
        guard let depth = recommendedDepth else { return "" }
        switch (variantFamily, depth) {
        case (.emh, .easy):
            return "Matched to your reading pace — keeps ideas clear and actionable."
        case (.emh, .medium):
            return "Calibrated to your recent engagement and comprehension pace."
        case (.emh, .hard):
            return "Your comprehension signals suggest you're ready for the full depth."
        case (.pbc, .precise):
            return "Matched to your reading pace — keeps ideas concise and direct."
        case (.pbc, .balanced):
            return "Calibrated to your pace and recent chapter engagement."
        case (.pbc, .challenging):
            return "Your reading patterns indicate readiness for the most rigorous version."
        default:
            return "Calibrated to your reading patterns for this book."
        }
    }
}
