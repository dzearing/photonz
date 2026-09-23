import Foundation

/// **What kind of track a row of the timeline is** (`docs/design/mocks/pages/video.html`).
///
/// The mock gives every track an icon and every clip a colour, and both say the
/// same one thing: what the clip on it is. A recording is video, a sound is
/// audio, words are text, a placed component is a component, and anything else
/// drawn over the picture is an overlay. Nothing else about a clip changes its
/// colour; being picked, retimed or keyed is drawn on top.
public enum TimelineTrackKind: String, Hashable, Sendable, CaseIterable {
    case video, audio, text, component, overlay
}

extension Layer {
    /// The kind of track this layer's row is on the timeline.
    ///
    /// A recording stays video even while it still carries its own sound: the
    /// picture is what it is, and its sound is drawn inside its clip.
    public var timelineTrackKind: TimelineTrackKind {
        if instanceOf != nil { return .component }
        if movie != nil { return .video }
        switch content {
        case .sound: return .audio
        case .text: return .text
        default: return .overlay
        }
    }
}

extension MotionStripRuler {
    /// The numbers along a document's ruler, written in plain seconds the way
    /// the mock writes them: `0s 3s 6s`, `2.5s` once the numbers are closer
    /// than a second apart, and `1:00` once the ruler reaches a minute.
    ///
    /// Every label carries its unit, unlike the icon strip's milliseconds,
    /// because "3s" is a short word and "3" on a video ruler reads as a frame.
    public var secondTicks: [Tick] {
        let step = Self.secondStep(for: spanMS)
        var values: [Double] = []
        var ms = (startMS / step).rounded(.down) * step
        if ms < startMS - 0.001 { ms += step }
        while ms <= startMS + spanMS + 0.001 {
            values.append(ms)
            ms += step
        }
        let inMinutes = startMS + spanMS >= 60_000
        return values.map { value in
            Tick(ms: value, label: inMinutes && step >= 1000
                 ? Self.timecode(value) : Self.seconds(value))
        }
    }

    /// A step a video editor would say out loud: tenths and halves below a
    /// second, then 1, 2, 3, 5, 10, 15, 30 seconds, then whole minutes. The
    /// threes and fifteens are what make a fifteen second ruler read in threes,
    /// which is the mock's.
    static func secondStep(for span: Double) -> Double {
        // About six numbers across the width, the density the mock's ruler has.
        let target = span / 6
        let ladder: [Double] = [100, 200, 500, 1000, 2000, 3000, 5000, 10_000,
                                15_000, 30_000, 60_000, 120_000, 300_000, 600_000,
                                900_000, 1_800_000, 3_600_000]
        return ladder.first { $0 >= target } ?? 3_600_000
    }

    /// `3s`, or `2.5s` where there is a fraction.
    static func seconds(_ ms: Double) -> String {
        let tenths = (max(0, ms) / 100).rounded()
        if Int(tenths) % 10 == 0 { return "\(Int(tenths) / 10)s" }
        return String(format: "%.1fs", tenths / 10)
    }
}
