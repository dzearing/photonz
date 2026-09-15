import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Copying the look of one shape onto another.
///
/// Asked for by the user on 2026-09-15: *"I wish there was some way to just
/// copy the format of one shape and best effort apply it to the properties of
/// another shape."*
///
/// The headline case is the one in the task: make a line match a circle's
/// border. A circle wears its edge as a Border in the Effects list and a line
/// IS its edge, so the look has to carry "the edge" once and let each layer put
/// it where its own edge lives.
struct LayerLookTests {

    // MARK: - Fixtures

    private func circle(fill: String? = "#3366FF", border: String = "#FF0055",
                        width: CGFloat = 3) -> Layer {
        // Strokeless: a shape drawn today is its fill and nothing else, and
        // the edge it wears is the Border put in the Effects list below.
        var content = AnnotationContent(shape: .ellipse, strokeWidth: 0, start: .zero,
                                        end: CGPoint(x: 60, y: 60))
        content.fillColorHex = fill
        var layer = Layer(name: "Circle", content: .annotation(content),
                          frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        layer.style.effects = [.border(BorderEffect(width: width, colorHex: border))]
        return layer
    }

    private func line(_ hex: String = "#101010", width: CGFloat = 1) -> Layer {
        var content = AnnotationContent(shape: .line, strokeWidth: width,
                                        start: .zero, end: CGPoint(x: 80, y: 0))
        content.colorHex = hex
        return Layer(name: "Line", content: .annotation(content),
                     frame: CGRect(x: 0, y: 0, width: 80, height: 2))
    }

    private func box(fill: String? = "#00AA55") -> Layer {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0, start: .zero,
                                        end: CGPoint(x: 60, y: 30))
        content.fillColorHex = fill
        return Layer(name: "Box", content: .annotation(content),
                     frame: CGRect(x: 0, y: 0, width: 60, height: 30))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    // MARK: - The headline: a line matches a circle's border

    @Test func aLineTakesTheCirclesBorderAsItsOwnLine() {
        var doc = document([circle(border: "#FF0055", width: 3), line("#101010", width: 1)])
        let look = doc.look(ofLayer: doc.layers[0].id)
        #expect(look != nil)
        let report = doc.applyLook(look!, to: [doc.layers[1].id])

        #expect(report.layerCount == 1)
        #expect(doc.layers[1].colorHex(for: .stroke) == "#FF0055")
        #expect(doc.layers[1].outlineWidth == 3)
    }

    @Test func aLineDoesNotGrowARingRoundItsBox() {
        var doc = document([circle(), line()])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        doc.applyLook(look, to: [doc.layers[1].id])
        // The circle's edge became the line's own line. It must not ALSO land
        // in the Effects list, or the line wears a rectangle round its box.
        #expect(doc.layers[1].style.effects.contains { $0.kind == .border } == false)
    }

    @Test func aLineHasNothingToFillAndSaysSo() {
        var doc = document([circle(fill: "#3366FF"), line()])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        let report = doc.applyLook(look, to: [doc.layers[1].id])
        #expect(report.skipped == ["Fill"])
        #expect(report.detail == "1 layer took it. Skipped the fill, which it does not have")
    }

    @Test func theOtherWayRoundAlsoWorks() {
        var doc = document([line("#FF8800", width: 6), circle(border: "#000000", width: 1)])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        doc.applyLook(look, to: [doc.layers[1].id])
        // The line's ink is the circle's ring, at the line's weight.
        #expect(doc.layers[1].outlineWidth == 6)
        #expect(doc.layers[1].outlineColorHex == "#FF8800")
    }

    // MARK: - What a look carries

    @Test func itCarriesTheThingsALookIsMadeOf() {
        var source = circle(fill: "#3366FF", border: "#FF0055", width: 3)
        source.style.opacity = 0.4
        source.style.cornerRadius = 12
        source.style.effects.append(.shadow(ShadowStyle()))
        var doc = document([source, box(fill: "#00AA55")])

        let look = doc.look(ofLayer: doc.layers[0].id)!
        doc.applyLook(look, to: [doc.layers[1].id])

        let target = doc.layers[1]
        #expect(target.colorHex(for: .fill) == "#3366FF")
        #expect(target.outlineWidth == 3)
        #expect(target.outlineColorHex == "#FF0055")
        #expect(target.style.opacity == 0.4)
        #expect(target.style.cornerRadius == 12)
        #expect(target.style.shadows.count == 1)
    }

    @Test func itLeavesPositionSizeRotationAndWhatTheShapeIsAlone() {
        var target = line()
        target.transform = LayerTransform(rotation: .pi / 4)
        var doc = document([circle(), target])
        let before = doc.layers[1]
        let look = doc.look(ofLayer: doc.layers[0].id)!
        doc.applyLook(look, to: [doc.layers[1].id])

        #expect(doc.layers[1].frame == before.frame)
        #expect(doc.layers[1].transform == before.transform)
        #expect(doc.layers[1].annotation?.shape == .line)
    }

    @Test func itIsOneUndoStepHoweverManyShapesItReached() {
        var history = History(document: document([circle(), box(), box(), box()]))
        let look = history.current.look(ofLayer: history.current.layers[0].id)!
        let targets = history.current.layers.dropFirst().map(\.id)
        let before = history.current.layers

        _ = history.perform { $0.applyLook(look, to: Array(targets)) }
        #expect(history.current.layers[1].outlineWidth == 3)
        #expect(history.current.layers[3].outlineWidth == 3)

        history.undo()
        #expect(history.current.layers == before)
    }

    @Test func theEffectsListIsReplacedRatherThanMerged() {
        var target = box()
        target.style.effects = [.blur(BlurEffect(radius: 8))]
        var doc = document([circle(), target])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        doc.applyLook(look, to: [doc.layers[1].id])
        // Matching one shape to another means it wears what that one wears.
        #expect(doc.layers[1].style.effects.contains { $0.kind == .blur } == false)
        #expect(doc.layers[1].style.borderWidth == 3)
    }

    @Test func aRingGoesBackOnTheSameSideOfTheEdge() {
        var source = circle(width: 4)
        source.style.effects = [.border(BorderEffect(width: 4, colorHex: "#FF0055",
                                                     position: .outside, offset: 6))]
        var doc = document([source, box()])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        doc.applyLook(look, to: [doc.layers[1].id])

        let ring = doc.layers[1].style.effects.compactMap(\.border).first
        #expect(ring?.position == .outside)
        #expect(ring?.offset == 6)
    }

    @Test func aSwitchedOffFillArrivesSwitchedOff() {
        var doc = document([circle(fill: nil), box(fill: "#00AA55")])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        doc.applyLook(look, to: [doc.layers[1].id])
        #expect(doc.layers[1].colorHex(for: .fill) == nil)
    }

    @Test func aSwitchedOffFillComesBackWhenTheLookHasOne() {
        var doc = document([circle(fill: "#3366FF"), box(fill: nil)])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        doc.applyLook(look, to: [doc.layers[1].id])
        #expect(doc.layers[1].colorHex(for: .fill) == "#3366FF")
    }

    // MARK: - A saved colour arrives still wearing its name

    @Test func aColourWearingASavedStyleArrivesStillWearingIt() {
        var doc = document([circle(fill: "#3366FF"), box()])
        let accent = doc.saveColorStyle(from: [doc.layers[0].id], slot: .fill, name: "Accent")
        #expect(accent != nil)

        let look = doc.look(ofLayer: doc.layers[0].id)!
        doc.applyLook(look, to: [doc.layers[1].id])

        #expect(doc.layers[1].colorStyleID(for: .fill) == accent)
        #expect(doc.layers[1].colorHex(for: .fill) == "#3366FF")
    }

    @Test func aBorderWearingASavedStyleCarriesItToAnotherBox() {
        var doc = document([circle(border: "#FF0055"), box()])
        let ring = doc.saveColorStyle(from: [doc.layers[0].id], effectAt: 0, name: "Ring")
        #expect(ring != nil)

        let look = doc.look(ofLayer: doc.layers[0].id)!
        doc.applyLook(look, to: [doc.layers[1].id])

        #expect(doc.layers[1].colorStyleID(for: .border) == ring)
    }

    @Test func aSavedColourThisDocumentHasNeverHeardOfArrivesAsTheColour() {
        var source = document([circle(fill: "#3366FF")])
        _ = source.saveColorStyle(from: [source.layers[0].id], slot: .fill, name: "Accent")
        let look = source.look(ofLayer: source.layers[0].id)!

        var elsewhere = document([box(fill: "#000000")])
        elsewhere.applyLook(look, to: [elsewhere.layers[0].id])

        #expect(elsewhere.layers[0].colorStyleID(for: .fill) == nil)
        #expect(elsewhere.layers[0].colorHex(for: .fill) == "#3366FF")
    }

    // MARK: - Best effort, and saying what it skipped

    @Test func itReachesSeveralLayersAtOnce() {
        var doc = document([circle(), box(), box(), line()])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        let ids = doc.layers.dropFirst().map(\.id)
        let report = doc.applyLook(look, to: Array(ids))
        #expect(report.layerCount == 3)
    }

    @Test func aLockedLayerIsLeftExactlyAsItIs() {
        var target = box(fill: "#00AA55")
        target.isLocked = true
        var doc = document([circle(), target])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        let report = doc.applyLook(look, to: [doc.layers[1].id])

        #expect(report.layerCount == 0)
        #expect(report.lockedCount == 1)
        #expect(doc.layers[1].colorHex(for: .fill) == "#00AA55")
        #expect(report.detail == "The layer is locked")
    }

    @Test func aLineKeepsItsOwnLineWhenTheLookHasNoEdge() {
        var doc = document([box(fill: "#00AA55"), line("#101010", width: 5)])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        let report = doc.applyLook(look, to: [doc.layers[1].id])
        // A line with no line is not a setting, it is a delete.
        #expect(doc.layers[1].outlineWidth == 5)
        #expect(report.skipped == ["Outline", "Fill"])
    }

    @Test func aSkippedPartIsNamedOnceHoweverManyLayersSkipIt() {
        var doc = document([circle(), line(), line()])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        let report = doc.applyLook(look, to: [doc.layers[1].id, doc.layers[2].id])
        #expect(report.skipped == ["Fill"])
    }

    @Test func itNeverFailsBecauseOneSettingDidNotFit() {
        var doc = document([circle(), Layer(name: "Words",
                                            content: .text(TextContent(string: "Hi")),
                                            frame: CGRect(x: 0, y: 0, width: 40, height: 20))])
        let look = doc.look(ofLayer: doc.layers[0].id)!
        let report = doc.applyLook(look, to: [doc.layers[1].id])
        #expect(report.layerCount == 1)
    }

    // MARK: - What the pill says

    @Test func thePillCountsWhatItReached() {
        #expect(LookPaste(layerCount: 3).detail == "3 layers took it")
        #expect(LookPaste(layerCount: 1).title == "Pasted")
        #expect(LookPaste(layerCount: 0).title == "Nothing took it")
    }

    @Test func thePillListsTwoSkippedPartsReadably() {
        let report = LookPaste(layerCount: 2, skipped: ["Fill", "Head"])
        #expect(report.detail == "2 layers took it. Skipped the fill and the head, which they do not have")
    }

    @Test func onePillSpeaksOfOneLayerAsOne() {
        let report = LookPaste(layerCount: 1, skipped: ["Fill"])
        #expect(report.detail == "1 layer took it. Skipped the fill, which it does not have")
    }

    @Test func thePillSaysWhenALockedLayerSatOut() {
        let report = LookPaste(layerCount: 2, lockedCount: 1)
        #expect(report.detail == "2 layers took it. 1 locked layer was left alone")
    }
}
