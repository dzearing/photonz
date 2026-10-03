import Foundation

/// How long a recording may take to begin once Start is pressed.
///
/// Whatever the person does straight after pressing Start is what they meant
/// to film, so the first frame has to be taken before they can have done
/// anything: a beat they can feel is a beat missing from the file. The reading
/// runs from the Return key (or the end of a region drag) to the stream's
/// first frame, and the median of a set of runs decides.
public enum RecordingStartBudget {
    /// Return to the first frame, in milliseconds.
    public static let returnToFirstFrameMS: Double = 100

    /// The middle reading of a set, or the mean of the middle two.
    public static func median(_ readings: [Double]) -> Double? {
        guard !readings.isEmpty else { return nil }
        let sorted = readings.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Whether a set of runs is inside the budget. Any reading that is not a
    /// real duration fails the whole set, and so does an empty one.
    public static func isWithin(readingsMS readings: [Double]) -> Bool {
        guard readings.allSatisfy({ $0.isFinite && $0 >= 0 }),
              let median = median(readings) else { return false }
        return median <= returnToFirstFrameMS
    }
}

/// What to do with a capture stream started while the recording card was up,
/// once the person presses Start.
///
/// Starting a stream costs about 60 ms of ScreenCaptureKit's time, and finding
/// the display and the stop control's window about 30 more, all before the
/// first frame. Doing that while the card is up, writing nothing, leaves Start
/// with only the file to begin. The stream's picture can be reframed in place
/// (a region chosen after the card), but its sound cannot be changed without a
/// new stream, and neither can its display.
public enum RecordingWarmStart: Equatable, Sendable {
    /// The warm stream is exactly what was chosen: begin the file on it.
    case begin
    /// Same sound, different part of the screen: reframe it, then begin.
    case reframe
    /// Nothing warm fits: start a stream from scratch.
    case cold

    public static func plan(warm: RecordingConfig?, chosen: RecordingConfig, sameDisplay: Bool) -> Self {
        guard let warm, sameDisplay, sound(warm) == sound(chosen) else { return .cold }
        return warm.source == chosen.source ? .begin : .reframe
    }

    /// What the stream hears: the sources, and which microphone when one is on.
    private static func sound(_ config: RecordingConfig) -> [String?] {
        [String(config.audio.rawValue), config.audio.capturesMicrophone ? config.microphoneDeviceID : nil]
    }
}
