import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender

/// The demo document behind `Scripts/playtest/fixtures/path-demo.photonz`, the
/// one place in the repo where a path can be LOOKED at before the Pen exists.
///
/// It is built in code rather than hand-edited so the fixture can always be
/// made again: change this, run `PathDemoFixtureTests` with
/// `PATH_FIXTURE_OUT=<path>`, and the package is rewritten.
enum PathDemoDocument {

    static let canvas = CGSize(width: 820, height: 470)

    /// A hard-cornered triangle: three corner anchors and not one handle.
    static func triangle() -> PathContent {
        var path = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 70, y: 0)),
            PathAnchor(point: CGPoint(x: 140, y: 130)),
            PathAnchor(point: CGPoint(x: 0, y: 130))
        ], isClosed: true)
        path.fill = Paint(hex: "#2F6FED")
        path.paint = Paint(hex: "#16336F")
        path.strokeWidth = 4
        path.strokePosition = .inside
        return path
    }

    /// A leaf: two anchors, every run a curve, not one straight edge.
    static func leaf() -> PathContent {
        var path = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0),
                       handleIn: CGPoint(x: 0, y: 86), handleOut: CGPoint(x: 86, y: 0)),
            PathAnchor(point: CGPoint(x: 130, y: 130),
                       handleIn: CGPoint(x: 0, y: -86), handleOut: CGPoint(x: -86, y: 0))
        ], isClosed: true)
        path.fill = Paint(hex: "#34C759")
        path.paint = Paint(hex: "#186B2C")
        path.strokeWidth = 4
        path.strokePosition = .inside
        return path
    }

    /// The shape this whole slice is for: three straight edges and one curved
    /// one in a single outline, joined at two half-smooth anchors — each of
    /// them straight on one side and curved on the other.
    static func bowedSquare() -> PathContent {
        var path = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0), handleOut: CGPoint(x: 52, y: 39)),
            PathAnchor(point: CGPoint(x: 100, y: 130), handleIn: CGPoint(x: 52, y: -39)),
            PathAnchor(point: CGPoint(x: 0, y: 130))
        ], isClosed: true)
        path.fill = Paint(hex: "#FF9F0A")
        path.paint = Paint(hex: "#8A4B00")
        path.strokeWidth = 4
        path.strokePosition = .inside
        return path
    }

    /// An open path: a stroked squiggle with no inside at all.
    static func squiggle() -> PathContent {
        var path = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 90),
                       handleOut: CGPoint(x: 30, y: -60), kind: .smooth),
            PathAnchor(point: CGPoint(x: 70, y: 40),
                       handleIn: CGPoint(x: -30, y: 30), handleOut: CGPoint(x: 30, y: -30),
                       kind: .smooth),
            PathAnchor(point: CGPoint(x: 140, y: 90),
                       handleIn: CGPoint(x: -30, y: -60), kind: .smooth)
        ])
        path.isClosed = false
        path.fill = nil
        path.paint = Paint(hex: "#AF52DE")
        path.strokeWidth = 10
        return path
    }

    private static func label(_ words: String, at origin: CGPoint, width: CGFloat) -> Layer {
        let text = TextContent(string: words, fontSize: 15, colorHex: "#3A3A3C", weight: .medium)
        return Layer(name: words, content: .text(text),
                     frame: CGRect(origin: origin, size: CGSize(width: width, height: 20)))
    }

    /// A white canvas with four paths on it, each labelled, plus a plain
    /// rectangle drawn with the shape tool beside the bowed square so the two
    /// can be compared edge for edge.
    static func make() -> PhotonzDocument {
        var layers: [Layer] = []
        let top: CGFloat = 90

        layers.append(PathBuilder.layer(triangle(), at: CGPoint(x: 60, y: top), name: "Triangle"))
        layers.append(label("Corners only", at: CGPoint(x: 60, y: top + 148), width: 180))

        layers.append(PathBuilder.layer(leaf(), at: CGPoint(x: 250, y: top), name: "Leaf"))
        layers.append(label("Curves only", at: CGPoint(x: 250, y: top + 148), width: 180))

        layers.append(PathBuilder.layer(bowedSquare(), at: CGPoint(x: 440, y: top),
                                        name: "Bowed square"))
        layers.append(label("Straight and curved", at: CGPoint(x: 440, y: top + 148), width: 200))

        layers.append(PathBuilder.layer(squiggle(), at: CGPoint(x: 620, y: top + 20),
                                        name: "Squiggle"))
        layers.append(label("Open, no fill", at: CGPoint(x: 620, y: top + 148), width: 180))

        // The same 100 x 130 box drawn with the shape tool, directly under the
        // bowed square, so its three straight edges can be checked against a
        // rectangle's.
        var box = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#8A4B00")
        box.fillColorHex = "#FFD79A"
        box.start = CGPoint(x: 440, y: top + 190)
        box.end = CGPoint(x: 540, y: top + 320)
        layers.append(AnnotationBuilder.layer(content: box, from: box.start, to: box.end))
        layers.append(label("Rectangle, for comparison",
                            at: CGPoint(x: 440, y: top + 330), width: 260))
        layers.append(label("Paths: straight edges and curves in one outline",
                            at: CGPoint(x: 60, y: 36), width: 620))

        return PhotonzDocument(canvasSize: canvas, layers: layers)
    }
}
