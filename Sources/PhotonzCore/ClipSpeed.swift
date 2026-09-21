import Foundation

// What a speed MEANS (`docs/design/mocks/pages/video-speed.html`,
// `next-speed-a-stretch`).
//
// `ClipPieces.swift` owns the arithmetic: a speed keeps the frames a piece
// reads and changes how long they take. This owns the three things a person
// needs told about that arithmetic before they will trust it:
//
// 1. **Which speeds are on offer**, and what each of them is called.
// 2. **What happens to the sound**, which is the question everybody gets wrong.
// 3. **What it does about frames**, because "slow motion" makes people expect
//    smoothing that is not there.
//
// Every sentence a surface says about a speed is made here rather than typed
// into a view, so the words are unit tested and there is one of each.

/// What the sound of a retimed piece does.
///
/// **The decision, stated once:** the sound goes WITH the picture inside a band
/// around the speed it was recorded at, and stops outside it.
///
/// - Between half speed and double, the sound plays, pitched with the picture.
///   It is the honest thing: the sound you recorded, running at the speed the
///   picture is running, and at these speeds it is still a voice.
/// - Outside that band it is silent. Past double, a voice is a squeal; below
///   half, it is a drone. Neither is anything anybody wants under a four second
///   fast forward of an install bar, and both are WORSE than silence because
///   they sound like the app broke.
/// - Nothing corrects the pitch. A pitch correction at 4x turns an unlistenable
///   chipmunk into an unlistenable robot, and it is not free: it is a thing to
///   offer beside the rest of a clip's sound if anybody asks for it.
///
/// The one rule this is built to avoid is the one the task named: **dropping
/// the sound silently**. It is never dropped quietly. The panel says which of
/// these is happening, in words, for the speed you picked, and a muted stretch
/// draws no waveform on its bar, so the timeline says it too.
public enum ClipSpeedSound: Hashable, Sendable {
    /// Playing at the speed it was recorded at.
    case asRecorded
    /// Playing, and higher than it was recorded.
    case pitchedUp
    /// Playing, and lower than it was recorded.
    case pitchedDown
    /// Too fast to be sound any more.
    case silentTooFast
    /// Too slow to be sound any more.
    case silentTooSlow
    /// A held frame, which reads no stretch of the recording at all.
    case silentHeld

    /// Whether anything is heard under this piece.
    public var plays: Bool {
        switch self {
        case .asRecorded, .pitchedUp, .pitchedDown: true
        case .silentTooFast, .silentTooSlow, .silentHeld: false
        }
    }

    /// The whole answer in one sentence, for the panel.
    public var sentence: String {
        switch self {
        case .asRecorded:
            "Sound plays as recorded."
        case .pitchedUp:
            "Sound plays with the picture, so it is higher than you recorded it."
        case .pitchedDown:
            "Sound plays with the picture, so it is lower than you recorded it."
        case .silentTooFast:
            "Silent. Past \(ClipSpeed.loudestAudiblePercent / 100)x the sound is a squeal rather "
            + "than a voice, so this stretch plays with none."
        case .silentTooSlow:
            "Silent. Below half speed the sound is a drone rather than a voice, so this stretch "
            + "plays with none."
        case .silentHeld:
            "Silent. This is one frame held, and one frame has no sound under it."
        }
    }
}

/// What a retimed piece does about FRAMES.
///
/// It samples and it never invents. There is no blending, no optical flow and
/// no made up frame anywhere in the path: a moment of the timeline is turned
/// into a moment of the recording and the frame under it is decoded
/// (`ClipPiece.sourceMS(atOffsetMS:)`, `MovieRef.frameRef(atSourceMS:)`).
///
/// Which means speeding up is cheap and looks right, and slowing down shows
/// each recorded frame more than once rather than inventing what was between
/// them. Saying that out loud is the point of this type.
public enum ClipSpeedFrames: Hashable, Sendable {
    /// Faster than recorded: frames are skipped.
    case skipping(oneInEvery: Double)
    /// Slower than recorded: frames are shown more than once.
    case holding(eachFor: Double)
    /// At the speed it was recorded.
    case everyFrameOnce
    /// A held frame.
    case oneFrame
}

/// Everything a surface needs to say about one retimed piece, worked out once.
public struct ClipSpeedReading: Hashable, Sendable {

    public let speedPercent: Int
    /// How long the piece runs for on the timeline.
    public let lengthMS: Int
    /// How much of the recording that is. Nought for a held frame.
    public let sourceLengthMS: Int
    public let isHeld: Bool

    public init(_ piece: ClipPiece) {
        self.speedPercent = piece.speedPercent
        self.lengthMS = piece.lengthMS
        self.sourceLengthMS = piece.sourceLengthMS
        self.isHeld = piece.isHeld
    }

    /// What is being skipped or held.
    public var frames: ClipSpeedFrames {
        if isHeld { return .oneFrame }
        let speed = Double(speedPercent) / 100
        if speedPercent == ClipPiece.asRecordedPercent { return .everyFrameOnce }
        return speed > 1 ? .skipping(oneInEvery: speed) : .holding(eachFor: 1 / speed)
    }

    /// What the sound is doing.
    public var sound: ClipSpeedSound {
        isHeld ? .silentHeld : ClipSpeed.sound(atPercent: speedPercent)
    }

    /// How much recording fits in how much timeline, which is the whole of what
    /// a retime did, in the two numbers a person would check it by.
    public var lengthSentence: String {
        guard !isHeld else {
            return "One frame, on screen for \(ClipSpeed.seconds(lengthMS))."
        }
        return "\(ClipSpeed.seconds(sourceLengthMS)) of the recording in "
            + "\(ClipSpeed.seconds(lengthMS))."
    }

    /// What it did about frames, said plainly, including what it did NOT do.
    public var framesSentence: String {
        switch frames {
        case .oneFrame:
            "One frame of the recording, held."
        case .everyFrameOnce:
            "Every frame of the recording, once each."
        case .skipping(let every):
            "One frame in every \(ClipSpeed.ratio(every)) is shown. The rest are skipped, never "
            + "blended together."
        case .holding(let each):
            "Each frame of the recording is held for \(ClipSpeed.ratio(each)) of the frames on "
            + "screen. Nothing is made up in between them."
        }
    }
}

/// The speeds on offer, what they are called, and where the sound stops.
public enum ClipSpeed {

    /// The speeds a person can reach in one click.
    ///
    /// A short list rather than a number to type: retiming a stretch is a
    /// judgment you make by watching it, and the judgment is "slower" long
    /// before it is "sixty two percent".
    ///
    /// It runs to thirty times because that is the job this feature was asked
    /// for: **a two minute wait becomes four seconds.** Four and ten times are
    /// the ordinary fast forwards; thirty is for the stretch where nothing at
    /// all is happening, and nothing below it can do that job.
    public static let stops: [Int] = [25, 50, 100, 200, 400, 1000, 3000]

    /// The band inside which a retimed piece still plays its sound
    /// (`ClipSpeedSound`).
    public static let quietestAudiblePercent = 50
    public static let loudestAudiblePercent = 200

    /// Whether a piece at this speed is heard at all.
    public static func isAudible(percent: Int) -> Bool {
        percent >= quietestAudiblePercent && percent <= loudestAudiblePercent
    }

    /// What the sound does at a speed, for a piece that is not a held frame.
    public static func sound(atPercent percent: Int) -> ClipSpeedSound {
        if percent > loudestAudiblePercent { return .silentTooFast }
        if percent < quietestAudiblePercent { return .silentTooSlow }
        if percent > ClipPiece.asRecordedPercent { return .pitchedUp }
        if percent < ClipPiece.asRecordedPercent { return .pitchedDown }
        return .asRecorded
    }

    /// What a speed is called where it is offered. `Normal` rather than `100%`,
    /// because the one everybody picks is the one going back to how it was
    /// recorded and nobody thinks of that as a percentage.
    public static func title(_ percent: Int) -> String {
        switch percent {
        case ClipPiece.asRecordedPercent: return "Normal"
        case 50: return "Half Speed"
        case 25: return "Quarter Speed"
        case let p where p < 100: return "\(p)% Speed"
        default: return "\(ratio(Double(percent) / 100))x Speed"
        }
    }

    /// A multiple written the way somebody would say it: `4`, not `4.0`, and
    /// `2.5` where it really is a half.
    static func ratio(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    /// A length in seconds, said the way somebody would say it.
    static func seconds(_ ms: Int) -> String {
        guard ms >= 1000 else { return "\(ms) ms" }
        let value = Double(ms) / 1000
        return value == value.rounded()
            ? "\(Int(value))s"
            : String(format: "%.1fs", value)
    }
}
