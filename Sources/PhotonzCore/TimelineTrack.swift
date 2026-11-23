import Foundation

/// **What kind of track a row of the timeline is** (`docs/design/mocks/pages/video.html`).
///
/// The mock gives every track an icon and every clip a colour, and both say the
/// same one thing: what the clip on it is. A recording is video, a sound is
/// audio, words are text, a placed component is a component, a still picture
/// or logo laid over the video for a stretch is a graphic (the title mock's
/// Gfx track), and anything else drawn over the picture is an overlay. Nothing
/// else about a clip changes its colour; being picked, retimed or keyed is
/// drawn on top.
public enum TimelineTrackKind: String, Hashable, Sendable, CaseIterable {
    case video, audio, text, component, graphic, overlay
    /// A colour grade over what is under it (`ColorGradeLayer.swift`): the
    /// compositing mock's V4, with its sliders icon and its own bar.
    case grade
}

extension Layer {
    /// The kind of track this layer's row is on the timeline.
    ///
    /// A recording stays video even while it still carries its own sound: the
    /// picture is what it is, and its sound is drawn inside its clip.
    public var timelineTrackKind: TimelineTrackKind {
        if instanceOf != nil { return .component }
        if isColorGrade { return .grade }
        if movie != nil { return .video }
        if let merged { return merged.isSoundOnly ? .audio : .video }
        switch content {
        case .sound: return .audio
        case .text: return .text
        // A title built from a preset is words, however many layers draw it.
        case .group(let group) where group.titleRecipe != nil: return .text
        // A picture with no time of its own is the one the motion is drawn
        // over, not one laid over the video.
        case .image: return time == nil ? .overlay : .graphic
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

    /// Where the gridlines fall across `stretch`, at the step this window's
    /// own numbers take (`secondTicks`): a lane that paints its clips draws
    /// them on the same canvas, which covers the drawn stretch either side of
    /// the window and is slid, not drawn again, by a scroll.
    public func secondTickMS(across stretch: ClosedRange<Double>) -> [Double] {
        let step = Self.secondStep(for: spanMS)
        var values: [Double] = []
        var ms = (stretch.lowerBound / step).rounded(.down) * step
        if ms < stretch.lowerBound - 0.001 { ms += step }
        while ms <= stretch.upperBound + 0.001 {
            values.append(ms)
            ms += step
        }
        return values
    }

    /// The numbers along the ruler the way View > Timecode asks: in seconds
    /// as `secondTicks` reads them, or in timecode, each line on a whole
    /// frame and labelled with that frame (`00:00:04:12`), so the ruler and
    /// the transport name the same frame at every zoom.
    public func ticks(display: VideoTimeDisplay) -> [Tick] {
        guard display.isTimecode else { return secondTicks }
        return frameTickMS(across: startMS...(startMS + spanMS)).map {
            Tick(ms: $0, label: VideoTimecode.moment(Int($0)))
        }
    }

    /// Where the gridlines fall across `stretch` at the step the ruler's own
    /// numbers take for `display` (`secondTickMS(across:)`).
    public func tickMS(across stretch: ClosedRange<Double>, display: VideoTimeDisplay) -> [Double] {
        display.isTimecode ? frameTickMS(across: stretch) : secondTickMS(across: stretch)
    }

    /// Whole frames, on a step an editor counts in: 1, 2, 3, 5, 10 and 15
    /// frames, then whole seconds as `secondStep` climbs them. Fewer across
    /// the width than seconds, because `00:00:04:12` is a longer word than
    /// `4.4s`.
    private func frameTickMS(across stretch: ClosedRange<Double>) -> [Double] {
        let fps = Double(VideoTimecode.framesPerSecond)
        let target = spanMS / 5 * fps / 1000
        let ladder: [Double] = [1, 2, 3, 5, 10, 15] + [1, 2, 3, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600].map { $0 * fps }
        let step = ladder.first { $0 >= target } ?? 3600 * fps
        var frame = (Double(MovieRef.gridFrame(atMS: Int(stretch.lowerBound.rounded(.down)))) / step).rounded(.down) * step
        var values: [Double] = []
        while true {
            let ms = Double(MovieRef.gridMS(ofFrame: Int(frame)))
            if ms > stretch.upperBound + 0.001 { break }
            if ms >= stretch.lowerBound - 0.001 { values.append(ms) }
            frame += step
        }
        return values
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
