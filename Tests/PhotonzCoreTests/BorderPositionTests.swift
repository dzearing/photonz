import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A line round a layer can sit inside the edge, on it, or outside it.
///
/// Inside is where every line the app has ever drawn sits, so the whole of this
/// suite is about two things: that nothing already on disk moves, and that a
/// layer told to put its line outside reports a reach that makes room for it,
/// so a group, a frame, a drag sprite and a dirty rect all know it is there.
/// `docs/design/shape-parts.md`, "How the list grows".
@Suite("Border position")
struct BorderPositionTests {

    private func rectangle(width: CGFloat, position: BorderPosition) -> Layer {
        var shape = AnnotationContent(shape: .rectangle, strokeWidth: width,
                                      start: .zero, end: CGPoint(x: 100, y: 60))
        shape.strokePosition = position
        return Layer(name: "Box", content: .annotation(shape),
                     frame: CGRect(x: 20, y: 30, width: 100, height: 60))
    }

    private func picture(width: CGFloat, position: BorderPosition) -> Layer {
        var layer = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 100, height: 60))),
                          frame: CGRect(x: 20, y: 30, width: 100, height: 60))
        layer.style.borderWidth = width
        layer.style.borderPosition = position
        return layer
    }

    // MARK: What the outset is

    @Test("Inside reaches nowhere, centred reaches half a width, outside a whole one")
    func outsets() {
        #expect(BorderPosition.inside.outset(width: 8) == 0)
        #expect(BorderPosition.center.outset(width: 8) == 4)
        #expect(BorderPosition.outside.outset(width: 8) == 8)
        // A line of no width is no line, wherever it is said to sit.
        for position in BorderPosition.allCases {
            #expect(position.outset(width: 0) == 0)
        }
    }

    @Test("A line and an arrow have no inside and no outside")
    func linesHaveNoSides() {
        #expect(AnnotationShape.rectangle.hasOutlinePosition)
        #expect(AnnotationShape.ellipse.hasOutlinePosition)
        #expect(!AnnotationShape.line.hasOutlinePosition)
        #expect(!AnnotationShape.arrow.hasOutlinePosition)
        #expect(!AnnotationShape.highlight.hasOutlinePosition)
        var arrow = AnnotationContent(shape: .arrow, strokeWidth: 10)
        arrow.strokePosition = .outside
        #expect(arrow.strokeOutset == 0)
    }

    // MARK: Nothing already drawn moves

    @Test("Everything starts inside, so a fresh layer reaches no further than it ever did")
    func defaultsToInside() {
        let box = rectangle(width: 6, position: .inside)
        #expect(box.outlinePosition == .inside)
        #expect(box.outlineOutset == 0)
        #expect(box.contentOutset == 0)
        #expect(box.renderBounds == box.localBounds)
        #expect(LayerStyle().borderPosition == .inside)
    }

    @Test("A document written before there was a choice opens inside")
    func decodesLegacyAsInside() throws {
        let styleJSON = Data(##"{"opacity":1,"borderWidth":4,"borderColorHex":"#FF0000"}"##.utf8)
        let style = try JSONDecoder().decode(LayerStyle.self, from: styleJSON)
        #expect(style.borderPosition == .inside)

        let shapeJSON = Data(##"""
        {"shape":"rectangle","strokeWidth":4,"colorHex":"#FF3B30",
         "start":[0,0],"end":[10,10]}
        """##.utf8)
        let shape = try JSONDecoder().decode(AnnotationContent.self, from: shapeJSON)
        #expect(shape.strokePosition == .inside)
    }

    @Test("A style that never moved its ring writes exactly the keys it always wrote")
    func encodesNothingExtraWhenInside() throws {
        var style = LayerStyle()
        style.borderWidth = 4
        let written = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(style)) as? [String: Any]
        #expect(written?["borderPosition"] == nil)

        style.borderPosition = .outside
        let moved = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(style)) as? [String: Any]
        #expect(moved?["borderPosition"] as? String == "outside")
    }

    @Test("A moved ring survives a save and a reopen")
    func roundTrips() throws {
        var style = LayerStyle()
        style.borderWidth = 4
        style.borderPosition = .center
        let back = try JSONDecoder().decode(LayerStyle.self,
                                            from: try JSONEncoder().encode(style))
        #expect(back.borderPosition == .center)

        var shape = AnnotationContent(shape: .ellipse, strokeWidth: 3)
        shape.strokePosition = .outside
        let shapeBack = try JSONDecoder().decode(AnnotationContent.self,
                                                 from: try JSONEncoder().encode(shape))
        #expect(shapeBack.strokePosition == .outside)
    }

    // MARK: The reach grows with it

    @Test("An outside stroke makes the shape's reach a whole width bigger all round")
    func shapeReachGrows() {
        let box = rectangle(width: 6, position: .outside)
        #expect(box.contentOutset == 6)
        #expect(box.outlineOutset == 6)
        #expect(box.renderBounds == box.localBounds.insetBy(dx: -6, dy: -6))
        // The frame itself does not move, so clicking still follows the shape.
        #expect(box.frame == CGRect(x: 20, y: 30, width: 100, height: 60))
    }

    @Test("A centred stroke reaches half as far")
    func centredReachGrows() {
        let box = rectangle(width: 6, position: .center)
        #expect(box.contentOutset == 3)
        #expect(box.renderBounds == box.localBounds.insetBy(dx: -3, dy: -3))
    }

    @Test("An outside ring round a picture grows its reach too")
    func pictureReachGrows() {
        let shot = picture(width: 5, position: .outside)
        // The ring is laid on by the renderer rather than baked into the
        // bitmap, so it is style reach rather than content reach.
        #expect(shot.contentOutset == 0)
        #expect(shot.style.previewPadding == 5)
        #expect(shot.renderBounds == shot.localBounds.insetBy(dx: -5, dy: -5))
    }

    @Test("An outside ring reaches past a group, and past one that clips")
    func groupReachGrows() {
        let child = rectangle(width: 6, position: .outside)
        var group = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        // What a child reaches is what the group's buffer has to hold.
        #expect(group.renderBounds.contains(child.renderBounds))

        // A container that clips its contents still draws its OWN ring, which
        // is laid on after the clip, so its reach makes room for it.
        var clipping = Layer(name: "Screen",
                             content: .group(GroupContent(children: [], isFrame: true,
                                                          clipsContents: true)),
                             frame: CGRect(x: 10, y: 10, width: 100, height: 80))
        #expect(clipping.clipsToBounds)
        clipping.style.borderWidth = 4
        clipping.style.borderPosition = .outside
        #expect(clipping.renderBounds == clipping.localBounds.insetBy(dx: -4, dy: -4))

        group.style.borderWidth = 0
        #expect(group.style.previewPadding == 0)
    }

    @Test("A dirty rect covers a line that sits outside the layer")
    func dirtyRectCoversIt() {
        let box = rectangle(width: 6, position: .outside)
        let touched = RenderDiff.visualBounds(of: box)
        #expect(touched.contains(box.frame.insetBy(dx: -6, dy: -6)))
    }

    // MARK: One control over a mixed selection

    @Test("One pick reaches a shape and a picture, each the way it draws")
    func setsBothKinds() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let box = rectangle(width: 6, position: .inside)
        let shot = picture(width: 5, position: .inside)
        doc.addLayer(box)
        doc.addLayer(shot)

        let changed = doc.setOutlinePosition(layerIDs: [box.id, shot.id], to: .outside)
        #expect(changed == 2)
        #expect(doc.layer(id: box.id)?.annotation?.strokePosition == .outside)
        #expect(doc.layer(id: shot.id)?.style.borderPosition == .outside)
        #expect(doc.outlinePositionReading(layerIDs: [box.id, shot.id]).value == .outside)
        #expect(doc.outlinePositionReading(layerIDs: [box.id, shot.id]).isMixed == false)

        // Setting it again changes nothing, so a menu that reopens on the same
        // answer is not an undo step.
        #expect(doc.setOutlinePosition(layerIDs: [box.id, shot.id], to: .outside) == 0)
    }

    @Test("Two layers that disagree read as mixed")
    func mixedReading() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let inside = rectangle(width: 6, position: .inside)
        let outside = rectangle(width: 6, position: .outside)
        doc.addLayer(inside)
        doc.addLayer(outside)
        #expect(doc.outlinePositionReading(layerIDs: [inside.id, outside.id]).isMixed)
    }

    @Test("A locked layer keeps the line where it had it")
    func locksAreLeftAlone() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        var box = rectangle(width: 6, position: .inside)
        box.isLocked = true
        doc.addLayer(box)
        #expect(doc.setOutlinePosition(layerIDs: [box.id], to: .outside) == 0)
        #expect(doc.layer(id: box.id)?.annotation?.strokePosition == .inside)
    }

    @Test("A line is not offered a position, so a pick over one leaves it alone")
    func arrowsAreLeftAlone() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let arrow = Layer(name: "Arrow",
                          content: .annotation(AnnotationContent(shape: .arrow, strokeWidth: 6)),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 40))
        doc.addLayer(arrow)
        #expect(doc.layer(id: arrow.id)?.hasOutlinePosition == false)
        #expect(doc.setOutlinePosition(layerIDs: [arrow.id], to: .outside) == 0)
    }
}

/// The tool remembers where you put the line, the way it remembers how thick
/// you made it.
@Suite("Outline position is remembered")
struct OutlinePositionMemoryTests {

    @Test("The next box of the same kind comes out where the last one was set")
    func nextShapeFollows() {
        var styles = AnnotationStyles()
        #expect(styles.strokePosition(forShape: .rectangle) == .inside)
        styles.setStrokePosition(.outside, forShape: .rectangle)
        #expect(styles.content(for: .rectangle)?.strokePosition == .outside)
        // Per kind, so a box does not speak for an ellipse.
        #expect(styles.content(for: .ellipse)?.strokePosition == .inside)
    }

    @Test("Preferences written before there was a choice still open")
    func legacyPreferencesDecode() throws {
        let json = Data(##"""
        {"colorHex":"#FF3B30","strokeWidth":4,"arrowheadScale":1,
         "cornerRadius":0,"layerStyle":{"opacity":1},"captionFontSize":20}
        """##.utf8)
        let defaults = try JSONDecoder().decode(ShapeDefaults.self, from: json)
        #expect(defaults.strokePosition == .inside)
        #expect(defaults.strokeWidth == 4)
    }
}
