import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// ⌘-click a layer → load its opaque pixels as a selection. These cover the
/// render-side primitive: a layer's silhouette traced into a canvas-space path.
@Suite("Layer selection mask (load pixels)")
struct LayerSelectionMaskTests {

    private func solidImage(width: Int, height: Int, alpha: CGFloat = 1) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func approx(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 3) -> Bool { abs(a - b) <= tol }

    @Test("A filled rectangle shape selects its interior, not the exterior")
    func filledRectangleSilhouette() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200))
        var doc = PhotonzDocument.withBaseImage(base)
        var shape = AnnotationContent(shape: .rectangle, colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: 60, y: 40))
        shape.fillColorHex = "#FF3B30"
        let rect = Layer(name: "Box", content: .annotation(shape),
                         frame: CGRect(x: 20, y: 30, width: 60, height: 40))
        doc.addLayer(rect)

        let path = DocumentRenderer().layerSelectionPath(for: rect.id, in: doc, store: store)
        #expect(path != nil)
        guard let path, let region = SelectionRegion(path: path) else { return }
        let b = region.bounds
        #expect(approx(b.minX, 20) && approx(b.minY, 30), "bounds origin \(b)")
        #expect(approx(b.width, 60) && approx(b.height, 40), "bounds size \(b)")
        #expect(region.contains(CGPoint(x: 50, y: 50)))       // interior
        #expect(!region.contains(CGPoint(x: 5, y: 5)))        // outside
        #expect(!region.contains(CGPoint(x: 150, y: 150)))    // far outside
    }

    @Test("Shadow, blur, and low opacity don't bleed or empty the selection")
    func softEffectsIgnored() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200))
        var doc = PhotonzDocument.withBaseImage(base)
        var shape = AnnotationContent(shape: .rectangle, colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: 60, y: 40))
        shape.fillColorHex = "#FF3B30"
        var style = LayerStyle(opacity: 0.3, blurRadius: 6,
                               shadow: ShadowStyle(radius: 20, offset: CGSize(width: 12, height: 12),
                                                   opacity: 0.9))
        style.blurRadius = 6
        let rect = Layer(name: "Box", content: .annotation(shape),
                         frame: CGRect(x: 40, y: 40, width: 60, height: 40), style: style)
        doc.addLayer(rect)

        let path = DocumentRenderer().layerSelectionPath(for: rect.id, in: doc, store: store)
        guard let path, let region = SelectionRegion(path: path) else {
            Issue.record("expected a selection despite soft effects")
            return
        }
        let b = region.bounds
        // Tracks the shape frame, not the shadow's expanded, offset footprint.
        #expect(approx(b.minX, 40, 4) && approx(b.minY, 40, 4), "bounds \(b)")
        #expect(approx(b.width, 60, 4) && approx(b.height, 40, 4), "bounds \(b)")
        #expect(region.contains(CGPoint(x: 70, y: 60)))       // shape interior
        // Well into where the offset shadow would be, outside the shape.
        #expect(!region.contains(CGPoint(x: 118, y: 78)))
    }

    @Test("A solid image layer selects its whole frame")
    func imageLayerSelectsFrame() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200))
        var doc = PhotonzDocument.withBaseImage(base)
        let patch = store.register(solidImage(width: 40, height: 30))
        let layer = Layer(name: "Patch", content: .image(patch),
                          frame: CGRect(x: 25, y: 35, width: 40, height: 30))
        doc.addLayer(layer)

        let path = DocumentRenderer().layerSelectionPath(for: layer.id, in: doc, store: store)
        guard let path, let region = SelectionRegion(path: path) else {
            Issue.record("expected a selection")
            return
        }
        let b = region.bounds
        #expect(approx(b.minX, 25) && approx(b.minY, 35), "bounds \(b)")
        #expect(approx(b.width, 40) && approx(b.height, 30), "bounds \(b)")
    }

    @Test("A layer that draws nothing opaque yields no selection")
    func fullyTransparentYieldsNil() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100))
        var doc = PhotonzDocument.withBaseImage(base)
        let clear = store.register(solidImage(width: 30, height: 30, alpha: 0))
        let layer = Layer(name: "Clear", content: .image(clear),
                          frame: CGRect(x: 10, y: 10, width: 30, height: 30))
        doc.addLayer(layer)
        let path = DocumentRenderer().layerSelectionPath(for: layer.id, in: doc, store: store)
        #expect(path == nil)
    }
}
