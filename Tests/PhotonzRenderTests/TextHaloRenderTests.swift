import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The halo, actually drawn. A black label on a pure red button: the halo is
/// white, so any pixel inside the button that is lighter than the fill can only
/// have come from it. Antialiasing between black glyphs and red fill never
/// raises green or blue, so the test cannot mistake a soft edge for a smudge.
@Suite("Text halo, drawn")
struct TextHaloRenderTests {

    private let renderer = DocumentRenderer()

    private func label(_ string: String, at point: CGPoint) -> Layer {
        let content = TextContent(string: string, fontSize: 18, colorHex: "#000000", weight: .semibold)
        let size = TextRasterizer.naturalSize(content)
        return TextBuilder.layer(content: content, at: point, naturalSize: size)
    }

    private func button(_ rect: CGRect) -> Layer {
        var annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: rect.width, y: rect.height))
        annotation.strokeWidth = 0
        annotation.fillColorHex = "#FF0000"
        annotation.colorHex = "#FF0000"
        return Layer(name: "Background", content: .annotation(annotation), frame: rect)
    }

    /// A red button with a black "Save" on it, grouped. `promote` turns the
    /// group into a component; otherwise it stays an ordinary group.
    private func document(promote: Bool) -> PhotonzDocument {
        let box = button(CGRect(x: 20, y: 20, width: 160, height: 60))
        let text = label("Save", at: CGPoint(x: 60, y: 38))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 100),
                                  layers: [box, text])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Group")!
        if promote { doc.makeComponent(id: group.id) }
        return doc
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return data }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// Pixels inside the button that are lighter than its fill: the halo.
    private func lightPixels(_ image: CGImage) -> Int {
        let pixels = rgba(image)
        var count = 0
        for y in 24..<76 {
            for x in 24..<176 {
                let i = (y * image.width + x) * 4
                if pixels[i + 1] > 24 || pixels[i + 2] > 24 { count += 1 }
            }
        }
        return count
    }

    @Test func aLabelInAPlainGroupStillWearsItsHalo() throws {
        let image = try #require(renderer.render(document(promote: false), store: ImageStore()))
        #expect(lightPixels(image) > 0)
    }

    @Test func aLabelInsideAComponentDrawsClean() throws {
        let image = try #require(renderer.render(document(promote: true), store: ImageStore()))
        #expect(lightPixels(image) == 0)
    }

    @Test func everyCopyDrawsCleanToo() throws {
        var doc = document(promote: true)
        let componentID = try #require(doc.mainComponents.first?.componentID)
        // Room for a second button, and a copy of the first placed in it.
        doc.canvasSize = CGSize(width: 200, height: 200)
        _ = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 100, y: 150))
        let image = try #require(renderer.render(doc, store: ImageStore()))

        let pixels = rgba(image)
        var count = 0
        for y in 124..<176 {
            for x in 24..<176 {
                let i = (y * image.width + x) * 4
                if pixels[i + 1] > 24 || pixels[i + 2] > 24 { count += 1 }
            }
        }
        #expect(count == 0)
    }

    @Test func takingItBackOutBringsTheHaloBack() throws {
        var doc = document(promote: true)
        let group = try #require(doc.mainComponents.first?.id)
        #expect(lightPixels(try #require(renderer.render(doc, store: ImageStore()))) == 0)

        _ = doc.ungroupLayers(ids: [group])
        #expect(lightPixels(try #require(renderer.render(doc, store: ImageStore()))) > 0)
    }

    // MARK: - Screens

    /// A phone-sized screen painted pure red with a black heading typed onto
    /// it: the same trick as the button, one level up.
    private func screenDocument(background: String?) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 100))
        let made = doc.addFrame(name: "Screen", origin: CGPoint(x: 20, y: 20),
                                size: CGSize(width: 160, height: 60),
                                backgroundHex: background)
        if background == nil {
            // Nothing painted, so give the text something red to sit on, the
            // way a screenshot dropped inside a boundary would.
            _ = doc.addLayer(button(CGRect(x: 0, y: 0, width: 160, height: 60)), toGroup: made.id)
        }
        _ = doc.addLayer(label("Settings", at: CGPoint(x: 40, y: 18)), toGroup: made.id)
        return doc
    }

    @Test func textTypedOnAScreenDrawsClean() throws {
        let image = try #require(renderer.render(screenDocument(background: "#FF0000"),
                                                 store: ImageStore()))
        #expect(lightPixels(image) == 0)
    }

    @Test func aBoundaryThatPaintsNothingLeavesTheHaloAlone() throws {
        let image = try #require(renderer.render(screenDocument(background: nil),
                                                 store: ImageStore()))
        #expect(lightPixels(image) > 0)
    }

    @Test func aGroupInsideAScreenIsStillOnTheScreen() throws {
        var doc = screenDocument(background: "#FF0000")
        let labelID = try #require(doc.frames.first?.children.first(where: \.isText)?.id)
        _ = doc.groupLayers(ids: [labelID], name: "Row")
        #expect(lightPixels(try #require(renderer.render(doc, store: ImageStore()))) == 0)
    }

    @Test func clearingTheScreensSurfaceBringsTheHaloBack() throws {
        var doc = screenDocument(background: "#FF0000")
        let frameID = try #require(doc.frames.first?.id)
        #expect(lightPixels(try #require(renderer.render(doc, store: ImageStore()))) == 0)

        // No surface, so the screen is a boundary again and the text is a
        // caption over whatever shows through. Painted red first so the halo
        // has something to be lighter than.
        _ = doc.addLayer(button(CGRect(x: 0, y: 0, width: 160, height: 60)),
                         toGroup: frameID, at: 0)
        doc.setFrameBackground(id: frameID, hex: nil)
        #expect(lightPixels(try #require(renderer.render(doc, store: ImageStore()))) > 0)
    }
}
