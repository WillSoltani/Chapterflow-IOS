import SwiftUI

/// Pseudo-localization for previews and QA.
///
/// The OS pseudolanguages (`en-XA`, `ar-XB`) are the primary QA mechanism —
/// launch the app in them to reveal untranslated strings and truncation
/// (see `docs/LOCALIZATION.md`). This pure-Swift transform brings the same idea
/// into SwiftUI **previews**, so truncation and overflow are visible in the
/// canvas at design time without booting a simulator.
///
/// It intentionally mimics the two OS pseudolanguages:
/// - ``Style/accented`` — accents Latin letters and pads by ~40% (mirrors
///   `en-XA`), the worst case for English layout width.
/// - ``Style/bidi`` — accents, roughly doubles length, and wraps the string in
///   right-to-left isolates (mirrors `ar-XB`), exposing RTL/mirroring issues.
public enum PseudoLocalization {

    /// Which OS pseudolanguage the transform imitates.
    public enum Style: Sendable {
        /// Accented + ~40% longer (imitates `en-XA`).
        case accented
        /// Accented + ~100% longer + RTL isolates (imitates `ar-XB`).
        case bidi
    }

    /// Returns a pseudo-localized copy of `string`.
    ///
    /// Format specifiers (`%@`, `%lld`, `%1$@`, `%%`) are preserved verbatim so a
    /// pseudo-localized *format string* still interpolates correctly. Whitespace
    /// and punctuation are left untouched so word boundaries stay legible.
    ///
    /// - Parameters:
    ///   - string: The source (development-language) string.
    ///   - style: The pseudolanguage to imitate. Defaults to ``Style/accented``.
    public static func transform(_ string: String, style: Style = .accented) -> String {
        let accented = accentPreservingFormatSpecifiers(string)
        let padded = pad(accented, by: style == .bidi ? 1.0 : 0.4)
        let wrapped = "⟦\(padded)⟧"
        guard style == .bidi else { return wrapped }
        // U+2067 RIGHT-TO-LEFT ISOLATE … U+2069 POP DIRECTIONAL ISOLATE
        return "\u{2067}\(wrapped)\u{2069}"
    }

    // MARK: - Internals

    /// Accents every Latin letter except those inside a format specifier.
    ///
    /// The specifier regex matches a whole `printf`/`NSString`-style token
    /// (`%%`, `%@`, `%lld`, `%1$@`, `%.2f`, `%2$lld`, …). The length modifier
    /// (`ll`, `h`, …) and positional `n$` are kept together so accenting never
    /// splits a specifier.
    static func accentPreservingFormatSpecifiers(_ string: String) -> String {
        let specifier =
            /%(?:%|(?:[0-9]+\$)?[-+ 0#']*[0-9]*(?:\.[0-9]+)?(?:hh|h|ll|l|q|L|z|t|j)?[@a-zA-Z])/
        var result = ""
        result.reserveCapacity(string.count)
        var cursor = string.startIndex
        for match in string.matches(of: specifier) {
            if cursor < match.range.lowerBound {
                result += accentAll(string[cursor..<match.range.lowerBound])
            }
            result += string[match.range]          // specifier verbatim
            cursor = match.range.upperBound
        }
        if cursor < string.endIndex {
            result += accentAll(string[cursor...])
        }
        return result
    }

    private static func accentAll<S: StringProtocol>(_ s: S) -> String {
        String(s.map { accentMap[$0] ?? $0 })
    }

    private static func pad(_ string: String, by fraction: Double) -> String {
        // Count only "real" letters so specifiers don't inflate the estimate.
        let letters = string.filter { $0.isLetter }.count
        let extra = Int((Double(letters) * fraction).rounded(.up))
        guard extra > 0 else { return string }
        // Accented filler appended so wrapped/truncated layout is visible.
        let filler = String(repeating: "aeiou", count: (extra / 5) + 1).prefix(extra)
        return string + " " + accentAll(filler)
    }

    private static let accentMap: [Character: Character] = [
        "a": "á", "b": "ƀ", "c": "ç", "d": "ð", "e": "é", "f": "ƒ", "g": "ĝ",
        "h": "ĥ", "i": "í", "j": "ĵ", "k": "ķ", "l": "ĺ", "m": "ɱ", "n": "ñ",
        "o": "ó", "p": "þ", "q": "ǫ", "r": "ŕ", "s": "š", "t": "ţ", "u": "ú",
        "v": "ṽ", "w": "ŵ", "x": "ẋ", "y": "ý", "z": "ž",
        "A": "Á", "B": "Ɓ", "C": "Ç", "D": "Ð", "E": "É", "F": "Ƒ", "G": "Ĝ",
        "H": "Ĥ", "I": "Í", "J": "Ĵ", "K": "Ķ", "L": "Ĺ", "M": "Ṁ", "N": "Ñ",
        "O": "Ó", "P": "Þ", "Q": "Ǫ", "R": "Ŕ", "S": "Š", "T": "Ţ", "U": "Ú",
        "V": "Ṽ", "W": "Ŵ", "X": "Ẋ", "Y": "Ý", "Z": "Ž",
    ]
}

// MARK: - Preview helper

#if DEBUG
/// A tiny card that renders a label pseudo-localized, for truncation QA.
struct PseudoLocalizationSpecimen: View {
    let title: String
    let style: PseudoLocalization.Style

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(PseudoLocalization.transform(title, style: style))
                .font(.cfHeadline)
            Button {
            } label: {
                Text(PseudoLocalization.transform("Download for offline", style: style))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.cfSpacing16)
        .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.horizontal, .cfSpacing16)
    }
}

#Preview("Pseudo — Accented (Light)") {
    PseudoLocalizationSpecimen(title: "Continue Reading", style: .accented)
        .environment(\.layoutDirection, .leftToRight)
}

#Preview("Pseudo — Bidi/RTL (Dark)") {
    PseudoLocalizationSpecimen(title: "Continue Reading", style: .bidi)
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
}

#Preview("Pseudo — Accented (XXL)") {
    PseudoLocalizationSpecimen(title: "Continue Reading", style: .accented)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
