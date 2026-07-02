/// A string value that ships in three tone-specific variants.
///
/// Use `resolve(_:)` to select the right string for the user's active tone.
public struct ToneKeyed: Codable, Sendable, Equatable {
    public let gentle: String
    public let direct: String
    public let competitive: String

    public init(gentle: String, direct: String, competitive: String) {
        self.gentle = gentle
        self.direct = direct
        self.competitive = competitive
    }

    /// Returns the string for the given tone preference.
    /// Falls back to the `gentle` variant for any unrecognised future tone.
    public func resolve(_ tone: ToneKey) -> String {
        switch tone {
        case .gentle:      return gentle
        case .direct:      return direct
        case .competitive: return competitive
        case .unknown:     return gentle
        }
    }
}
