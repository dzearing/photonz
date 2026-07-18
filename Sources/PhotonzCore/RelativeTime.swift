import Foundation

/// Plain, human "time ago" strings for the history overlay's idle tiles
/// (e.g. "15 seconds ago", "2 hours ago", "yesterday"). Pure and deterministic:
/// buckets are driven by elapsed seconds, not a calendar, so there's no timezone
/// flakiness to test around. Copy rule: short, human, never an em dash.
public enum RelativeTime {
    /// A "time ago" phrase for a capture that happened `seconds` before now.
    /// Negative values (clock skew / a slightly-future stamp) read as "just now".
    public static func string(secondsAgo seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 5 { return "just now" }
        if s < 60 { return "\(Int(s)) seconds ago" }

        let minutes = Int(s / 60)
        if minutes < 60 { return count(minutes, "minute") }

        let hours = Int(s / 3600)
        if hours < 24 { return count(hours, "hour") }

        let days = Int(s / 86_400)
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }

        let weeks = days / 7
        if weeks < 5 { return count(weeks, "week") }

        let months = days / 30
        if months < 12 { return count(months, "month") }

        return count(days / 365, "year")
    }

    /// Convenience for two `Date`s: the phrase for `date` as seen from `now`.
    public static func string(from date: Date, to now: Date) -> String {
        string(secondsAgo: now.timeIntervalSince(date))
    }

    private static func count(_ n: Int, _ unit: String) -> String {
        n == 1 ? "1 \(unit) ago" : "\(n) \(unit)s ago"
    }
}
