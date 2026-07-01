import Foundation

/// Relative-time formatting helpers for timestamps in the UI.
public enum RelativeDate {
    /// A localized, spelled-out relative string (e.g. "2 hours ago", "in 3 days").
    /// - Parameters:
    ///   - date: The date to describe.
    ///   - reference: The "now" to measure against (injectable for tests).
    ///   - locale: The locale for formatting.
    public static func string(
        for date: Date,
        relativeTo reference: Date = Date(),
        locale: Locale = .current
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: reference)
    }

    /// A terse magnitude label with no locale dependence: `"now"`, `"5m"`, `"2h"`,
    /// `"3d"`, `"4w"`, `"2mo"`, `"1y"`. Direction (past/future) is not encoded.
    public static func compact(for date: Date, relativeTo reference: Date = Date()) -> String {
        let seconds = abs(reference.timeIntervalSince(date))
        let minute = 60.0
        let hour = 3_600.0
        let day = 86_400.0
        let week = 604_800.0
        let month = 2_592_000.0   // 30 days
        let year = 31_536_000.0   // 365 days

        switch seconds {
        case ..<minute:
            return "now"
        case ..<hour:
            return "\(Int(seconds / minute))m"
        case ..<day:
            return "\(Int(seconds / hour))h"
        case ..<week:
            return "\(Int(seconds / day))d"
        case ..<month:
            return "\(Int(seconds / week))w"
        case ..<year:
            return "\(Int(seconds / month))mo"
        default:
            return "\(Int(seconds / year))y"
        }
    }
}
