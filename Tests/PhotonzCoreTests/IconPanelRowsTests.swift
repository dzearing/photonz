import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What is picked in an icon brings only rows that change the icon: the page
/// layout rows (Layout, Columns) are for screens, and say nothing about a
/// drawing 24 units across.
struct IconPanelRowsTests {

    private func iconPicture() -> PhotonzDocument {
        var document = PhotonzDocument.withBaseImage(
            ImageRef(id: UUID(), pixelSize: CGSize(width: 512, height: 512)))
        document.madeAsIcon = true
        return document
    }

    private func plainPicture() -> PhotonzDocument {
        PhotonzDocument.withBaseImage(ImageRef(id: UUID(), pixelSize: CGSize(width: 1200, height: 900)))
    }

    private func oval(at box: CGRect) -> Layer {
        Layer(name: "Oval",
              content: .annotation(AnnotationContent(shape: .ellipse, start: .zero,
                                                     end: CGPoint(x: box.width, y: box.height))),
              frame: box)
    }

    /// Two ovals put in a group, and the group's id.
    private func grouped(in document: inout PhotonzDocument, offset: CGFloat = 0) throws -> UUID {
        let a = oval(at: CGRect(x: 100 + offset, y: 100, width: 100, height: 100))
        let b = oval(at: CGRect(x: 250 + offset, y: 250, width: 100, height: 100))
        document.addLayer(a)
        document.addLayer(b)
        let group = document.groupLayers(ids: [a.id, b.id])
        return try #require(group).id
    }

    @Test("A group on a picture made as an icon is drawn in an icon")
    func groupOnIconPicture() throws {
        var document = iconPicture()
        let group = try grouped(in: &document)
        #expect(document.isAllDrawnInAnIcon([group]))
        let inside = try #require(document.layer(id: group)?.children.first).id
        #expect(document.isAllDrawnInAnIcon([inside]))
    }

    @Test("A shape in an icon frame, and the icon frame itself, are drawn in an icon")
    func inAnIconFrame() {
        var document = plainPicture()
        let frame = document.addFrame(origin: CGPoint(x: 400, y: 300), size: CGSize(width: 24, height: 24))
        let shape = oval(at: CGRect(x: 4, y: 4, width: 10, height: 10))
        let placed = document.addLayer(shape, toGroup: frame.id)
        #expect(placed)
        #expect(document.isAllDrawnInAnIcon([shape.id]))
        #expect(document.isAllDrawnInAnIcon([frame.id]))
    }

    @Test("A group on an ordinary picture, or on a screen, is not")
    func notAnIcon() throws {
        var document = plainPicture()
        let group = try grouped(in: &document)
        #expect(!document.isAllDrawnInAnIcon([group]))

        let screen = document.addFrame(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 390, height: 844))
        let shape = oval(at: CGRect(x: 10, y: 10, width: 40, height: 40))
        let placed = document.addLayer(shape, toGroup: screen.id)
        #expect(placed)
        #expect(!document.isAllDrawnInAnIcon([shape.id]))
        #expect(!document.isAllDrawnInAnIcon([screen.id]))
    }

    @Test("A pick that reaches past the icon keeps the page rows, and so does nothing picked")
    func mixedAndEmpty() {
        var document = plainPicture()
        let icon = document.addFrame(origin: CGPoint(x: 600, y: 300), size: CGSize(width: 24, height: 24))
        let inIcon = oval(at: CGRect(x: 4, y: 4, width: 10, height: 10))
        let placed = document.addLayer(inIcon, toGroup: icon.id)
        #expect(placed)
        let loose = oval(at: CGRect(x: 10, y: 10, width: 40, height: 40))
        document.addLayer(loose)
        #expect(!document.isAllDrawnInAnIcon([inIcon.id, loose.id]))
        #expect(!document.isAllDrawnInAnIcon([]))
    }

    @Test("A picture made as an icon and cut to a banner is no longer one")
    func cutToABanner() throws {
        var document = iconPicture()
        let group = try grouped(in: &document)
        document.canvasSize = CGSize(width: 512, height: 300)
        #expect(!document.isAllDrawnInAnIcon([group]))
    }
}
