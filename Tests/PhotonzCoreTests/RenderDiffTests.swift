import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Dirty-region math for incremental re-rendering (phase-7 perf pass).
/// Given two document snapshots, `RenderDiff` reports the canvas region the
/// renderer must redraw — conservatively too big, never too small.
@Suite("Render diff")
struct RenderDiffTests {

    private let ref = ImageRef(pixelSize: CGSize(width: 100, height: 80))

    private func baseDocument() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 800))
        doc.addLayer(Layer(name: "Base", content: .image(ref),
                           frame: CGRect(x: 0, y: 0, width: 1000, height: 800), isLocked: true))
        return doc
    }

    private func patchLayer(at frame: CGRect, style: LayerStyle = LayerStyle()) -> Layer {
        Layer(name: "Patch", content: .image(ref), frame: frame, style: style)
    }

    // MARK: visualBounds

    @Test func plainLayerBoundsCoverTheFrame() {
        let layer = patchLayer(at: CGRect(x: 100, y: 100, width: 200, height: 150))
        let bounds = RenderDiff.visualBounds(of: layer)
        #expect(bounds.contains(CGRect(x: 100, y: 100, width: 200, height: 150)))
    }

    @Test func shadowAndBlurExpandTheBounds() {
        let style = LayerStyle(blurRadius: 10,
                               shadow: ShadowStyle(radius: 20, offset: CGSize(width: 8, height: 12)))
        let layer = patchLayer(at: CGRect(x: 100, y: 100, width: 200, height: 150), style: style)
        let bounds = RenderDiff.visualBounds(of: layer)
        // previewPadding = blur*3 + shadowRadius*3 + maxOffset = 30 + 60 + 12.
        let padded = CGRect(x: 100, y: 100, width: 200, height: 150)
            .insetBy(dx: -layer.style.previewPadding, dy: -layer.style.previewPadding)
        #expect(bounds.contains(padded))
    }

    @Test func rotatedLayerBoundsCoverTheRotatedExtent() {
        var layer = patchLayer(at: CGRect(x: 100, y: 100, width: 400, height: 20))
        layer.transform = LayerTransform(rotation: .pi / 2)
        let bounds = RenderDiff.visualBounds(of: layer)
        // Rotating a wide strip 90° around its center makes it tall: the
        // bounds must cover the vertical extent (center y 110 ± 200).
        #expect(bounds.minY <= -90)
        #expect(bounds.maxY >= 310)
    }

    @Test func calloutBoundsIncludeSourceAndBox() {
        let layer = Layer(name: "Zoom",
                          content: .zoomCallout(ZoomCalloutContent(
                              sourceRect: CGRect(x: 50, y: 50, width: 60, height: 40),
                              magnification: 2)),
                          frame: CGRect(x: 500, y: 400, width: 120, height: 80))
        let bounds = RenderDiff.visualBounds(of: layer)
        // Chrome (source outline + leader lines) spans source to box.
        #expect(bounds.contains(CGRect(x: 50, y: 50, width: 60, height: 40)))
        #expect(bounds.contains(CGRect(x: 500, y: 400, width: 120, height: 80)))
    }

    // MARK: dirtyRegion basics

    @Test func identicalDocumentsAreClean() {
        let doc = baseDocument()
        #expect(RenderDiff.dirtyRegion(from: doc, to: doc) == RenderDirty.none)
    }

    @Test func canvasResizeIsFull() {
        let old = baseDocument()
        var new = old
        new.canvasSize = CGSize(width: 500, height: 400)
        #expect(RenderDiff.dirtyRegion(from: old, to: new) == .full)
    }

    @Test func movedLayerDirtiesOldAndNewSpots() throws {
        var old = baseDocument()
        old.addLayer(patchLayer(at: CGRect(x: 100, y: 100, width: 50, height: 50)))
        var new = old
        let id = new.layers[1].id
        new.updateLayer(id: id) { $0.frame = CGRect(x: 700, y: 600, width: 50, height: 50) }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: old, to: new) else {
            Issue.record("expected .rect"); return
        }
        #expect(dirty.contains(CGRect(x: 100, y: 100, width: 50, height: 50)))
        #expect(dirty.contains(CGRect(x: 700, y: 600, width: 50, height: 50)))
        // …but not the whole canvas.
        #expect(dirty.width < 1000 || dirty.height < 800)
    }

    @Test func addedAndRemovedLayersDirtyTheirFootprints() throws {
        var old = baseDocument()
        old.addLayer(patchLayer(at: CGRect(x: 50, y: 50, width: 40, height: 40)))
        var new = baseDocument()
        new.layers[0] = old.layers[0] // same base layer
        new.addLayer(patchLayer(at: CGRect(x: 800, y: 700, width: 40, height: 40)))

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: old, to: new) else {
            Issue.record("expected .rect"); return
        }
        #expect(dirty.contains(CGRect(x: 50, y: 50, width: 40, height: 40)))
        #expect(dirty.contains(CGRect(x: 800, y: 700, width: 40, height: 40)))
    }

    @Test func visibilityToggleDirtiesTheLayer() throws {
        var old = baseDocument()
        old.addLayer(patchLayer(at: CGRect(x: 300, y: 300, width: 100, height: 100)))
        var new = old
        new.updateLayer(id: new.layers[1].id) { $0.isVisible = false }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: old, to: new) else {
            Issue.record("expected .rect"); return
        }
        #expect(dirty.contains(CGRect(x: 300, y: 300, width: 100, height: 100)))
    }

    @Test func reorderedLayersDirtyTheirFootprints() throws {
        var old = baseDocument()
        old.addLayer(patchLayer(at: CGRect(x: 100, y: 100, width: 80, height: 80)))
        old.addLayer(patchLayer(at: CGRect(x: 150, y: 150, width: 80, height: 80)))
        var new = old
        new.moveLayer(id: new.layers[1].id, to: 2)

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: old, to: new) else {
            Issue.record("expected .rect"); return
        }
        #expect(dirty.contains(CGRect(x: 100, y: 100, width: 80, height: 80)))
        #expect(dirty.contains(CGRect(x: 150, y: 150, width: 80, height: 80)))
    }

    @Test func dirtyRectIsClampedToCanvas() throws {
        var old = baseDocument()
        old.addLayer(patchLayer(at: CGRect(x: -40, y: -40, width: 100, height: 100),
                                style: LayerStyle(shadow: ShadowStyle(radius: 30))))
        var new = old
        new.updateLayer(id: new.layers[1].id) { $0.isVisible = false }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: old, to: new) else {
            Issue.record("expected .rect"); return
        }
        #expect(dirty.minX >= 0 && dirty.minY >= 0)
        #expect(dirty.maxX <= 1000 && dirty.maxY <= 800)
    }

    // MARK: zoom-callout coupling

    @Test func editUnderCalloutSourceDirtiesTheCalloutBox() throws {
        var old = baseDocument()
        old.addLayer(patchLayer(at: CGRect(x: 60, y: 60, width: 30, height: 30)))
        old.addLayer(Layer(name: "Zoom",
                           content: .zoomCallout(ZoomCalloutContent(
                               sourceRect: CGRect(x: 50, y: 50, width: 100, height: 80),
                               magnification: 2)),
                           frame: CGRect(x: 700, y: 500, width: 200, height: 160)))
        var new = old
        // Move the patch within the callout's source region.
        new.updateLayer(id: new.layers[1].id) { $0.frame = CGRect(x: 80, y: 70, width: 30, height: 30) }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: old, to: new) else {
            Issue.record("expected .rect"); return
        }
        // The callout magnifies the edited region, so its box re-renders too.
        #expect(dirty.contains(CGRect(x: 700, y: 500, width: 200, height: 160)))
    }

    @Test func editAwayFromCalloutSourceLeavesTheBoxClean() throws {
        var old = baseDocument()
        old.addLayer(patchLayer(at: CGRect(x: 400, y: 700, width: 30, height: 30)))
        old.addLayer(Layer(name: "Zoom",
                           content: .zoomCallout(ZoomCalloutContent(
                               sourceRect: CGRect(x: 50, y: 50, width: 100, height: 80),
                               magnification: 2)),
                           frame: CGRect(x: 700, y: 100, width: 200, height: 160)))
        var new = old
        new.updateLayer(id: new.layers[1].id) { $0.frame = CGRect(x: 430, y: 710, width: 30, height: 30) }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: old, to: new) else {
            Issue.record("expected .rect"); return
        }
        #expect(!dirty.intersects(CGRect(x: 700, y: 100, width: 200, height: 160)))
    }

    // MARK: frames that paint a surface

    private func screen(_ frame: CGRect, children: [Layer] = []) -> Layer {
        Layer(name: "Screen",
              content: .group(GroupContent(children: children, isFrame: true,
                                           clipsContents: true, backgroundHex: "#4A80F0")),
              frame: frame)
    }

    @Test func widenedScreenRepaintsTheBandItGained() throws {
        let child = patchLayer(at: CGRect(x: 20, y: 20, width: 80, height: 40))
        var old = baseDocument()
        old.addLayer(screen(CGRect(x: 100, y: 100, width: 300, height: 200), children: [child]))
        var new = old
        // Dragged by the bottom-right corner: same origin, bigger box, and the
        // child inside moved the way a layout rule moves it.
        new.updateLayer(id: new.layers[1].id) { layer in
            layer.frame = CGRect(x: 100, y: 100, width: 500, height: 340)
            layer.children[0].frame = CGRect(x: 30, y: 25, width: 90, height: 40)
        }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: old, to: new) else {
            Issue.record("expected .rect"); return
        }
        // The surface now fills the whole new box, so every part of it repaints.
        #expect(dirty.contains(CGRect(x: 100, y: 100, width: 500, height: 340)))
    }

    @Test func shrunkScreenRepaintsTheBandItGaveUp() throws {
        let child = patchLayer(at: CGRect(x: 20, y: 20, width: 80, height: 40))
        var old = baseDocument()
        old.addLayer(screen(CGRect(x: 100, y: 100, width: 500, height: 340), children: [child]))
        var new = old
        new.updateLayer(id: new.layers[1].id) { layer in
            layer.frame = CGRect(x: 100, y: 100, width: 300, height: 200)
            layer.children[0].frame = CGRect(x: 15, y: 18, width: 70, height: 40)
        }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: old, to: new) else {
            Issue.record("expected .rect"); return
        }
        // What the screen used to cover has to go back to being canvas.
        #expect(dirty.contains(CGRect(x: 100, y: 100, width: 500, height: 340)))
    }

    @Test func repaintingTheScreenSurfaceRepaintsTheWholeBox() throws {
        var old = baseDocument()
        old.addLayer(screen(CGRect(x: 100, y: 100, width: 300, height: 200)))
        var new = old
        new.updateLayer(id: new.layers[1].id) { layer in
            guard case .group(var g) = layer.content else { return }
            g.backgroundHex = "#FF0000"
            layer.content = .group(g)
        }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: old, to: new) else {
            Issue.record("expected .rect"); return
        }
        #expect(dirty.contains(CGRect(x: 100, y: 100, width: 300, height: 200)))
    }

    @Test func draggingOneLayerInsideAPlainGroupRepaintsOnlyThatLayer() throws {
        let a = patchLayer(at: CGRect(x: 10, y: 10, width: 40, height: 40))
        let b = patchLayer(at: CGRect(x: 300, y: 300, width: 40, height: 40))
        var old = baseDocument()
        old.addLayer(Layer(name: "Group", content: .group(GroupContent(children: [a, b])),
                           frame: CGRect(x: 100, y: 100, width: 0, height: 0)))
        var new = old
        new.updateLayer(id: new.layers[1].id) { $0.children[0].frame.origin.x += 5 }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: old, to: new) else {
            Issue.record("expected .rect"); return
        }
        // The far corner of the group is untouched: this is the optimization
        // the frame fix must not cost us.
        #expect(!dirty.intersects(CGRect(x: 400, y: 400, width: 40, height: 40)))
    }
}
