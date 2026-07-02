// MARK: - StringOrTone

/// A field that the server sends as EITHER a plain `String` OR a `ToneKeyed` map.
///
/// Used for `scenario` and `whyItMatters` in `Example`. Older content uses plain
/// strings; v2.1 content uses tone-keyed maps.
public enum StringOrTone: Codable, Sendable, Equatable {
    case string(String)
    case toneKeyed(ToneKeyed)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .toneKeyed(try container.decode(ToneKeyed.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .toneKeyed(let t): try container.encode(t)
        }
    }

    /// Resolves to a single string for the given tone.
    public func resolve(_ tone: ToneKey) -> String {
        switch self {
        case .string(let s): return s
        case .toneKeyed(let t): return t.resolve(tone)
        }
    }
}

// MARK: - StringsOrTone

/// A field that the server sends as EITHER `[String]` OR a `ToneKeyed` map.
///
/// Used for `whatToDo` in `Example`.
public enum StringsOrTone: Codable, Sendable {
    case strings([String])
    case toneKeyed(ToneKeyed)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([String].self) {
            self = .strings(arr)
        } else {
            self = .toneKeyed(try container.decode(ToneKeyed.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .strings(let arr): try container.encode(arr)
        case .toneKeyed(let t): try container.encode(t)
        }
    }

    /// Resolves to an array of strings for the given tone.
    /// - A `ToneKeyed` value resolves to a single-element array.
    public func resolve(_ tone: ToneKey) -> [String] {
        switch self {
        case .strings(let arr): return arr
        case .toneKeyed(let t): return [t.resolve(tone)]
        }
    }
}

// MARK: - OneMinuteRecap

/// The `oneMinuteRecap` content field, which arrives in one of two shapes:
///
/// **Simple:** `{ gentle, direct, competitive }` — a plain `ToneKeyed` string.
/// **Structured:** `{ retrieve, connect, preview }` — each value is a `ToneKeyed`.
///
/// Discriminate by the presence of the `retrieve` key.
public enum OneMinuteRecap: Codable, Sendable {
    case simple(ToneKeyed)
    case structured(retrieve: ToneKeyed, connect: ToneKeyed, preview: ToneKeyed)

    private enum DiscriminatorKey: String, CodingKey { case retrieve }

    private struct Structured: Codable {
        let retrieve: ToneKeyed
        let connect: ToneKeyed
        let preview: ToneKeyed
    }

    public init(from decoder: Decoder) throws {
        let probe = try decoder.container(keyedBy: DiscriminatorKey.self)
        if probe.allKeys.contains(.retrieve) {
            let s = try Structured(from: decoder)
            self = .structured(retrieve: s.retrieve, connect: s.connect, preview: s.preview)
        } else {
            self = .simple(try ToneKeyed(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .simple(let t):
            try t.encode(to: encoder)
        case .structured(let r, let c, let p):
            try Structured(retrieve: r, connect: c, preview: p).encode(to: encoder)
        }
    }

    /// Resolves to a `ResolvedOneMinuteRecap` for the given tone.
    public func resolve(_ tone: ToneKey) -> ResolvedOneMinuteRecap {
        switch self {
        case .simple(let t):
            return ResolvedOneMinuteRecap(
                text: t.resolve(tone),
                retrieve: nil, connect: nil, preview: nil
            )
        case .structured(let r, let c, let p):
            return ResolvedOneMinuteRecap(
                text: nil,
                retrieve: r.resolve(tone),
                connect: c.resolve(tone),
                preview: p.resolve(tone)
            )
        }
    }
}

/// A `OneMinuteRecap` with all tone-keyed fields collapsed to strings.
public struct ResolvedOneMinuteRecap: Sendable, Equatable {
    /// Set for the simple (`ToneKeyed`) form.
    public let text: String?
    /// Set for the structured (`retrieve`/`connect`/`preview`) form.
    public let retrieve: String?
    public let connect: String?
    public let preview: String?

    public init(text: String?, retrieve: String?, connect: String?, preview: String?) {
        self.text = text
        self.retrieve = retrieve
        self.connect = connect
        self.preview = preview
    }
}
