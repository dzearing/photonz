import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// An icon that moves, leaving the app as a file that still moves
/// (`docs/design/svg-export.md`).
@Suite("An animated icon leaves the app as an animated SVG")
struct SVGMotionExportTests {

    // MARK: - Things to export

    /// A plain square, the smallest shape worth animating.
    static func square(_ size: CGFloat = 24) -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: size, y: 0)),
            PathAnchor(point: CGPoint(x: size, y: size)),
            PathAnchor(point: CGPoint(x: 0, y: size))
        ], isClosed: true, paint: Paint(hex: "#112233"), strokeWidth: 2,
           fill: Paint(hex: "#AABBCC"))
    }

    static func layer(_ motions: [LayerMotion],
                      at origin: CGPoint = CGPoint(x: 8, y: 10),
                      size: CGFloat = 24) -> Layer {
        var layer = Layer(name: "Bell", content: .path(square(size)),
                          frame: CGRect(origin: origin, size: CGSize(width: size, height: size)))
        layer.motions = motions
        return layer
    }

    static func document(_ layers: [Layer], cycleMS: Int? = nil) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 48, height: 48),
                                       layers: layers)
        document.motionCycleMS = cycleMS
        return document
    }

    /// The file, with the document's own lap written into it.
    static func moving(_ document: PhotonzDocument) -> String {
        SVGExport.write(document,
                        animation: .moving(cycleMS: document.motionCycleLengthMS)).text
    }

    static func turn(_ from: Double, _ to: Double,
                     startMS: Int = 0, durationMS: Int = 900,
                     curve: EasingCurve = .linear,
                     repeats: MotionRepeat = .forever,
                     pivot: MotionPivot? = .centre) -> LayerMotion {
        LayerMotion(property: .rotation, from: .number(from), to: .number(to),
                    timing: MotionTiming(startMS: startMS, durationMS: durationMS),
                    curve: curve, repeats: repeats, pivot: pivot)
    }

    /// Every `values="…"` list in the file, in the order they appear.
    static func valueLists(_ svg: String) -> [[String]] {
        svg.split(separator: "\n").compactMap { line -> [String]? in
            guard let range = line.range(of: " values=\"") else { return nil }
            let rest = line[range.upperBound...]
            guard let close = rest.firstIndex(of: "\"") else { return nil }
            return rest[..<close].split(separator: ";").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }
    }

    static func attribute(_ name: String, in svg: String) -> String? {
        guard let range = svg.range(of: " \(name)=\"") else { return nil }
        let rest = svg[range.upperBound...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<close])
    }

    // MARK: - Nothing moving is exactly what it was

    @Test("A document with nothing moving writes the still file it always did")
    func stillDocumentIsUntouched() {
        let document = Self.document([Self.layer([])])
        let still = SVGExport.write(document).text
        #expect(Self.moving(document) == still)
        #expect(!still.contains("animate"))
    }

    @Test("A motion switched off leaves the file still")
    func aMotionSwitchedOffIsNotWritten() {
        var motion = Self.turn(-12, 12)
        motion.isOn = false
        let document = Self.document([Self.layer([motion])])
        #expect(Self.moving(document) == SVGExport.write(document).text)
    }

    // MARK: - The motion itself

    @Test("A turn goes out as a rotation the file plays itself")
    func aTurnIsWrittenAsARotation() {
        let document = Self.document([Self.layer([Self.turn(-12, 12)])])
        let svg = Self.moving(document)
        #expect(svg.contains("<animateTransform attributeName=\"transform\" type=\"rotate\""))
        #expect(Self.attribute("dur", in: svg) == "900ms")
        #expect(Self.attribute("repeatCount", in: svg) == "indefinite")
        // Nothing about an icon needs a bitmap in it.
        #expect(!svg.contains("data:image"))
    }

    @Test("A turn swings about the point the layer hangs from")
    func aTurnUsesItsPivot() {
        let hanging = Self.turn(-12, 12, pivot: MotionPivot(unit: CGPoint(x: 0.5, y: 0)))
        let document = Self.document([Self.layer([hanging])])
        let values = Self.valueLists(Self.moving(document))
        // The mount is the top middle of the 24pt box, said where the layer
        // sits: the groups that animate sit outside the one that places it.
        #expect(values.first?.first == "-12 20 10")
        #expect(values.first?.last == "12 20 10")
    }

    @Test("A fade goes out as opacity, and the layer stops carrying its own")
    func aFadeIsWrittenAsOpacity() {
        let fade = LayerMotion(property: .opacity, from: .number(100), to: .number(0),
                               timing: MotionTiming(startMS: 0, durationMS: 600),
                               curve: .linear, repeats: .forever)
        var moving = Self.layer([fade])
        moving.style.opacity = 0.5
        let svg = Self.moving(Self.document([moving]))
        #expect(svg.contains("<animate attributeName=\"opacity\""))
        #expect(Self.valueLists(svg).first == ["1", "0"])
        // The still value would multiply with the animated one and fade it twice.
        #expect(!svg.contains("opacity=\"0.5\""))
    }

    @Test("A slide goes out as a move from where it was drawn")
    func aSlideIsWrittenAsATranslate() {
        let slide = LayerMotion(property: .position,
                                from: .point(CGPoint(x: 8, y: 10)),
                                to: .point(CGPoint(x: 8, y: 2)),
                                timing: MotionTiming(startMS: 0, durationMS: 600),
                                curve: .linear, repeats: .forever)
        let svg = Self.moving(Self.document([Self.layer([slide])]))
        #expect(svg.contains("type=\"translate\""))
        #expect(Self.valueLists(svg).first == ["0 0", "0 -8"])
    }

    @Test("A grow goes out as a scale about the middle of the layer")
    func aGrowIsWrittenAsAScale() {
        let grow = LayerMotion(property: .scale, from: .number(100), to: .number(200),
                               timing: MotionTiming(startMS: 0, durationMS: 600),
                               curve: .linear, repeats: .forever)
        let svg = Self.moving(Self.document([Self.layer([grow])]))
        #expect(svg.contains("type=\"scale\""))
        #expect(Self.valueLists(svg).first == ["1 1", "2 2"])
        // Scaling about the middle is a step out to it and back again.
        #expect(svg.contains("translate(20 22)"))
        #expect(svg.contains("translate(-20 -22)"))
    }

    @Test("A colour change is inherited, so the shape stops stating its own fill")
    func aColourChangeIsInherited() {
        let repaint = LayerMotion(property: .color, from: .color("#AABBCC"),
                                  to: .color("#FF0000"),
                                  timing: MotionTiming(startMS: 0, durationMS: 600),
                                  curve: .linear, repeats: .forever)
        let svg = Self.moving(Self.document([Self.layer([repaint])]))
        #expect(svg.contains("<animate attributeName=\"fill\""))
        #expect(Self.valueLists(svg).first == ["#AABBCC", "#FF0000"])
        // The shape stops stating its own fill and inherits the animated one,
        // while the group keeps the still colour for a host that strips the
        // animation out.
        let shape = svg.split(separator: "\n").first { $0.contains("<path ") } ?? ""
        #expect(!shape.contains("fill=\"#"))
        #expect(svg.contains("<g fill=\"#AABBCC\">"))
        // The line round it is nothing to do with the inside.
        #expect(shape.contains("stroke=\"#112233\""))
    }

    @Test("A line that thickens goes out as a stroke width")
    func aLineWidthChangeIsWritten() {
        let thicken = LayerMotion(property: .strokeWidth, from: .number(2), to: .number(4),
                                  timing: MotionTiming(startMS: 0, durationMS: 600),
                                  curve: .linear, repeats: .forever)
        let svg = Self.moving(Self.document([Self.layer([thicken])]))
        #expect(svg.contains("<animate attributeName=\"stroke-width\""))
        #expect(Self.valueLists(svg).first == ["2", "4"])
    }

    @Test("A motion on a layer inside a group is found")
    func aMotionInsideAGroupIsFound() {
        let inner = Self.layer([Self.turn(-12, 12)], at: CGPoint(x: 2, y: 2))
        var group = Layer(name: "Bell", content: .group(GroupContent(children: [inner])),
                          frame: CGRect(x: 4, y: 4, width: 0, height: 0))
        group.motions = []
        let svg = Self.moving(Self.document([group]))
        #expect(svg.contains("type=\"rotate\""))
    }

    // MARK: - Milliseconds on screen, percentages in the file

    @Test("A lag is written as a fraction of the lap, not as milliseconds")
    func aLateStartIsAFractionOfTheLap() {
        let late = Self.turn(-17, 17, startMS: 90, durationMS: 900)
        let document = Self.document([Self.layer([late])], cycleMS: 1000)
        let svg = Self.moving(document)
        #expect(Self.attribute("dur", in: svg) == "1000ms")
        let keyTimes = Self.attribute("keyTimes", in: svg)?
            .split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(keyTimes?.first == "0")
        #expect(keyTimes?.contains("0.09") == true)
        #expect(keyTimes?.last == "1")
        // It holds where it was drawn until its turn comes.
        #expect(Self.valueLists(svg).first?.prefix(2).allSatisfy { $0 == "-17 20 22" } == true)
    }

    @Test("Everything in one drawing shares one lap, so nothing drifts apart")
    func everyMotionSharesTheLap() {
        let bell = Self.layer([Self.turn(-12, 12, durationMS: 900)],
                              at: CGPoint(x: 0, y: 0))
        let knob = Self.layer([Self.turn(-17, 17, startMS: 90, durationMS: 900)],
                              at: CGPoint(x: 24, y: 0))
        let document = Self.document([bell, knob])
        let svg = Self.moving(document)
        let durations = svg.split(separator: "\n")
            .filter { $0.contains("<animate") }
            .compactMap { Self.attribute("dur", in: String($0)) }
        #expect(durations.count == 2)
        #expect(Set(durations).count == 1)
    }

    // MARK: - Repeats

    @Test("Playing once stops where it landed")
    func playingOnceFreezes() {
        let once = Self.turn(0, 90, repeats: .once)
        let svg = Self.moving(Self.document([Self.layer([once])]))
        #expect(Self.attribute("repeatCount", in: svg) == "1")
        #expect(Self.attribute("fill", in: svg) == "freeze")
    }

    @Test("Three times is three times")
    func threeTimesIsWritten() {
        let thrice = Self.turn(0, 90, repeats: .times(3))
        let svg = Self.moving(Self.document([Self.layer([thrice])]))
        #expect(Self.attribute("repeatCount", in: svg) == "3")
    }

    @Test("There and back goes out and comes home inside one lap")
    func thereAndBackComesHome() {
        let swing = Self.turn(-12, 12, repeats: .foreverThereAndBack)
        let values = Self.valueLists(Self.moving(Self.document([Self.layer([swing])])))
        #expect(values.first?.first == "-12 20 22")
        #expect(values.first?.contains("12 20 22") == true)
        // No seam: the lap ends exactly where the next one starts.
        #expect(values.first?.last == "-12 20 22")
    }

    // MARK: - Curves

    @Test("A curve SVG can state is stated rather than drawn point by point")
    func anExactCurveIsAKeySplines() {
        let eased = Self.turn(-12, 12, curve: .easeInOut)
        let svg = Self.moving(Self.document([Self.layer([eased])]))
        #expect(Self.attribute("calcMode", in: svg) == "spline")
        #expect(Self.attribute("keySplines", in: svg) == "0.4 0 0.2 1")
        #expect(Self.valueLists(svg).first?.count == 2)
    }

    @Test("A curve that overshoots is drawn point by point, overshoot and all")
    func anOvershootCurveIsSampled() {
        let springy = Self.turn(0, 100, curve: .easeOutBack)
        let svg = Self.moving(Self.document([Self.layer([springy])]))
        let values = Self.valueLists(svg).first ?? []
        #expect(values.count > 6)
        // It really goes past where it was told to stop and comes back.
        let angles = values.compactMap { Double($0.split(separator: " ").first ?? "") }
        #expect(angles.contains { $0 > 100 })
        #expect(angles.last == 100)
    }

    @Test("Steps jump rather than slide")
    func stepsJump() {
        let stepped = Self.turn(0, 90, curve: .steps(3))
        let svg = Self.moving(Self.document([Self.layer([stepped])]))
        #expect(Self.attribute("calcMode", in: svg) == "discrete")
        let angles = (Self.valueLists(svg).first ?? [])
            .compactMap { Double($0.split(separator: " ").first ?? "") }
        #expect(angles.contains(30))
        #expect(angles.contains(60))
    }

    @Test("A curve you drew yourself goes out as the cubic you drew")
    func aDrawnCurveIsItsOwnCubic() {
        let drawn = Self.turn(-12, 12, curve: .custom(x1: 0.1, y1: 0.8, x2: 0.9, y2: 0.2))
        let svg = Self.moving(Self.document([Self.layer([drawn])]))
        #expect(Self.attribute("keySplines", in: svg) == "0.1 0.8 0.9 0.2")
    }

    // MARK: - Small enough to read

    @Test("An animated icon is a file you could read in a terminal")
    func theFileStaysSmall() {
        let bell = Self.layer([Self.turn(-12, 12, curve: .easeInOutSine,
                                         repeats: .foreverThereAndBack)])
        let svg = Self.moving(Self.document([bell]))
        #expect(svg.utf8.count < 2_000)
        #expect(!svg.contains("base64"))
    }
}

/// Where the file is going, and what the trip costs it.
@Suite("The hand-off sheet says what survives the trip")
struct SVGHandoffTests {

    static func movingDocument() -> PhotonzDocument {
        var layer = Layer(name: "Bell", content: .path(SVGMotionExportTests.square()),
                          frame: CGRect(x: 8, y: 10, width: 24, height: 24))
        layer.motions = [SVGMotionExportTests.turn(-12, 12)]
        return PhotonzDocument(canvasSize: CGSize(width: 48, height: 48), layers: [layer])
    }

    @Test("A web page is the one destination that runs the motion")
    func aWebPageCarriesTheMotion() {
        let document = Self.movingDocument()
        #expect(SVGHandoff.Destination.webPage.carriesMotion)
        #expect(SVGHandoff.format(for: .webPage, in: document) == .animatedSVG)
        let lines = SVGHandoff.lines(for: .webPage, in: document)
        #expect(lines.first { $0.text.contains("motion") }?.survives == true)
    }

    @Test("A code host strips the motion, and the sheet says so before you save")
    func aReadmeLosesTheMotion() {
        let document = Self.movingDocument()
        #expect(!SVGHandoff.Destination.readme.carriesMotion)
        #expect(SVGHandoff.format(for: .readme, in: document) == .picture)
        let motion = SVGHandoff.lines(for: .readme, in: document)
            .first { $0.text.contains("motion") }
        #expect(motion?.survives == false)
        #expect(motion?.detail?.isEmpty == false)
    }

    @Test("A design tool takes the shapes and throws the motion away")
    func aDesignToolKeepsTheShapes() {
        let document = Self.movingDocument()
        #expect(SVGHandoff.format(for: .designTool, in: document) == .stillSVG)
        let lines = SVGHandoff.lines(for: .designTool, in: document)
        #expect(lines.first { $0.text.contains("Sharp") }?.survives == true)
        #expect(lines.first { $0.text.contains("motion") }?.survives == false)
    }

    @Test("Reacting to a tap survives nowhere, which is the line worth saying")
    func aTapNeverSurvives() {
        let document = Self.movingDocument()
        for destination in SVGHandoff.Destination.allCases {
            let lines = SVGHandoff.lines(for: destination, in: document)
            let tap = lines.first { $0.text.lowercased().contains("tap") }
            #expect(tap?.survives == false)
        }
    }

    @Test("Every destination says something about every part of the hand-off")
    func everyLineIsAnswered() {
        let document = Self.movingDocument()
        for destination in SVGHandoff.Destination.allCases {
            let lines = SVGHandoff.lines(for: destination, in: document)
            #expect(lines.count >= 4)
            // Anything that does not survive says why in plain words.
            for line in lines where !line.survives {
                #expect(line.detail?.isEmpty == false)
            }
        }
    }

    @Test("A drawing with a photograph in it stops claiming to be sharp at every size")
    func anEmbeddedPictureIsAdmitted() {
        var document = Self.movingDocument()
        document.layers.append(Layer(name: "Photo", content: .image(ImageRef(pixelSize: CGSize(width: 48, height: 48))),
                                     frame: CGRect(x: 0, y: 0, width: 48, height: 48)))
        let sharp = SVGHandoff.lines(for: .webPage, in: document)
            .first { $0.text.contains("Sharp") }
        #expect(sharp?.survives == false)
    }
}
