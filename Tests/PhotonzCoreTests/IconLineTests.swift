import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A new Pen line on an icon starts in the line the icon is already using
/// (`IconLine.swift`). Found on the whole-workflow walk of 2026-11-07: a Pen
/// line drawn after a 1.75 round outline came out red, 2 units and sharp
/// cornered, so a glyph's second part never matched its first until three rows
/// were set again.
struct IconLineTests {

    private let ink = Paint(hex: "#0C0E14")

    private func glyph(_ name: String, closed: Bool = true, width: CGFloat = 1.75,
                       ink: Paint? = nil, fill: Paint? = nil,
                       at origin: CGPoint = CGPoint(x: 4, y: 4)) -> Layer {
        let anchors = [PathAnchor(point: .zero), PathAnchor(point: CGPoint(x: 8, y: 0)),
                       PathAnchor(point: CGPoint(x: 8, y: 8))]
        let content = PathContent(anchors: anchors, isClosed: closed,
                                  paint: ink ?? self.ink, strokeWidth: width,
                                  strokePosition: .center, fill: fill,
                                  lineEnd: .round, lineCorner: .round)
        return Layer(name: name, content: .path(content),
                     frame: CGRect(origin: origin, size: CGSize(width: 8, height: 8)))
    }

    /// A canvas made as an icon, 24 across, holding these layers.
    private func icon(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 24, height: 24), layers: layers)
        doc.madeAsIcon = true
        return doc
    }

    private let middle = CGPoint(x: 12, y: 12)

    // MARK: - Which line

    @Test func anIconWithNoLineHasNothingToSay() {
        let doc = icon([glyph("Solid", width: 0, fill: ink)])
        #expect(doc.iconLine(drawnAt: middle, picked: nil) == nil)
    }

    @Test func aPictureThatIsNotAnIconHasNothingToSay() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [glyph("Line")])
        #expect(doc.iconLine(drawnAt: CGPoint(x: 8, y: 8), picked: nil) == nil)
    }

    @Test func theLineIsTheTopmostOne() {
        let doc = icon([glyph("Under", width: 3), glyph("Over", width: 1.75),
                        glyph("Solid", width: 0, fill: ink)])
        #expect(doc.iconLine(drawnAt: middle, picked: nil)?.look.width == 1.75)
    }

    @Test func aPathInsideAGroupCounts() {
        let group = Layer(name: "Glyph",
                          content: .group(GroupContent(children: [glyph("Inner", width: 1.75)])),
                          frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        #expect(icon([group]).iconLine(drawnAt: middle, picked: nil)?.look.width == 1.75)
    }

    @Test func aHiddenPathDoesNotCount() {
        var hidden = glyph("Hidden", width: 3)
        hidden.isVisible = false
        let doc = icon([glyph("Shown", width: 1.75), hidden])
        #expect(doc.iconLine(drawnAt: middle, picked: nil)?.look.width == 1.75)
    }

    @Test func thePickedPathSpeaksFirst() {
        let picked = glyph("Picked", width: 3)
        let doc = icon([picked, glyph("Over", width: 1.75)])
        #expect(doc.iconLine(drawnAt: middle, picked: picked.id)?.look.width == 3)
    }

    @Test func aPickedShapeWithNoLineLeavesItToTheRest() {
        let solid = glyph("Solid", width: 0, fill: ink)
        let doc = icon([glyph("Line", width: 1.75), solid])
        #expect(doc.iconLine(drawnAt: middle, picked: solid.id)?.look.width == 1.75)
    }

    @Test func aFrameSpeaksOnlyForItself() {
        let frame = Layer(name: "Icon",
                          content: .group(GroupContent(children: [glyph("In", width: 1.5, at: CGPoint(x: 2, y: 2))],
                                                       isFrame: true)),
                          frame: CGRect(x: 100, y: 100, width: 24, height: 24))
        let other = Layer(name: "Other", content: .group(GroupContent(children: [], isFrame: true)),
                          frame: CGRect(x: 200, y: 100, width: 24, height: 24))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 600, height: 400), layers: [frame, other])
        #expect(doc.iconLine(drawnAt: CGPoint(x: 110, y: 110), picked: nil)?.look.width == 1.5)
        #expect(doc.iconLine(drawnAt: CGPoint(x: 210, y: 110), picked: nil) == Optional<IconLine>.none)
    }

    // MARK: - What the tool bar reads

    @Test func aPictureThatIsAnIconAnswersWithNothingPickedAndThePointerElsewhere() {
        // The pointer is up on the tool bar reading the row, so nothing names
        // an icon, and the row must still say what the next line will be.
        let doc = icon([glyph("Cloud", width: 1.75)])
        #expect(doc.iconLine(picked: nil, pointerIn: nil)?.look.width == 1.75)
    }

    @Test func aFrameOnABiggerPictureStillNeedsSomethingToNameIt() {
        let frame = Layer(name: "Icon",
                          content: .group(GroupContent(children: [glyph("In", width: 1.5, at: CGPoint(x: 2, y: 2))],
                                                       isFrame: true)),
                          frame: CGRect(x: 100, y: 100, width: 24, height: 24))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 600, height: 400), layers: [frame])
        #expect(doc.iconLine(picked: nil, pointerIn: nil) == Optional<IconLine>.none)
        #expect(doc.iconLine(picked: nil, pointerIn: frame.id)?.look.width == 1.5)
    }

    // MARK: - What the Pen does with it

    private func session(following line: IconLine?) -> PenSession {
        var pen = PenSession()
        pen.startingPaint = Paint(hex: PathContent.defaultColorHex)
        pen.startingStrokeWidth = 2
        pen.follow(line)
        return pen
    }

    private func finished(_ pen: PenSession) -> PathContent? {
        var pen = pen
        for point in [CGPoint(x: 2, y: 2), CGPoint(x: 20, y: 2), CGPoint(x: 20, y: 20)] {
            _ = pen.press(at: point, constrained: false, breaking: false, free: true, zoom: 1)
            _ = pen.release()
        }
        return pen.finish()
    }

    @Test func aNewLineStartsInTheIconsColourWidthAndCorners() throws {
        let doc = icon([glyph("Cloud", width: 1.75)])
        let line = doc.iconLine(drawnAt: middle, picked: nil)
        let drawn = try #require(finished(session(following: line)))
        #expect(drawn.paint == ink)
        #expect(drawn.strokeWidth == 1.75)
        #expect(drawn.lineCorner == .round)
        #expect(drawn.lineEnd == .round)
        #expect(drawn.fill == nil)
    }

    @Test func noLineToFollowLeavesThePenAsItWas() throws {
        let drawn = try #require(finished(session(following: nil)))
        #expect(drawn.paint.hex == PathContent.defaultColorHex)
        #expect(drawn.strokeWidth == 2)
        #expect(drawn.lineCorner == .sharp)
    }

    @Test func aNewLineWearsTheSavedStrokeTheIconUses() throws {
        let cloud = glyph("Cloud")
        var doc = icon([cloud])
        let savedId = doc.saveStroke(from: [cloud.id])
        let id = try #require(savedId)
        let drawn = try #require(finished(session(following: doc.iconLine(drawnAt: middle, picked: nil))))
        #expect(drawn.savedStrokeID == id)
    }

    @Test func aWidthSetByHandOnTheToolBarBeatsTheIcon() throws {
        let cloud = glyph("Cloud")
        var doc = icon([cloud])
        let saved = doc.saveStroke(from: [cloud.id])
        #expect(saved != nil)
        let line = doc.iconLine(drawnAt: middle, picked: nil)?.keeping(width: 3)
        let drawn = try #require(finished(session(following: line)))
        #expect(drawn.strokeWidth == 3)
        #expect(drawn.savedStrokeID == nil, "a line at another weight does not wear the name")
        #expect(drawn.paint == ink)
        #expect(drawn.lineCorner == .round)
    }

    @Test func aColourSetByHandOnTheToolBarBeatsTheIcon() throws {
        let doc = icon([glyph("Cloud")])
        let blue = Paint(hex: "#0000FF")
        let line = doc.iconLine(drawnAt: middle, picked: nil)?.keeping(paint: blue)
        let drawn = try #require(finished(session(following: line)))
        #expect(drawn.paint == blue)
        #expect(drawn.strokeWidth == 1.75)
    }

    @Test func aClosedShapeOnALineIconIsAnotherPartOfTheSameDrawing() throws {
        var pen = session(following: icon([glyph("Arrow", closed: false)])
            .iconLine(drawnAt: middle, picked: nil))
        var closed: PathContent?
        for point in [CGPoint(x: 2, y: 2), CGPoint(x: 20, y: 2), CGPoint(x: 20, y: 20), CGPoint(x: 2, y: 2)] {
            _ = pen.press(at: point, constrained: false, breaking: false, free: true, zoom: 1)
            if case .closed(let content) = pen.release() { closed = content }
        }
        let content = try #require(closed)
        #expect(content.strokeWidth == 1.75)
        #expect(content.fill == nil)
    }

    @Test func aClosedShapeTakesTheFillOfAClosedPartBesideIt() throws {
        let red = Paint(hex: "#FF0000")
        var pen = session(following: icon([glyph("Cloud", fill: red)])
            .iconLine(drawnAt: middle, picked: nil))
        var closed: PathContent?
        for point in [CGPoint(x: 2, y: 2), CGPoint(x: 20, y: 2), CGPoint(x: 20, y: 20), CGPoint(x: 2, y: 2)] {
            _ = pen.press(at: point, constrained: false, breaking: false, free: true, zoom: 1)
            if case .closed(let content) = pen.release() { closed = content }
        }
        #expect(closed?.fill == red)
    }

    @Test func theLayerKeepsTheColourStylesTheLineWears() throws {
        var cloud = glyph("Cloud")
        let style = UUID()
        cloud.bindColorStyle(style, for: .stroke)
        let line = icon([cloud]).iconLine(drawnAt: middle, picked: nil)
        let drawn = try #require(finished(session(following: line)))
        let layer = PenSession.layer(from: drawn, following: line)
        #expect(layer.colorStyleID(for: .stroke) == style)
    }

    @Test func aColourSetByHandDoesNotClaimTheColourStyle() throws {
        var cloud = glyph("Cloud")
        cloud.bindColorStyle(UUID(), for: .stroke)
        let line = icon([cloud]).iconLine(drawnAt: middle, picked: nil)?.keeping(paint: Paint(hex: "#0000FF"))
        let drawn = try #require(finished(session(following: line)))
        #expect(PenSession.layer(from: drawn, following: line).colorStyleID(for: .stroke) == nil)
    }

    // MARK: - The mock's note

    @Test func theNoteSpeaksOverALineInAnIconAndNowhereElse() {
        let line = glyph("Line"), solid = glyph("Solid", width: 0, fill: ink)
        let doc = icon([line, solid])
        #expect(doc.savedStrokeNote(for: [line.id]) == PhotonzDocument.savedStrokeNote)
        #expect(doc.savedStrokeNote(for: [solid.id]) == nil)
        #expect(doc.savedStrokeNote(for: []) == nil)
        let plain = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [line])
        #expect(plain.savedStrokeNote(for: [line.id]) == nil)
    }

    // MARK: - An outline switched on

    @Test func anOutlineSwitchedOnInAnIconTakesTheLineItIsUsing() throws {
        let cloud = glyph("Cloud", width: 2.5)
        let blob = glyph("Blob", width: 0, ink: Paint(hex: "#FF3B30"), fill: Paint(hex: "#FFFFFF"))
        var doc = icon([cloud, blob])
        let savedId = doc.saveStroke(from: [cloud.id])
        let id = try #require(savedId)
        doc.setPathOutline(layerIDs: [blob.id], on: true, iconLook: true)
        let line = try #require(doc.layer(id: blob.id)?.path)
        #expect(line.strokeWidth == 2.5)
        #expect(line.paint == ink)
        #expect(line.savedStrokeID == id)
    }

    @Test func anOutlineOnAnIconWithNoLineStartsAtTheSetsWeight() throws {
        let blob = glyph("Blob", width: 0, fill: Paint(hex: "#FFFFFF"))
        var doc = icon([blob])
        doc.setPathOutline(layerIDs: [blob.id], on: true, iconLook: true)
        #expect(doc.layer(id: blob.id)?.path?.strokeWidth == 1.75)
    }
}
