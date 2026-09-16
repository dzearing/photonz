import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Separate into Layers measured against a REAL screenshot, because that is the
/// only kind of test that can catch this heuristic going wrong. A drawn scene
/// contains exactly the shapes the code is looking for; a capture brings
/// antialiasing, rounded corners, a switch with a knob in it, hairline dividers
/// and a bold display heading — and every one of those broke an earlier version
/// of the sweep.
///
/// The fixture is `Fixtures/settings-pane-2x.png`, the same 2x capture element
/// detection is pinned against. It holds nine runs of text:
///
/// | run | what it is |
/// | --- | --- |
/// | 1 | "General", a bold display heading on the page |
/// | 2…4 | three row labels on a white card |
/// | 5…7 | three more row labels on the second card |
/// | 8 | "Reset", dark words on a light grey button |
/// | 9 | "Save Changes", WHITE words on a solid blue button |
///
/// …and four switches, two text fields and two buttons, none of which are text.
/// The buttons sit on the page, so they are boxes of their own; the switches and
/// the fields sit on the cards, so they come out nested under them.
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("Separate into Layers on a real capture")
struct SeparateIntoLayersFixtureTests {

    private static let capture: CGImage? = {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }()

    private static let analysis: EdgeMapAnalyzer.Analysis = {
        guard let capture else { return .empty }
        return EdgeMapAnalyzer.analyzeFully(capture)
    }()

    private static let separated: LayerSeparator.Result? = {
        guard let capture else { return nil }
        return LayerSeparator.separateText(capture, luma: analysis.luma)
    }()

    /// One pixel of a bitmap, unpremultiplied, in 0…255 per channel.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        guard let bytes = LayerSeparator.read(image), x >= 0, y >= 0,
              x < image.width, y < image.height else { return (-1, -1, -1, -1) }
        let i = (y * image.width + x) * 4
        let a = Int(bytes[i + 3])
        guard a > 0 else { return (0, 0, 0, 0) }
        return (Int(bytes[i]) * 255 / a, Int(bytes[i + 1]) * 255 / a, Int(bytes[i + 2]) * 255 / a, a)
    }

    // MARK: - What the sweep finds

    @Test func everyRunOfTextInTheCaptureComesOut() throws {
        let runs = TextRunSweep.sweep(in: Self.analysis.luma).runs
        #expect(runs.count == 9)
        // Down the page, then across — the order an eye reads them in. The
        // last two share a row (the Reset and Save Changes buttons sit side by
        // side), and on a shared row the left one comes first even though its
        // letters start a pixel lower.
        let tops = runs.dropLast().map { Int($0.minY) }
        #expect(tops == tops.sorted())
        // The heading first, then the six row labels, then the two buttons'
        // labels left to right.
        #expect(runs.first.map { Int($0.minX) } == 66)
        #expect(runs.dropLast().last.map { Int($0.minX) } == 104)
        #expect(runs.last.map { Int($0.minX) } == 272)
        #expect(runs.last.map { Int($0.minY) } == 776)
    }

    @Test func noSwitchAndNoButtonComesOutAsAPieceOfText() throws {
        let runs = TextRunSweep.sweep(in: Self.analysis.luma).runs
        // The three switches sit at the right edge of the cards, x past 1250.
        #expect(!runs.contains { $0.minX > 1200 })
        // The blue button is 262 wide and 46 tall; its LABEL is 170 by 25. If
        // the button itself had been taken, the label could not have been.
        #expect(!runs.contains { $0.width > 280 })
    }

    @Test func everyRunIsSeparatedAndNoneIsSkipped() throws {
        let result = try #require(Self.separated)
        #expect(result.pieces.count == 9)
        #expect(result.skipped == 0)
    }

    // MARK: - No holes

    @Test func whiteWordsOnASolidBlueButtonLeaveThatButtonOneFlatColour() throws {
        let result = try #require(Self.separated)
        let label = try #require(result.pieces.last).rect
        let patched = result.background

        // The button's own blue, read well away from where the words were.
        let button = pixel(patched, 250, 788)
        var worst = 0
        var readings: Set<String> = []
        guard let bytes = LayerSeparator.read(patched) else {
            Issue.record("the repaired picture could not be read back")
            return
        }
        for y in Int(label.minY)..<Int(label.maxY) {
            for x in Int(label.minX)..<Int(label.maxX) {
                let i = (y * patched.width + x) * 4
                let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
                readings.insert("\(r),\(g),\(b)")
                worst = max(worst, max(abs(r - button.r), max(abs(g - button.g), abs(b - button.b))))
            }
        }
        print("PATCH the Save Changes label's \(Int(label.width))x\(Int(label.height)) box "
            + "reads \(readings.count) distinct colour(s); worst channel difference from the "
            + "button's own blue elsewhere: \(worst)/255")
        // Exact, not approximate: one colour across the whole box, and it is
        // the button's colour.
        #expect(readings.count == 1)
        #expect(worst == 0)
    }

    @Test func everyRunLeavesItsSpaceFlatAndMatchingWhatSurroundsIt() throws {
        let result = try #require(Self.separated)
        let patched = result.background
        let bytes = try #require(LayerSeparator.read(patched))
        var report: [String] = []
        for (index, piece) in result.pieces.enumerated() {
            let box = piece.rect
            // What is just outside the box, three pixels clear of it.
            let outside = pixel(patched, Int(box.minX) - 4, Int(box.midY))
            var worst = 0
            for y in Int(box.minY)..<Int(box.maxY) {
                for x in Int(box.minX)..<Int(box.maxX) {
                    let i = (y * patched.width + x) * 4
                    worst = max(worst, abs(Int(bytes[i]) - outside.r))
                    worst = max(worst, abs(Int(bytes[i + 1]) - outside.g))
                    worst = max(worst, abs(Int(bytes[i + 2]) - outside.b))
                }
            }
            report.append("Text \(index + 1): \(worst)")
            #expect(worst <= 1, "Text \(index + 1) does not match what surrounds it")
        }
        print("PATCH worst channel difference between the filled space and the pixel "
            + "4 px to its left, per run, out of 255 — \(report.joined(separator: ", "))")
    }

    @Test func runningItTwiceFindsNothingLeftToTake() throws {
        let result = try #require(Self.separated)
        let again = EdgeMapAnalyzer.analyzeFully(result.background)
        let runs = TextRunSweep.sweep(in: again.luma).runs
        print("TWICE the repaired picture offers \(runs.count) runs")
        #expect(runs.isEmpty)
    }

    // MARK: - What comes out is the letters

    @Test func aPieceIsTheLettersAndNotARectangleOfButton() throws {
        let result = try #require(Self.separated)
        let label = try #require(result.pieces.last)
        let piece = try #require(label.image)
        // Its corners are the button, and the button did not come with it.
        for corner in [(0, 0), (piece.width - 1, 0), (0, piece.height - 1),
                       (piece.width - 1, piece.height - 1)] {
            #expect(pixel(piece, corner.0, corner.1).a == 0)
        }
        // And the letters did: somewhere in the middle is opaque and white.
        var opaque = 0, white = 0
        let bytes = try #require(LayerSeparator.read(piece))
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] == 255 {
            opaque += 1
            if bytes[i] > 240, bytes[i + 1] > 240, bytes[i + 2] > 240 { white += 1 }
        }
        let coverage = Double(opaque) / Double(piece.width * piece.height)
        print("CUT the Save Changes piece is \(piece.width)x\(piece.height); "
            + "\(Int(coverage * 100))% of it is solid ink and \(white) of those \(opaque) "
            + "pixels are white")
        #expect(opaque > 0)
        #expect(white == opaque)
        // Letters, not a tile: most of the box is see-through.
        #expect(coverage < 0.5)
    }

    @Test func aDarkLabelKeepsItsOwnColourWhenItComesOut() throws {
        let result = try #require(Self.separated)
        // Run 2 is "Launch at login": near black words on a white card.
        let run = try #require(result.pieces.dropFirst().first)
        let piece = try #require(run.image)
        let bytes = try #require(LayerSeparator.read(piece))
        var darkest = 255
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] == 255 {
            darkest = min(darkest, Int(bytes[i]))
        }
        #expect(darkest < 40)
    }

    // MARK: - What it refuses

    @Test func wordsOnAPhotographAreLeftInThePicture() throws {
        // Rule three. The ring round these words is neither one colour nor a
        // straight ramp, so there is no fill the app can justify: the run stays
        // in the picture and no layer is made of it.
        let w = 400, h = 240
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        // Smooth enough that it is not ink, curved enough that it is neither a
        // colour nor a ramp — the shape a photograph has behind a caption.
        for y in 0..<h {
            for x in 0..<w {
                let shade = 110 + 34 * sin(Double(x) / 11) * cos(Double(y) / 9)
                let i = (y * w + x) * 4
                bytes[i] = UInt8(shade)
                bytes[i + 1] = UInt8(shade * 0.8)
                bytes[i + 2] = UInt8(shade * 0.6)
                bytes[i + 3] = 255
            }
        }
        // White "letters" over it: ascenders, x height, and a descender, so the
        // sweep reads them as a run rather than as a box.
        for letter in 0..<14 {
            let x0 = 100 + letter * 8
            let top = (letter == 0 || letter == 3) ? 100 : 106
            let bottom = letter == 13 ? 130 : 124
            for y in top..<bottom {
                for x in x0..<(x0 + 3) {
                    let i = (y * w + x) * 4
                    bytes[i] = 255; bytes[i + 1] = 255; bytes[i + 2] = 255; bytes[i + 3] = 255
                }
            }
        }
        let image = try #require(LayerSeparator.makeImage(bytes, width: w, height: h))
        let analysis = EdgeMapAnalyzer.analyzeFully(image)
        let found = TextRunSweep.sweep(in: analysis.luma).runs
        let result = try #require(LayerSeparator.separateText(image, luma: analysis.luma))
        print("SKIP words on a photograph: \(found.count) run(s) found, "
            + "\(result.pieces.count) separated, \(result.skipped) left in the picture")
        #expect(!found.isEmpty)
        #expect(result.pieces.isEmpty)
        #expect(result.skipped == found.count)
        // And the picture came back untouched, since nothing was taken out of it.
        #expect(result.background === image)
    }

    // MARK: - The boxes

    /// The same capture, taken apart completely: text first, then boxes.
    private static let whole: LayerSeparator.Result? = {
        guard let capture else { return nil }
        return LayerSeparator.separate(capture, luma: analysis.luma)
    }()

    @Test func theBoxesComeOutBesideTheRunsOfText() throws {
        let result = try #require(Self.whole)
        #expect(result.runs.count == 9)
        let boxes = result.boxes
        print("BOXES " + boxes.map {
            "\(Int($0.rect.width))x\(Int($0.rect.height)) at (\(Int($0.rect.minX)),"
                + "\(Int($0.rect.minY))) \($0.image == nil ? "shape" : "picture")"
        }.joined(separator: ", "))
        // On the page: both cards and both buttons. The cards used to be left
        // in the picture because of their shadow; they come out wearing it now.
        let onThePage = boxes.filter { box in
            !boxes.contains { $0.rect != box.rect && $0.rect.contains(box.rect) }
        }
        #expect(onThePage.count == 4)
        #expect(onThePage.contains { $0.rect == CGRect(x: 233, y: 756, width: 248, height: 60) })
        #expect(onThePage.contains { $0.rect == CGRect(x: 64, y: 756, width: 145, height: 60) })
        #expect(onThePage.contains { $0.rect == CGRect(x: 64, y: 148, width: 1312, height: 264) })
        #expect(onThePage.contains { $0.rect == CGRect(x: 64, y: 452, width: 1312, height: 264) })
        // And on the cards: four switches down the right, and the two text
        // fields on the second card, which come out as real rounded rectangles
        // now that they are read against the card rather than against the page.
        let onTheCards = boxes.filter { box in
            boxes.contains { $0.rect != box.rect && $0.rect.contains(box.rect) }
        }
        #expect(onTheCards.count == 6)
        #expect(onTheCards.filter { $0.rect.width == 84 && $0.rect.height == 48 }.count == 4)
        #expect(onTheCards.filter { $0.rect.width == 440 && $0.rect.height == 52 }.count == 2)
        // A box comes out AFTER whatever holds it, so a card is never laid over
        // its own switches.
        for (index, box) in boxes.enumerated() {
            for other in boxes[(index + 1)...] {
                #expect(!other.rect.contains(box.rect),
                        "\(box.rect) came out before the \(other.rect) holding it")
            }
        }
    }

    // MARK: - Text inside a box comes out inside that box

    @Test func eachButtonsLabelComesOutInsideThatButton() throws {
        let result = try #require(Self.whole)
        let tree = result.nested
        func describe(_ nodes: [LayerNesting.Node], _ indent: String) -> [String] {
            nodes.flatMap { node -> [String] in
                let piece = result.pieces[node.index]
                let kind = piece.kind == .text ? "text" : "box"
                return ["\(indent)\(kind) \(Int(piece.rect.width))x\(Int(piece.rect.height))"
                    + " at (\(Int(piece.rect.minX)),\(Int(piece.rect.minY)))"]
                    + describe(node.children, indent + "  ")
            }
        }
        print("TREE\n" + describe(tree, "").joined(separator: "\n"))

        // Five pieces are nobody's child: the heading, the two cards and the
        // two buttons. Everything else sits in one of them — a card holds its
        // three row labels and the switches and fields on it, a button holds
        // its one label.
        #expect(tree.count == 5)
        let holders = tree.filter { !$0.children.isEmpty }
        #expect(holders.count == 4)
        for holder in holders {
            #expect(result.pieces[holder.index].kind == .box)
            let box = result.pieces[holder.index].rect
            let labels = holder.children.filter { result.pieces[$0.index].kind == .text }
            #expect(labels.count == (box.width > 1000 ? 3 : 1))
            for child in holder.children {
                // Everything in it really does sit in it.
                #expect(box.contains(result.pieces[child.index].rect))
            }
        }
        // The cards hold the controls that were sitting on them, three deep
        // with the labels: a card, the things on it, and nothing orphaned.
        let cards = holders.filter { result.pieces[$0.index].rect.width > 1000 }
        #expect(cards.count == 2)
        #expect(cards.flatMap { $0.children }
            .filter { result.pieces[$0.index].kind == .box }.count == 6)
        // The Save Changes label under the blue button, not beside it.
        let blue = try #require(tree.first { result.pieces[$0.index].rect.minX == 233 })
        #expect(Int(result.pieces[blue.children[0].index].rect.minX) == 270)
    }

    @Test func everyPieceIsInExactlyOnePlace() throws {
        let result = try #require(Self.whole)
        func indices(_ nodes: [LayerNesting.Node]) -> [Int] {
            nodes.flatMap { [$0.index] + indices($0.children) }
        }
        let all = indices(result.nested)
        #expect(all.sorted() == Array(result.pieces.indices))
        #expect(Set(all).count == all.count)
    }

    // MARK: - A card brings its shadow with it

    @Test func aCardComesOutWearingTheShadowItHadInThePicture() throws {
        let result = try #require(Self.whole)
        // The cards used to be the one thing on this page the command could not
        // take: what surrounds them is neither one colour nor a straight ramp,
        // it is a soft shadow, and filling that space with any single colour
        // would have left a grey halo of a card that is no longer there.
        #expect(result.skipped == 0)
        let cards = result.boxes.filter { $0.rect.width > 1000 }
        #expect(cards.count == 2)
        let bytes = try #require(LayerSeparator.read(Self.capture!))
        let profile = (411...419).map { "\($0):\(bytes[($0 * 1440 + 700) * 4])" }
        print("SHADOW under the first card, down the page at x=700, the grey runs "
            + profile.joined(separator: " "))
        for card in cards {
            let shadow = try #require(card.shadow)
            print("SHADOW \(Int(card.rect.width))x\(Int(card.rect.height)) at "
                + "(\(Int(card.rect.minX)),\(Int(card.rect.minY))): \(shadow.colorHex) at "
                + String(format: "%.1f%%", shadow.opacity * 100)
                + ", blur \(shadow.radius) px, "
                + "offset (\(shadow.offset.width), \(shadow.offset.height))")
            #expect(shadow.colorHex == "#000000")
            #expect(shadow.kind == .drop)
            #expect(shadow.spread == 0)
            // Straight down, not sideways, and soft rather than a hard edge.
            #expect(abs(shadow.offset.width) <= 0.3)
            #expect(shadow.offset.height >= 1 && shadow.offset.height <= 3)
            #expect(shadow.radius >= 1.5 && shadow.radius <= 3)
            // Around a fifth, which is what a system card's shadow is once it
            // is written as the opacity a renderer would lay down in linear
            // light rather than the darkening a PNG happens to store.
            #expect(shadow.opacity > 0.15 && shadow.opacity < 0.3)
        }
        // Both cards on one page were drawn with one shadow, so both come back
        // with the same one. Two cards wearing two different shadows would look
        // wrong the moment they sat beside each other.
        #expect(cards[0].shadow == cards[1].shadow)
    }

    @Test func theSpaceACardAndItsShadowCameFromIsPlainPage() throws {
        let result = try #require(Self.whole)
        let card = try #require(result.boxes.first { $0.rect.width > 1000 })
        let bytes = try #require(LayerSeparator.read(result.background))
        // The page's own colour, read from a corner nothing was ever near.
        let page = (bytes[(8 * 1440 + 8) * 4], bytes[(8 * 1440 + 8) * 4 + 1],
                    bytes[(8 * 1440 + 8) * 4 + 2])
        var worst = 0
        var seen: Set<String> = []
        // The card's own box plus everything the shadow reached, which on this
        // capture is about seven pixels on every side.
        let grown = card.rect.insetBy(dx: -8, dy: -8)
        for y in Int(grown.minY)..<Int(grown.maxY) {
            for x in Int(grown.minX)..<Int(grown.maxX) {
                let i = (y * 1440 + x) * 4
                seen.insert("\(bytes[i]),\(bytes[i + 1]),\(bytes[i + 2])")
                worst = max(worst, max(abs(Int(bytes[i]) - Int(page.0)),
                                       max(abs(Int(bytes[i + 1]) - Int(page.1)),
                                           abs(Int(bytes[i + 2]) - Int(page.2)))))
            }
        }
        print("PATCH the card's space plus its shadow, \(Int(grown.width))x"
            + "\(Int(grown.height)), reads \(seen.count) distinct colour(s); worst channel "
            + "difference from the page elsewhere: \(worst)/255")
        // Exact: not a trace of the shadow is left where the card used to be.
        #expect(seen.count == 1)
        #expect(worst == 0)
    }

    @Test func aBoxWithARuleUnderItComesOutWithNoShadowRatherThanAWrongOne() throws {
        // The case the whole reading is built to refuse. A dark rule six pixels
        // under a card is exactly what a one-sided falloff test would call a
        // shadow with a big offset, and a card wearing a shadow it never had
        // looks broken in a way a card with no shadow does not. So the box
        // still comes out — nothing about the repair changed — and it comes out
        // flat.
        let w = 640, h = 440
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = 242; bytes[i + 1] = 242; bytes[i + 2] = 247; bytes[i + 3] = 255
        }
        func paint(_ rect: CGRect, _ radius: Double, _ rgb: (Double, Double, Double)) {
            let r = min(radius, min(Double(rect.width), Double(rect.height)) / 2)
            for y in Int(rect.minY - 2)..<Int(rect.maxY + 2) {
                for x in Int(rect.minX - 2)..<Int(rect.maxX + 2) {
                    guard x >= 0, y >= 0, x < w, y < h else { continue }
                    let hx = Double(rect.width) / 2 - r, hy = Double(rect.height) / 2 - r
                    let ax = abs(Double(x) + 0.5 - Double(rect.midX)) - hx
                    let ay = abs(Double(y) + 0.5 - Double(rect.midY)) - hy
                    let d = sqrt(max(ax, 0) * max(ax, 0) + max(ay, 0) * max(ay, 0))
                        + min(max(ax, ay), 0) - r
                    let cover = min(max(0.5 - d, 0), 1)
                    guard cover > 0 else { continue }
                    let i = (y * w + x) * 4
                    for (k, value) in [rgb.0, rgb.1, rgb.2].enumerated() {
                        bytes[i + k] = UInt8(value * cover + Double(bytes[i + k]) * (1 - cover))
                    }
                }
            }
        }
        paint(CGRect(x: 120, y: 310, width: 400, height: 2), 0, (170, 170, 175))
        paint(CGRect(x: 120, y: 100, width: 400, height: 200), 16, (10, 132, 255))
        let image = try #require(LayerSeparator.makeImage(bytes, width: w, height: h))
        let luma = EdgeMapAnalyzer.analyzeFully(image).luma
        let result = try #require(LayerSeparator.separate(image, luma: luma))
        let box = try #require(result.boxes.first)
        print("RULE a card with a dark rule six pixels under it came out "
            + "\(Int(box.rect.width))x\(Int(box.rect.height)) with "
            + "\(box.shadow == nil ? "no shadow" : "a shadow"), which is the right answer")
        #expect(result.boxes.count == 1)
        #expect(box.rect == CGRect(x: 120, y: 100, width: 400, height: 200))
        #expect(box.shadow == nil)
        // And the rule is still in the picture, untouched, since a 2 px strip is
        // nothing a person would point at.
        let after = try #require(LayerSeparator.read(result.background))
        #expect(after[(311 * w + 300) * 4] == 170)
    }

    @Test func aFlatButtonComesOutAsARealShapeWithItsOwnRounding() throws {
        let result = try #require(Self.whole)
        // The Save Changes button. It can only be a shape because its label
        // came out first and the space it left was filled with the button's
        // own blue: read before that, it is a button with words on it.
        let button = try #require(result.boxes.first { $0.rect.minX == 233 })
        guard case .shape(let shape) = button.body else {
            Issue.record("the blue button came out as a picture")
            return
        }
        print("SHAPE the blue button: fill \(shape.fill.hexString), corners "
            + "\(Int(shape.radii.topLeft))/\(Int(shape.radii.topRight))/"
            + "\(Int(shape.radii.bottomRight))/\(Int(shape.radii.bottomLeft)) px, edge "
            + "\(Int(shape.borderWidth)) px")
        #expect(shape.fill.hexString == "#0A84FF")
        #expect(shape.borderWidth == 0)
        #expect(shape.radii == CornerRadii(14))
    }

    @Test func aButtonWithAnEdgeKeepsThatEdge() throws {
        let result = try #require(Self.whole)
        let reset = try #require(result.boxes.first { $0.rect.minX == 64 && $0.rect.minY == 756 })
        guard case .shape(let shape) = reset.body else {
            Issue.record("the Reset button came out as a picture")
            return
        }
        print("SHAPE the Reset button: fill \(shape.fill.hexString), edge "
            + "\(Int(shape.borderWidth)) px of \(shape.borderColor?.hexString ?? "nothing"), "
            + "corners \(Int(shape.radii.topLeft)) px")
        #expect(shape.fill.hexString == "#E9E9ED")
        #expect(shape.borderWidth == 2)
        #expect(shape.borderColor?.hexString == "#CFCFD4")
        #expect(shape.radii == CornerRadii(14))
    }

    @Test func aBoxWithSomethingOnItComesOutAsPixelsAndKeepsThem() throws {
        // A switch: a green track with a white knob in it. Nobody can say what
        // shape that is, so it comes out as pixels — cut to its own rounded
        // outline, with the page it was sitting on left behind and the knob
        // still in it.
        let w = 320, h = 240
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        func paint(_ rect: CGRect, _ radius: Double, _ rgb: (Double, Double, Double)) {
            let r = min(radius, min(Double(rect.width), Double(rect.height)) / 2)
            for y in Int(rect.minY - 2)..<Int(rect.maxY + 2) {
                for x in Int(rect.minX - 2)..<Int(rect.maxX + 2) {
                    guard x >= 0, y >= 0, x < w, y < h else { continue }
                    let hx = Double(rect.width) / 2 - r, hy = Double(rect.height) / 2 - r
                    let ax = abs(Double(x) + 0.5 - Double(rect.midX)) - hx
                    let ay = abs(Double(y) + 0.5 - Double(rect.midY)) - hy
                    let d = sqrt(max(ax, 0) * max(ax, 0) + max(ay, 0) * max(ay, 0))
                        + min(max(ax, ay), 0) - r
                    let cover = min(max(0.5 - d, 0), 1)
                    guard cover > 0 else { continue }
                    let i = (y * w + x) * 4
                    for (k, value) in [rgb.0, rgb.1, rgb.2].enumerated() {
                        bytes[i + k] = UInt8(value * cover + Double(bytes[i + k]) * (1 - cover))
                    }
                }
            }
        }
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = 242; bytes[i + 1] = 242; bytes[i + 2] = 247; bytes[i + 3] = 255
        }
        paint(CGRect(x: 110, y: 90, width: 86, height: 46), 23, (52, 199, 89))
        paint(CGRect(x: 152, y: 93, width: 40, height: 40), 20, (255, 255, 255))
        let image = try #require(LayerSeparator.makeImage(bytes, width: w, height: h))
        let analysis = EdgeMapAnalyzer.analyzeFully(image)
        let result = try #require(LayerSeparator.separate(image, luma: analysis.luma))
        #expect(result.boxes.count == 1)
        let piece = try #require(result.boxes.first?.image)
        // Its rounded ends are the page, and the page did not come with it.
        #expect(pixel(piece, 0, 0).a == 0)
        #expect(pixel(piece, piece.width - 1, piece.height - 1).a == 0)
        // The track did, and so did the knob sitting on it.
        var green = 0, white = 0
        let out = try #require(LayerSeparator.read(piece))
        for i in stride(from: 0, to: out.count, by: 4) where out[i + 3] == 255 {
            if out[i + 1] > 150, out[i] < 120 { green += 1 }
            if out[i] > 240, out[i + 1] > 240, out[i + 2] > 240 { white += 1 }
        }
        print("CUT the switch is \(piece.width)x\(piece.height): \(green) pixels of track "
            + "and \(white) of knob, and its corners are see-through")
        #expect(green > 500)
        #expect(white > 500)
    }

    // MARK: - No holes under a box

    @Test func everyBoxLeavesItsSpaceMatchingWhatSurroundsIt() throws {
        let result = try #require(Self.whole)
        let patched = result.background
        let bytes = try #require(LayerSeparator.read(patched))
        var report: [String] = []
        for box in result.boxes {
            // What is just outside it, four pixels clear.
            let outside = pixel(patched, Int(box.rect.minX) - 4, Int(box.rect.midY))
            var worst = 0
            for y in Int(box.rect.minY)..<Int(box.rect.maxY) {
                for x in Int(box.rect.minX)..<Int(box.rect.maxX) {
                    let i = (y * patched.width + x) * 4
                    worst = max(worst, abs(Int(bytes[i]) - outside.r))
                    worst = max(worst, abs(Int(bytes[i + 1]) - outside.g))
                    worst = max(worst, abs(Int(bytes[i + 2]) - outside.b))
                }
            }
            report.append("\(Int(box.rect.width))x\(Int(box.rect.height)): \(worst)")
            #expect(worst <= 1, "the space a box came out of does not match the page")
        }
        print("PATCH worst channel difference between a box's filled space and the page "
            + "4 px to its left, out of 255 — \(report.joined(separator: ", "))")
    }

    @Test func nothingIsSeparatedTwiceAndNoSpaceIsFilledTwice() throws {
        let result = try #require(Self.whole)
        // No two repairs overlap, so no pixel of the picture was painted by one
        // piece and then painted again by another.
        for (i, a) in result.patched.enumerated() {
            for b in result.patched[(i + 1)...] {
                #expect(!a.intersects(b), "two repairs overlap: \(a) and \(b)")
            }
        }
        // And no two pieces claim the same pixels: a run of text is either
        // clear of every box or wholly inside one, which is a label ON a card
        // and not a second copy of it.
        for run in result.runs {
            for box in result.boxes where run.rect.intersects(box.rect) {
                #expect(box.rect.contains(run.rect))
            }
        }
        print("TWICE \(result.patched.count) repairs, none overlapping, for "
            + "\(result.pieces.count) pieces")
    }

    @Test func runningItTwiceOnTheWholePictureFindsNothingLeft() throws {
        let result = try #require(Self.whole)
        let again = EdgeMapAnalyzer.analyzeFully(result.background)
        let second = try #require(LayerSeparator.separate(result.background, luma: again.luma))
        print("TWICE the repaired picture offers \(second.runs.count) runs and "
            + "\(second.boxes.count) boxes")
        #expect(second.pieces.isEmpty)
    }

    // MARK: - A box on a gradient, and a box it cannot read

    /// A drawn capture: a page painted as a smooth ramp with two boxes sitting
    /// on it, one square and one rounded. Drawn rather than captured because
    /// the point is the RAMP, and no real screenshot of one has a known answer.
    private func rampedScene(boxes: [(CGRect, CGFloat)]) throws -> CGImage {
        let w = 420, h = 320
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        func set(_ x: Int, _ y: Int, _ r: Double, _ g: Double, _ b: Double) {
            guard x >= 0, y >= 0, x < w, y < h else { return }
            let i = (y * w + x) * 4
            bytes[i] = UInt8(min(max(r, 0), 1) * 255)
            bytes[i + 1] = UInt8(min(max(g, 0), 1) * 255)
            bytes[i + 2] = UInt8(min(max(b, 0), 1) * 255)
            bytes[i + 3] = 255
        }
        func page(_ y: Int) -> Double { 0.35 + 0.4 * Double(y) / Double(h) }
        for y in 0..<h {
            for x in 0..<w { set(x, y, page(y), page(y), page(y) * 0.98) }
        }
        for (rect, radius) in boxes {
            let r = min(radius, min(rect.width, rect.height) / 2)
            for y in Int(rect.minY - 2)..<Int(rect.maxY + 2) {
                for x in Int(rect.minX - 2)..<Int(rect.maxX + 2) {
                    let cx = rect.midX, cy = rect.midY
                    let hx = rect.width / 2 - r, hy = rect.height / 2 - r
                    let dx = max(abs(CGFloat(x) + 0.5 - cx) - hx, 0)
                    let dy = max(abs(CGFloat(y) + 0.5 - cy) - hy, 0)
                    let inside = min(max(abs(CGFloat(x) + 0.5 - cx) - hx,
                                         abs(CGFloat(y) + 0.5 - cy) - hy), 0)
                    let d = Double(sqrt(dx * dx + dy * dy) + inside - r)
                    let cover = min(max(0.5 - d, 0), 1)
                    guard cover > 0 else { continue }
                    let back = page(y)
                    set(x, y, 0.05 * cover + back * (1 - cover),
                        0.48 * cover + back * (1 - cover),
                        1.0 * cover + back * 0.98 * (1 - cover))
                }
            }
        }
        return try #require(LayerSeparator.makeImage(bytes, width: w, height: h))
    }

    @Test func aBoxOnARampLeavesTheRampRunningThroughWhereItWas() throws {
        let flat = CGRect(x: 60, y: 80, width: 140, height: 60)
        let round = CGRect(x: 240, y: 180, width: 120, height: 56)
        let scene = try rampedScene(boxes: [(flat, 0), (round, 16)])
        let analysis = EdgeMapAnalyzer.analyzeFully(scene)
        let result = try #require(LayerSeparator.separate(scene, luma: analysis.luma))
        #expect(result.boxes.count == 2)
        // Both are one flat colour on a page that is not, so both are shapes,
        // and the rounded one keeps its rounding.
        let radii = result.boxes.compactMap { piece -> CornerRadii? in
            guard case .shape(let shape) = piece.body else { return nil }
            return shape.radii
        }
        print("RAMP \(result.boxes.count) boxes, roundings \(radii)")
        #expect(radii.count == 2)
        #expect(radii.contains(.none))
        #expect(radii.contains { abs($0.topLeft - 16) <= 1 && abs($0.bottomRight - 16) <= 1 })

        // And the ramp runs on through where each one was: every row of the
        // filled space matches the page at that same height, rather than one
        // flat colour smeared over it.
        let bytes = try #require(LayerSeparator.read(result.background))
        var worst = 0
        for box in result.boxes {
            for y in Int(box.rect.minY)..<Int(box.rect.maxY) {
                let beside = pixel(result.background, Int(box.rect.minX) - 6, y)
                for x in Int(box.rect.minX)..<Int(box.rect.maxX) {
                    let i = (y * result.background.width + x) * 4
                    worst = max(worst, abs(Int(bytes[i]) - beside.r))
                    worst = max(worst, abs(Int(bytes[i + 1]) - beside.g))
                    worst = max(worst, abs(Int(bytes[i + 2]) - beside.b))
                }
            }
        }
        print("RAMP worst channel difference between a filled space and the ramp beside it "
            + "at the same height: \(worst)/255")
        #expect(worst <= 2)
    }

    @Test func aBoxOnAPhotographIsLeftInThePicture() throws {
        // Rule three again, for boxes. There is no page here for anything to be
        // sitting on, so nothing can be said about what is behind the box, and
        // nothing is claimed.
        let w = 360, h = 260
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let shade = 110 + 40 * sin(Double(x) / 7) * cos(Double(y) / 5)
                let i = (y * w + x) * 4
                bytes[i] = UInt8(shade)
                bytes[i + 1] = UInt8(shade * 0.8)
                bytes[i + 2] = UInt8(shade * 0.6)
                bytes[i + 3] = 255
            }
        }
        for y in 90..<150 {
            for x in 120..<260 {
                let i = (y * w + x) * 4
                bytes[i] = 12; bytes[i + 1] = 122; bytes[i + 2] = 255; bytes[i + 3] = 255
            }
        }
        let image = try #require(LayerSeparator.makeImage(bytes, width: w, height: h))
        let analysis = EdgeMapAnalyzer.analyzeFully(image)
        let result = try #require(LayerSeparator.separate(image, luma: analysis.luma))
        print("SKIP a box on a photograph: \(result.boxes.count) boxes separated")
        #expect(result.boxes.isEmpty)
        #expect(result.background === image)
    }

    // MARK: - How long it takes

    /// The fastest of three passes, since the first pays for a cold cache and
    /// what a person feels is the ordinary one.
    private func best(_ runs: Int = 3, _ work: () -> Void) -> TimeInterval {
        var quickest = TimeInterval.greatestFiniteMagnitude
        for _ in 0..<runs {
            let started = Date()
            work()
            quickest = min(quickest, Date().timeIntervalSince(started))
        }
        return quickest
    }

    @Test func separatingTheCaptureIsQuickEnoughToFeelLikeACommand() throws {
        let capture = try #require(Self.capture)
        let megapixels = Double(capture.width * capture.height) / 1_000_000
        let sweep = best { _ = TextRunSweep.sweep(in: Self.analysis.luma) }
        let text = best { _ = LayerSeparator.separateText(capture, luma: Self.analysis.luma) }
        let whole = best { _ = LayerSeparator.separate(capture, luma: Self.analysis.luma) }
        print(String(format: "PERF %.1f megapixels: text sweep %.0f ms, text %.0f ms, "
                     + "text and boxes %.0f ms (%.0f ms per megapixel)",
                     megapixels, sweep * 1000, text * 1000, whole * 1000,
                     whole * 1000 / megapixels))
    }

    /// The number the perf note quotes, on a capture the size of a real retina
    /// screen. Off by default: it is seconds of work in a debug build, and the
    /// everyday suite runs debug. `PHOTONZ_PERF=1 Scripts/test.sh -c release
    /// --filter separatingATwelveMegapixel` is how it is read.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_PERF"] == "1"))
    func separatingATwelveMegapixelCaptureIsUnderASecond() throws {
        let capture = try #require(Self.capture)
        // The fixture tiled out to 4032 x 3024 — 12.2 megapixels, a 2x capture
        // of a 16 inch screen, with twelve times as much text in it as any real
        // screenshot would have.
        let w = 4032, h = 3024
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        for row in 0..<4 {
            for column in 0..<3 {
                context.draw(capture, in: CGRect(x: column * capture.width,
                                                 y: row * capture.height,
                                                 width: capture.width, height: capture.height))
            }
        }
        let big = try #require(context.makeImage())
        // The brightness field itself, which is the one pass this shares with
        // the measure tool and pays for only once per picture.
        let reading = best(2) { _ = EdgeMapAnalyzer.analyzeFully(big) }
        let analysis = EdgeMapAnalyzer.analyzeFully(big)
        let sweep = best(2) { _ = TextRunSweep.sweep(in: analysis.luma) }
        let text = best(2) { _ = LayerSeparator.separateText(big, luma: analysis.luma) }
        let whole = best(2) { _ = LayerSeparator.separate(big, luma: analysis.luma) }
        let result = try #require(LayerSeparator.separate(big, luma: analysis.luma))
        print(String(format: "PERF12 %d x %d (%.1f megapixels), %d runs and %d boxes: reading "
                     + "the picture %.0f ms, text sweep %.0f ms, text %.0f ms, "
                     + "text and boxes %.0f ms", w, h, Double(w * h) / 1_000_000,
                     result.runs.count, result.boxes.count,
                     reading * 1000, sweep * 1000, text * 1000, whole * 1000))
    }
}

/// A row inside a card inside a screen: the three levels the fixture cannot
/// show, because its own cards paint their rows the same white as the card and
/// so never draw a row there is anything to find.
///
/// Drawn, and drawn the way real UI is painted: a page colour, a card on it, a
/// row on the card, a label on the row, antialiasing down every rounded edge.
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("A row inside a card")
struct SeparatedRowInsideACardTests {

    /// A picture being painted, in premultiplied sRGB bytes.
    private struct Scene {
        let width: Int
        let height: Int
        var bytes: [UInt8]

        init(width: Int, height: Int, background: (Double, Double, Double)) {
            self.width = width
            self.height = height
            bytes = [UInt8](repeating: 0, count: width * height * 4)
            for i in stride(from: 0, to: bytes.count, by: 4) {
                bytes[i] = UInt8(background.0)
                bytes[i + 1] = UInt8(background.1)
                bytes[i + 2] = UInt8(background.2)
                bytes[i + 3] = 255
            }
        }

        /// A rounded rectangle with the antialiasing a real renderer leaves.
        mutating func rounded(_ rect: CGRect, radius: Double,
                              _ rgb: (Double, Double, Double)) {
            let r = min(radius, min(Double(rect.width), Double(rect.height)) / 2)
            for y in Int(rect.minY - 2)..<Int(rect.maxY + 2) {
                for x in Int(rect.minX - 2)..<Int(rect.maxX + 2) {
                    guard x >= 0, y >= 0, x < width, y < height else { continue }
                    let hx = Double(rect.width) / 2 - r, hy = Double(rect.height) / 2 - r
                    let ax = abs(Double(x) + 0.5 - Double(rect.midX)) - hx
                    let ay = abs(Double(y) + 0.5 - Double(rect.midY)) - hy
                    let d = sqrt(max(ax, 0) * max(ax, 0) + max(ay, 0) * max(ay, 0))
                        + min(max(ax, ay), 0) - r
                    let cover = min(max(0.5 - d, 0), 1)
                    guard cover > 0 else { continue }
                    let i = (y * width + x) * 4
                    for (k, value) in [rgb.0, rgb.1, rgb.2].enumerated() {
                        bytes[i + k] = UInt8(value * cover + Double(bytes[i + k]) * (1 - cover))
                    }
                }
            }
        }

        /// A line of "words": stems with daylight between them, most of them x
        /// height, two reaching the ascender and the last dropping a descender,
        /// which is what stops a row of bars reading as a box.
        @discardableResult
        mutating func words(at origin: CGPoint, letters: Int, height: Int,
                            _ rgb: (Double, Double, Double)) -> CGRect {
            let x = Int(origin.x), y = Int(origin.y)
            let stem = 3, spacing = 6
            let xHeight = max(1, height / 4), descender = max(2, height / 5)
            for i in 0..<letters {
                let top = (i == 0 || i == 3) ? y : y + xHeight
                let bottom = i == letters - 1 ? y + height + descender : y + height
                rounded(CGRect(x: x + i * spacing, y: top, width: stem, height: bottom - top),
                        radius: 0, rgb)
            }
            return CGRect(x: x, y: y, width: (letters - 1) * spacing + stem,
                          height: height + descender)
        }

        var image: CGImage? { LayerSeparator.makeImage(bytes, width: width, height: height) }
    }

    private static let page = (242.0, 242.0, 247.0)
    private static let card = (255.0, 255.0, 255.0)
    private static let row = (233.0, 233.0, 237.0)
    private static let ink = (28.0, 28.0, 30.0)

    /// The card, the row on it, the label on the row.
    private static let scene: Scene = {
        var scene = Scene(width: 600, height: 400, background: page)
        scene.rounded(CGRect(x: 40, y: 40, width: 520, height: 260), radius: 12, card)
        scene.rounded(CGRect(x: 70, y: 90, width: 460, height: 90), radius: 10, row)
        scene.words(at: CGPoint(x: 110, y: 118), letters: 14, height: 24, ink)
        return scene
    }()

    private static let separated: LayerSeparator.Result? = {
        guard let image = scene.image else { return nil }
        return LayerSeparator.separate(image, luma: EdgeMapAnalyzer.analyzeFully(image).luma)
    }()

    private func describe(_ nodes: [LayerNesting.Node], _ result: LayerSeparator.Result,
                          _ indent: String) -> [String] {
        nodes.flatMap { node -> [String] in
            let piece = result.pieces[node.index]
            return ["\(indent)\(piece.kind == .text ? "text" : "box") "
                + "\(Int(piece.rect.width))x\(Int(piece.rect.height)) at "
                + "(\(Int(piece.rect.minX)),\(Int(piece.rect.minY)))"]
                + describe(node.children, result, indent + "  ")
        }
    }

    @Test func aRowOnACardComesOutThreeDeep() throws {
        let result = try #require(Self.separated)
        print("TREE\n" + describe(result.nested, result, "").joined(separator: "\n"))
        #expect(result.pieces.count == 3)
        #expect(LayerNesting.depth(of: result.nested) == 3)

        let card = try #require(result.nested.first)
        #expect(result.pieces[card.index].rect == CGRect(x: 40, y: 40, width: 520, height: 260))
        let row = try #require(card.children.first)
        #expect(card.children.count == 1)
        #expect(result.pieces[row.index].rect == CGRect(x: 70, y: 90, width: 460, height: 90))
        // Picking the row up takes its label and nothing else.
        #expect(row.children.count == 1)
        let label = result.pieces[row.children[0].index]
        #expect(label.kind == .text)
        #expect(CGRect(x: 70, y: 90, width: 460, height: 90).contains(label.rect))
    }

    @Test func theCardHasNoHoleWhereTheRowWas() throws {
        let result = try #require(Self.separated)
        let card = try #require(result.boxes.first { $0.rect.width == 520 })
        let piece = try #require(card.image)
        let bytes = try #require(LayerSeparator.read(piece))
        // Right through the middle of where the row was, in the card's own
        // coordinates: every pixel is the card's white, fully opaque.
        var worst = 0, seen = 0
        for y in Int(90 - card.rect.minY)..<Int(180 - card.rect.minY) {
            for x in Int(70 - card.rect.minX)..<Int(530 - card.rect.minX) {
                let i = (y * piece.width + x) * 4
                #expect(bytes[i + 3] == 255)
                for channel in 0..<3 { worst = max(worst, abs(Int(bytes[i + channel]) - 255)) }
                seen += 1
            }
        }
        print("HOLE the card's \(seen) pixels where the row was: worst channel "
            + "difference from its own white is \(worst)/255")
        #expect(worst <= 1)
    }

    @Test func theRowIsTheRowAndNotARectangleOfCard() throws {
        let result = try #require(Self.separated)
        let row = try #require(result.boxes.first { $0.rect.width == 460 })
        // It came out as a real rounded rectangle, read against the card rather
        // than against a page it cannot see.
        guard case .shape(let shape) = row.body else {
            Issue.record("the row came out as a picture")
            return
        }
        print("SHAPE the row: fill \(shape.fill.hexString), corners "
            + "\(Int(shape.radii.topLeft)) px, edge \(Int(shape.borderWidth)) px")
        #expect(shape.fill.hexString == "#E9E9ED")
        #expect(abs(shape.radii.topLeft - 10) <= 1)
        #expect(shape.borderWidth == 0)
    }

    @Test func theSpaceTheCardCameFromIsPlainPage() throws {
        let result = try #require(Self.separated)
        let bytes = try #require(LayerSeparator.read(result.background))
        var worst = 0
        for y in 38..<302 {
            for x in 38..<562 {
                let i = (y * result.background.width + x) * 4
                worst = max(worst, abs(Int(bytes[i]) - 242))
                worst = max(worst, abs(Int(bytes[i + 1]) - 242))
                worst = max(worst, abs(Int(bytes[i + 2]) - 247))
            }
        }
        print("PATCH the card's whole space reads within \(worst)/255 of the page")
        #expect(worst <= 1)
    }

    @Test func theCeilingIsSpentOnTheCardsBeforeWhatIsOnThem() throws {
        // Thirty two cards, each with one control on it: sixty four things and
        // room for thirty. Every slot goes to a card, because a screenshot with
        // more cards than the ceiling allows should come apart into cards and
        // not into some cards plus the controls off whichever one was biggest.
        var scene = Scene(width: 680, height: 360, background: Self.page)
        for row in 0..<4 {
            for column in 0..<8 {
                let x = 20 + column * 80, y = 20 + row * 80
                scene.rounded(CGRect(x: x, y: y, width: 60, height: 60), radius: 10, Self.card)
                scene.rounded(CGRect(x: x + 15, y: y + 15, width: 30, height: 30),
                              radius: 6, Self.row)
            }
        }
        let image = try #require(scene.image)
        let result = try #require(LayerSeparator.separate(
            image, luma: EdgeMapAnalyzer.analyzeFully(image).luma))
        print("CEILING \(result.boxes.count) boxes came out of 32 cards with a control on "
            + "each, \(result.crowded) left in the picture")
        #expect(result.boxes.count == SeparateBudget.maxBoxes)
        #expect(result.boxes.allSatisfy { $0.rect.width == 60 })
        #expect(result.nested.allSatisfy { $0.children.isEmpty })
        #expect(result.left == 64 - SeparateBudget.maxBoxes)
    }

    @Test func aCardTheFrameCutStaysInThePictureButTheRowOnItComesOut() throws {
        // The card runs off the right edge, so the picture cut it in half and
        // its real shape is not in there: it is never handed back as a layer.
        //
        // It is also big and full of holes, which is what scenery looks like —
        // something a person sees straight THROUGH to what is sitting on it —
        // so the row is read against the card's own paint and does come out.
        // That is the change: this used to give back nothing at all, because a
        // piece the frame cut took everything on it down with it.
        //
        // The old reason for holding the row back was that lifting it would
        // leave a hole in a card nobody could fill. That stopped being true
        // when the card became background: the space repairs to the card's own
        // white, which is what the last check here is for.
        var scene = Scene(width: 600, height: 400, background: Self.page)
        scene.rounded(CGRect(x: 40, y: 40, width: 620, height: 260), radius: 12, Self.card)
        scene.rounded(CGRect(x: 70, y: 90, width: 460, height: 90), radius: 10, Self.row)
        let image = try #require(scene.image)
        let result = try #require(LayerSeparator.separate(
            image, luma: EdgeMapAnalyzer.analyzeFully(image).luma))
        print("CUT \(result.boxes.count) boxes came out of a card the frame cut in half")
        #expect(result.boxes.map(\.rect) == [CGRect(x: 70, y: 90, width: 460, height: 90)])

        let bytes = try #require(LayerSeparator.read(result.background))
        var worst = 0
        for y in 95..<175 {
            for x in 75..<525 {
                let i = (y * result.background.width + x) * 4
                for channel in 0..<3 { worst = max(worst, abs(Int(bytes[i + channel]) - 255)) }
            }
        }
        print("PATCH the row's space on the cut card reads within \(worst)/255 of the card")
        #expect(worst <= 1)
    }
}

/// A dark inspector, cropped to its four number fields
/// (`Fixtures/dark-fields-2x.png`, a 502x144 2x crop of this app's own
/// inspector panel).
///
/// It is here because a dark panel breaks an assumption a light one never
/// does. The field's own edge is painted eight levels off the panel behind it,
/// and somewhere down its rounded corner the step between the two is under
/// `BoxSweep.colorTolerance`, so the edge chains into the PANEL's colour region
/// and counts as background. The field's island stops inside its own edge, and
/// the band read just outside the field to find out what is behind it is one
/// row of the field's own edge. Refused as "not one flat colour", three of the
/// four fields stayed in the picture.
///
/// Full design: `docs/design/separate-into-layers.md`, "Stepping off the box's
/// own edge".
@Suite("Four fields on a dark panel")
struct SeparatedDarkFieldsTests {

    private static let capture: CGImage? = {
        guard let url = Bundle.module.url(forResource: "Fixtures/dark-fields-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }()

    private static let separated: LayerSeparator.Result? = {
        guard let capture else { return nil }
        return LayerSeparator.separate(capture, luma: EdgeMapAnalyzer.analyzeFully(capture).luma,
                                       gap: Double(AlignmentScan.visibleGap) * 2,
                                       minElement: 20)
    }()

    @Test func allFourFieldsComeOut() throws {
        let result = try #require(Self.separated)
        print("FIELDS \(result.boxes.count) of 4 fields came out, \(result.left) left: "
            + result.boxes.map { "\(Int($0.rect.width))x\(Int($0.rect.height)) at "
                + "(\(Int($0.rect.minX)),\(Int($0.rect.minY)))" }.joined(separator: ", "))
        // Four fields, two on each row, each about 195 by 44.
        #expect(result.boxes.count == 4)
        #expect(result.boxes.allSatisfy { $0.rect.width > 180 && $0.rect.width < 210 })
        #expect(result.boxes.allSatisfy { $0.rect.height > 38 && $0.rect.height < 50 })
        #expect(Set(result.boxes.map { Int($0.rect.minY / 40) }).count == 2)
    }

    @Test func theSpaceEachFieldCameFromIsThePanelAgain() throws {
        let result = try #require(Self.separated)
        let bytes = try #require(LayerSeparator.read(result.background))
        let w = result.background.width
        var worst = 0
        for box in result.boxes {
            // The WHOLE footprint and two pixels past it, not just the middle.
            // The field's own edge is a little outside the rect the sweep
            // reports, because the edge is what the sweep mistook for the
            // panel, and a repair that stops short of it leaves a hairline
            // rectangle where the field had been.
            for y in Int(box.rect.minY) - 2..<Int(box.rect.maxY) + 2 {
                for x in Int(box.rect.minX) - 2..<Int(box.rect.maxX) + 2 {
                    let i = (y * w + x) * 4
                    worst = max(worst, abs(Int(bytes[i]) - 38))
                    worst = max(worst, abs(Int(bytes[i + 1]) - 45))
                    worst = max(worst, abs(Int(bytes[i + 2]) - 48))
                }
            }
        }
        print("PATCH every field's space reads within \(worst)/255 of the panel")
        #expect(worst <= 3)
    }
}
