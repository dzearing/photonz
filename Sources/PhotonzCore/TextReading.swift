import CoreGraphics
import Foundation

/// Turning a separated run of text back into WORDS you can retype.
///
/// This is the deciding half, and it is pure: no Vision, no CoreText, no
/// pixels. `PhotonzRender/TextReader.swift` is the half that reads the
/// characters off the screen and sets them again in a candidate face; this is
/// the part that says how well the two agree and whether that is good enough
/// to hand a person words instead of a picture.
///
/// The reason it is split this way is the thing the whole feature turns on.
/// Reading the characters is the easy half and macOS does it well. Matching the
/// FACE is the half that decides whether this is delightful or uncanny, and
/// there is no font identification API on any platform. So the app does the
/// only honest thing available: it sets the words it read in each of the few
/// faces a Mac screenshot actually contains, lays each result over the original
/// ink, and keeps the best — and where even the best does not agree closely
/// enough, it REFUSES and the run stays a picture. A retyped label in the wrong
/// face is the kind of thing that makes a person distrust the whole feature, so
/// refusing has to be a real, common, unembarrassing outcome.
///
/// Full design: `docs/design/separate-into-layers.md`.
public enum TextReading {

    // MARK: - Ink

    /// How much of each pixel is ink, 0…1, row-major, top-left origin.
    ///
    /// One mask is built from the picture (a separated run's own alpha, or the
    /// contrast of a plain crop against what it sits on); the other from the
    /// same words set in a candidate face. Comparing COVERAGE rather than
    /// colour is what lets white words on blue and black words on grey be
    /// scored by the same number: both are a shape, and the shape is the thing
    /// a face either matches or does not.
    public struct Mask: Sendable, Equatable {
        public let width: Int
        public let height: Int
        /// `width * height` values in 0…1.
        public let coverage: [Double]

        public init(width: Int, height: Int, coverage: [Double]) {
            precondition(coverage.count == max(0, width) * max(0, height))
            self.width = max(0, width)
            self.height = max(0, height)
            self.coverage = coverage
        }

        public subscript(x: Int, y: Int) -> Double {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            return coverage[y * width + x]
        }

        /// How much ink there is in total, in pixels' worth.
        public var inkTotal: Double { coverage.reduce(0, +) }

        /// The tight box round every pixel carrying at least `floor` ink, in
        /// pixels, top-left origin. Nil when there is no ink at all.
        ///
        /// The floor exists because a rendered glyph's antialiased rim trails
        /// off to nothing, and a box drawn round the last pixel above zero is a
        /// box round the rim rather than round the letters. A tenth is far
        /// enough down to keep every real stroke and far enough up to ignore
        /// the haze.
        public func inkBounds(floor: Double = 0.1) -> CGRect? {
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                let row = y * width
                for x in 0..<width where coverage[row + x] >= floor {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }

    /// How far apart two masks may be nudged, in pixels, while looking for the
    /// lay that agrees best.
    ///
    /// The two are brought together by their ink boxes first, so this is only
    /// the slack a rounded point size and a different rasterizer's subpixel
    /// placement leave behind. Two pixels each way covers that; more would let
    /// a genuinely wrong face slide until something lined up.
    public static let alignmentSlack = 2

    /// How closely two masks agree once laid on top of each other, 0…1.
    ///
    /// This is the ONE number that decides whether retyped words pass as the
    /// original. It is the soft Jaccard — the ink they share over the ink
    /// either of them has — which is strict in exactly the way this needs:
    /// a face whose letters are the right height but the wrong width loses
    /// area at both ends of every glyph and cannot score its way back.
    ///
    /// The two are laid ink box on ink box and then nudged around within
    /// `alignmentSlack`, keeping the best, because a point size that had to be
    /// rounded to a tenth and a rasterizer that places subpixels differently
    /// would otherwise be scored as a mismatch of the face.
    public static func agreement(_ a: Mask, _ b: Mask,
                                 slack: Int = alignmentSlack) -> Double {
        guard let inkA = a.inkBounds(), let inkB = b.inkBounds() else { return 0 }
        let baseX = Int(inkA.minX - inkB.minX)
        let baseY = Int(inkA.minY - inkB.minY)
        // Both totals are fixed, so only the SHARED ink changes as the two are
        // nudged about. max(x, y) is x + y - min(x, y), and outside the part
        // where the two overlap one of them is zero, so the ink either of them
        // has is the two totals less what they share. That turns the whole
        // score into one sum over the rectangle where they actually meet,
        // rather than a pass over both canvases for every position tried.
        let totalA = a.inkTotal, totalB = b.inkTotal
        guard totalA > 0, totalB > 0 else { return 0 }
        var best = 0.0
        a.coverage.withUnsafeBufferPointer { pa in
            b.coverage.withUnsafeBufferPointer { pb in
                for dy in (baseY - slack)...(baseY + slack) {
                    for dx in (baseX - slack)...(baseX + slack) {
                        let shared = Self.shared(pa, a.width, a.height,
                                                 pb, b.width, b.height, dx: dx, dy: dy)
                        let either = totalA + totalB - shared
                        if either > 0 { best = max(best, shared / either) }
                    }
                }
            }
        }
        return best
    }

    /// The ink two masks share with `b` shifted by (`dx`, `dy`) into `a`'s
    /// space: one sum over the rectangle where the two canvases overlap.
    private static func shared(_ a: UnsafeBufferPointer<Double>, _ aw: Int, _ ah: Int,
                               _ b: UnsafeBufferPointer<Double>, _ bw: Int, _ bh: Int,
                               dx: Int, dy: Int) -> Double {
        let x0 = max(0, dx), x1 = min(aw, bw + dx)
        let y0 = max(0, dy), y1 = min(ah, bh + dy)
        guard x1 > x0, y1 > y0 else { return 0 }
        var total = 0.0
        for y in y0..<y1 {
            let rowA = y * aw
            let rowB = (y - dy) * bw - dx
            for x in x0..<x1 {
                let va = a[rowA + x], vb = b[rowB + x]
                total += va < vb ? va : vb
            }
        }
        return total
    }

    // MARK: - Colour

    /// The colour of the ink, from samples taken where a stroke is solid.
    ///
    /// The median of each channel rather than the mean, so one stray pixel of
    /// something else caught inside the run — a cursor, a badge, the dot of a
    /// coloured bullet — cannot drag the whole label off its colour. Nil when
    /// there was nothing solid enough to sample, which is the run this feature
    /// refuses rather than guesses at.
    public static func inkColor(_ samples: [RGBA]) -> RGBA? {
        guard !samples.isEmpty else { return nil }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        return RGBA(r: median(samples.map(\.r)),
                    g: median(samples.map(\.g)),
                    b: median(samples.map(\.b)))
    }

    // MARK: - Faces

    /// One face to try the words in: a family the app can set, at one weight.
    public struct Face: Hashable, Sendable {
        public let fontName: String
        public let weight: TextWeight

        public init(fontName: String, weight: TextWeight) {
            self.fontName = fontName
            self.weight = weight
        }

        /// What the pill and the audit call it: "SF Pro Semibold".
        public var displayName: String {
            weight == .regular ? fontName : "\(fontName) \(weight.rawValue.capitalized)"
        }
    }

    /// How one candidate face did.
    public struct Scored: Sendable, Hashable {
        public let face: Face
        /// The point size at which this face's ink came out the height the
        /// picture's ink is, in the same units the mask was measured in.
        public let fontSize: CGFloat
        /// `agreement` against the original.
        public let agreement: Double

        public init(face: Face, fontSize: CGFloat, agreement: Double) {
            self.face = face
            self.fontSize = fontSize
            self.agreement = agreement
        }
    }

    /// How closely the best face has to agree with the picture before the app
    /// will hand a person words instead of pixels.
    ///
    /// Measured, not chosen. On the settings-pane fixture the right face scores
    /// 0.70 to 0.80 on every one of the nine runs; the same words set in a
    /// deliberately wrong face (a serif for a sans, a monospace for a
    /// proportional) land between 0.35 and 0.55. The bar sits in the empty
    /// middle of that, near the bottom of it, because the cost of the two
    /// mistakes is not symmetric: refusing a run leaves a person exactly where
    /// they were, and accepting a wrong one puts a label on their screenshot in
    /// a face that is not the one in it.
    public static let agreementBar = 0.62

    /// And how closely what actually LANDS has to agree, once that face is set
    /// at the size this document needs.
    ///
    /// Lower than `agreementBar` on purpose, and the reason is a real limit
    /// rather than a fudge. A Retina capture's document is in the capture's own
    /// device pixels, so a label set at 13 points in the picture has to be set
    /// at 26 in the document to cover the same space — and the system font is
    /// not one shape at both sizes: it tracks its letters closer together as it
    /// gets bigger. The words come back a fraction of a pixel per letter tight,
    /// which is not something an eye finds and is something an overlap score
    /// punishes hard, because half a pixel of displacement costs half of every
    /// stroke's width. So the face is judged at the size it was set at, where
    /// the question is fair, and this second number only has to catch a result
    /// that has genuinely landed somewhere else.
    public static let landedBar = 0.55

    /// How far ahead of the next family the winner has to be before the app
    /// will say it IDENTIFIED the face rather than fell back on the closest
    /// thing.
    ///
    /// Two weights of one family are not two answers, so this is measured
    /// between FAMILIES. Where nothing is clearly ahead the app still sets the
    /// words in the best it found, and the audit says so — the point of the
    /// distinction is honesty about which happened, not a second refusal.
    public static let distinctMargin = 0.04

    /// The family the app falls back on when the picture does not say which it
    /// is.
    ///
    /// Not an arbitrary default. At label size two grotesques a few percent
    /// apart are genuinely hard to tell apart from a screenshot, and when two
    /// of them are within `distinctMargin` the honest answer is "it is one of
    /// these" — at which point the system font is the one to reach for, because
    /// nearly every screenshot of a Mac, an iPhone or a modern web page is set
    /// in it or in something drawn to look like it. It also keeps a PAGE
    /// consistent: six row labels of one settings pane that each scored a hair
    /// differently all come back in the same face rather than three in one and
    /// three in another, which is the thing a person would actually notice.
    public static let fallbackFamily = "SF Pro"

    /// Which of the two things happened to the face.
    public enum Provenance: String, Sendable {
        /// One family agreed with the picture clearly better than any other.
        case matched
        /// Several were within `distinctMargin` of each other, so the best of
        /// them was used and is a stated fallback rather than an answer.
        case fallback
    }

    /// Words the app is willing to hand back, and how it is setting them.
    public struct Reading: Sendable, Hashable {
        public let string: String
        public let face: Face
        public let fontSize: CGFloat
        public let colorHex: String
        public let agreement: Double
        public let provenance: Provenance

        public init(string: String, face: Face, fontSize: CGFloat, colorHex: String,
                    agreement: Double, provenance: Provenance) {
            self.string = string
            self.face = face
            self.fontSize = fontSize
            self.colorHex = colorHex
            self.agreement = agreement
            self.provenance = provenance
        }
    }

    /// Why the run stayed a picture. Every one of these is a sentence the pill
    /// says out loud: a refusal a person cannot account for reads as the app
    /// being broken.
    public enum Refusal: String, Sendable, Hashable, Error {
        /// Nothing here is a picture to read.
        case notAPicture
        /// The picture was read and holds no words.
        case noWords
        /// More than one run of text. This one is a signpost rather than a
        /// dead end: Separate into Layers first, then turn a single run into
        /// words.
        case moreThanOneRun
        /// The ink barely differs from what it sits on, so which is which is a
        /// guess. The same floor the cut itself refuses at.
        case tooFaint
        /// The words were read perfectly well and no face the app can set
        /// agrees with the picture closely enough to pass as the original.
        /// The expected outcome on anything that is not a Mac screenshot, and
        /// the reason this feature is trustworthy.
        case noFaceMatches

        /// What the pill says. Every one of these is something a person can
        /// act on, which is the whole point of saying it out loud: two are
        /// things to go and do, one is a fact about the picture they are
        /// looking at, and only the last is the app declining. A refusal
        /// nobody can account for reads as the app being broken.
        public var sentence: String {
            switch self {
            case .notAPicture: return "Only a picture can be read into words"
            case .noWords: return "No words could be read here"
            case .moreThanOneRun:
                return "More than one run of text here. Separate into Layers first, "
                    + "then turn one run into words"
            case .tooFaint: return "Too faint to tell the words from what they sit on"
            case .noFaceMatches:
                return "No face here is close enough to the one in the picture, "
                    + "so it stays a picture"
            }
        }
    }

    public enum Outcome: Sendable, Hashable {
        case read(Reading)
        case refused(Refusal)

        public var reading: Reading? {
            if case .read(let reading) = self { return reading }
            return nil
        }

        public var refusal: Refusal? {
            if case .refused(let refusal) = self { return refusal }
            return nil
        }
    }

    /// The verdict: the best face, whether it is an answer or a fallback, and
    /// whether it clears the bar at all.
    public static func decide(string: String, scores: [Scored], color: RGBA?) -> Outcome {
        let string = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return .refused(.noWords) }
        guard let color else { return .refused(.tooFaint) }
        guard let best = scores.max(by: { $0.agreement < $1.agreement }),
              best.agreement >= agreementBar
        else { return .refused(.noFaceMatches) }
        // Between FAMILIES, not between weights: SF Pro Medium beating SF Pro
        // Semibold by a hair is one family answering, not two candidates
        // tying. A tie between families is the case where the picture does not
        // say which it is, and saying so — and then reaching for the system
        // font — is the honest thing.
        let tied = scores.filter { best.agreement - $0.agreement < distinctMargin }
        let families = Set(tied.map(\.face.fontName))
        let provenance: Provenance = families.count > 1 ? .fallback : .matched
        let chosen = provenance == .fallback
            ? (tied.filter { $0.face.fontName == fallbackFamily }
                   .max { $0.agreement < $1.agreement } ?? best)
            : best
        return .read(Reading(string: string, face: chosen.face, fontSize: chosen.fontSize,
                             colorHex: color.hexString, agreement: chosen.agreement,
                             provenance: provenance))
    }

    // MARK: - Naming

    /// What a run of words is called: the words themselves, which is the whole
    /// visible reward for having asked. A run long enough to push every other
    /// row out of the layers list is cut at a word boundary and ended with an
    /// ellipsis, the way every other long name in the app is.
    ///
    /// One rule, in one place: this is the same shortening the layers list
    /// does when it reads a piece of text's own words off it
    /// (`LayerNaming.name(fromWords:)`), so the pill that says what landed and
    /// the row it landed in cannot say different things.
    public static var nameLimit: Int { LayerNaming.wordsLimit }

    public static func layerName(for string: String) -> String {
        LayerNaming.name(fromWords: string)
    }
}
