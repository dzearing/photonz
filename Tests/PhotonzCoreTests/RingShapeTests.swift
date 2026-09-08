import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Ring shape")
struct RingShapeTests {

    private func shape(_ shape: AnnotationShape) -> Layer {
        Layer(name: "Shape",
              content: .annotation(AnnotationContent(shape: shape, strokeWidth: 2,
                                                     colorHex: "#FF0000", start: .zero,
                                                     end: CGPoint(x: 100, y: 80))),
              frame: CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    @Test("An ellipse's ring follows the oval")
    func ellipseRingsAnOval() {
        #expect(shape(.ellipse).ringShape == .ellipse)
    }

    @Test("Every other shape keeps the ring round its box")
    func everythingElseRingsItsBox() {
        #expect(shape(.rectangle).ringShape == .box)
        #expect(shape(.highlight).ringShape == .box)
        #expect(shape(.line).ringShape == .box)
        #expect(shape(.arrow).ringShape == .box)
    }

    @Test("A layer with no shape of its own rings its box")
    func aPictureRingsItsBox() {
        let picture = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                            frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(picture.ringShape == .box)
        let label = Layer(name: "Label", content: .text(TextContent(string: "Hi")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(label.ringShape == .box)
    }
}
