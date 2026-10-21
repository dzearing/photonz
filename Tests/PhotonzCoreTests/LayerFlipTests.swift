import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Flip Horizontal and Flip Vertical (Photoshop's Edit ▸ Transform pair): what
/// is picked is mirrored in place, about its own middle, or about the middle
/// of everything picked when there are several.
@Suite("Layer flip")
struct LayerFlipTests {

    // MARK: Fixtures

    private func rectangle(_ frame: CGRect, name: String = "Rectangle") -> Layer {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#112233",
                                        start: .zero, end: CGPoint(x: frame.width, y: frame.height),
                                        fillColorHex: "#445566")
        return Layer(name: name, content: .annotation(content), frame: frame)
    }

    private func arrow(_ frame: CGRect, from: CGPoint, to: CGPoint) -> Layer {
        let content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#112233",
                                        start: from, end: to)
        return Layer(name: "Arrow", content: .annotation(content), frame: frame)
    }

    private func picture(_ frame: CGRect) -> Layer {
        Layer(name: "Picture", content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    private func words(_ frame: CGRect) -> Layer {
        Layer(name: "Words", content: .text(TextContent(string: "Hello")), frame: frame)
    }

    private func doc(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: layers)
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    // MARK: One layer, in place

    @Test func aPictureFlipsAboutItsOwnMiddleAndStaysWhereItIs() throws {
        var d = doc([picture(CGRect(x: 10, y: 20, width: 100, height: 50))])
        let layer = id(d, "Picture")
        let flippedIt = d.flip(ids: [layer], .horizontal)
        #expect(flippedIt)
        let flipped = try #require(d.layer(id: layer))
        #expect(flipped.frame == CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(flipped.transform.flipHorizontal)
        #expect(!flipped.transform.flipVertical)
        let flippedAgain = d.flip(ids: [layer], .vertical)
        #expect(flippedAgain)
        #expect(d.layer(id: layer)?.transform.flipVertical == true)
    }

    @Test func flippingTwiceGivesBackTheLayerItWas() throws {
        let original = arrow(CGRect(x: 0, y: 0, width: 100, height: 40),
                             from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 40))
        var d = doc([original])
        for axis in FlipAxis.allCases {
            d.flip(ids: [original.id], axis)
            d.flip(ids: [original.id], axis)
            #expect(d.layer(id: original.id) == original)
        }
    }

    @Test func wordsReadMirroredBecauseTheyAreFlippedNotRewritten() throws {
        var d = doc([words(CGRect(x: 10, y: 10, width: 80, height: 30))])
        let layer = id(d, "Words")
        d.flip(ids: [layer], .horizontal)
        let flipped = try #require(d.layer(id: layer))
        #expect(flipped.transform.flipHorizontal)
        #expect(flipped.text?.string == "Hello")
    }

    @Test func anArrowsEndsSwapSidesInItsOwnNumbers() throws {
        var d = doc([arrow(CGRect(x: 0, y: 0, width: 100, height: 40),
                           from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 40))])
        let layer = id(d, "Arrow")
        d.flip(ids: [layer], .horizontal)
        var mark = try #require(d.layer(id: layer)?.annotation)
        #expect(mark.start == CGPoint(x: 100, y: 0))
        #expect(mark.end == CGPoint(x: 0, y: 40))
        d.flip(ids: [layer], .vertical)
        mark = try #require(d.layer(id: layer)?.annotation)
        #expect(mark.start == CGPoint(x: 100, y: 40))
        #expect(mark.end == CGPoint(x: 0, y: 0))
        // Drawn in its own numbers, so nothing is left on the transform.
        #expect(d.layer(id: layer)?.transform.isIdentity == true)
    }

    @Test func aPathIsReflectedPointForPoint() throws {
        let path = PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 0)),
                                         PathAnchor(point: CGPoint(x: 30, y: 10)),
                                         PathAnchor(point: CGPoint(x: 10, y: 20))],
                               isClosed: true)
        let layer = Layer(name: "Path", content: .path(path), frame: CGRect(x: 5, y: 5, width: 30, height: 20))
        var d = doc([layer])
        d.flip(ids: [layer.id], .vertical)
        let flipped = try #require(d.layer(id: layer.id)?.path)
        #expect(flipped.anchors.map(\.point) == [CGPoint(x: 0, y: 20), CGPoint(x: 30, y: 10), CGPoint(x: 10, y: 0)])
        #expect(d.layer(id: layer.id)?.frame == layer.frame)
    }

    @Test func aRoundedCornerChangesSideTopToBottom() throws {
        var box = rectangle(CGRect(x: 0, y: 0, width: 50, height: 50))
        if var mark = box.annotation {
            mark.cornerRadii = CornerRadii(topLeft: 8, topRight: 0, bottomRight: 0, bottomLeft: 0)
            box.content = .annotation(mark)
        }
        var d = doc([box])
        d.flip(ids: [box.id], .vertical)
        #expect(d.layer(id: box.id)?.annotation?.cornerRadii
                == CornerRadii(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 8))
    }

    @Test func aTurnedLayerIsMirroredOnTheCanvasSoItTurnsTheOtherWay() throws {
        var layer = picture(CGRect(x: 10, y: 10, width: 100, height: 50))
        layer.transform.rotation = 0.3
        layer.transform.skewX = 0.1
        var d = doc([layer])
        d.flip(ids: [layer.id], .vertical)
        let flipped = try #require(d.layer(id: layer.id))
        #expect(flipped.transform.rotation == -0.3)
        #expect(flipped.transform.skewX == -0.1)
        #expect(flipped.transform.flipVertical)
        // The drawn corners are the old ones reflected about the middle line.
        let mid = layer.frame.midY
        let was = Set(layer.transformedCorners.map { CGPoint(x: round($0.x * 1000), y: round((2 * mid - $0.y) * 1000)) })
        let now = Set(flipped.transformedCorners.map { CGPoint(x: round($0.x * 1000), y: round($0.y * 1000)) })
        #expect(was == now)
    }

    @Test func aTurningLayerTurnsTheOtherWayAtEveryMoment() throws {
        var layer = picture(CGRect(x: 10, y: 10, width: 100, height: 50))
        layer.motions = [LayerMotion(property: .rotation, from: .number(0), to: .number(90),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000))]
        var d = doc([layer])
        d.flip(ids: [layer.id], .horizontal)
        let motion = try #require(d.layer(id: layer.id)?.motions?.first)
        #expect(motion.from == .number(0))
        #expect(motion.to == .number(-90))
    }

    // MARK: Several, about their shared middle

    @Test func severalPickedSwapSidesAboutTheirSharedMiddle() throws {
        let left = rectangle(CGRect(x: 0, y: 0, width: 20, height: 10), name: "Left")
        let right = rectangle(CGRect(x: 80, y: 30, width: 20, height: 10), name: "Right")
        var d = doc([left, right])
        d.flip(ids: [left.id, right.id], .horizontal)
        #expect(d.layer(id: left.id)?.frame == CGRect(x: 80, y: 0, width: 20, height: 10))
        #expect(d.layer(id: right.id)?.frame == CGRect(x: 0, y: 30, width: 20, height: 10))
        d.flip(ids: [left.id, right.id], .vertical)
        #expect(d.layer(id: left.id)?.frame == CGRect(x: 80, y: 30, width: 20, height: 10))
        #expect(d.layer(id: right.id)?.frame == CGRect(x: 0, y: 0, width: 20, height: 10))
    }

    @Test func aMovingLayerFlippedWithOthersKeepsItsPathShiftedWithIt() throws {
        var left = rectangle(CGRect(x: 0, y: 0, width: 20, height: 10), name: "Left")
        left.motions = [LayerMotion(property: .position, from: .point(CGPoint(x: 0, y: 0)),
                                    to: .point(CGPoint(x: 10, y: 0)),
                                    timing: MotionTiming(startMS: 0, durationMS: 1000))]
        let right = rectangle(CGRect(x: 80, y: 0, width: 20, height: 10), name: "Right")
        var d = doc([left, right])
        d.flip(ids: [left.id, right.id], .horizontal)
        let motion = try #require(d.layer(id: left.id)?.motions?.first)
        #expect(motion.from == .point(CGPoint(x: 80, y: 0)))
        #expect(motion.to == .point(CGPoint(x: 90, y: 0)))
    }

    @Test func aGroupFlipsItsContentsAboutTheGroupsMiddle() throws {
        let a = rectangle(CGRect(x: 0, y: 0, width: 10, height: 10), name: "A")
        let b = rectangle(CGRect(x: 40, y: 0, width: 20, height: 10), name: "B")
        var d = doc([a, b])
        let grouped = d.groupLayers(ids: [a.id, b.id], name: "Group")?.id
        let group = try #require(grouped)
        let before = try #require(d.canvasBounds(of: group))
        d.flip(ids: [group], .horizontal)
        #expect(d.canvasBounds(of: group) == before)
        #expect(d.canvasFrame(of: a.id) == CGRect(x: 50, y: 0, width: 10, height: 10))
        #expect(d.canvasFrame(of: b.id) == CGRect(x: 0, y: 0, width: 20, height: 10))
    }

    @Test func aComponentCopyWearsTheFlipAndKeepsFollowingItsOriginal() throws {
        let a = rectangle(CGRect(x: 0, y: 0, width: 10, height: 10), name: "A")
        let b = rectangle(CGRect(x: 40, y: 0, width: 20, height: 10), name: "B")
        var d = doc([a, b])
        let grouped = d.groupLayers(ids: [a.id, b.id], name: "Card")?.id
        let group = try #require(grouped)
        let made = d.makeComponent(id: group)
        let component = try #require(made)
        let placed = d.insertComponentInstance(of: component, at: CGPoint(x: 200, y: 200))
        let copy = try #require(placed)
        let before = try #require(d.canvasBounds(of: copy))
        #expect(d.canFlip(ids: [copy]))
        d.flip(ids: [copy], .horizontal)
        let flipped = try #require(d.layer(id: copy))
        #expect(flipped.transform.flipHorizontal)
        #expect(flipped.isComponentInstance)
        #expect(d.canvasBounds(of: copy) == before)
    }

    // MARK: What is left alone

    @Test func aLockedLayerAndAMeasurementAreNotFlipped() throws {
        var locked = picture(CGRect(x: 0, y: 0, width: 10, height: 10))
        locked.isLocked = true
        var d = doc([locked])
        #expect(!d.canFlip(ids: [locked.id]))
        let flippedIt = d.flip(ids: [locked.id], .horizontal)
        #expect(!flippedIt)
        #expect(d.layer(id: locked.id)?.transform.isIdentity == true)
        #expect(!d.canFlip(ids: []))
    }

    @Test func theTitlesArePhotoshops() {
        #expect(FlipAxis.horizontal.title == "Flip Horizontal")
        #expect(FlipAxis.vertical.title == "Flip Vertical")
    }

    // MARK: A side handle dragged past the other side

    @Test func aRightHandleDraggedPastTheLeftEdgeFlipsAndKeepsGoing() {
        let start = CGRect(x: 400, y: 300, width: 200, height: 150)
        let r = Handles.resizeFlipping(start, dragging: .right, to: CGPoint(x: 300, y: 375),
                                       preserveAspect: false)
        #expect(r.frame == CGRect(x: 300, y: 300, width: 100, height: 150))
        #expect(r.flips == [.horizontal])
    }

    @Test func aHandleThatHasNotCrossedIsThePlainResize() {
        let start = CGRect(x: 400, y: 300, width: 200, height: 150)
        let p = CGPoint(x: 450, y: 375)
        let r = Handles.resizeFlipping(start, dragging: .right, to: p, preserveAspect: false)
        #expect(r.frame == Handles.resize(start, dragging: .right, to: p, preserveAspect: false))
        #expect(r.flips.isEmpty)
    }

    @Test func aCornerDraggedPastBothSidesFlipsBothWays() {
        let start = CGRect(x: 100, y: 100, width: 100, height: 50)
        let r = Handles.resizeFlipping(start, dragging: .bottomRight, to: CGPoint(x: 60, y: 80),
                                       preserveAspect: false)
        #expect(r.frame == CGRect(x: 60, y: 80, width: 40, height: 20))
        #expect(r.flips == [.horizontal, .vertical])
    }

    @Test func aTopHandleDraggedBelowTheBottomFlipsUpsideDown() {
        let start = CGRect(x: 0, y: 0, width: 100, height: 50)
        let r = Handles.resizeFlipping(start, dragging: .top, to: CGPoint(x: 50, y: 70),
                                       preserveAspect: false)
        #expect(r.frame == CGRect(x: 0, y: 50, width: 100, height: 20))
        #expect(r.flips == [.vertical])
    }

    @Test func aShapeKeptCornerFlipsAtTheSameShape() {
        let start = CGRect(x: 0, y: 0, width: 100, height: 50)
        let r = Handles.resizeFlipping(start, dragging: .right, to: CGPoint(x: -50, y: 25),
                                       preserveAspect: true)
        #expect(r.frame.width == 50)
        #expect(r.frame.height == 25)
        #expect(r.frame.maxX == 0)
        #expect(r.flips == [.horizontal])
    }

    @Test func theAnchorStaysPutOnATurnedLayerFlippedByItsHandle() {
        let start = CGRect(x: 0, y: 0, width: 100, height: 50)
        let transform = LayerTransform(rotation: 0.5)
        let proposed = CGRect(x: -40, y: 0, width: 40, height: 50)
        let anchored = Handles.anchoredFrame(start: start, proposed: proposed, handle: .right,
                                             transform: transform, flips: [.horizontal])
        let was = Handles.point(for: .left, in: start)
            .applying(transform.affineTransform(around: CGPoint(x: start.midX, y: start.midY)))
        // The left edge the drag held is now the box's RIGHT edge.
        let now = Handles.point(for: .right, in: anchored)
            .applying(transform.affineTransform(around: CGPoint(x: anchored.midX, y: anchored.midY)))
        #expect(abs(was.x - now.x) < 1e-9 && abs(was.y - now.y) < 1e-9)
    }

    @Test func mirroringInPlaceKeepsTheTurnAndTheBox() {
        var layer = picture(CGRect(x: 10, y: 10, width: 100, height: 50))
        layer.transform.rotation = 0.4
        let mirrored = layer.mirroredInPlace([.horizontal])
        #expect(mirrored.frame == layer.frame)
        #expect(mirrored.transform.rotation == 0.4)
        #expect(mirrored.transform.flipHorizontal)
    }
}
