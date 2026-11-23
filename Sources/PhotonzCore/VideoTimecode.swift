import Foundation

// Time on a video, read in frames where an editor expects frames.
//
// Premiere parks its playhead at 00:00:04:12 and trims a transition to twelve
// frames; Photonz said 0:04 and 0.4s, so an editor could not land on a frame
// they could name. Seconds stay the default (settled 2026-10-20) and View >
// Timecode reads every readout in hours, minutes, seconds and frames.
//
// The frames are the timeline's own: thirty a second, the grid every clip
// asks for its pictures on and every movie is written at
// (`MovieRef.framesPerSecond`, `DocumentVideoExport.movieFPS`). So the frame
// a readout names is the frame the canvas draws and the export writes.

/// How a video's time is read out: in seconds, as it always was, or in
/// timecode.
public enum VideoTimeDisplay: String, Codable, Sendable, CaseIterable {
    case seconds
    case timecode

    public static let defaultValue: VideoTimeDisplay = .seconds

    public var isTimecode: Bool { self == .timecode }

    /// Where the playhead is, the way the transport says it: `0:04`, or
    /// `00:00:04:12` in timecode.
    public func moment(_ ms: Int) -> String {
        switch self {
        case .seconds: VideoTimecode.clock(ms)
        case .timecode: VideoTimecode.moment(ms)
        }
    }

    /// How long something lasts, the way a panel row says it: `0.4s`, or
    /// `00:00:00:12` in timecode.
    public func length(_ ms: Int) -> String {
        switch self {
        case .seconds: String(format: "%.1fs", Double(ms) / 1000)
        case .timecode: VideoTimecode.length(ms)
        }
    }

    /// How long the whole thing is, the way the transport's end says it:
    /// whole seconds rounded down, or the frames it lasts.
    public func duration(_ ms: Int) -> String {
        switch self {
        case .seconds: VideoTimecode.clock(ms)
        case .timecode: VideoTimecode.length(ms)
        }
    }
}

/// Timecode at the timeline's thirty frames a second: `HH:MM:SS:FF`.
public enum VideoTimecode {

    public static let framesPerSecond = MovieRef.framesPerSecond

    /// The frame a moment is in, in timecode: 4.4 seconds is `00:00:04:12`.
    /// Inside a frame is that frame, never the next, so the playhead reads
    /// the frame the canvas is drawing.
    public static func moment(_ ms: Int) -> String {
        format(frames: MovieRef.gridFrame(atMS: max(0, ms)))
    }

    /// The whole frames a length lasts, to the nearest frame.
    public static func frames(inLengthMS ms: Int) -> Int {
        Int((Double(max(0, ms)) * Double(framesPerSecond) / 1000).rounded())
    }

    /// The milliseconds `frames` whole frames last: the first moment of that
    /// frame on the grid, so it reads back as the same number of frames.
    public static func lengthMS(ofFrames frames: Int) -> Int {
        MovieRef.gridMS(ofFrame: max(0, frames))
    }

    /// A length moved to the nearest whole frame.
    public static func wholeFrames(_ ms: Int) -> Int {
        lengthMS(ofFrames: frames(inLengthMS: ms))
    }

    /// A length in timecode: twelve frames is `00:00:00:12`.
    public static func length(_ ms: Int) -> String {
        format(frames: frames(inLengthMS: ms))
    }

    /// `HH:MM:SS:FF` for a count of frames.
    public static func format(frames: Int) -> String {
        let total = max(0, frames)
        let frame = total % framesPerSecond
        let seconds = total / framesPerSecond
        return String(format: "%02d:%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60, frame)
    }

    /// `0:04`, or `1:02:11` once there are hours: whole seconds rounded down,
    /// the way every transport in the world says it.
    public static func clock(_ ms: Int) -> String {
        let total = max(0, ms) / 1000
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// A length typed in timecode, in milliseconds on whole frames, or nil
    /// where it is not one.
    ///
    /// Four parts (`00:00:00:12`) are always timecode. With
    /// `bareNumberIsFrames` (timecode is on) a bare number is frames and
    /// shorter forms read from the right the way Premiere's field does:
    /// `4:12` is four seconds and twelve frames, `1:00:00` a minute. A unit
    /// (`12f`, `2s`) is not timecode and is left to the caller.
    public static func parseLength(_ text: String, bareNumberIsFrames: Bool = false) -> Int? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        let parts = typed.split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4 || (bareNumberIsFrames && parts.count <= 4) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCIIDigit), let value = Int(part) else { return nil }
            numbers.append(value)
        }
        // Right-aligned: frames last, then seconds, minutes, hours.
        let fields = Array(repeating: 0, count: 4 - numbers.count) + numbers
        let (hours, minutes, seconds, frames) = (fields[0], fields[1], fields[2], fields[3])
        // A bare number is a count of frames, however many; a frame field
        // beside seconds stops at the last frame of a second.
        if numbers.count > 1 {
            guard frames < framesPerSecond, seconds < 60, minutes < 60 else { return nil }
        }
        let total = ((hours * 60 + minutes) * 60 + seconds) * framesPerSecond + frames
        return lengthMS(ofFrames: total)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
