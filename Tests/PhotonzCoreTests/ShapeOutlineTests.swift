import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A Border that follows the shape runs round what the layer draws, not round
/// its box: one ring round a whole group, along an arrow's shaft and round its
/// head, round a cut-out's visible edge (`ShapeOutline.swift`). The user,
/// 2026-10-20: "borders are borders, not always boxes."
@Suite("What a border follows on a shape")
struct ShapeOutlineTests {

    private func oval(_ box: CGRect) -> Layer {
        Layer(name: "Oval",
              content: .annotation(AnnotationContent(shape: .ellipse, strokeWidth: 0,
                                                     start: .zero,
                                                     end: CGPoint(x: box.width, y: box.height),
                                                     fillColorHex: "#FF0000")),
              frame: box)
    }

    private func rectangle(_ box: CGRect) -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                     start: .zero,
                                                     end: CGPoint(x: box.width, y: box.height),
                                                     fillColorHex: "#FF0000")),
              frame: box)
    }

    private func arrow() -> Layer {
        Layer(name: "Arrow",
              content: .annotation(AnnotationContent(shape: .arrow, strokeWidth: 4,
                                                     start: CGPoint(x: 10, y: 10),
                                                     end: CGPoint(x: 190, y: 90))),
              frame: CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    private func group(_ children: [Layer], at anchor: CGPoint = .zero) -> Layer {
        Layer(name: "Group", content: .group(GroupContent(children: children)),
              frame: CGRect(origin: anchor, size: .zero))
    }

    private func picture() -> Layer {
        Layer(name: "Sticker",
              content: .image(ImageRef(pixelSize: CGSize(width: 100, height: 100))),
              frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    /// Two overlapping shapes in a group: the outline goes round the pair as
    /// ONE shape, so a point in the overlap is inside it, a point in the box's
    /// empty corner is not, and there is no edge left where the two met.
    @Test func aGroupIsOutlinedAsTheUnionOfItsParts() throws {
        let package = group([oval(CGRect(x: 0, y: 0, width: 100, height: 100)),
                             rectangle(CGRect(x: 50, y: 40, width: 100, height: 60))])
        let outline = try #require(package.followedOutline())
        let path = outline.cgPath
        #expect(outline.isClosed)
        // In the oval, in the box, and where they overlap.
        #expect(path.contains(CGPoint(x: 20, y: 50)))
        #expect(path.contains(CGPoint(x: 140, y: 70)))
        #expect(path.contains(CGPoint(x: 75, y: 60)))
        // The group's box reaches the top right corner; the shapes do not.
        #expect(!path.contains(CGPoint(x: 145, y: 5)))
        #expect(!path.contains(CGPoint(x: 3, y: 97)))
        // One ring round the whole: the oval's edge that ran through the box
        // is gone, so it is a single loop.
        var loops = 0
        path.applyWithBlock { if $0.pointee.type == .moveToPoint { loops += 1 } }
        #expect(loops == 1)
        let bounds = path.boundingBoxOfPath
        #expect(abs(bounds.minX) < 0.5 && abs(bounds.minY) < 0.5)
        #expect(abs(bounds.maxX - 150) < 0.5 && abs(bounds.maxY - 100) < 0.5)
    }

    /// The outline is stated from the top-left of the GROUP'S box, which is
    /// where its parts are, not from the anchor it is moved by.
    @Test func aGroupOutlineStartsAtItsOwnBox() throws {
        let package = group([oval(CGRect(x: 30, y: 20, width: 100, height: 100))],
                            at: CGPoint(x: 400, y: 300))
        let outline = try #require(package.followedOutline())
        let bounds = outline.cgPath.boundingBoxOfPath
        #expect(abs(bounds.minX) < 0.5 && abs(bounds.minY) < 0.5)
        #expect(abs(bounds.width - 100) < 0.5 && abs(bounds.height - 100) < 0.5)
    }

    /// A document the renderer has magnified has frames in pixels and drawings
    /// in points, and the outline comes back in points either way.
    @Test func aMagnifiedGroupGivesItsOutlineInPoints() throws {
        var magnified = oval(CGRect(x: 0, y: 0, width: 200, height: 200))
        if case .annotation(var mark) = magnified.content {
            mark.end = CGPoint(x: 100, y: 100)
            magnified.content = .annotation(mark)
        }
        let package = group([magnified])
        let outline = try #require(package.followedOutline(contentScale: 2))
        let bounds = outline.cgPath.boundingBoxOfPath
        #expect(abs(bounds.width - 100) < 0.5)
    }

    /// A turned part is outlined turned.
    @Test func aTurnedPartIsOutlinedTurned() throws {
        var bar = rectangle(CGRect(x: 0, y: 0, width: 100, height: 10))
        bar.transform.rotation = .pi / 2
        let outline = try #require(group([bar]).followedOutline())
        let bounds = outline.cgPath.boundingBoxOfPath
        #expect(abs(bounds.width - 10) < 0.5)
        #expect(abs(bounds.height - 100) < 0.5)
    }

    /// A hidden part draws nothing, so the ring does not go round it.
    @Test func aHiddenPartIsLeftOut() throws {
        var hidden = rectangle(CGRect(x: 200, y: 0, width: 50, height: 50))
        hidden.isVisible = false
        let outline = try #require(group([oval(CGRect(x: 0, y: 0, width: 100, height: 100)),
                                          hidden]).followedOutline())
        #expect(outline.cgPath.boundingBoxOfPath.maxX < 101)
    }

    /// An arrow's outline is its shaft AND its head, as one shape: a point on
    /// the shaft and a point in the head are both inside, and the box's empty
    /// corner is not.
    @Test func anArrowIsOutlinedShaftAndHeadTogether() throws {
        let outline = try #require(arrow().followedOutline())
        let path = outline.cgPath
        #expect(path.contains(CGPoint(x: 100, y: 50)))
        // Just behind the tip, inside the head and wider than the shaft.
        let head = Geometry.arrowhead(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 190, y: 90),
                                      strokeWidth: 4, scale: 1, style: .triangle)
        #expect(head.count == 3)
        if head.count == 3 {
            let middle = CGPoint(x: (head[0].x + head[1].x + head[2].x) / 3,
                                 y: (head[0].y + head[1].y + head[2].y) / 3)
            #expect(path.contains(middle))
        }
        #expect(!path.contains(CGPoint(x: 180, y: 10)))
        #expect(!path.contains(CGPoint(x: 20, y: 90)))
    }

    /// A line is the band its stroke covers.
    @Test func aLineIsOutlinedAsItsStroke() throws {
        let line = Layer(name: "Line",
                         content: .annotation(AnnotationContent(shape: .line, strokeWidth: 6,
                                                                start: CGPoint(x: 0, y: 50),
                                                                end: CGPoint(x: 200, y: 50))),
                         frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let bounds = try #require(line.followedOutline()).cgPath.boundingBoxOfPath
        #expect(abs(bounds.height - 6) < 0.5)
    }

    /// A path is its own outline, open or closed, exactly as before.
    @Test func aPathIsItsOwnOutline() throws {
        let content = PathContent(anchors: [PathAnchor(point: .zero),
                                            PathAnchor(point: CGPoint(x: 50, y: 80)),
                                            PathAnchor(point: CGPoint(x: 100, y: 0))],
                                  isClosed: true)
        let layer = Layer(name: "Path", content: .path(content),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 80))
        #expect(layer.followedOutline() == content)
    }

    /// A rectangle, an oval and a frame are drawn some other way: a rectangle
    /// and a frame ARE their box, and an oval has a ring of its own.
    @Test func aBoxAndAnOvalAndAFrameHaveNoOutlineToSweep() {
        #expect(rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)).followedOutline() == nil)
        #expect(oval(CGRect(x: 0, y: 0, width: 10, height: 10)).followedOutline() == nil)
        let frame = Layer(name: "Frame",
                          content: .group(GroupContent(children: [arrow()], isFrame: true)),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(frame.followedOutline() == nil)
    }

    /// A picture follows the edge its transparency makes, stretched to its
    /// frame; a solid picture has none.
    @Test func aPictureFollowsItsSeeThroughEdge() throws {
        let unit = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 1, height: 1), transform: nil)
        let outline = try #require(picture().followedOutline(pictureEdge: { _ in unit }))
        let bounds = outline.cgPath.boundingBoxOfPath
        #expect(abs(bounds.width - 200) < 0.5 && abs(bounds.height - 200) < 0.5)
        #expect(picture().followedOutline() == nil)
    }

    /// What each kind of layer offers the Border row: letters on a label, an
    /// outline on anything with a silhouette, and nothing on a box.
    @Test func whatEachLayerCanFollow() {
        #expect(rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)).shapeToFollow() == .none)
        #expect(oval(CGRect(x: 0, y: 0, width: 10, height: 10)).shapeToFollow() == .outline)
        #expect(arrow().shapeToFollow() == .outline)
        #expect(group([arrow()]).shapeToFollow() == .outline)
        #expect(picture().shapeToFollow() == .none)
        #expect(picture().shapeToFollow(pictureHasEdge: { _ in true }) == .outline)
        let label = Layer(name: "Label", content: .text(TextContent(string: "Hi")),
                          frame: CGRect(x: 0, y: 0, width: 50, height: 20))
        #expect(label.shapeToFollow() == .letters)
    }

    /// The Border row asks Shape or Box of a group, and asks nothing of a box.
    @Test func theRowAsksWhereThereIsAShape() {
        let package = group([arrow()])
        let box = rectangle(CGRect(x: 0, y: 0, width: 10, height: 10))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [package, box])
        #expect(doc.layerStyleSelection(layerIDs: [package.id]).shapeToFollowEverywhere == .outline)
        #expect(doc.layerStyleSelection(layerIDs: [box.id]).shapeToFollowEverywhere == nil)
        #expect(doc.layerStyleSelection(layerIDs: [package.id, box.id]).shapeToFollowEverywhere == nil)
    }
}

/// The see-through edge of a picture, traced out of its alpha.
@Suite("A picture's edge")
struct PictureEdgeTests {

    /// A disc on a clear square: the edge is round, in fractions of the
    /// picture, and smooth rather than a staircase of pixel corners.
    @Test func aDiscTracesToARoundEdge() throws {
        let side = 64
        var alpha = [UInt8](repeating: 0, count: side * side)
        for y in 0..<side {
            for x in 0..<side {
                let dx = CGFloat(x) + 0.5 - 32, dy = CGFloat(y) + 0.5 - 32
                if dx * dx + dy * dy <= 24 * 24 { alpha[y * side + x] = 255 }
            }
        }
        let edge = try #require(PictureEdge.outline(alpha: alpha, width: side, height: side))
        let bounds = edge.boundingBoxOfPath
        #expect(abs(bounds.midX - 0.5) < 0.02 && abs(bounds.midY - 0.5) < 0.02)
        #expect(abs(bounds.width - 48.0 / 64) < 0.03)
        #expect(edge.contains(CGPoint(x: 0.5, y: 0.5)))
        #expect(!edge.contains(CGPoint(x: 0.05, y: 0.05)))
        // Far fewer points than the staircase had corners.
        let points = PictureEdge.rings(of: edge).map(\.count).reduce(0, +)
        #expect(points < 120)
    }

    /// Where it is solid to every edge, there is no edge to follow but the box.
    @Test func aSolidPictureHasNoEdge() {
        #expect(PictureEdge.outline(alpha: [UInt8](repeating: 255, count: 16), width: 4, height: 4) == nil)
        #expect(PictureEdge.outline(alpha: [UInt8](repeating: 0, count: 16), width: 4, height: 4) == nil)
    }

    /// The top row of the alpha is the top of the picture.
    @Test func theFirstRowIsTheTop() throws {
        var alpha = [UInt8](repeating: 0, count: 100)
        for x in 0..<10 { for y in 0..<3 { alpha[y * 10 + x] = 255 } }
        let edge = try #require(PictureEdge.outline(alpha: alpha, width: 10, height: 10))
        let bounds = edge.boundingBoxOfPath
        #expect(bounds.minY < 0.05)
        #expect(abs(bounds.maxY - 0.3) < 0.06)
    }
}
