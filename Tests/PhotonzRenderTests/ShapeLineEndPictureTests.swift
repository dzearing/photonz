import CoreGraphics
import Foundation
import ImageIO
import Testing
import PhotonzCore
import UniformTypeIdentifiers
@testable import PhotonzRender

/// One picture of the three ends side by side, for the audit to ship.
///
/// The Mac's screen was locked when this feature landed, so no walk could run
/// and macOS refused every window capture. This draws the same lines through
/// the app's own composite instead, which is an honest picture of the CANVAS
/// even though it is not a picture of the window.
///
/// To write it out:
/// `LINE_ENDS_PNG=/tmp/line-ends.png Scripts/test.sh --filter ShapeLineEndPicture`
@Suite("A picture of the three ends")
struct ShapeLineEndPictureTests {

    private static let canvas = CGSize(width: 700, height: 520)

    private static func label(_ words: String, at origin: CGPoint) -> Layer {
        let text = TextContent(string: words, fontSize: 17, colorHex: "#3A3A3C", weight: .medium)
        return Layer(name: words, content: .text(text),
                     frame: CGRect(origin: origin, size: CGSize(width: 260, height: 24)))
    }

    private static func line(_ end: PathLineEnd, y: CGFloat) -> Layer {
        var mark = AnnotationContent(shape: .line, strokeWidth: 24, colorHex: "#2F6FED")
        mark.lineEnd = end
        let from = CGPoint(x: 230, y: y), to = CGPoint(x: 560, y: y)
        mark.start = from
        mark.end = to
        return AnnotationBuilder.layer(content: mark, from: from, to: to)
    }

    /// The document the picture is of: three lines that stop on exactly the
    /// same two points and differ only in what happens there, an arrow whose
    /// tail is cut flat, and a chevron whose sharp corner is drawn in full.
    static func make() -> PhotonzDocument {
        var layers: [Layer] = []
        layers.append(label("What a line ends in", at: CGPoint(x: 40, y: 34)))

        for (index, end) in PathLineEnd.allCases.enumerated() {
            let y = 110 + CGFloat(index) * 70
            layers.append(label(end.title, at: CGPoint(x: 40, y: y - 11)))
            layers.append(line(end, y: y))
        }

        var arrow = AnnotationContent(shape: .arrow, strokeWidth: 20, colorHex: "#FF9F0A")
        arrow.lineEnd = .flat
        let tail = CGPoint(x: 230, y: 360), tip = CGPoint(x: 560, y: 360)
        arrow.start = tail
        arrow.end = tip
        layers.append(label("Arrow, flat tail", at: CGPoint(x: 40, y: 349)))
        layers.append(AnnotationBuilder.layer(content: arrow, from: tail, to: tip))

        var chevron = PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 0)),
                                            PathAnchor(point: CGPoint(x: 60, y: 45)),
                                            PathAnchor(point: CGPoint(x: 0, y: 90))],
                                  isClosed: false, fill: nil)
        chevron.paint = Paint(hex: "#AF52DE")
        chevron.strokeWidth = 20
        chevron.lineEnd = .flat
        chevron.lineCorner = .sharp
        layers.append(label("Sharp corner, drawn in full", at: CGPoint(x: 40, y: 440)))
        layers.append(PathBuilder.layer(chevron, at: CGPoint(x: 300, y: 420), name: "Chevron"))

        return PhotonzDocument(canvasSize: canvas, layers: layers)
    }

    @Test func writesThePictureWhenAskedTo() throws {
        let store = ImageStore()
        let image = try #require(DocumentRenderer().render(Self.make(), store: store))
        #expect(image.width > 0 && image.height > 0)
        guard let out = ProcessInfo.processInfo.environment["LINE_ENDS_PNG"] else { return }
        let url = URL(fileURLWithPath: out)
        if let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }
}
