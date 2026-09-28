import Foundation

/// Which stretches of a video the Export sheet writes to find out what the
/// whole MP4 will weigh, and how what they weigh is counted up.
///
/// **Why a budget is not enough.** The export asks the encoder for a number of
/// bits per second (`VideoExportRecipe`), and on ordinary screen material the
/// file lands at or under it. On a page of fine text scrolling past it does
/// not: the system's H.264 encoder has a floor it will not go under for a
/// picture that is new detail every frame, and at 900 pixels a second Small
/// came out at 1.3 times its budget however little it was asked for
/// (constant bit rate at a tenth of the budget included, measured 2026-09-28).
/// Nothing about the recording on disk says in advance which recordings are
/// like that: two sources written at High came out 1.27 and 1.32 MB, and Small
/// of them landed at 0.96 and 1.64 times its budget. Only writing some of it
/// tells, so the sheet does.
///
/// **Two second stretches on two second steps** from the start of the file,
/// because that is where the export puts a key frame. A stretch is then one
/// whole group of pictures of the real file, costing what that group costs
/// there, rather than paying for a key frame the real file does not have.
public enum VideoExportSample {

    /// How long each stretch runs: the export's key frame interval.
    public static let stretchMS = 2000

    /// How many stretches a long video is weighed from. Twelve seconds of
    /// writing in all, which is a few seconds of work on a document and well
    /// under one on a recording, spread across it so a busy middle is seen.
    public static let stretchCount = 6

    /// The stretches of `span` to write, in order, never overlapping. A span
    /// no longer than all of them together is written whole.
    public static func stretches(of span: Range<Int>) -> [Range<Int>] {
        let length = span.count
        guard length > 0 else { return [] }
        guard length > stretchMS * stretchCount else { return [span] }
        let steps = length / stretchMS
        var starts: [Int] = []
        for index in 0..<stretchCount {
            // The step nearest the middle of each of `stretchCount` equal
            // parts, so the first and last reach into the ends of the video.
            let middle = Double(length) * (Double(index) + 0.5) / Double(stretchCount)
            let step = min(max(0, Int(middle / Double(stretchMS))), steps - 1)
            if starts.last != step { starts.append(step) }
        }
        return starts.map { step in
            let start = span.lowerBound + step * stretchMS
            return start..<min(start + stretchMS, span.upperBound)
        }
    }

    /// The stretches of `span` in the order they are written, one after
    /// another into one file, and where in that file the counting starts.
    ///
    /// **A long video's stretches follow a warm-up.** The encoder spends more
    /// at the start of a file than anywhere after it while it learns the
    /// picture: in a 24 second export of Small the first two seconds came to
    /// 274,665 bytes and every two seconds after them to 170,000 to 200,000,
    /// and the same two second stretch written as a file of its own came to
    /// 277,000 wherever it was taken from. Stretches written that way weighed
    /// the file at 1.42 times what landed. So a long video's first stretch is
    /// written twice, and only what follows the first copy is counted. A short
    /// video is written whole, warm-up and all, exactly as the export will
    /// write it, and all of it counts.
    public static func writingOrder(of span: Range<Int>) -> (stretches: [Range<Int>],
                                                             countedFromMS: Int) {
        let stretches = stretches(of: span)
        guard stretches != [span], let first = stretches.first else {
            return (stretches, 0)
        }
        return ([first] + stretches, first.count)
    }

    /// How far over its budget a picture may land before the encoder is held
    /// to it: not at all. A picture that fits is left alone, and one that would
    /// spend more than it was allowed is held. A quarter's grace was tried
    /// first, and left Standard of text scrolling at 300 pixels a second
    /// unheld at 1.20 times its budget on a quiet machine, which the whole
    /// test suite running beside it pushed to 1.57; held, it lands at 0.92
    /// whatever else is running.
    public static let holdAbove = 1.0

    /// Whether the encoder should be held to its budget for a picture whose
    /// stretches, written without holding it, come to `pictureBytes` for the
    /// whole length.
    ///
    /// **Only where it would overshoot.** Holding the system's H.264 encoder
    /// to a rate changes how it spends everywhere, not just where it would go
    /// over: a five minute talk at 1080p, a twentieth of its High budget, came
    /// out 43 per cent smaller with any hold of twice its budget a second or
    /// less (2.12 MB a minute to 1.21 MB, measured 2026-09-28). That is a
    /// softer picture bought for nothing. So an easy recording is written
    /// exactly as before, and only one that would land over its budget
    /// (`holdAbove`) is held.
    public static func holdsToBudget(pictureBytes: Int, budgetBytes: Int) -> Bool {
        guard budgetBytes > 0 else { return false }
        return Double(pictureBytes) > Double(budgetBytes) * holdAbove
    }

    /// What the whole file will weigh: the stretches' pictures scaled up to
    /// the whole length, and the sound on top. The stretches are written
    /// without sound, because the sound costs the same whatever the picture
    /// does: it is written whole, the way the export writes it, and what it
    /// weighed is added as it is. A flat allowance for it was tried first and
    /// said 117 KB for a four second recording that landed at 63 KB: the
    /// system's m4a encoder writes far under any fixed rate on quiet sound.
    /// Zero when no picture was written, which is no answer rather than a
    /// file that weighs nothing.
    public static func estimate(pictureBytes: Int, sampledMS: Int, spanMS: Int,
                                soundBytes: Int = 0) -> Int {
        guard pictureBytes > 0, sampledMS > 0, spanMS > 0 else { return 0 }
        let picture = Double(pictureBytes) * Double(spanMS) / Double(sampledMS)
        return Int(picture.rounded()) + max(0, soundBytes)
    }
}
