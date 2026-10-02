import Foundation

/// A `filmWindow` step: press a key and film the whole window while whatever
/// it sets off slides, to see how often the window drew a new picture.
///
/// The main thread's busy time does not say this. On 2026-09-29 the slide into
/// Edit mode and the slide back to View kept it about equally busy, and one
/// drew a new picture every 8ms while the other drew one every 40 to 90. What
/// a person sees is the pictures, so that is what this counts.
public struct PlaytestSlideFilm: Sendable, Equatable {
    public static let defaultSeconds: Double = 0.8

    /// Frames go to `<name>-<n>-sc.png` and the readings to `<name>.json`.
    public var name: String
    /// What sets the slide off: a key, or a press on a panel control's face
    /// (a section header opening, say), the same two a `filmThumb` takes.
    public var trigger: PlaytestThumbFilm.Trigger
    public var seconds: Double
    /// How long after the key the slide is read for, nil for the whole film.
    /// Whatever the window draws after the slide has landed (the editor
    /// arriving onto a window that has stopped) is not the slide.
    public var withinMS: Double?
    /// A claim: the step fails when, between the first new picture after the
    /// key and the last it reads, the window went longer than this without one.
    public var longestStillUnderMS: Double?

    /// The key, when a key sets it off.
    public var key: PlaytestKey? {
        if case .key(let key, _) = trigger { key } else { nil }
    }

    public var modifiers: [PlaytestModifier] {
        if case .key(_, let modifiers) = trigger { modifiers } else { [] }
    }

    public init(name: String, trigger: PlaytestThumbFilm.Trigger,
                seconds: Double = Self.defaultSeconds, withinMS: Double? = nil,
                longestStillUnderMS: Double? = nil) {
        self.name = name
        self.trigger = trigger
        self.seconds = seconds
        self.withinMS = withinMS
        self.longestStillUnderMS = longestStillUnderMS
    }

    public init(name: String, key: PlaytestKey, modifiers: [PlaytestModifier] = [],
                seconds: Double = Self.defaultSeconds, withinMS: Double? = nil,
                longestStillUnderMS: Double? = nil) {
        self.init(name: name, trigger: .key(key, modifiers), seconds: seconds,
                  withinMS: withinMS, longestStillUnderMS: longestStillUnderMS)
    }
}

/// When a window drew its new pictures, read as one slide: the first after
/// the key, the last, how many, and the longest it sat still in between.
public struct SlideCadence: Sendable, Equatable {
    /// Milliseconds after the key of the first new picture, nil if none came.
    public let firstMS: Double?
    /// ...and of the last, which is where the slide settled.
    public let lastMS: Double?
    /// New pictures from the first to the last, both counted.
    public let pictures: Int
    /// The longest gap between two of them: a frame the window never drew.
    public let longestStillMS: Double

    /// `picturesAtMS` is when each new picture was drawn, on the same clock
    /// as `keyAtMS`; pictures from before the key are the window at rest, and
    /// those more than `withinMS` after it are left out when it is given.
    public static func read(picturesAtMS: [Double], keyAtMS: Double, withinMS: Double? = nil) -> SlideCadence {
        let after = picturesAtMS.map { $0 - keyAtMS }
            .filter { $0 >= 0 && $0 <= (withinMS ?? .infinity) }.sorted()
        let longest = zip(after, after.dropFirst()).map { $1 - $0 }.max() ?? 0
        return SlideCadence(firstMS: after.first, lastMS: after.last, pictures: after.count,
                            longestStillMS: longest)
    }

    public var summary: String {
        guard let firstMS, let lastMS else { return "the window drew nothing new after the key" }
        return String(format: "first new picture %.0fms after the key, %d pictures until it settled at %.0fms, "
                          + "longest still %.0fms", firstMS, pictures, lastMS, longestStillMS)
    }
}
