import Foundation
import Observation

/// The user's preferred teaching tone (matches the server's `ToneKeyed` scheme).
public enum ReadingTone: String, Sendable, CaseIterable, Codable {
    case gentle, direct, competitive
}

/// The user's preferred reading-depth variant (EMH or PBC family).
public enum DepthVariant: String, Sendable, CaseIterable, Codable {
    case easy, medium, hard
    case precise, balanced, challenging
}

/// The app's appearance mode.
public enum ThemeMode: String, Sendable, CaseIterable, Codable {
    case system, light, dark
}

/// The reader's visual theme.
///
/// Each case maps to a full token set (page background, text, accent, quote,
/// separator) computed in `ReaderFeature`. `system` follows the current
/// iOS light/dark mode; the rest are fixed regardless of the system setting.
public enum ReadingTheme: String, Sendable, CaseIterable, Codable {
    /// Follows the system light/dark appearance.
    case system
    /// Clean white page, near-black text.
    case light
    /// Warm cream page, rich brown text — premium sepia.
    case sepia
    /// OLED true-black page, soft light text.
    case dark
    /// Warm off-white page, near-black text — e-reader paper feel.
    case paper

    /// Human-readable label used in the appearance panel.
    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .dark: return "Dark"
        case .paper: return "Paper"
        }
    }
}

/// The user's preferred learning mode for a book.
public enum LearningMode: String, Sendable, CaseIterable, Codable {
    /// Read the chapter text (default).
    case reading
    /// Prefer audio narration.
    case listening
    /// Focus on quizzes and reviews.
    case reviewing

    public var displayName: String {
        switch self {
        case .reading: return "Reading"
        case .listening: return "Listening"
        case .reviewing: return "Reviewing"
        }
    }

    public var systemImage: String {
        switch self {
        case .reading: return "book.pages"
        case .listening: return "headphones"
        case .reviewing: return "checkmark.circle"
        }
    }
}

/// An `@Observable` store of user reading/audio/appearance preferences, backed by
/// App-Group `UserDefaults` so widgets and extensions read the same values.
///
/// Reads happen once at init; each mutation writes through to the backing store.
@MainActor
@Observable
public final class AppPreferences {
    @ObservationIgnored private let defaults: UserDefaults

    /// Preferred teaching tone.
    public var readingTone: ReadingTone {
        didSet { defaults.set(readingTone.rawValue, forKey: Keys.readingTone) }
    }

    /// Preferred reading-depth variant.
    public var depthVariant: DepthVariant {
        didSet { defaults.set(depthVariant.rawValue, forKey: Keys.depthVariant) }
    }

    /// Appearance mode (system/light/dark).
    public var themeMode: ThemeMode {
        didSet { defaults.set(themeMode.rawValue, forKey: Keys.themeMode) }
    }

    /// Reader visual theme.
    public var readerTheme: ReadingTheme {
        didSet { defaults.set(readerTheme.rawValue, forKey: Keys.readerTheme) }
    }

    /// Reader font scale multiplier (1.0 == Dynamic Type base size).
    /// Range 0.8 – 1.8; values below 1.0 are clamped to DT base at render time.
    public var readerFontScale: Double {
        didSet { defaults.set(readerFontScale, forKey: Keys.readerFontScale) }
    }

    /// Extra line spacing added to the reader body text (in points).
    /// Range 0 – 16; default 6.
    public var readerLineSpacing: Double {
        didSet { defaults.set(readerLineSpacing, forKey: Keys.readerLineSpacing) }
    }

    /// Audio narration playback speed (1.0 == normal).
    public var audioSpeed: Double {
        didSet { defaults.set(audioSpeed, forKey: Keys.audioSpeed) }
    }

    /// Daily reminder hour (0...23).
    public var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: Keys.reminderHour) }
    }

    /// Daily reminder minute (0...59).
    public var reminderMinute: Int {
        didSet { defaults.set(reminderMinute, forKey: Keys.reminderMinute) }
    }

    /// The daily reminder time as `DateComponents` (hour + minute).
    public var reminderTime: DateComponents {
        get { DateComponents(hour: reminderHour, minute: reminderMinute) }
        set {
            reminderHour = newValue.hour ?? reminderHour
            reminderMinute = newValue.minute ?? reminderMinute
        }
    }

    // MARK: - Onboarding / Interests

    /// IDs of interest categories the user selected during onboarding.
    /// Read by the Discover "For You" rail (P2.9) to rank content.
    public var interestIds: [String] {
        didSet { defaults.set(interestIds, forKey: Keys.interestIds) }
    }

    /// `true` once the first-run onboarding flow has been completed or skipped.
    public var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }

    // MARK: - Downloads

    /// When `true`, audio segment downloads are restricted to Wi-Fi connections.
    public var downloadOverWifiOnly: Bool {
        didSet { defaults.set(downloadOverWifiOnly, forKey: Keys.downloadOverWifiOnly) }
    }

    /// Maximum on-disk storage for all downloaded books, in gigabytes.
    /// `0` means unlimited. Default: 5 GB.
    public var downloadStorageLimitGB: Double {
        didSet { defaults.set(downloadStorageLimitGB, forKey: Keys.downloadStorageLimitGB) }
    }

    /// Convenience: `downloadStorageLimitGB` converted to bytes, or `nil` when unlimited.
    public var downloadStorageLimitBytes: Int64? {
        downloadStorageLimitGB > 0 ? Int64(downloadStorageLimitGB * 1_073_741_824) : nil
    }

    /// Creates a preferences store. Pass a custom `defaults` for tests/previews;
    /// defaults to the App Group suite, falling back to `.standard`.
    public init(defaults: UserDefaults? = nil) {
        let store = defaults ?? UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        self.defaults = store

        self.readingTone = store.string(forKey: Keys.readingTone)
            .flatMap(ReadingTone.init(rawValue:)) ?? .direct
        self.depthVariant = store.string(forKey: Keys.depthVariant)
            .flatMap(DepthVariant.init(rawValue:)) ?? .medium
        self.themeMode = store.string(forKey: Keys.themeMode)
            .flatMap(ThemeMode.init(rawValue:)) ?? .system
        self.readerTheme = store.string(forKey: Keys.readerTheme)
            .flatMap(ReadingTheme.init(rawValue:)) ?? .system
        self.readerFontScale = (store.object(forKey: Keys.readerFontScale) as? Double) ?? 1.0
        self.readerLineSpacing = (store.object(forKey: Keys.readerLineSpacing) as? Double) ?? 6.0
        self.audioSpeed = (store.object(forKey: Keys.audioSpeed) as? Double) ?? 1.0
        self.reminderHour = (store.object(forKey: Keys.reminderHour) as? Int) ?? 20
        self.reminderMinute = (store.object(forKey: Keys.reminderMinute) as? Int) ?? 0
        self.interestIds = store.stringArray(forKey: Keys.interestIds) ?? []
        self.onboardingCompleted = store.bool(forKey: Keys.onboardingCompleted)
        self.downloadOverWifiOnly = store.bool(forKey: Keys.downloadOverWifiOnly)
        self.downloadStorageLimitGB = (store.object(forKey: Keys.downloadStorageLimitGB) as? Double) ?? 5.0
    }

    private enum Keys {
        static let readingTone = "pref.readingTone"
        static let depthVariant = "pref.depthVariant"
        static let themeMode = "pref.themeMode"
        static let readerTheme = "pref.readerTheme"
        static let readerFontScale = "pref.readerFontScale"
        static let readerLineSpacing = "pref.readerLineSpacing"
        static let audioSpeed = "pref.audioSpeed"
        static let reminderHour = "pref.reminderHour"
        static let reminderMinute = "pref.reminderMinute"
        static let interestIds = "pref.interestIds"
        static let onboardingCompleted = "pref.onboardingCompleted"
        static let downloadOverWifiOnly = "pref.downloadOverWifiOnly"
        static let downloadStorageLimitGB = "pref.downloadStorageLimitGB"
    }
}
