import CoreGraphics
import CoreText
import Dispatch
import Foundation
import PhotonzCore
import Vision

/// Reads a picture of a run of text back into WORDS you can retype.
///
/// This is the reading half of the decision `PhotonzCore/TextReading.swift`
/// makes. It does three things and hands the answer over:
///
/// 1. **The characters.** `VNRecognizeTextRequest`, on device, which is the one
///    thing in this feature that no geometric detector can do and the reason
///    Vision earns its place here and nowhere else in the app. Everything up to
///    this point — finding the runs, cutting them out, patching behind them —
///    is done without it on purpose.
/// 2. **The size and the colour**, measured off the picture's own ink rather
///    than guessed: the height of the ink decides the point size, and the
///    colour of the solid middle of the strokes decides the colour.
/// 3. **The face**, which has no API anywhere and is the half that decides
///    whether this is delightful or uncanny. The words are SET AGAIN in each of
///    the few faces a Mac screenshot actually contains, each at the point size
///    that makes its ink the height the picture's ink is, and the one that lies
///    on the original most closely wins — if it agrees closely enough at all.
///
/// Full design: `docs/design/separate-into-layers.md`.
public enum TextReader {

    /// The faces the words are tried in.
    ///
    /// Deliberately short, and it is the honest answer to a question with no
    /// API: there is no way to ask what face a picture is set in, so the app
    /// tries the ones a Mac screenshot is actually made of and refuses when
    /// none of them fits. The system font first because nearly every screenshot
    /// of a Mac, an iPhone or a modern web page is set in it or in something
    /// indistinguishable from it at label size; then the monospace a terminal
    /// or a code editor gives you; then the two the rest of the web still uses.
    ///
    /// Every extra face is a chance to be wrong as well as a chance to be
    /// right, which is why this is a list of five families rather than every
    /// font installed.
    public static let faces: [TextReading.Face] = {
        var faces: [TextReading.Face] = []
        for weight in TextWeight.allCases {
            faces.append(TextReading.Face(fontName: "SF Pro", weight: weight))
        }
        for weight in [TextWeight.regular, .bold] {
            faces.append(TextReading.Face(fontName: "SF Mono", weight: weight))
            faces.append(TextReading.Face(fontName: "Helvetica Neue", weight: weight))
            faces.append(TextReading.Face(fontName: "Georgia", weight: weight))
            faces.append(TextReading.Face(fontName: "Times New Roman", weight: weight))
        }
        return faces
    }()

    /// What came back from reading one picture.
    public struct Read: Sendable {
        public let outcome: TextReading.Outcome
        /// Where the ink sat in the picture, in IMAGE PIXELS, top-left origin.
        /// What the placement needs so the retyped words land exactly where the
        /// old ones did. Nil when there was no ink to find.
        public let inkRect: CGRect?
        /// Every face that was tried and how it did, best first. The audit
        /// reads this: it is the difference between "the app chose SF Pro" and
        /// "SF Pro beat Georgia 0.78 to 0.41".
        public let scores: [TextReading.Scored]

        public init(outcome: TextReading.Outcome, inkRect: CGRect?,
                    scores: [TextReading.Scored]) {
            self.outcome = outcome
            self.inkRect = inkRect
            self.scores = scores
        }
    }

    /// The point size the words are first set at while their height is being
    /// measured. Big enough that the measurement is not quantised by whole
    /// pixels, small enough that the probe render is cheap.
    static let probeSize: CGFloat = 40

    /// The sizes each face is tried at, as fractions of the one that makes its
    /// ink the height the picture's ink is.
    ///
    /// Matching the height gets within a percent or two, and that is not close
    /// enough to judge a face by. Which glyphs a run happens to contain decides
    /// what its ink height MEANS — a row label with no ascender is x-height
    /// tall, a heading with a cap and a descender is far more — so a face with
    /// a different x-height for the same cap height is measured at the wrong
    /// size and loses for a reason that has nothing to do with its shape. Every
    /// face is given its own best size and then they are compared.
    static let sizeFactors: [CGFloat] = stride(from: 0.90, through: 1.10, by: 0.025).map { $0 }

    /// How tall the ink is made before it is handed to the recogniser, in
    /// pixels. A row label on a 1x capture is thirteen pixels of ink, which is
    /// near the floor of what text recognition reads reliably; scaled up it is
    /// read with the same confidence as the 2x one.
    static let recognitionInkHeight: CGFloat = 32

    /// Reads `image` — a separated run of text, or any picture holding one —
    /// back into words.
    ///
    /// Two scales, and they are not the same number, which is the one thing in
    /// this file worth reading twice.
    ///
    /// `captureScale` is how many image pixels the screenshot has per point of
    /// the type in it: 2 for a Retina capture, 1 for a plain one. The face is
    /// identified at THAT size, because a face is designed for a size. The
    /// system font is not one shape: it tracks its letters further apart at
    /// label size than at heading size, and asking whether a 13 point label is
    /// SF Pro by setting SF Pro at 27 points answers a different question.
    /// Measured on the settings-pane fixture, that difference is not a rounding
    /// error — "Reset" agrees 0.92 with SF Pro read at the size it was set and
    /// 0.76 read at twice it, and four of the six row labels come back
    /// Helvetica Neue when the question is asked the wrong way round.
    ///
    /// `layerScale` is how many image pixels there are per DOCUMENT point,
    /// which is what turns the size that was identified into the size the layer
    /// has to be SET at to cover the same space. A screenshot opened whole is
    /// 1; the same picture shown at half size on the canvas is 2.
    ///
    /// `family` is the family the picture this run was cut out of is set in,
    /// where the caller knows it (`pageFamily`). Given one, the face is chosen
    /// inside that family and nowhere else, which is the only thing measured to
    /// fix a label coming back heavier than the identical label beside it.
    /// Nil is one run on its own, deciding for itself, which is what Turn into
    /// Text does before anything has told it what the page is.
    public static func read(_ image: CGImage, captureScale: CGFloat = 1,
                            layerScale: CGFloat = 1,
                            preferring family: String? = nil,
                            at weight: TextWeight? = nil) -> Read {
        switch measure(image, captureScale: captureScale) {
        case .refused(let read):
            return read
        case .measured(let measured):
            return settle(measured, layerScale: layerScale, preferring: family, at: weight)
        }
    }

    /// Everything reading a picture COSTS, done once.
    ///
    /// Split out from the deciding because a page settles its family and the
    /// weight of each kind of label AFTER every run has been read, and holding
    /// a run to what the page settled must not mean recognising its characters
    /// and scoring thirteen faces all over again. The recogniser is most of
    /// the cost of a reading (1650 ms of the dense page's 3643), and a second
    /// pass over it buys nothing: the characters, the ink and the colour do
    /// not change when the page tells a run what family it is in.
    struct Measured: Sendable {
        let mask: TextReading.Mask
        let inkRect: CGRect
        let string: String
        let color: RGBA
        /// Every face tried, at the size the TYPE was set at. Nothing in here
        /// depends on what the page settles, which is what makes settling
        /// cheap.
        let scores: [TextReading.Scored]
    }

    /// A run measured, or the refusal that ended it before it got that far.
    enum Measurement: Sendable {
        case measured(Measured)
        case refused(Read)
    }

    static func measure(_ image: CGImage, captureScale: CGFloat = 1) -> Measurement {
        let captureScale = max(captureScale, 0.01)
        guard let ink = ink(image), let inkRect = ink.mask.inkBounds() else {
            return .refused(Read(outcome: .refused(.tooFaint), inkRect: nil, scores: []))
        }
        guard let color = TextReading.inkColor(ink.samples) else {
            return .refused(Read(outcome: .refused(.tooFaint), inkRect: inkRect, scores: []))
        }
        let string: String
        switch recognize(ink.mask, inkHeight: inkRect.height) {
        case .failure(let refusal):
            return .refused(Read(outcome: .refused(refusal), inkRect: inkRect, scores: []))
        case .success(let read):
            string = read
        }
        let scores = score(string, against: ink.mask, inkHeight: inkRect.height,
                           scale: captureScale)
        return .measured(Measured(mask: ink.mask, inkRect: inkRect, string: string,
                                  color: color, scores: scores))
    }

    /// Which face a measured run comes back in, and at what size, given what
    /// the page has settled.
    static func settle(_ run: Measured, layerScale: CGFloat = 1,
                       preferring family: String? = nil,
                       at weight: TextWeight? = nil) -> Read {
        let layerScale = max(layerScale, 0.01)
        let identified = TextReading.decide(string: run.string, scores: run.scores,
                                            color: run.color, preferring: family, at: weight)
        guard let reading = identified.reading else {
            return Read(outcome: identified, inkRect: run.inkRect, scores: run.scores)
        }
        // The face has been identified at the size the type was set at. The
        // SIZE is a different question with a different answer: what the layer
        // needs is whatever makes that face cover the space the picture's ink
        // covers, in the document's own units. So the size is matched again, in
        // the chosen face, at the scale the layer will be drawn at.
        guard let landed = best(run.string, in: reading.face, against: run.mask,
                                inkHeight: run.inkRect.height, scale: layerScale),
              landed.agreement >= TextReading.landedBar
        else {
            return Read(outcome: .refused(.noFaceMatches), inkRect: run.inkRect,
                        scores: run.scores)
        }
        return Read(outcome: .read(TextReading.Reading(
            string: reading.string, face: reading.face, fontSize: landed.fontSize,
            colorHex: reading.colorHex, agreement: landed.agreement,
            provenance: reading.provenance)), inkRect: run.inkRect, scores: run.scores)
    }

    /// Every run cut out of ONE picture, read, with the picture's own family
    /// settled first.
    ///
    /// The whole point of reading a page rather than a run: every screenshot
    /// anybody takes apart is set in one family, and the runs can only be
    /// compared with each other. Read one at a time, about one run in eight of
    /// this app's own window comes back in a family the window does not contain
    /// — and comes back CONFIDENT, scoring higher than plenty of correct
    /// readings, so no bar and no provenance filter can tell the two apart.
    /// Read together they vote, every run is set in the family that won, and a
    /// run the winner cannot account for stays a picture instead.
    ///
    /// Measured on the three study captures: the strays go to nought, at a cost
    /// of one reading of thirty-one on this app's window and eight of
    /// eighty-two on a dense web page. See
    /// `docs/design/separate-reads-the-words.md`.
    ///
    /// Serial unless it is told otherwise, because the caller is the one that
    /// knows whether it may take the cores: the command that reads every label
    /// in a screenshot at once spreads it, a test does not.
    public static func readPage(_ images: [CGImage], captureScale: CGFloat = 1,
                                layerScale: CGFloat = 1, preferring family: String? = nil,
                                spreadingOverTheCores: Bool = false) -> [Read] {
        readPage(images.map { PageRun(image: $0, layerScale: layerScale) },
                 captureScale: captureScale, preferring: family,
                 spreadingOverTheCores: spreadingOverTheCores)
    }

    /// One run of a page, for a caller whose runs are LAYERS and so can each be
    /// drawn at their own size: a label somebody resized after separating the
    /// screenshot has to have its words set to cover the space it covers now,
    /// not the space the picture covered.
    public struct PageRun: Sendable {
        public let image: CGImage
        /// How many of the picture's pixels fit in a document point.
        public let layerScale: CGFloat

        public init(image: CGImage, layerScale: CGFloat = 1) {
            self.image = image
            self.layerScale = layerScale
        }
    }

    /// The same page reading, run by run.
    ///
    /// `family`, where the caller already knows it, settles the question before
    /// anything is read: a screenshot whose family has been voted on once must
    /// not be voted on again and come back with a different answer, or one
    /// label read on its own and the same label read in a batch would disagree.
    public static func readPage(_ runs: [PageRun], captureScale: CGFloat = 1,
                                preferring family: String? = nil,
                                spreadingOverTheCores: Bool = false) -> [Read] {
        let measured = measureEachOf(runs, captureScale: captureScale,
                                     spreading: spreadingOverTheCores)
        // Read free first, so the page has something to vote with. Nothing
        // expensive happens twice here: the characters, the ink and the scores
        // were taken once above, and settling a run again is one face laid
        // over the ink at a handful of sizes.
        let free = settleEachOf(measured, runs: runs, preferring: family,
                                at: nil, spreading: spreadingOverTheCores)
        // One family for the whole picture, unless the caller already knows
        // it: a screenshot whose family has been voted on once must not be
        // voted on again and come back with a different answer.
        guard let voted = family
            ?? TextReading.pageFamily(of: free.compactMap(\.outcome.reading))
        else { return free }
        // And then one weight per KIND of label, which is the half the family
        // vote leaves open: six row labels of one pane can be four Regular and
        // two Medium while being one weight on screen.
        let ballots = measured.map { ballot($0, in: voted) }
        let weights = TextReading.pageWeights(of: ballots)
        let settled = settleEachOf(measured, runs: runs, preferring: voted,
                                   at: weights, spreading: spreadingOverTheCores)
        let held = measured.indices.map { index in
            // A run the page's own FAMILY cannot account for stays a picture,
            // and that is the safety net under the vote: a page that genuinely
            // mixes families loses a reading rather than gaining a label in
            // the wrong face.
            //
            // The WEIGHT is never a reason to lose one. A weight a shade off
            // is a smaller harm than a label that does not come back at all,
            // and a run whose ink the cohort's weight cannot account for is
            // exactly the run that really is heavier than the labels beside
            // it — the bold key cap in this app's own hint line, measured at
            // 0.72 bold against 0.52 semibold. So it is settled on its family
            // alone, the way it was before there was a weight vote at all.
            guard settled[index].outcome.reading == nil, weights[index] != nil,
                  case .measured(let run) = measured[index] else { return settled[index] }
            return settle(run, layerScale: runs[index].layerScale, preferring: voted)
        }
        // And finally one SIZE per kind of label, which is what the weight
        // vote leaves open in its turn: those same six row labels come back
        // 27.6, 28.0, 28.5, 28.0, 28.5 and 28.4 points while every one of them
        // is 13 points on screen, so picking all six reads Mixed and anybody
        // who then sets a size is tidying up after the app.
        return holdEachToItsCohortsSize(held, runs: runs, measured: measured,
                                        ballots: ballots, weights: weights,
                                        spreading: spreadingOverTheCores)
    }

    /// Sets every run at the size its KIND of label settled on.
    ///
    /// Settled in layer points rather than in the size the face was identified
    /// at, because those two are not one number divided by the other: rendering
    /// the same words at a different scale moves the ink by an antialiased edge
    /// either side, and measured on the settings pane that is a 6 to 10 per
    /// cent difference, per run. So the sizes compared here are the ones each
    /// run would actually be SET at, multiplied back up by its own scale so a
    /// label somebody shrank after separating is still comparable with the
    /// labels beside it.
    ///
    /// Two runs never take it:
    ///
    /// - one held to its own face rather than its cohort's, whose size means
    ///   something different, because a heavier face reaches the same ink
    ///   height at a smaller size;
    /// - one whose ink the settled size cannot account for. Settling a size
    ///   never costs a reading, exactly as settling a weight never does: a
    ///   label back at its own size is a smaller harm than a label that does
    ///   not come back at all.
    private static func holdEachToItsCohortsSize(
        _ reads: [Read], runs: [PageRun], measured: [Measurement],
        ballots: [TextReading.WeightBallot?], weights: [TextWeight?],
        spreading: Bool
    ) -> [Read] {
        let fits: [CGFloat?] = reads.indices.map { index in
            guard let reading = reads[index].outcome.reading else { return nil }
            if let settled = weights[index], reading.face.weight != settled { return nil }
            return reading.fontSize * runs[index].layerScale
        }
        let sizes = TextReading.pageSizes(of: ballots, fitting: fits)
        @Sendable func one(_ index: Int) -> Read {
            guard let settled = sizes[index], case .measured(let run) = measured[index],
                  runs[index].layerScale > 0
            else { return reads[index] }
            return hold(reads[index], of: run, to: settled / runs[index].layerScale,
                        scale: runs[index].layerScale)
        }
        guard spreading, reads.count > 1 else { return reads.indices.map(one) }
        var landed = [Read?](repeating: nil, count: reads.count)
        landed.withUnsafeMutableBufferPointer { buffer in
            guard let raw = buffer.baseAddress else { return }
            DispatchQueue.concurrentPerform(iterations: reads.count) { index in
                (raw + index).pointee = one(index)
            }
        }
        return landed.indices.map { landed[$0] ?? reads[$0] }
    }

    /// One run set at `size` instead of the size it fitted itself at, if its
    /// own ink can still be accounted for at that size. The run as it was
    /// otherwise.
    private static func hold(_ read: Read, of run: Measured, to size: CGFloat,
                             scale: CGFloat) -> Read {
        guard let reading = read.outcome.reading, size > 0.5, size < 2000,
              size != reading.fontSize,
              let mask = render(reading.string, in: reading.face, size: size, scale: scale)
        else { return read }
        let agreement = TextReading.agreement(run.mask, mask)
        guard agreement >= TextReading.landedBar else { return read }
        return Read(outcome: .read(TextReading.Reading(
            string: reading.string, face: reading.face, fontSize: size,
            colorHex: reading.colorHex, agreement: agreement,
            provenance: reading.provenance)), inkRect: read.inkRect, scores: read.scores)
    }

    /// What one measured run says about the weight its kind of label is set
    /// in. Nil where there was nothing to read, which is a run with no vote to
    /// cast.
    private static func ballot(_ measurement: Measurement,
                               in family: String) -> TextReading.WeightBallot? {
        guard case .measured(let run) = measurement else { return nil }
        let inFamily = run.scores.filter { $0.face.fontName == family }
        guard !inFamily.isEmpty else { return nil }
        var agreement: [TextWeight: Double] = [:]
        for scored in inFamily { agreement[scored.face.weight] = scored.agreement }
        // The size at the family's LIGHTEST weight, so the size a run is put
        // in a cohort by does not depend on which weight happened to win it.
        let lightest = TextWeight.allCases.first { agreement[$0] != nil }
        guard let size = inFamily.first(where: { $0.face.weight == lightest })?.fontSize
        else { return nil }
        return TextReading.WeightBallot(size: size, color: run.color, agreement: agreement)
    }

    /// One pass of the RECOGNISER over a list of runs, across the cores or not.
    ///
    /// This is where nearly all the cost of reading a page is: measured on a
    /// release build, 143 ms for nine runs, 1910 ms for a hundred and forty
    /// two, spread — about half what the same work costs one after another.
    private static func measureEachOf(_ runs: [PageRun], captureScale: CGFloat,
                                      spreading: Bool) -> [Measurement] {
        guard spreading, runs.count > 1 else {
            return runs.map { measure($0.image, captureScale: captureScale) }
        }
        var landed = [Measurement?](repeating: nil, count: runs.count)
        landed.withUnsafeMutableBufferPointer { buffer in
            guard let raw = buffer.baseAddress else { return }
            DispatchQueue.concurrentPerform(iterations: runs.count) { index in
                (raw + index).pointee = measure(runs[index].image, captureScale: captureScale)
            }
        }
        // Every slot is written by the loop above. The fallback is unreachable
        // and is here because this module holds no force unwrap.
        return landed.map {
            $0 ?? .refused(Read(outcome: .refused(.noWords), inkRect: nil, scores: []))
        }
    }

    /// And one pass of the DECIDING over the same runs, holding each to what
    /// the page settled. Cheap by comparison: one face laid over the ink at a
    /// handful of sizes, with nothing recognised again.
    private static func settleEachOf(_ measured: [Measurement], runs: [PageRun],
                                     preferring family: String?, at weights: [TextWeight?]?,
                                     spreading: Bool) -> [Read] {
        @Sendable func one(_ index: Int) -> Read {
            switch measured[index] {
            case .refused(let read): return read
            case .measured(let run):
                return settle(run, layerScale: runs[index].layerScale,
                              preferring: family, at: weights?[index])
            }
        }
        guard spreading, measured.count > 1 else { return measured.indices.map(one) }
        var landed = [Read?](repeating: nil, count: measured.count)
        landed.withUnsafeMutableBufferPointer { buffer in
            guard let raw = buffer.baseAddress else { return }
            DispatchQueue.concurrentPerform(iterations: measured.count) { index in
                (raw + index).pointee = one(index)
            }
        }
        return landed.map { $0 ?? Read(outcome: .refused(.noWords), inkRect: nil, scores: []) }
    }

    /// Which family ONE run says it is, and nothing else about it.
    ///
    /// What a vote is counted from. It stops before the size the layer would
    /// have to be set at, because a vote never lands anything on the canvas —
    /// it only has to name a family — and that last step is a face set nine
    /// more times over.
    ///
    /// Nil where the run could not be read at all, which is a run with no vote
    /// to cast rather than a vote for nothing.
    public static func family(in image: CGImage, captureScale: CGFloat = 1) -> String? {
        guard let ink = ink(image), let inkRect = ink.mask.inkBounds(),
              let color = TextReading.inkColor(ink.samples),
              case .success(let string) = recognize(ink.mask, inkHeight: inkRect.height)
        else { return nil }
        let scores = score(string, against: ink.mask, inkHeight: inkRect.height,
                           scale: captureScale)
        return TextReading.decide(string: string, scores: scores,
                                  color: color).reading?.face.fontName
    }

    /// Just the WORDS in a picture of a run of text, for something that wants
    /// to SAY them rather than set them — the row in the layers list under a
    /// separated label (`docs/design/separate-into-layers.md`, "A separated row
    /// says its words").
    ///
    /// The same recogniser `read` uses, and then it stops. Everything after the
    /// characters — the colour, the size, and above all the face, which sets
    /// the words again in thirteen faces at nine sizes each and lays every one
    /// of them over the picture's ink — exists to put real text back on the
    /// canvas. A row needs none of it, and a row must not HAVE it: the study
    /// measured the face coming back wrong on four of thirty one runs of this
    /// app's own window, with the app calling all four its confident verdict.
    /// The words were right in every one of those. So a name takes the half
    /// that is reliable and leaves the half that is not.
    ///
    /// It is cheaper too, though by less than it looks: optimised, the
    /// recogniser is most of the cost. Reading the settings pane's nine runs
    /// for their words is 276 ms against 358 ms whole, and the dense page's
    /// hundred and forty two are 1650 ms against 3643 ms — about half, spread
    /// over the cores a few hundred milliseconds, which is what makes a pass
    /// over a whole page something that finishes behind the command.
    ///
    /// It also answers where the whole reading gives up. Sixty of the dense
    /// page's hundred and forty two runs are refused for having no face the app
    /// can match, and every one of those is still a label somebody would read
    /// and search for.
    ///
    /// Nil when there is no ink to find or nothing readable in it, which is the
    /// honest answer for a switch, an icon or a patch of flat panel: the row
    /// keeps the name the app gave it.
    public static func words(in image: CGImage) -> String? {
        guard let ink = ink(image), let bounds = ink.mask.inkBounds() else { return nil }
        // Every line of it, joined. `read` refuses a picture holding more than
        // one run, because it could only set ONE of them back on the canvas; a
        // name has no such trouble and two lines of a label are two words of a
        // name (`LayerNaming.name(fromWords:)` folds them into one line).
        let lines = lines(ink.mask, inkHeight: bounds.height)
        let words = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? nil : words
    }

    // MARK: - The ink

    /// The shape of the ink in a picture, and samples of its colour from the
    /// solid middle of the strokes.
    ///
    /// Two pictures arrive here and they are read differently. A run that came
    /// out of Separate into Layers is already just the LETTERS, with everything
    /// that was behind them transparent, so its own alpha is the coverage —
    /// exactly the number the cut worked out. A plain crop of a screenshot is
    /// opaque, so the ink has to be told apart from what it sits on, which is
    /// the same unmix the cut does: the background is what the border of the
    /// picture is painted, and how far a pixel sits from it is how much ink it
    /// holds.
    static func ink(_ image: CGImage) -> (mask: TextReading.Mask, samples: [RGBA])? {
        let w = image.width, h = image.height
        guard w > 1, h > 1, let bytes = LayerSeparator.read(image) else { return nil }

        func unpremultiplied(_ i: Int) -> RGBA {
            let a = Double(bytes[i + 3])
            guard a > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
            return RGBA(r: Double(bytes[i]) / a, g: Double(bytes[i + 1]) / a,
                        b: Double(bytes[i + 2]) / a, a: a / 255)
        }

        var coverage = [Double](repeating: 0, count: w * h)
        var samples: [RGBA] = []
        let cutOut = bytes.striding4Min(offset: 3) < 8

        if cutOut {
            for p in 0..<(w * h) {
                let a = Double(bytes[p * 4 + 3]) / 255
                coverage[p] = a
                if a >= 0.9 { samples.append(unpremultiplied(p * 4)) }
            }
        } else {
            // The border of the picture is what the run was sitting on. A
            // separated run's box is its letters grown by a halo, so the rim is
            // background by construction; a crop somebody made by hand has a
            // rim of whatever they cropped out of, which is the same thing.
            var ring: [RGBA] = []
            for x in 0..<w {
                ring.append(unpremultiplied(x * 4))
                ring.append(unpremultiplied(((h - 1) * w + x) * 4))
            }
            for y in 1..<(h - 1) {
                ring.append(unpremultiplied((y * w) * 4))
                ring.append(unpremultiplied((y * w + w - 1) * 4))
            }
            guard let background = TextReading.inkColor(ring) else { return nil }
            func distance(_ c: RGBA) -> Double {
                max(abs(c.r - background.r), max(abs(c.g - background.g),
                                                 abs(c.b - background.b)))
            }
            var distances = [Double](repeating: 0, count: w * h)
            for p in 0..<(w * h) { distances[p] = distance(unpremultiplied(p * 4)) }
            // What a full stroke is worth here: the darkest (or brightest)
            // tenth of the picture, the same reading the cut uses, so a pale
            // grey caption is read at its own contrast rather than against an
            // absolute that only a black-on-white label would reach.
            let sorted = distances.sorted()
            let peak = sorted[Int(Double(sorted.count - 1) * 0.98)]
            guard peak >= LayerSeparator.minimumContrast else { return nil }
            for p in 0..<(w * h) {
                let value = min(distances[p] / peak, 1)
                coverage[p] = value
                if value >= 0.9 { samples.append(unpremultiplied(p * 4)) }
            }
        }
        guard !samples.isEmpty else { return nil }
        return (TextReading.Mask(width: w, height: h, coverage: coverage), samples)
    }

    // MARK: - The characters

    /// The words in a shape of ink, or why they could not be taken.
    ///
    /// The recogniser is handed the COVERAGE, drawn black on white, rather than
    /// the picture itself. That is deliberate and it is what makes white words
    /// on a blue button read as well as black words on grey: the shape of the
    /// ink is the only thing that carries the characters, and handing over a
    /// clean high contrast version of it takes the colour question away
    /// entirely.
    static func recognize(_ mask: TextReading.Mask,
                          inkHeight: CGFloat) -> Result<String, TextReading.Refusal> {
        let lines = lines(mask, inkHeight: inkHeight)
        guard !lines.isEmpty else { return .failure(.noWords) }
        // More than one run is a signpost rather than a dead end: Separate into
        // Layers takes a picture apart into runs first, and then each one of
        // them is a single line this can read.
        guard lines.count == 1 else { return .failure(.moreThanOneRun) }
        return .success(lines[0])
    }

    /// Every line of text the recogniser finds in a shape of ink, top down.
    ///
    /// Empty when there is nothing readable there, which covers a switch, an
    /// icon and a patch of flat panel alike. The caller decides what more than
    /// one line means: putting words back on the canvas refuses, naming a row
    /// joins them.
    ///
    /// Empty is ALSO what comes back when the machine would not read at all,
    /// and the two are not the same news. Use `reading(_:inkHeight:)` where
    /// that difference matters; everything that reaches here has already
    /// decided it does not, and a refusal is counted in `recogniserHealth` on
    /// the way past so somebody can still find out.
    static func lines(_ mask: TextReading.Mask, inkHeight: CGFloat) -> [String] {
        switch reading(mask, inkHeight: inkHeight) {
        case .read(let lines):
            return lines
        case .refused(let why):
            refusals.record(why)
            return []
        }
    }

    /// What one pass of the recogniser came back with: the lines it found, or
    /// the reason it would not answer.
    ///
    /// The second case is the one this type exists for. Vision is a shared
    /// on-device service, so a request can fail outright rather than read
    /// nothing, and it does so exactly when the machine is busy: the same
    /// picture that reads perfectly on an idle Mac comes back refused on one
    /// running a build and a hundred other readings at once. Folded into an
    /// empty answer, that is indistinguishable from a blank picture, and every
    /// caller downstream reports it as the app having failed to read something
    /// it can plainly read.
    enum Reading: Equatable {
        case read([String])
        case refused(String)

        /// The reason, when there was one.
        var refusal: String? {
            if case .refused(let why) = self { return why }
            return nil
        }
    }

    /// How many times the recogniser has refused to answer in this process,
    /// and what it last said.
    ///
    /// A count rather than a flag because a single read is allowed to fail:
    /// what a caller wants to know is whether the machine was reading AT ALL
    /// while it was working. Tests that depend on real reading take this
    /// before and after and skip instead of failing when it moved.
    public struct RecogniserHealth: Equatable, Sendable {
        var refusals: Int
        var reason: String?
    }

    /// The running count, safe to read and add to from any thread. A whole
    /// separation reads a dozen runs at once across every core.
    final class RecogniserHealthCount: @unchecked Sendable {
        private let lock = NSLock()
        private var total = 0
        private var last: String?

        var snapshot: RecogniserHealth {
            lock.withLock { RecogniserHealth(refusals: total, reason: last) }
        }

        func record(_ reason: String) {
            lock.withLock {
                total += 1
                last = reason
            }
        }
    }

    static let refusals = RecogniserHealthCount()

    /// Whether the machine has been answering, and what it said when it did
    /// not. See `RecogniserHealth`.
    public static var recogniserHealth: RecogniserHealth { refusals.snapshot }

    /// How many more goes a refused read gets before it is counted as one.
    ///
    /// Two, with a short wait between them, because what is being waited out
    /// is the rest of the machine rather than anything about the picture. An
    /// ordinary read never reaches the retry, so this costs a run that is
    /// working precisely nothing.
    static let recogniserRetries = 2

    /// A drill: every read comes back refused.
    ///
    /// There is no way to make the on-device recogniser refuse on demand, and
    /// a refusal is rare enough that waiting for one is not a plan, so this
    /// makes one happen. It is how the behaviour on a machine that will not
    /// read gets checked on a machine that will:
    ///
    /// ```
    /// PHOTONZ_RECOGNISER_REFUSES=1 Scripts/test.sh --filter SeparatedRowsSayTheirWords
    /// ```
    ///
    /// Read once, so an ordinary run pays nothing for it.
    static let recogniserAlwaysRefuses =
        ProcessInfo.processInfo.environment["PHOTONZ_RECOGNISER_REFUSES"] == "1"

    static func reading(_ mask: TextReading.Mask, inkHeight: CGFloat,
                        refusing alwaysRefuses: Bool = recogniserAlwaysRefuses) -> Reading {
        guard inkHeight > 0 else { return .read([]) }
        if alwaysRefuses {
            return .refused("PHOTONZ_RECOGNISER_REFUSES is set: this is a drill, not a real refusal")
        }
        // Small ink is scaled up before it is read. A row label on a 1x capture
        // is thirteen pixels tall, which is near the floor of what text
        // recognition reads reliably.
        let up = max(1, recognitionInkHeight / inkHeight)
        // And a margin of white round it, because a recogniser given a picture
        // whose letters run into all four edges reads the edges as strokes.
        let margin = Int((inkHeight * up / 2).rounded())
        let w = Int((CGFloat(mask.width) * up).rounded()) + margin * 2
        let h = Int((CGFloat(mask.height) * up).rounded()) + margin * 2
        // Nothing here is the recogniser refusing: a page this code cannot
        // draw is a picture with no reading in it, the same as a blank one.
        guard w > 0, h > 0, w < 20_000, h < 20_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return .read([]) }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        guard let inkImage = maskImage(mask) else { return .read([]) }
        context.interpolationQuality = .high
        context.draw(inkImage, in: CGRect(x: CGFloat(margin), y: CGFloat(margin),
                                          width: CGFloat(mask.width) * up,
                                          height: CGFloat(mask.height) * up))
        guard let page = context.makeImage() else { return .read([]) }

        var refusal = "the recogniser gave no reason"
        for attempt in 0...recogniserRetries {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // A label is a label, not a sentence. Correction turns "Photonz"
            // into "Photons" and a product name into a word, which is exactly
            // the kind of quiet wrongness this feature cannot afford.
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: page, options: [:])
            do {
                try handler.perform([request])
            } catch {
                refusal = "\(error)"
                // Waiting is the point: what has to pass is the rest of the
                // machine, not anything about this picture.
                if attempt < recogniserRetries {
                    Thread.sleep(forTimeInterval: 0.1 * Double(attempt + 1))
                }
                continue
            }
            return .read((request.results ?? []).compactMap {
                guard let best = $0.topCandidates(1).first,
                      !best.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }
                return best.string
            })
        }
        return .refused(refusal)
    }

    /// Coverage as a black-on-transparent bitmap, so it can be drawn onto a
    /// white page for the recogniser.
    static func maskImage(_ mask: TextReading.Mask) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
        for p in 0..<(mask.width * mask.height) {
            pixels[p * 4 + 3] = UInt8(min(max(mask.coverage[p], 0), 1) * 255)
        }
        return LayerSeparator.makeImage(pixels, width: mask.width, height: mask.height)
    }

    // MARK: - The face

    /// Every face tried, best first.
    static func score(_ string: String, against original: TextReading.Mask,
                      inkHeight: CGFloat, scale: CGFloat) -> [TextReading.Scored] {
        faces.compactMap {
            best(string, in: $0, against: original, inkHeight: inkHeight, scale: scale)
        }
        .sorted { $0.agreement > $1.agreement }
    }

    /// How far a face's whole word may be the wrong length before it is not
    /// worth setting properly, as a fraction.
    ///
    /// A word's length against its height is the one thing about a face you can
    /// read off a probe render for nothing, and it is decisive: a monospace
    /// setting a proportional label runs a third long, and a serif with a wide
    /// lowercase runs a fifth. Anything out by more than this is not the face
    /// in the picture and no size will make it one, so it is dropped before the
    /// nine renders and the overlap search it would otherwise cost.
    static let aspectSlack = 0.15

    /// One face at its own best size: the size that makes its ink the height
    /// the picture's ink is, then nudged over `sizeFactors` and the best kept.
    /// Nil for a face whose word comes out the wrong LENGTH, which is answered
    /// by the probe render alone.
    static func best(_ string: String, in face: TextReading.Face,
                     against original: TextReading.Mask, inkHeight: CGFloat,
                     scale: CGFloat) -> TextReading.Scored? {
        guard inkHeight > 0, let aspect = original.inkBounds().map({ $0.width / inkHeight }),
              let probe = render(string, in: face, size: probeSize, scale: scale),
              let probeInk = probe.inkBounds(), probeInk.height > 0
        else { return nil }
        guard abs(probeInk.width / probeInk.height / aspect - 1) <= aspectSlack
        else { return nil }
        let matched = probeSize * inkHeight / probeInk.height
        guard matched.isFinite, matched > 0.5, matched < 2000 else { return nil }
        var best: TextReading.Scored?
        for factor in sizeFactors {
            let size = matched * factor
            guard let mask = render(string, in: face, size: size, scale: scale)
            else { continue }
            let agreement = TextReading.agreement(original, mask)
            if agreement > (best?.agreement ?? -1) {
                best = TextReading.Scored(face: face, fontSize: size, agreement: agreement)
            }
        }
        return best
    }

    /// The point size at which `string` set in `face` has ink `inkHeight`
    /// pixels tall.
    ///
    /// Measured rather than derived from the face's metrics, because the ink of
    /// a real string is whatever that string happens to contain: a row label
    /// with no ascender and no descender is x-height tall, a heading with a
    /// cap and a descender is far more, and no single ratio covers both. Set it
    /// once at a known size, see how tall it came out, scale.
    static func size(of string: String, in face: TextReading.Face,
                     matchingInkHeight inkHeight: CGFloat, scale: CGFloat) -> CGFloat? {
        guard inkHeight > 0,
              let probe = render(string, in: face, size: probeSize, scale: scale),
              let bounds = probe.inkBounds(), bounds.height > 0
        else { return nil }
        let size = probeSize * inkHeight / bounds.height
        guard size.isFinite, size > 0.5, size < 2000 else { return nil }
        return size
    }

    /// `string` set in `face` at `size`, as a coverage mask in image pixels.
    static func render(_ string: String, in face: TextReading.Face, size: CGFloat,
                       scale: CGFloat) -> TextReading.Mask? {
        var text = TextContent(string: string, fontName: face.fontName, fontSize: size,
                               colorHex: "#000000", weight: face.weight)
        // One line, always. A run of text is one line by the time it gets here
        // — that is what a run IS — and letting the measurer wrap it would
        // score a face against words it has broken somewhere else.
        text.staysOnOneLine = true
        let box = TextRasterizer.naturalSize(text)
        guard box.width > 0, box.height > 0,
              let image = TextRasterizer.rasterize(text, size: box, scale: scale),
              let bytes = LayerSeparator.read(image)
        else { return nil }
        let w = image.width, h = image.height
        var coverage = [Double](repeating: 0, count: w * h)
        for p in 0..<(w * h) { coverage[p] = Double(bytes[p * 4 + 3]) / 255 }
        return TextReading.Mask(width: w, height: h, coverage: coverage)
    }

    // MARK: - Where the words go

    /// The frame a text layer must be given, in DOCUMENT POINTS, for its ink to
    /// land exactly where the picture's ink did.
    ///
    /// This is the difference between a feature that is nearly right and one
    /// that is right. A text layer's box is not its letters: it holds the
    /// ascent above them, the descent below, and the couple of points of slack
    /// the rasterizer leaves so nothing clips. So the words are set once,
    /// measured, and the box is placed by how far its own ink sits inside it.
    ///
    /// `ink` is where the picture's ink sat, in document points.
    public static func frame(for text: TextContent, placingInkAt ink: CGRect,
                             scale: CGFloat = 1) -> CGRect {
        var text = text
        text.staysOnOneLine = true
        let box = TextRasterizer.naturalSize(text)
        guard let mask = render(text.string,
                                in: TextReading.Face(fontName: text.fontName,
                                                     weight: text.weight),
                                size: text.fontSize, scale: scale),
              let bounds = mask.inkBounds(), scale > 0
        else { return CGRect(origin: ink.origin, size: box) }
        return CGRect(x: ink.minX - bounds.minX / scale,
                      y: ink.minY - bounds.minY / scale,
                      width: box.width, height: box.height)
    }
}

private extension Array where Element == UInt8 {
    /// The smallest byte at `offset` of every four — the alpha channel of a
    /// premultiplied-last bitmap, without copying it out first.
    func striding4Min(offset: Int) -> UInt8 {
        var smallest = UInt8.max
        var i = offset
        while i < count {
            if self[i] < smallest { smallest = self[i] }
            i += 4
        }
        return smallest
    }
}
