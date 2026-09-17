import Foundation

/// How much of a lossy picture format's quality an export keeps, and what is
/// worth saying about that number.
///
/// This lives here rather than beside the encoder because none of it needs a
/// pixel: it is a preference with rules. Which formats have a quality at all, a
/// floor and a step for the slider, a plain word for a percentage, one
/// remembered answer per format, and how to say a file size out loud.
///
/// The number of bytes itself is never guessed here. There is no formula worth
/// trusting across pictures, so the size the Export sheet shows comes from
/// actually encoding the picture (`ExportSizer`); this only knows how to say it.
public enum ExportQuality {

    /// The formats that throw pixels away, by the name the codec calls them.
    ///
    /// A positive list on purpose: a format nobody has taught this about gets
    /// no control rather than a control that does nothing to it.
    public static let lossyFormats: Set<String> = ["jpeg", "heic", "webp"]

    /// The formats where the very top of the slider throws nothing away at all.
    ///
    /// WebP alone: it is two encoders in one file format, and asking for all of
    /// the picture asks for the lossless one. That is what lets the top of the
    /// slider mean lossless without Export growing a second control, and it is
    /// the setting a screenshot of flat panels usually wants, because the
    /// lossless encoder beats both PNG and lossy WebP on that kind of picture.
    public static let losslessAtFullQuality: Set<String> = ["webp"]

    /// The lowest quality the slider can reach, as a percentage.
    ///
    /// Not zero, on purpose. Below about thirty a JPEG of a screenshot breaks
    /// the words in it into blocks, and somebody weighing "sharp" against
    /// "small" does not want to land there by accident on the way past. The
    /// file is already tiny by thirty, so the range underneath buys almost
    /// nothing and costs the picture.
    public static let lowest = 30

    public static let highest = 100

    /// What the slider moves in. Coarse enough to land on a round number,
    /// fine enough to tune.
    public static let step = 5

    /// What a format is set to until somebody says otherwise: the quality every
    /// export already went out at, so a build with the control in it writes the
    /// same file as a build without it.
    public static let standard = 90

    /// Every quality the slider can stop on, lowest first.
    public static let stops: [Int] = Array(stride(from: lowest, through: highest, by: step))

    /// Whether this format has a quality to choose at all.
    public static func applies(toFormat id: String) -> Bool {
        lossyFormats.contains(id)
    }

    /// The nearest stop to `percent`, and never outside the range.
    public static func snapped(_ percent: Int) -> Int {
        let bounded = Swift.min(Swift.max(percent, lowest), highest)
        let steps = Int((Double(bounded - lowest) / Double(step)).rounded())
        return Swift.min(lowest + steps * step, highest)
    }

    /// Whether this answer keeps every pixel: the top of the slider, on a
    /// format whose top is lossless.
    public static func isLossless(atPercent percent: Int, format id: String) -> Bool {
        losslessAtFullQuality.contains(id) && snapped(percent) >= highest
    }

    /// The 0 to 1 the encoder wants.
    public static func fraction(_ percent: Int) -> Double {
        Double(snapped(percent)) / 100
    }

    /// One word for what a percentage looks like, with the one thing a format
    /// can add to it: on WebP the top of the slider is not "Best", it is
    /// lossless, and saying so out loud is what makes that setting findable.
    public static func word(for percent: Int, format id: String) -> String {
        isLossless(atPercent: percent, format: id) ? "Lossless" : word(for: percent)
    }

    /// One word for what a percentage looks like.
    ///
    /// A percentage says how much is kept. It does not say what that looks
    /// like, and the honest answer to that is a preview the sheet has no room
    /// for, so this is the glance: somebody who wants "good enough" can find it
    /// without knowing that seventy is good enough.
    public static func word(for percent: Int) -> String {
        switch percent {
        case 95...: "Best"
        case 80..<95: "High"
        case 60..<80: "Good"
        case 45..<60: "Low"
        default: "Rough"
        }
    }

    /// Where this format's last answer is kept. One per format, because eighty
    /// for a JPEG and eighty for a HEIC are not the same picture.
    public static func storageKey(format id: String) -> String {
        "export.quality.\(id)"
    }

    /// The word for a format with no quality to choose because it throws
    /// nothing away. PNG is the case this exists for: no slider, so the line
    /// under the format has to say what the missing slider would have meant,
    /// or the absence reads as a control that failed to arrive.
    public static let losslessWord = "Lossless"

    /// The one line under the format: what the answer is called, and what the
    /// file weighs there.
    ///
    /// Every picture format says it, in the same place and the same words, so
    /// PNG and JPEG answer "how big will this be" the same way. A format with
    /// a quality is named by its quality; one without is named lossless.
    ///
    /// `bytes` is nil until the first weigh lands, and `weighed` is what tells
    /// "not yet" from "never": a picture that cannot be encoded at all must
    /// stop promising a number rather than say it is working on one forever.
    public static func note(forFormat id: String, percent: Int,
                            bytes: Int?, weighed: Bool) -> String {
        let name = applies(toFormat: id) ? word(for: percent, format: id) : losslessWord
        return note(forName: name, bytes: bytes, weighed: weighed)
    }

    /// The same line for something named by what it is rather than by a
    /// quality: a file made of shapes.
    ///
    /// SVG has no quality to choose and no pixels to throw away, so nothing on
    /// the left of the line comes from a percentage — it is simply what the
    /// file is, "SVG" or "Animated SVG". Everything on the right is the same,
    /// which is the point: the one format people hand to somebody else answers
    /// "how big is it" in the same words and the same place as the ones that
    /// are only ever looked at.
    public static func note(forName name: String, bytes: Int?, weighed: Bool) -> String {
        if let bytes { return "\(name) · \(fileSize(bytes: bytes))" }
        return weighed ? name : "\(name) · working out the size"
    }

    /// What a file of this many bytes weighs, said the way a person would say
    /// it: never more than three significant figures, and a decimal only where
    /// dropping it would lose something.
    public static func fileSize(bytes: Int) -> String {
        guard bytes > 0 else { return "0 bytes" }
        if bytes < 1024 { return "\(bytes) bytes" }
        let kilobytes = Double(bytes) / 1024
        if kilobytes < 1024 { return rounded(kilobytes, unit: "KB") }
        return rounded(kilobytes / 1024, unit: "MB")
    }

    private static func rounded(_ value: Double, unit: String) -> String {
        value < 10
            ? String(format: "%.1f %@", value, unit)
            : String(format: "%.0f %@", value, unit)
    }
}
