import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A piece that moves inside an icon that is itself moving.
///
/// Written before the fix, which is the rule for `PhotonzCore`. Growing a
/// group magnifies everything in it, so a piece told to slide 20pt inside a
/// group drawn at twice the size has to travel 40pt: in an exported file the
/// slide is written INSIDE the growth (`MotionProperty.nestingOrder`), and a
/// browser multiplies it without being asked. The canvas did not, so the same
/// icon played one way in the app and another way everywhere else.
@Suite("A piece inside a growing icon moves by the grown distance")
struct NestedMotionTests {

    // MARK: - Things to move

    static let lapMS = 1000

    /// A 10pt square at the corner of whatever contains it.
    static func piece(strokeWidth: CGFloat = 2) -> Layer {
        let path = PathContent(anchors: [PathAnchor(point: .zero),
                                         PathAnchor(point: CGPoint(x: 10, y: 0)),
                                         PathAnchor(point: CGPoint(x: 10, y: 10)),
                                         PathAnchor(point: CGPoint(x: 0, y: 10))],
                               isClosed: true,
                               paint: Paint(hex: "#112233"),
                               strokeWidth: strokeWidth,
                               fill: Paint(hex: "#AABBCC"))
        return Layer(name: "Dot", content: .path(path),
                     frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    /// A slide that is over by the half way mark and then holds, so both ends
    /// of the lap are exact numbers rather than samples of a curve.
    static func slide(to point: CGPoint) -> LayerMotion {
        LayerMotion(property: .position, from: .point(.zero), to: .point(point),
                    timing: MotionTiming(startMS: 0, durationMS: lapMS / 2),
                    curve: .linear, repeats: .forever)
    }

    /// A growth pinned at one size for the whole lap.
    static func growth(toPercent percent: Double) -> LayerMotion {
        LayerMotion(property: .scale, from: .number(percent), to: .number(percent),
                    timing: MotionTiming(startMS: 0, durationMS: lapMS),
                    curve: .linear, repeats: .forever)
    }

    /// A 100pt icon frame holding `children`, growing to `percent`.
    ///
    /// It does not cut off what sticks out of it, because a frame that does
    /// leaves as a picture rather than as shapes, and a picture has no
    /// animation in it to compare the canvas against (`SVGExport.answer`).
    static func icon(_ children: [Layer], growingTo percent: Double? = 200) -> Layer {
        var frame = Layer(name: "Icon",
                          content: .group(GroupContent(children: children, isFrame: true,
                                                       clipsContents: false,
                                                       backgroundHex: "#FFFFFF")),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        if let percent { frame.motions = [growth(toPercent: percent)] }
        return frame
    }

    static func document(_ icon: Layer) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100),
                                       layers: [icon])
        document.motionCycleMS = lapMS
        return document
    }

    /// The piece as the canvas draws it `ms` into the lap, in the coordinates
    /// its group states it in.
    static func pieceOnCanvas(_ document: PhotonzDocument, atMS ms: Int) throws -> Layer {
        let icon = try #require(document.moved(toMotionTimeMS: ms).layers.first)
        return try #require(icon.group?.children.first)
    }

    // MARK: - The distance itself

    /// THE TEST: 20pt of slide inside a group drawn at 200% is 40pt of slide.
    @Test func aPieceSlidesTheGrownDistance() throws {
        var dot = Self.piece()
        dot.motions = [Self.slide(to: CGPoint(x: 20, y: 0))]
        let document = Self.document(Self.icon([dot]))

        let atTheTop = try Self.pieceOnCanvas(document, atMS: 0)
        #expect(atTheTop.frame.origin.x == 0)
        #expect(atTheTop.frame.width == 20, "the piece itself is drawn at twice the size")

        let atTheEnd = try Self.pieceOnCanvas(document, atMS: 900)
        #expect(atTheEnd.frame.origin.x == 40,
                "20pt of slide on a drawing at twice the size is 40pt of slide")
        #expect(atTheEnd.frame.width == 20)
    }

    /// Half way along the slide is half the grown distance, so the piece
    /// travels at the right speed and not just to the right place.
    @Test func aPieceIsHalfWayAlongTheGrownDistanceHalfWayThrough() throws {
        var dot = Self.piece()
        dot.motions = [Self.slide(to: CGPoint(x: 20, y: 0))]
        let document = Self.document(Self.icon([dot]))
        let quarter = try Self.pieceOnCanvas(document, atMS: 250)
        #expect(abs(quarter.frame.origin.x - 20) < 0.001)
    }

    /// A group that is NOT growing leaves the distance exactly as it was
    /// written: the magnification is the only thing that multiplies it.
    @Test func aPieceInAStillIconSlidesTheDistanceItWasGiven() throws {
        var dot = Self.piece()
        dot.motions = [Self.slide(to: CGPoint(x: 20, y: 0))]
        let document = Self.document(Self.icon([dot], growingTo: nil))
        #expect(try Self.pieceOnCanvas(document, atMS: 900).frame.origin.x == 20)
    }

    /// Two growths compose: a piece inside a group at 200% inside a group at
    /// 150% slides three times as far.
    @Test func growthsCompoundDownTheTree() throws {
        var dot = Self.piece()
        dot.motions = [Self.slide(to: CGPoint(x: 20, y: 0))]
        var inner = Layer(name: "Inner", content: .group(GroupContent(children: [dot])),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        inner.motions = [Self.growth(toPercent: 200)]
        let document = Self.document(Self.icon([inner], growingTo: 150))
        let moved = try #require(document.moved(toMotionTimeMS: 900).layers.first)
        let piece = try #require(moved.group?.children.first?.group?.children.first)
        #expect(abs(piece.frame.origin.x - 60) < 0.001,
                "20pt through 200% and then 150% is 60pt")
    }

    /// The line round a piece is stated in points too, and a file writes it
    /// inside the growth, so the app has to multiply it the same way.
    @Test func aLineToldToThickenInsideAGrowingIconIsDrawnThicker() throws {
        var dot = Self.piece()
        dot.motions = [LayerMotion(property: .strokeWidth,
                                   from: .number(3), to: .number(3),
                                   timing: MotionTiming(startMS: 0, durationMS: Self.lapMS),
                                   curve: .linear, repeats: .forever)]
        let document = Self.document(Self.icon([dot]))
        let drawn = try Self.pieceOnCanvas(document, atMS: 500)
        #expect(try #require(drawn.path).strokeWidth == 6,
                "3pt of line on a drawing at twice the size is 6pt of line")
    }

    // MARK: - The app and the file agree

    /// What the file says, composed by hand the way a browser composes it:
    /// the slide is written in the units the piece was drawn in and sits
    /// inside the growth, so the growth multiplies it.
    @Test func theCanvasSlidesByExactlyWhatTheFileSays() throws {
        var dot = Self.piece()
        dot.motions = [Self.slide(to: CGPoint(x: 20, y: 0))]
        let document = Self.document(Self.icon([dot]))
        let svg = SVGExport.write(document, animation: .moving(cycleMS: Self.lapMS)).text
        let lines = svg.split(separator: "\n").map(String.init)

        func lastValue(ofType type: String) throws -> String {
            let line = try #require(lines.first { $0.contains("type=\"\(type)\"") },
                                    "the file has no \(type) animation:\n\(svg)")
            let values = try #require(line.range(of: " values=\"").map {
                String(line[$0.upperBound...].prefix(while: { $0 != "\"" }))
            })
            return try #require(values.split(separator: ";").last.map(String.init))
        }

        // The growth wraps the slide, which is what makes a browser multiply
        // one by the other.
        let scaleAt = try #require(lines.firstIndex { $0.contains("type=\"scale\"") })
        let slideAt = try #require(lines.firstIndex { $0.contains("type=\"translate\"") })
        #expect(scaleAt < slideAt, "the slide has to sit inside the growth:\n\(svg)")

        let factor = try #require(Double(lastValue(ofType: "scale").split(separator: " ")[0]))
        let slid = try #require(Double(lastValue(ofType: "translate").split(separator: " ")[0]))
        let inTheBrowser = factor * slid

        let onCanvas = try Self.pieceOnCanvas(document, atMS: 900).frame.origin.x
        #expect(abs(onCanvas - CGFloat(inTheBrowser)) < 0.001,
                "the browser puts the piece at \(inTheBrowser), the canvas at \(onCanvas)")
    }
}

