import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Resizing a group whose pieces carry NO placement rule: everything is
/// multiplied by the amount the group's box changed by, all the way down, and
/// what is measured in points — text size, stroke width, corner radius — holds
/// still. This is the default half of "Resizing places the pieces"
/// (`docs/design/ui-building.md`); the rules themselves are in
/// `LayerPlacementTests`.
///
/// Text is the one piece whose box is not simply multiplied. Its width is —
/// that is its wrap width — but its height is however tall the words are once
/// they have re-wrapped to it, because the type never changed size. A label
/// stretched to twice the height with the same 14-point glyphs in it would be
/// a box with a hole under the words ("A label grows to fit what it says").
@Suite("Resizing a group with no placement rules scales what is inside it")
struct LayerScalingTests {

    private func box(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    private func text(_ name: String, _ frame: CGRect, size: CGFloat = 14) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name, fontSize: size)), frame: frame)
    }

    /// How tall a label in this suite is once it has measured itself at
    /// `width`. Written as a call rather than a number because the app measures
    /// with CoreText and these tests may run with the built-in estimate.
    private func labelHeight(_ name: String = "Label", width: CGFloat,
                             size: CGFloat = 14) -> CGFloat {
        TextMeasurement.size(of: TextContent(string: name, fontSize: size),
                             wrappingAt: width).height
    }

    /// A card: a group anchored at (50, 60) holding a 100×40 box at local
    /// (0, 0) and a 60-wide label at local (8, 4), as tall as its one line of
    /// type. Its box is (50, 60, 100, 40).
    private func card() -> Layer {
        Layer(name: "Card",
              content: .group(GroupContent(children: [
                  box("Box", CGRect(x: 0, y: 0, width: 100, height: 40)),
                  text("Label", CGRect(x: 8, y: 4, width: 60, height: labelHeight(width: 60))),
              ])),
              frame: CGRect(x: 50, y: 60, width: 0, height: 0))
    }

    private func child(_ layer: Layer, _ name: String) -> Layer? {
        layer.selfAndDescendants.first { $0.name == name }
    }

    // MARK: - The box lands where it was dragged

    @Test("A group resized to a box occupies exactly that box")
    func theBoxLandsOnTheTarget() {
        let target = CGRect(x: 10, y: 20, width: 200, height: 80)
        let resized = card().resized(to: target)
        #expect(resized.localBounds == target)
    }

    @Test("Every piece inside moves and grows by the same amount the box did")
    func childrenScaleWithTheBox() {
        // (50, 60, 100, 40) → (50, 60, 200, 80): twice as wide and twice as tall,
        // anchored at the same top left.
        let resized = card().resized(to: CGRect(x: 50, y: 60, width: 200, height: 80))
        #expect(child(resized, "Box")?.frame == CGRect(x: 0, y: 0, width: 200, height: 80))
        // The label's box doubles across, because that is its wrap width; down
        // it is as tall as one line of 14-point type, which is what it holds.
        #expect(child(resized, "Label")?.frame == CGRect(x: 16, y: 8, width: 120,
                                                         height: labelHeight(width: 120)))
    }

    @Test("A resize that changes the box's corner scales and moves in one step")
    func draggingTheTopLeftCornerScalesTowardTheOppositeCorner() {
        // Grab the top left and pull it to (0, 40): the bottom right (150, 100)
        // stays put, so the box becomes (0, 40, 150, 60).
        let resized = card().resized(to: CGRect(x: 0, y: 40, width: 150, height: 60))
        #expect(resized.localBounds == CGRect(x: 0, y: 40, width: 150, height: 60))
        // The label sat 8 % in from the left of a 100-wide box; it still does.
        let label = child(resized, "Label")
        #expect(label?.frame.width == 90)
        #expect(label?.frame.height == labelHeight(width: 90))
    }

    @Test("Nothing inside ever lands outside the box that was dragged")
    func everythingStaysInsideTheDraggedBox() {
        let target = CGRect(x: -20, y: 5, width: 37, height: 91)
        let resized = card().resized(to: target)
        for piece in resized.children {
            let inParentSpace = piece.localBounds.offsetBy(dx: resized.frame.minX,
                                                           dy: resized.frame.minY)
            #expect(target.insetBy(dx: -0.001, dy: -0.001).contains(inParentSpace))
        }
    }

    // MARK: - What holds its size

    @Test("Text keeps its point size when the group it sits in is scaled")
    func textKeepsItsPointSize() {
        let resized = card().resized(to: CGRect(x: 50, y: 60, width: 400, height: 160))
        guard case .text(let content)? = child(resized, "Label")?.content else {
            Issue.record("the label stopped being text")
            return
        }
        #expect(content.fontSize == 14)
    }

    @Test("A stroke and a corner radius keep their point sizes")
    func strokesAndRadiiHoldStill() {
        var shape = AnnotationContent(shape: .rectangle)
        shape.strokeWidth = 4
        shape.cornerRadius = 6
        let drawn = AnnotationBuilder.layer(content: shape, from: .zero,
                                            to: CGPoint(x: 40, y: 20))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [drawn])),
                          frame: .zero)
        let doubled = group.resized(to: group.localBounds.applying(
            CGAffineTransform(scaleX: 3, y: 3)))
        let after = doubled.children.first?.annotation
        #expect(after?.strokeWidth == 4)
        #expect(after?.cornerRadius == 6)
    }

    @Test("A shape's drawn span scales with the group")
    func aDrawnShapeScales() {
        let drawn = AnnotationBuilder.layer(content: AnnotationContent(shape: .line),
                                            from: .zero, to: CGPoint(x: 40, y: 0))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [drawn])),
                          frame: .zero)
        let before = group.localBounds
        let after = group.resized(to: CGRect(x: before.minX, y: before.minY,
                                             width: before.width * 2, height: before.height))
        let line = after.children.first
        let span = (line?.annotationEndpoint(.end)?.x ?? 0) - (line?.annotationEndpoint(.start)?.x ?? 0)
        #expect(abs(abs(span) - 80) < 0.5)
    }

    // MARK: - Groups inside groups

    @Test("A group inside a group scales too, contents and all")
    func nestedGroupsScale() {
        let inner = Layer(name: "Inner",
                          content: .group(GroupContent(children: [
                              box("Dot", CGRect(x: 0, y: 0, width: 10, height: 10)),
                          ])),
                          frame: CGRect(x: 20, y: 20, width: 0, height: 0))
        let outer = Layer(name: "Outer",
                          content: .group(GroupContent(children: [
                              box("Plate", CGRect(x: 0, y: 0, width: 40, height: 40)), inner,
                          ])),
                          frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        #expect(outer.localBounds == CGRect(x: 0, y: 0, width: 40, height: 40))
        let scaled = outer.resized(to: CGRect(x: 0, y: 0, width: 80, height: 80))
        #expect(scaled.localBounds == CGRect(x: 0, y: 0, width: 80, height: 80))
        let dot = scaled.selfAndDescendants.first { $0.name == "Dot" }
        #expect(dot?.frame == CGRect(x: 0, y: 0, width: 20, height: 20))
        let nested = scaled.children.first { $0.name == "Inner" }
        #expect(nested?.frame.origin == CGPoint(x: 40, y: 40))
    }

    @Test("A frame inside a scaled group scales its box and its contents")
    func aNestedFrameScalesWithItsGroup() {
        let screen = Layer.frameLayer(name: "Screen", origin: CGPoint(x: 0, y: 0),
                                      size: CGSize(width: 100, height: 100),
                                      children: [box("Tile", CGRect(x: 10, y: 10,
                                                                    width: 20, height: 20))])
        let group = Layer(name: "Group", content: .group(GroupContent(children: [screen])),
                          frame: .zero)
        let scaled = group.resized(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let inner = scaled.children.first
        #expect(inner?.frame == CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(inner?.children.first?.frame == CGRect(x: 20, y: 20, width: 40, height: 40))
    }

    @Test("Dragging a frame's own handle still moves where it clips, it does not scale")
    func aFrameResizesItsClipBoxNotItsContents() {
        let screen = Layer.frameLayer(name: "Screen", origin: .zero,
                                      size: CGSize(width: 100, height: 100),
                                      children: [box("Tile", CGRect(x: 10, y: 10,
                                                                    width: 20, height: 20))])
        let wider = screen.resized(to: CGRect(x: 0, y: 0, width: 300, height: 100))
        #expect(wider.frame == CGRect(x: 0, y: 0, width: 300, height: 100))
        #expect(wider.children.first?.frame == CGRect(x: 10, y: 10, width: 20, height: 20))
    }

    // MARK: - Moving is a resize that changed no size

    @Test("Resizing a group to a box the same size just moves it")
    func aSameSizeBoxIsAPlainMove() {
        let moved = card().resized(to: CGRect(x: 0, y: 0, width: 100, height: 40))
        #expect(moved.localBounds == CGRect(x: 0, y: 0, width: 100, height: 40))
        #expect(child(moved, "Box")?.frame == CGRect(x: 0, y: 0, width: 100, height: 40))
        #expect(child(moved, "Label")?.frame
                == CGRect(x: 8, y: 4, width: 60, height: labelHeight(width: 60)))
    }

    @Test("Scaling up and back down again returns the geometry it started with")
    func scalingRoundTrips() {
        let start = card()
        let big = start.resized(to: CGRect(x: 50, y: 60, width: 350, height: 140))
        let back = big.resized(to: start.localBounds)
        #expect(back.localBounds == start.localBounds)
        for name in ["Box", "Label"] {
            let a = child(start, name)?.frame ?? .null
            let b = child(back, name)?.frame ?? .infinite
            #expect(abs(a.minX - b.minX) < 0.001)
            #expect(abs(a.minY - b.minY) < 0.001)
            #expect(abs(a.width - b.width) < 0.001)
            #expect(abs(a.height - b.height) < 0.001)
        }
    }

    // MARK: - Nothing to scale

    @Test("A group with no height is not stretched vertically, and stays finite")
    func aFlatGroupIsNotStretched() {
        let rule = Layer(name: "Group",
                         content: .group(GroupContent(children: [
                             box("Rule", CGRect(x: 0, y: 0, width: 100, height: 0)),
                         ])),
                         frame: .zero)
        let scaled = rule.resized(to: CGRect(x: 0, y: 0, width: 200, height: 50))
        #expect(scaled.localBounds == CGRect(x: 0, y: 0, width: 200, height: 0))
        for piece in scaled.selfAndDescendants {
            #expect(piece.frame.origin.x.isFinite && piece.frame.origin.y.isFinite)
            #expect(piece.frame.width.isFinite && piece.frame.height.isFinite)
        }
    }

    @Test("An empty group resizes to nothing rather than crashing")
    func anEmptyGroupSurvivesAResize() {
        let empty = Layer(name: "Group", content: .group(GroupContent()),
                          frame: CGRect(x: 4, y: 5, width: 0, height: 0))
        let scaled = empty.resized(to: CGRect(x: 10, y: 10, width: 40, height: 40))
        #expect(scaled.localBounds.origin == CGPoint(x: 10, y: 10))
        #expect(scaled.localBounds.size == .zero)
    }

    // MARK: - Handles and typed numbers

    @Test("A group offers the eight frame handles and takes a typed width and height")
    func aGroupOffersHandlesAndTypedNumbers() {
        let group = card()
        #expect(group.allowsFrameResize)
        let editing = LayerGeometryEditing(layer: group)
        for field in LayerGeometryField.allCases { #expect(editing.allows(field)) }
        #expect(editing.fixedReason(for: .width) == nil)
        #expect(editing.fixedReason(for: .height) == nil)
    }

    @Test("A copy of a component says its size comes from the original")
    func aComponentCopyIsNotResizable() {
        var content = GroupContent(children: card().children)
        content.instanceOf = UUID()
        let copy = Layer(name: "Card", content: .group(content), frame: .zero)
        #expect(!copy.allowsFrameResize)
        let editing = LayerGeometryEditing(layer: copy)
        #expect(editing.allows(.x))
        #expect(!editing.allows(.width))
        #expect(!editing.allows(.height))
        #expect(editing.fixedReason(for: .width) == LayerGeometryEditing.instanceSizeReason)
    }

    @Test("A main component resizes like any other group, so its copies follow")
    func aMainComponentResizes() {
        var content = GroupContent(children: card().children)
        content.componentID = UUID()
        let main = Layer(name: "Card", content: .group(content), frame: .zero)
        #expect(main.allowsFrameResize)
    }

    // MARK: - What a measurement says afterwards

    @Test("A caliper inside a group that doubled reports twice the distance")
    func aCaliperReportsTheNewDistance() {
        let caliper = MeasureBuilder.layer(content: MeasureContent(mode: .horizontal),
                                           from: CGPoint(x: 0, y: 0),
                                           to: CGPoint(x: 100, y: 0))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [caliper])),
                          frame: .zero)
        let before = group.localBounds
        let doubled = group.resized(to: CGRect(x: before.minX, y: before.minY,
                                               width: before.width * 2, height: before.height))
        guard let after = doubled.children.first, let m = after.measure else {
            Issue.record("the caliper stopped being a caliper")
            return
        }
        #expect(abs(abs(m.end.x - m.start.x) - 200) < 0.5)
        // The ticks it draws with are points, not a share of the box, so they
        // are exactly the width they were.
        #expect(m.strokeWidth == caliper.measure?.strokeWidth)
    }

    // MARK: - Through the document

    @Test("Resizing a group in a document is one edit that carries the whole subtree")
    func resizingThroughTheDocument() {
        let group = card()
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [group])
        let target = CGRect(x: 50, y: 60, width: 200, height: 80)
        doc.updateLayer(id: group.id) { $0 = $0.resized(to: target) }
        #expect(doc.canvasBounds(of: group.id) == target)
        let label = doc.allLayers.first { $0.name == "Label" }
        #expect(doc.canvasFrame(of: label?.id ?? UUID())
                == CGRect(x: 66, y: 68, width: 120, height: labelHeight(width: 120)))
    }

    @Test("A copy of a component inside a resized group moves with it but keeps its size")
    func aCopyInsideAResizedGroupKeepsItsSize() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 600, height: 600))
        var original = card()
        original.frame = CGRect(x: 0, y: 0, width: 0, height: 0)
        doc.addLayer(original)
        guard let componentID = doc.makeComponent(id: original.id),
              let copyID = doc.insertComponentInstance(of: componentID,
                                                       at: CGPoint(x: 300, y: 300)) else {
            Issue.record("could not make a component and a copy of it")
            return
        }
        let sizeBefore = doc.canvasBounds(of: copyID)?.size
        // Wrap the copy in a group and pull that group twice as wide.
        guard let group = doc.groupLayers(ids: [copyID]) else {
            Issue.record("could not group the copy")
            return
        }
        let groupID = group.id
        let box = doc.canvasBounds(of: groupID) ?? .zero
        doc.updateLayer(id: groupID) {
            $0 = $0.resized(to: CGRect(x: box.minX, y: box.minY,
                                       width: box.width * 2, height: box.height))
        }
        doc.syncComponentInstances()
        #expect(doc.canvasBounds(of: copyID)?.size == sizeBefore)
    }
}
