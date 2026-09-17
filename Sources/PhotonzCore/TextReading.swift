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

    /// The family a whole capture is set in: the one the most of its runs came
    /// back in.
    ///
    /// This is the thing a single run cannot know and the page plainly does.
    /// Every screenshot anybody takes apart is set in one family, and the
    /// measurement says so — three real captures, one family each — so where
    /// one run of thirty-one disagrees with the other thirty, the run is wrong
    /// and the page is right. Asked per run, the app has no way to tell those
    /// apart: on this app's own window the four runs that came back in a family
    /// the window does not contain were its CONFIDENT verdict, scoring 0.72 to
    /// 0.81 while correct readings go down to 0.56.
    ///
    /// A tie goes to `fallbackFamily`, for the reason that constant exists: on
    /// a Mac screenshot the system font is the one to reach for when the
    /// picture does not say. Failing that the first by name, so a page read
    /// twice answers the same way twice.
    ///
    /// Nil when nothing read, which is a page with no vote to cast rather than
    /// a page set in nothing.
    public static func pageFamily(of readings: [Reading]) -> String? {
        pageFamily(ofFamilies: readings.map(\.face.fontName))
    }

    /// The same vote, counted off the families alone — for a caller that asked
    /// a handful of runs what family they are and nothing else about them.
    public static func pageFamily(ofFamilies families: [String]) -> String? {
        guard !families.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for family in families { counts[family, default: 0] += 1 }
        guard let most = counts.values.max() else { return nil }
        let leaders = counts.filter { $0.value == most }.keys.sorted()
        return leaders.contains(fallbackFamily) ? fallbackFamily : leaders.first
    }

    /// The verdict: the best face, whether it is an answer or a fallback, and
    /// whether it clears the bar at all.
    ///
    /// `family` is the family the run's own PAGE is set in, where that is
    /// known (`pageFamily`). Given one, the choice is made inside it and
    /// nowhere else: the words come back in the face the rest of the page is
    /// in, or — where that family cannot account for this run's ink at all —
    /// they do not come back and the run stays a picture. Both of those are
    /// better than a label set heavier than the identical label beside it,
    /// which is what a run deciding on its own produces on about one in eight
    /// of them. Nil is one run on its own, with no page to ask, and is
    /// unchanged.
    ///
    /// `weight` is the weight the page sets this run's KIND of label in, where
    /// the page has settled one (`pageWeights`). It narrows the choice the
    /// same way and for the same reason: two weights of one family are a few
    /// percent apart at label size, so a run deciding alone comes back Medium
    /// beside an identical label that came back Regular.
    public static func decide(string: String, scores: [Scored], color: RGBA?,
                              preferring family: String? = nil,
                              at weight: TextWeight? = nil) -> Outcome {
        let string = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return .refused(.noWords) }
        guard let color else { return .refused(.tooFaint) }
        var pool = family.map { name in scores.filter { $0.face.fontName == name } } ?? scores
        if let weight { pool = pool.filter { $0.face.weight == weight } }
        guard let best = pool.max(by: { $0.agreement < $1.agreement }),
              best.agreement >= agreementBar
        else { return .refused(.noFaceMatches) }
        // Between FAMILIES, not between weights: SF Pro Medium beating SF Pro
        // Semibold by a hair is one family answering, not two candidates
        // tying. A tie between families is the case where the picture does not
        // say which it is, and saying so — and then reaching for the system
        // font — is the honest thing.
        let tied = pool.filter { best.agreement - $0.agreement < distinctMargin }
        let families = Set(tied.map(\.face.fontName))
        var provenance: Provenance = families.count > 1 ? .fallback : .matched
        // A run set in the page's family when its own ink said something else
        // is the PAGE answering rather than the run, which is exactly what a
        // stated fallback means. Saying it out loud keeps the audit able to
        // count how often the vote had to overrule a run.
        let free = scores.max(by: { $0.agreement < $1.agreement })?.face
        if let family, free?.fontName != family { provenance = .fallback }
        if let weight, free?.weight != weight { provenance = .fallback }
        let chosen = families.count > 1
            ? (tied.filter { $0.face.fontName == fallbackFamily }
                   .max { $0.agreement < $1.agreement } ?? best)
            : best
        return .read(Reading(string: string, face: chosen.face, fontSize: chosen.fontSize,
                             colorHex: color.hexString, agreement: chosen.agreement,
                             provenance: provenance))
    }

    // MARK: - The weight a page sets one KIND of label in

    /// One run's say in what weight the labels like it are set in.
    ///
    /// The weight is the half of the face the family vote does not settle, and
    /// it wobbles for the same reason the family did: at label size two
    /// weights of one family are a few percent apart, so a run deciding alone
    /// comes back Medium beside an identical label that came back Regular.
    /// Measured on the settings-pane fixture, two of six row labels that are
    /// plainly one weight on screen come back Medium, and they come back
    /// CONFIDENT — 0.795 against Regular's 0.720, a lead wider than
    /// `distinctMargin` — so no bar and no provenance filter can tell them
    /// apart from a label that really is heavier.
    ///
    /// But a page is NOT one weight the way it is one family, so the vote
    /// cannot be the page's: a heading dragged down to the weight of its rows
    /// is a worse answer than the wobble. The vote is per KIND of label, and
    /// the only two things the app measured that say what kind a label is are
    /// how big it is and what colour its ink is. That is enough for the case
    /// this exists for: in this app's own Effects panel the section labels
    /// ("Corner Radius", "Border 1") are white and the rows under them
    /// ("Style", "Color") are grey, so the sections settle heavier than their
    /// rows rather than being flattened into them.
    public struct WeightBallot: Sendable, Hashable {
        /// The size the page's family fits this run's ink at, at its LIGHTEST
        /// weight.
        ///
        /// Weight-free on purpose. A heavier face reaches the same ink height
        /// at a smaller size, so a size measured off whichever weight happened
        /// to win would let the wobble decide who is in which cohort, which is
        /// the thing being fixed.
        public let size: CGFloat
        /// The colour of the ink.
        public let color: RGBA
        /// How well each weight of the page's family agreed with that ink.
        public let agreement: [TextWeight: Double]

        public init(size: CGFloat, color: RGBA, agreement: [TextWeight: Double]) {
            self.size = size
            self.color = color
            self.agreement = agreement
        }
    }

    /// How far apart two labels' sizes may be and still be labels of one kind.
    ///
    /// Measured. The six row labels of the settings pane fit between 12.85 and
    /// 13.17 points, a spread of 2.5 per cent, because which glyphs a run
    /// happens to contain moves its measured size about. The next kind of
    /// label up on the app's own panel sits four per cent away. Three is the
    /// gap between those two numbers.
    public static let weightCohortStep: CGFloat = 0.03

    /// And how far apart the smallest and the largest in one cohort may be,
    /// however small each step between them was.
    ///
    /// Without it, a page whose labels step up a little at a time — a row, a
    /// subhead, a head, a title — chains into one cohort and the title comes
    /// back in body weight.
    public static let weightCohortSpan: CGFloat = 0.08

    /// How far apart two labels' ink may be, per channel, and still be one
    /// colour. Ink colour is a median of sampled pixels, so one label reads
    /// #EAEAEB and the identical label beside it #E8E8E8.
    public static let weightCohortInkStep = 0.02

    /// And how far the lightest and darkest in one cohort may be, so a page
    /// with a ramp of greys on it does not chain into one.
    public static let weightCohortInkSpan = 0.05

    /// Which runs are labels of ONE KIND: indices into `ballots`, every run in
    /// exactly one cohort.
    ///
    /// Walked smallest first, each run joining the nearest cohort that has a
    /// member close to it in both size and ink and that stays inside
    /// `weightCohortSpan` with it added. Sorted rather than paired off so the
    /// answer does not depend on the order the runs were separated in: a page
    /// read twice settles the same way twice.
    public static func weightCohorts(of ballots: [WeightBallot]) -> [[Int]] {
        let order = ballots.indices.sorted {
            ballots[$0].size == ballots[$1].size ? $0 < $1 : ballots[$0].size < ballots[$1].size
        }
        var cohorts: [[WeightBallot]] = []
        var members: [[Int]] = []
        for index in order {
            let ballot = ballots[index]
            var joined = false
            // Nearest in size first: the walk is smallest first, so the last
            // cohort started is the one this run is closest to.
            for slot in cohorts.indices.reversed() where holds(cohorts[slot], ballot) {
                cohorts[slot].append(ballot)
                members[slot].append(index)
                joined = true
                break
            }
            if !joined {
                cohorts.append([ballot])
                members.append([index])
            }
        }
        return members.map { $0.sorted() }
    }

    /// Whether a cohort would still be one kind of label with this run in it.
    private static func holds(_ cohort: [WeightBallot], _ ballot: WeightBallot) -> Bool {
        guard cohort.contains(where: { alike($0, ballot) }) else { return false }
        let sizes = cohort.map(\.size) + [ballot.size]
        guard let low = sizes.min(), let high = sizes.max(), low > 0,
              high / low <= 1 + weightCohortSpan else { return false }
        return inkSpread(cohort + [ballot]) <= weightCohortInkSpan
    }

    /// Whether two runs are close enough to be the same kind of label.
    private static func alike(_ a: WeightBallot, _ b: WeightBallot) -> Bool {
        let low = min(a.size, b.size), high = max(a.size, b.size)
        guard low > 0, high / low <= 1 + weightCohortStep else { return false }
        return inkGap(a.color, b.color) <= weightCohortInkStep
    }

    /// How far apart two inks are, on their furthest channel.
    private static func inkGap(_ a: RGBA, _ b: RGBA) -> Double {
        max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b)))
    }

    /// And how far apart the two furthest inks in a group are.
    private static func inkSpread(_ ballots: [WeightBallot]) -> Double {
        var spread = 0.0
        for (nth, one) in ballots.enumerated() {
            for other in ballots[(nth + 1)...] {
                spread = max(spread, inkGap(one.color, other.color))
            }
        }
        return spread
    }

    /// The one weight a cohort of labels is set in.
    ///
    /// The TOTAL agreement rather than a show of hands, because a show of
    /// hands throws away how close each run was: two runs picking Medium by a
    /// thousandth and one picking Regular by a fifth are three runs that agree
    /// on Regular. Only a weight every run was scored against can win, or a
    /// weight two runs of six happen to do well in takes the cohort on their
    /// two numbers alone. A tie goes to the lighter, so a page read twice
    /// answers the same way twice.
    ///
    /// Nil where there is nothing they all share, which is a cohort with no
    /// answer rather than a cohort set in nothing.
    public static func pageWeight(of cohort: [WeightBallot]) -> TextWeight? {
        guard !cohort.isEmpty else { return nil }
        let candidates = TextWeight.allCases.filter { weight in
            cohort.allSatisfy { $0.agreement[weight] != nil }
        }
        func total(_ weight: TextWeight) -> Double {
            cohort.reduce(0) { $0 + ($1.agreement[weight] ?? 0) }
        }
        func lightness(_ weight: TextWeight) -> Int {
            TextWeight.allCases.firstIndex(of: weight) ?? 0
        }
        return candidates.max {
            total($0) == total($1) ? lightness($0) > lightness($1) : total($0) < total($1)
        }
    }

    /// The weight each run's own kind of label settled on, in step with
    /// `ballots`.
    ///
    /// Nil where the run could not be read at all, which is a run with no vote
    /// to cast and no answer to be given.
    public static func pageWeights(of ballots: [WeightBallot?]) -> [TextWeight?] {
        let cast = ballots.indices.filter { ballots[$0] != nil }
        let voting = cast.compactMap { ballots[$0] }
        var settled = [TextWeight?](repeating: nil, count: ballots.count)
        for cohort in weightCohorts(of: voting) {
            guard let weight = pageWeight(of: cohort.map { voting[$0] }) else { continue }
            for nth in cohort { settled[cast[nth]] = weight }
        }
        return settled
    }

    /// The one size a cohort of labels is set at: the MIDDLE of the sizes they
    /// each fit best at.
    ///
    /// The other half of what the family and the weight left open, and the
    /// half a vote cannot answer. A weight is one of four things, so the
    /// cohort can be asked which of the four they agree on best; a size is a
    /// number, and six labels that are 13 points on screen fit at 27.6, 28.0,
    /// 28.4, 28.0, 28.5 and 28.4 because which glyphs a run happens to contain
    /// moves its measured ink about. Nobody wants six sizes there, and
    /// anybody who picks all six and sets a size is tidying up after the app.
    ///
    /// The middle rather than the average, because the average is dragged by
    /// the one label whose ink was measured badly — a row whose descender ran
    /// into the divider under it — while the middle ignores it. Measured on
    /// this app's own captures, the middle is also the size the cohort agrees
    /// with BEST: on the settings pane's six rows it scores 4.571 against the
    /// nearest whole point's 4.204, and on the Effects panel's rows 4.484
    /// against 4.484. So there is nothing to be gained by searching for a
    /// better one, and a search costs a render per label per candidate.
    ///
    /// It is deliberately NOT rounded to a whole point, tempting as that is.
    /// Measured: holding the settings pane's six rows to 28 rather than 28.38
    /// puts "Copy to clipboard" 3 pixels short of the ink it is replacing and
    /// drops its agreement to 0.502, under `landedBar`, so the label that was
    /// meant to come back tidy comes back not at all. The Size menu says whole
    /// points anyway (`TextStyles.sizeWords`), so six labels settled at 28.38
    /// all read "28 pt" — one number, which is the thing being asked for.
    ///
    /// Nil for an empty cohort, which is a cohort with nothing to settle.
    public static func pageSize(of fits: [CGFloat]) -> CGFloat? {
        guard !fits.isEmpty else { return nil }
        let sorted = fits.sorted()
        let middle = sorted.count / 2
        guard sorted.count.isMultiple(of: 2) else { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// The size each run's own kind of label settled on, in step with
    /// `ballots`.
    ///
    /// The cohorts are the ones the weight settled on (`weightCohorts`): the
    /// runs that are one size and one ink colour in the picture are the runs
    /// that should come back one size, and a heading is not one of its rows.
    ///
    /// `fits` is the size each run fits its own ink at, in whatever unit the
    /// caller can compare them in — they are only ever compared with each
    /// other. Nil is a run with no size to offer and none to be given: one
    /// nobody could read, or one held to a heavier face than its cohort, whose
    /// size means something different because a heavier face reaches the same
    /// ink height at a smaller size.
    public static func pageSizes(of ballots: [WeightBallot?],
                                 fitting fits: [CGFloat?]) -> [CGFloat?] {
        var settled = [CGFloat?](repeating: nil, count: ballots.count)
        guard fits.count == ballots.count else { return settled }
        let cast = ballots.indices.filter { ballots[$0] != nil }
        let voting = cast.compactMap { ballots[$0] }
        for cohort in weightCohorts(of: voting) {
            let rows = cohort.map { cast[$0] }
            guard let size = pageSize(of: rows.compactMap { fits[$0] }) else { continue }
            for row in rows where fits[row] != nil { settled[row] = size }
        }
        return settled
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
