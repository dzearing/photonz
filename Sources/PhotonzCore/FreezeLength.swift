import Foundation

// How long a freeze is, as somebody types it into the Freeze Frame popover
// (the user, 2026-10-17: "why have a submenu with only a fixed set of options
// when you could just pop up a dialog and select what you want? Maybe I want
// to freeze it for 10 seconds").
//
// A length is read the ways an editor writes one: `10`, `10s`, `2.5 s`,
// `1:30` (minutes and seconds), `48f` or `48 frames` (at the timeline's
// thirty frames a second), `500ms`. Anything else is not a length, and the
// popover's Insert stays off rather than guessing.

/// A freeze's length, read from what was typed.
public enum FreezeLength {

    /// What the field holds when the popover opens.
    public static let defaultMS = ClipPieces.defaultHoldMS

    /// The longest freeze the field takes: an hour, which no edit wants and
    /// which keeps a slip of the keyboard (a stray row of zeros) from making a
    /// document days long.
    public static let longestMS = 3_600_000

    /// The timeline's frame rate, for a length typed in frames.
    static let framesPerSecond = (1000.0 / Double(MovieRef.frameStepMS)).rounded()

    /// The length `text` means, in milliseconds, or nil where it is not one.
    public static func parse(_ text: String) -> Int? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !typed.isEmpty else { return nil }
        let ms: Double?
        if typed.contains(":") {
            ms = minutesAndSeconds(typed)
        } else if let n = number(typed, endingIn: ["frames", "frame", "fr", "f"]) {
            ms = n * 1000 / framesPerSecond
        } else if let n = number(typed, endingIn: ["ms"]) {
            ms = n
        } else if let n = number(typed, endingIn: ["seconds", "second", "secs", "sec", "s", ""]) {
            ms = n * 1000
        } else {
            ms = nil
        }
        guard let ms, ms.isFinite else { return nil }
        let rounded = Int(ms.rounded())
        guard rounded >= ClipPiece.shortestMS, rounded <= longestMS else { return nil }
        return rounded
    }

    /// What the field shows for a length: the same words the timeline uses.
    public static func text(_ ms: Int) -> String { ClipPieces.holdTitle(ms) }

    /// `1:30` or `0:02.5`: minutes, then seconds.
    private static func minutesAndSeconds(_ typed: String) -> Double? {
        let parts = typed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let seconds = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              minutes >= 0, seconds >= 0, seconds < 60, minutes == minutes.rounded() else { return nil }
        return (minutes * 60 + seconds) * 1000
    }

    /// The number in front of the first of `units` that `typed` ends in, with
    /// or without a space between them.
    private static func number(_ typed: String, endingIn units: [String]) -> Double? {
        for unit in units where typed.hasSuffix(unit) {
            let head = typed.dropLast(unit.count).trimmingCharacters(in: .whitespaces)
            guard !head.isEmpty, head.allSatisfy({ $0.isNumber || $0 == "." }),
                  let value = Double(head), value > 0 else { continue }
            return value
        }
        return nil
    }
}
