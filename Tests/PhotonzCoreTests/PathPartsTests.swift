import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A path is a shape like any other, so its parts are named for what they
/// paint, the way every other shape's are (`docs/design/shape-parts.md`).
///
/// Reported by the user on 2026-09-14: "it is odd that in in appearance, there
/// is a color but it's not clear its the stroke color and thickness". A path
/// showed one row simply called Color.
@Suite("A path's parts")
struct PathPartsTests {

    private func path(closed: Bool, strokeWidth: CGFloat = 4,
                      fill: Paint? = Paint(hex: "#FF3B30")) -> Layer {
        var content = PathContent(anchors: [PathAnchor(point: .zero),
                                            PathAnchor(point: CGPoint(x: 60, y: 0)),
                                            PathAnchor(point: CGPoint(x: 30, y: 50))],
                                  isClosed: closed, fill: fill)
        content.strokeWidth = strokeWidth
        return Layer(name: "Path", content: .path(content),
                     frame: CGRect(x: 0, y: 0, width: 60, height: 50))
    }

    private func line() -> Layer {
        Layer(name: "Line",
              content: .annotation(AnnotationContent(shape: .line, colorHex: "#FF0000",
                                                     start: .zero,
                                                     end: CGPoint(x: 80, y: 0))),
              frame: CGRect(x: 0, y: 0, width: 80, height: 4))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: layers)
    }

    private func rows(_ layers: [Layer]) -> [LayerPartRow] {
        document(layers).layerPartRows(layerIDs: layers.map(\.id))
    }

    // MARK: The names

    @Test("A closed path's two colours are called Fill and Outline, never just Color")
    func closedPathNamesItsParts() {
        let titles = rows([path(closed: true)]).map(\.title)
        #expect(titles == ["Fill", "Outline"])
    }

    @Test("An open path has no inside, so its one colour is called Line, the word a line uses")
    func openPathIsALine() {
        let titles = rows([path(closed: false, fill: nil)]).map(\.title)
        #expect(titles == ["Line"])
    }

    @Test("An open path picked with a line is still one row, still called Line")
    func openPathAndALineAgree() {
        let list = rows([path(closed: false, fill: nil), line()])
        #expect(list.map(\.title) == ["Line"])
        #expect(list[0].colors.first?.layerIDs.count == 2)
    }

    @Test("A closed path picked with a line falls back to the plain word, because Outline is wrong for a line")
    func mixedSelectionStaysPlain() {
        let list = rows([path(closed: true), line()])
        #expect(list.map(\.title) == ["Fill", "Color"])
    }

    // MARK: The switch

    @Test("A closed path's outline has a switch, like every other part of every other shape")
    func closedPathOutlineSwitches() {
        let only = rows([path(closed: true)])[1]
        #expect(only.hasSwitch)
        #expect(only.isOn)
        #expect(only.part == .outline)
    }

    @Test("A path with no line shows the switch OFF and no dead colour well under it")
    func noLineNoWell() {
        let only = rows([path(closed: true, strokeWidth: 0)])[1]
        #expect(only.hasSwitch)
        #expect(!only.isOn)
        #expect(!only.showsSettings)
    }

    @Test("An OPEN path keeps no switch: it IS its line, so taking it off would be a delete")
    func openPathHasNoSwitch() {
        #expect(!rows([path(closed: false, fill: nil)])[0].hasSwitch)
    }

    @Test("Two closed paths where only one has a line read as Mixed, and say so in words")
    func mixedOutlines() {
        let row = rows([path(closed: true), path(closed: true, strokeWidth: 0)])[1]
        #expect(row.isMixed)
        #expect(row.reachNote?.contains("outline") == true)
    }

    @Test("Three closed paths with ONE line between them still read as Mixed, never as on")
    func threeWithOneOutlineAreMixed() {
        // The exact shape of the report: three picked, one outlined. A row
        // that reads plain "on" here says all three have a line, and a press
        // on it would take the one line away instead of giving the other two
        // one (switch-says-mixed-walk).
        let row = rows([path(closed: true),
                        path(closed: true, strokeWidth: 0),
                        path(closed: true, strokeWidth: 0)])[1]
        #expect(row.isMixed)
        #expect(!row.isOn)
        #expect(row.reachNote == "1 of the 3 selected layers has an outline. "
                + "Switching this on gives the rest one too.")
    }

    @Test("The row answers to a steady name a walk can write")
    func steadyName() {
        #expect(rows([path(closed: true)])[1].steadyNames == ["outline"])
    }

    // MARK: Switching it

    @Test("Switching the outline off takes the line away and leaves the colour where it was")
    func switchingOff() {
        let layer = path(closed: true)
        var doc = document([layer])
        let before = doc.layer(id: layer.id)?.path?.colorHex
        #expect(doc.setPathOutline(layerIDs: [layer.id], on: false) == 1)
        #expect(doc.layer(id: layer.id)?.path?.strokeWidth == 0)
        #expect(doc.layer(id: layer.id)?.path?.colorHex == before)
    }

    @Test("Switching it back on brings a line back at the weight a fresh shape wears")
    func switchingOn() {
        let layer = path(closed: true, strokeWidth: 0)
        var doc = document([layer])
        #expect(doc.setPathOutline(layerIDs: [layer.id], on: true) == 1)
        #expect(doc.layer(id: layer.id)?.path?.strokeWidth == PathContent.defaultStrokeWidth)
    }

    @Test("The FIRST outline a path is asked for reads against its own fill, never matches it")
    func firstOutlineStandsOut() {
        // A closed path arrives filled and unlined, both in the one ink the Pen
        // was armed with. Handing it the fill's own colour back as a line would
        // draw nothing anybody can see, so it takes the ink a box's first
        // border takes (`BorderInk.swift`).
        let layer = path(closed: true, strokeWidth: 0, fill: Paint(hex: "#FF3B30"))
        var doc = document([layer])
        #expect(doc.setPathOutline(layerIDs: [layer.id], on: true) == 1)
        let drawn = doc.layer(id: layer.id)?.path
        #expect(drawn?.strokeWidth == PathContent.defaultStrokeWidth)
        #expect(drawn?.colorHex == BorderInk.standingOutHex(from: Paint(hex: "#FF3B30")))
        #expect(drawn?.colorHex != "#FF3B30")
    }

    @Test("A line somebody painted comes back in its own colour when it is switched on again")
    func paintedOutlineKeepsItsColour() {
        var content = PathContent(anchors: [PathAnchor(point: .zero),
                                            PathAnchor(point: CGPoint(x: 60, y: 0)),
                                            PathAnchor(point: CGPoint(x: 30, y: 50))],
                                  isClosed: true, fill: Paint(hex: "#FF3B30"))
        content.strokeWidth = 0
        content.colorHex = "#2D7FF9"
        let layer = Layer(name: "Path", content: .path(content),
                          frame: CGRect(x: 0, y: 0, width: 60, height: 50))
        var doc = document([layer])
        #expect(doc.setPathOutline(layerIDs: [layer.id], on: true) == 1)
        #expect(doc.layer(id: layer.id)?.path?.colorHex == "#2D7FF9")
    }

    @Test("An open path's line is never repainted: there is no fill for it to be lost against")
    func openPathLineKeepsItsColour() {
        let layer = path(closed: false, strokeWidth: 0, fill: nil)
        var doc = document([layer])
        #expect(doc.setPathOutline(layerIDs: [layer.id], on: true) == 1)
        #expect(doc.layer(id: layer.id)?.path?.colorHex == PathContent.defaultColorHex)
    }

    @Test("Taking a closed path's fill away leaves the outline that carries it")
    func fillOffLeavesTheLine() {
        // A path with no inside and no line paints nothing at all: a layer you
        // can only find in the layers list. The same rule a box follows
        // (`BorderInk.swift`).
        let layer = path(closed: true, strokeWidth: 0, fill: Paint(hex: "#FF3B30"))
        var doc = document([layer])
        #expect(doc.setColorEnabled(layerIDs: [layer.id], slot: .fill, on: false) == 1)
        let drawn = doc.layer(id: layer.id)?.path
        #expect(drawn?.fill == nil)
        #expect(drawn?.strokeWidth == BorderInk.fallbackWidth)
    }

    @Test("A closed path that still has a line keeps it when its fill goes")
    func fillOffLeavesALineAlone() {
        let layer = path(closed: true, strokeWidth: 9, fill: Paint(hex: "#FF3B30"))
        var doc = document([layer])
        #expect(doc.setColorEnabled(layerIDs: [layer.id], slot: .fill, on: false) == 1)
        #expect(doc.layer(id: layer.id)?.path?.strokeWidth == 9)
    }

    @Test("Letting a colour go on a switched-off outline gives it a line in that colour")
    func droppingAColourOnIt() {
        let layer = path(closed: true, strokeWidth: 0)
        var doc = document([layer])
        #expect(doc.turnOnPart(.outline, layerIDs: [layer.id], paint: Paint(hex: "#00FF00")) == 1)
        #expect(doc.layer(id: layer.id)?.path?.strokeWidth ?? 0 > 0)
        #expect(doc.layer(id: layer.id)?.path?.colorHex == "#00FF00")
    }
}
