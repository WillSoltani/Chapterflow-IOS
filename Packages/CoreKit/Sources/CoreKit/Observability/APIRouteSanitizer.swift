import Foundation

/// Converts concrete API paths into a bounded, low-cardinality route.
///
/// Only reviewed static segments survive. Numeric values become a numeric
/// placeholder; every other value becomes an identifier placeholder. Query
/// strings and fragments are discarded before any segment work, and malformed
/// or ambiguous inputs fail closed.
public enum APIRouteSanitizer {
    public static let unknownRoute = "/unknown"

    private static let maxPathBytes = 512
    private static let maxSegmentBytes = 128
    private static let maxSegments = 12
    private static let maxOutputBytes = 160

    /// Route grammar reviewed from the current Networking contract inventory.
    /// A literal survives only in its reviewed position. When a concrete path
    /// matches both a literal and an identifier template, the identifier wins.
    private static let reviewedRouteTemplates: [[String]] = [
        "/auth/session",
        "/book/books",
        "/book/books/journeys",
        "/book/books/:id",
        "/book/books/:id/ask",
        "/book/books/:id/chapters/:number",
        "/book/books/:id/chapters/:number/audio",
        "/book/books/:id/chapters/:number/quiz",
        "/book/books/:id/chapters/:number/quiz/check",
        "/book/books/:id/concept-graph",
        "/book/config/ios",
        "/book/events/active",
        "/book/me/account/deactivate",
        "/book/me/account/delete",
        "/book/me/analytics/beacon",
        "/book/me/analytics/track",
        "/book/me/badges",
        "/book/me/billing/apple/verify",
        "/book/me/blocks",
        "/book/me/blocks/:id",
        "/book/me/books/:id/chapters/:number/scenarios",
        "/book/me/books/:id/depth-recommendation",
        "/book/me/books/:id/start",
        "/book/me/books/:id/state",
        "/book/me/commitments",
        "/book/me/commitments/:id",
        "/book/me/dashboard",
        "/book/me/devices/register",
        "/book/me/devices/unregister",
        "/book/me/entitlements",
        "/book/me/events/:id/join",
        "/book/me/events/:id/progress",
        "/book/me/export",
        "/book/me/flow-points",
        "/book/me/flow-points/redeem",
        "/book/me/gifts",
        "/book/me/gifts/:id",
        "/book/me/gifts/:id/claim",
        "/book/me/journeys/:id",
        "/book/me/journeys/:id/start",
        "/book/me/notebook",
        "/book/me/notebook/:id",
        "/book/me/notifications",
        "/book/me/notifications/read-all",
        "/book/me/onboarding/complete",
        "/book/me/onboarding/progress",
        "/book/me/pairs",
        "/book/me/pairs/accept/:id",
        "/book/me/pairs/invite",
        "/book/me/pairs/:id",
        "/book/me/pairs/:id/nudge",
        "/book/me/profile",
        "/book/me/progress",
        "/book/me/quiz/:id/:number/events",
        "/book/me/quiz/:id/:number/submit",
        "/book/me/reading-sessions",
        "/book/me/referrals",
        "/book/me/referrals/apply",
        "/book/me/reflections/:id/:number",
        "/book/me/reflections/:id/:number/feedback",
        "/book/me/reviews",
        "/book/me/reviews/:id",
        "/book/me/saved",
        "/book/me/settings",
        "/book/me/share-events",
        "/book/me/shop",
        "/book/me/streak",
        "/book/me/tier",
        "/book/moderation/reports",
        "/book/search-index",
        "/book/users/:id/profile",
    ].map { template in
        template.split(separator: "/").map(String.init)
    }

    public static func sanitize(_ rawPath: String) -> String {
        guard let path = boundedPathBeforeQueryOrFragment(rawPath),
              path.first == "/"
        else {
            return unknownRoute
        }

        var rawSegments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard rawSegments.first?.isEmpty == true else { return unknownRoute }
        rawSegments.removeFirst()

        // A single trailing slash has no route-cardinality meaning.
        if rawSegments.last?.isEmpty == true {
            rawSegments.removeLast()
        }

        guard !rawSegments.isEmpty,
              rawSegments.count <= maxSegments,
              rawSegments.allSatisfy({ !$0.isEmpty })
        else {
            return unknownRoute
        }

        var decodedSegments: [String] = []
        decodedSegments.reserveCapacity(rawSegments.count)
        for rawSegment in rawSegments {
            guard let segment = decodeUnambiguousSegment(rawSegment) else {
                return unknownRoute
            }
            decodedSegments.append(segment)
        }

        let matchingTemplates = reviewedRouteTemplates.filter {
            templateMatches($0, decodedSegments: decodedSegments)
        }
        guard !matchingTemplates.isEmpty else { return unknownRoute }

        let safeSegments = decodedSegments.indices.map { index in
            let isDynamic = matchingTemplates.contains {
                $0[index] == ":id" || $0[index] == ":number"
            }
            guard isDynamic else { return decodedSegments[index] }
            return isASCIINumber(decodedSegments[index]) ? ":number" : ":id"
        }

        let route = "/" + safeSegments.joined(separator: "/")
        guard route.utf8.count <= maxOutputBytes else { return unknownRoute }
        return route
    }

    /// Stops scanning as soon as a query or fragment delimiter is found. This
    /// keeps a huge query value from increasing route-sanitization work.
    private static func boundedPathBeforeQueryOrFragment(_ rawPath: String) -> String? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(maxPathBytes)

        for byte in rawPath.utf8 {
            if byte == Character("?").asciiValue || byte == Character("#").asciiValue {
                break
            }
            guard bytes.count < maxPathBytes else { return nil }
            bytes.append(byte)
        }

        return String(bytes: bytes, encoding: .utf8)
    }

    private static func decodeUnambiguousSegment(_ rawSegment: Substring) -> String? {
        let bytes = Array(rawSegment.utf8)
        guard !bytes.isEmpty, bytes.count <= maxSegmentBytes else { return nil }

        var index = 0
        while index < bytes.count {
            if bytes[index] == Character("%").asciiValue {
                guard index + 2 < bytes.count,
                      isHexDigit(bytes[index + 1]),
                      isHexDigit(bytes[index + 2])
                else {
                    return nil
                }
                index += 3
            } else {
                index += 1
            }
        }

        guard let decoded = String(rawSegment).removingPercentEncoding,
              !decoded.isEmpty,
              decoded.utf8.count <= maxSegmentBytes,
              decoded != ".",
              decoded != "..",
              !decoded.contains("%"),
              !decoded.contains("/"),
              !decoded.contains("\\"),
              !decoded.contains("?"),
              !decoded.contains("#"),
              decoded.unicodeScalars.allSatisfy({
                  $0.value >= 0x20
                      && $0.value != 0x7F
                      && !CharacterSet.whitespacesAndNewlines.contains($0)
              })
        else {
            return nil
        }

        return decoded
    }

    private static func templateMatches(
        _ template: [String],
        decodedSegments: [String]
    ) -> Bool {
        guard template.count == decodedSegments.count else { return false }

        return zip(template, decodedSegments).allSatisfy { pattern, segment in
            switch pattern {
            case ":id":
                true
            case ":number":
                isASCIINumber(segment)
            default:
                pattern == segment
            }
        }
    }

    private static func isASCIINumber(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
            || (65...70).contains(byte)
            || (97...102).contains(byte)
    }
}
