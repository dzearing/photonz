import CoreGraphics
import CoreText
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
    public static func read(_ image: CGImage, captureScale: CGFloat = 1,
                            layerScale: CGFloat = 1) -> Read {
        let captureScale = max(captureScale, 0.01), layerScale = max(layerScale, 0.01)
        guard let ink = ink(image), let inkRect = ink.mask.inkBounds() else {
            return Read(outcome: .refused(.tooFaint), inkRect: nil, scores: [])
        }
        guard let color = TextReading.inkColor(ink.samples) else {
            return Read(outcome: .refused(.tooFaint), inkRect: inkRect, scores: [])
        }
        let string: String
        switch recognize(ink.mask, inkHeight: inkRect.height) {
        case .failure(let refusal):
            return Read(outcome: .refused(refusal), inkRect: inkRect, scores: [])
        case .success(let read):
            string = read
        }
        let scores = score(string, against: ink.mask, inkHeight: inkRect.height,
                           scale: captureScale)
        let identified = TextReading.decide(string: string, scores: scores, color: color)
        guard let reading = identified.reading else {
            return Read(outcome: identified, inkRect: inkRect, scores: scores)
        }
        // The face has been identified at the size the type was set at. The
        // SIZE is a different question with a different answer: what the layer
        // needs is whatever makes that face cover the space the picture's ink
        // covers, in the document's own units. So the size is matched again, in
        // the chosen face, at the scale the layer will be drawn at.
        guard let landed = best(string, in: reading.face, against: ink.mask,
                                inkHeight: inkRect.height, scale: layerScale),
              landed.agreement >= TextReading.landedBar
        else {
            return Read(outcome: .refused(.noFaceMatches), inkRect: inkRect, scores: scores)
        }
        return Read(outcome: .read(TextReading.Reading(
            string: reading.string, face: reading.face, fontSize: landed.fontSize,
            colorHex: reading.colorHex, agreement: landed.agreement,
            provenance: reading.provenance)), inkRect: inkRect, scores: scores)
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
        guard inkHeight > 0 else { return .failure(.tooFaint) }
        // Small ink is scaled up before it is read. A row label on a 1x capture
        // is thirteen pixels tall, which is near the floor of what text
        // recognition reads reliably.
        let up = max(1, recognitionInkHeight / inkHeight)
        // And a margin of white round it, because a recogniser given a picture
        // whose letters run into all four edges reads the edges as strokes.
        let margin = Int((inkHeight * up / 2).rounded())
        let w = Int((CGFloat(mask.width) * up).rounded()) + margin * 2
        let h = Int((CGFloat(mask.height) * up).rounded()) + margin * 2
        guard w > 0, h > 0, w < 20_000, h < 20_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return .failure(.noWords) }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        guard let inkImage = maskImage(mask) else { return .failure(.noWords) }
        context.interpolationQuality = .high
        context.draw(inkImage, in: CGRect(x: CGFloat(margin), y: CGFloat(margin),
                                          width: CGFloat(mask.width) * up,
                                          height: CGFloat(mask.height) * up))
        guard let page = context.makeImage() else { return .failure(.noWords) }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // A label is a label, not a sentence. Correction turns "Photonz" into
        // "Photons" and a product name into a word, which is exactly the kind
        // of quiet wrongness this feature cannot afford.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: page, options: [:])
        guard (try? handler.perform([request])) != nil else { return .failure(.noWords) }
        let observations = request.results ?? []
        guard !observations.isEmpty else { return .failure(.noWords) }
        // More than one run is a signpost rather than a dead end: Separate into
        // Layers takes a picture apart into runs first, and then each one of
        // them is a single line this can read.
        guard observations.count == 1 else { return .failure(.moreThanOneRun) }
        guard let best = observations[0].topCandidates(1).first,
              !best.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .failure(.noWords) }
        return .success(best.string)
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
