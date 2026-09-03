import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Text on a surface somebody designed — a label on a control, a heading on a
/// screen — is not a caption over a screenshot, so the contrast halo every new
/// text layer is born wearing is not drawn there
/// (`docs/design/ui-building.md`, step E9).
///
/// Two things count as a designed surface: a component, and a frame that paints
/// a background. A frame with no surface does not count, because the canvas
/// still shows through it and a caption there is still a caption over whatever
/// is behind it.
///
/// The rule is read at draw time and nothing is erased: the halo the text was
/// given is still on the layer, so taking the text back out brings it back.
@Suite("Text halo")
struct TextHaloTests {

    private func text(_ string: String, colorHex: String = "#000000",
                      at point: CGPoint = .zero) -> Layer {
        TextBuilder.layer(content: TextContent(string: string, fontSize: 14, colorHex: colorHex),
                          at: point, naturalSize: CGSize(width: 40, height: 18))
    }

    private func box(_ rect: CGRect) -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// A red box with a black label on it, grouped and promoted: the button
    /// from the end-to-end walk that showed the smudge.
    private func button() -> (document: PhotonzDocument, componentID: UUID,
                              groupID: UUID, labelID: UUID) {
        let label = text("Save", at: CGPoint(x: 20, y: 12))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [box(CGRect(x: 10, y: 10, width: 120, height: 40)), label])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Group")!
        let componentID = doc.makeComponent(id: group.id)!
        return (doc, componentID, group.id, label.id)
    }

    // MARK: - The rule itself

    @Test func newTextIsBornWearingTheHalo() {
        let layer = text("Save")
        #expect(layer.style.shadow == TextBuilder.autoContrastShadow(forColorHex: "#000000"))
        #expect(layer.drawnShadow(onDesignedSurface: false) == layer.style.shadow)
    }

    @Test func insideAComponentTheHaloIsNotDrawn() {
        #expect(text("Save").drawnShadow(onDesignedSurface: true) == nil)
    }

    @Test func theHaloIsNotErasedOnlyLeftUndrawn() {
        let layer = text("Save")
        #expect(layer.style.shadow != nil)
        // The same layer, asked the other way, still has it to give.
        #expect(layer.drawnShadow(onDesignedSurface: false) != nil)
    }

    @Test func aShadowSomebodyChoseStillDrawsInsideAComponent() {
        var layer = text("Save")
        layer.style.shadow = ShadowStyle(radius: 12, offset: CGSize(width: 0, height: 6),
                                         colorHex: "#000000", opacity: 0.4)
        #expect(layer.drawnShadow(onDesignedSurface: true) == layer.style.shadow)
    }

    @Test func theRuleOnlyTouchesText() {
        var shape = box(CGRect(x: 0, y: 0, width: 10, height: 10))
        shape.style.shadow = TextBuilder.autoContrastShadow(forColorHex: "#000000")
        #expect(shape.drawnShadow(onDesignedSurface: true) == shape.style.shadow)
    }

    @Test func recoloredTextKeepsTheRule() {
        // Repainting refreshes the halo for the new color; the rule follows it.
        let layer = TextBuilder.restyled(layer: text("Save"), colorHex: "#FFFFFF")
        #expect(layer.style.shadow == TextBuilder.autoContrastShadow(forColorHex: "#FFFFFF"))
        #expect(layer.drawnShadow(onDesignedSurface: true) == nil)
    }

    // MARK: - Who counts as a designed surface

    @Test func textOnTheCanvasIsNotOnADesignedSurface() {
        let layer = text("Gap 16")
        let doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [layer])
        #expect(doc.isOnDesignedSurface(layer.id) == false)
    }

    @Test func aPlainGroupIsNotADesignedSurface() {
        // The everyday redline move: an arrow and its caption bundled together.
        let caption = text("Gap 16")
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [box(CGRect(x: 0, y: 0, width: 40, height: 4)), caption])
        _ = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Group")
        #expect(doc.isOnDesignedSurface(caption.id) == false)
    }

    @Test func textInsideTheOriginalCountsAsDesigned() {
        let made = button()
        #expect(made.document.isOnDesignedSurface(made.labelID))
    }

    @Test func textInsideACopyCountsAsDesigned() {
        var (doc, componentID, _, _) = button()
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 150))!
        let labelInCopy = doc.layer(id: copy)!.children.first { $0.isText }!
        #expect(doc.isOnDesignedSurface(labelInCopy.id))
        #expect(labelInCopy.drawnShadow(onDesignedSurface: true) == nil)
    }

    @Test func nestingDeeperStaysInside() {
        var (doc, _, groupID, labelID) = button()
        // A group inside the component: the label is two levels down now.
        _ = doc.groupLayers(ids: [labelID], name: "Inner")
        #expect(doc.isOnDesignedSurface(labelID))
        #expect(doc.layer(id: groupID)?.isMainComponent == true)
    }

    @Test func theComponentItselfIsNotOnItsOwnSurface() {
        let made = button()
        #expect(made.document.isOnDesignedSurface(made.groupID) == false)
    }

    // MARK: - Making and unmaking

    @Test func promotingDropsTheHaloAndUngroupingPutsItBack() {
        var (doc, _, groupID, labelID) = button()
        #expect(doc.isOnDesignedSurface(labelID))

        _ = doc.ungroupLayers(ids: [groupID])
        #expect(doc.isOnDesignedSurface(labelID) == false)
        // Nothing was erased on the way in, so the halo is simply drawn again.
        let label = doc.layer(id: labelID)!
        #expect(label.drawnShadow(onDesignedSurface: false)
                == TextBuilder.autoContrastShadow(forColorHex: "#000000"))
    }

    // MARK: - Screens

    private func screen(background: String? = Layer.defaultFrameBackgroundHex)
        -> (document: PhotonzDocument, frameID: UUID, labelID: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        let made = doc.addFrame(name: "Screen", origin: CGPoint(x: 20, y: 20),
                                size: CGSize(width: 390, height: 844),
                                backgroundHex: background)
        let label = text("Settings", at: CGPoint(x: 24, y: 60))
        _ = doc.addLayer(label, toGroup: made.id)
        return (doc, made.id, label.id)
    }

    @Test func textOnAScreenDrawsClean() {
        let made = screen()
        #expect(made.document.isOnDesignedSurface(made.labelID))
        let label = made.document.layer(id: made.labelID)!
        #expect(label.drawnShadow(onDesignedSurface: true) == nil)
    }

    @Test func aFrameWithNoSurfaceKeepsTheHalo() {
        // Frame Selection draws a boundary around work that already exists and
        // deliberately paints nothing, so a caption inside it is still a
        // caption over whatever the canvas is showing.
        let made = screen(background: nil)
        #expect(made.document.isOnDesignedSurface(made.labelID) == false)
    }

    @Test func framingAScreenshotLeavesItsCaptionsAlone() {
        let caption = text("Gap 16", at: CGPoint(x: 40, y: 40))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [box(CGRect(x: 0, y: 0, width: 300, height: 200)), caption])
        _ = doc.frameSelection(ids: Set(doc.layers.map(\.id)), name: "Capture")
        #expect(doc.isOnDesignedSurface(caption.id) == false)
    }

    @Test func aGroupInsideAScreenStaysOnTheScreen() {
        var (doc, _, labelID) = screen()
        _ = doc.groupLayers(ids: [labelID], name: "Row")
        #expect(doc.isOnDesignedSurface(labelID))
    }

    @Test func theScreenItselfIsNotOnItsOwnSurface() {
        let made = screen()
        #expect(made.document.isOnDesignedSurface(made.frameID) == false)
    }

    @Test func movingTextOntoAScreenDropsTheHaloAndTakingItOffPutsItBack() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000))
        let made = doc.addFrame(name: "Screen", origin: .zero,
                                size: CGSize(width: 390, height: 844))
        let caption = text("Gap 16", at: CGPoint(x: 500, y: 500))
        doc.addLayer(caption)
        #expect(doc.isOnDesignedSurface(caption.id) == false)

        _ = doc.moveLayer(id: caption.id, toGroup: made.id)
        #expect(doc.isOnDesignedSurface(caption.id))

        _ = doc.moveLayer(id: caption.id, toGroup: nil)
        #expect(doc.isOnDesignedSurface(caption.id) == false)
        let back = doc.layer(id: caption.id)!
        #expect(back.drawnShadow(onDesignedSurface: false)
                == TextBuilder.autoContrastShadow(forColorHex: "#000000"))
    }

    @Test func clearingAScreensSurfaceBringsTheHaloBack() {
        var (doc, frameID, labelID) = screen()
        #expect(doc.isOnDesignedSurface(labelID))
        doc.setFrameBackground(id: frameID, hex: nil)
        #expect(doc.isOnDesignedSurface(labelID) == false)
    }
}
