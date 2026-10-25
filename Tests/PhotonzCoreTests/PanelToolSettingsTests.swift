import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **The panel shows what the picked thing and the tool in hand need.** A
/// tool's own settings section is there only while that tool is in hand, and
/// it sits directly above the pick's own sections; a compositing row is there
/// only for a layer it means something on. The user, 2026-10-13: "You're
/// clogging up the right pane with useless non contextual crap".
///
/// Written before the code.
@Suite("The panel answers for the pick and the tool in hand")
struct PanelToolSettingsTests {

    // MARK: - Tool settings

    @Test func everyToolSectionNamesItsTool() {
        #expect(PanelToolSettings.tool(ofSection: "measureTool") == .measure)
        #expect(PanelToolSettings.tool(ofSection: "wandTool") == .wand)
        #expect(PanelToolSettings.tool(ofSection: "fillTool") == .fill)
        #expect(PanelToolSettings.tool(ofSection: "cropTool") == .crop)
        #expect(PanelToolSettings.tool(ofSection: "calloutTool") == .zoomCallout)
        #expect(PanelToolSettings.tool(ofSection: "lensTool") == .lens)
        #expect(PanelToolSettings.tool(ofSection: "brushTool") == .brush)
        #expect(PanelToolSettings.tool(ofSection: "color") == nil)
        #expect(PanelToolSettings.tool(ofSection: "layers") == nil)
    }

    /// The user's screenshot: a rectangle picked with Select in hand, and the
    /// Measure Tool's settings in the panel anyway.
    @Test func aToolSectionNeverShowsWithAnotherToolInHand() {
        let shown = PanelToolSettings.arrange(["layers", "measureTool", "color", "effects", "library"],
                                              toolInHand: .select)
        #expect(shown == ["layers", "color", "effects", "library"])
        #expect(PanelToolSettings.strays(["layers", "measureTool", "color"], toolInHand: .select)
                == ["measureTool"])
        #expect(PanelToolSettings.strays(["layers", "wandTool", "measureTool"], toolInHand: .measure)
                == ["wandTool"])
        #expect(PanelToolSettings.strays(["layers", "measureTool"], toolInHand: .measure).isEmpty)
    }

    /// With the tool in hand and something picked, the tool's settings come
    /// first and then what the pick is, whatever order the dock has saved.
    @Test func theToolInHandSitsAboveThePicksOwnSections() {
        let shown = PanelToolSettings.arrange(["layers", "color", "effects", "measureTool", "measurements"],
                                              toolInHand: .measure)
        #expect(shown == ["layers", "measureTool", "color", "effects", "measurements"])
    }

    /// Nothing picked: the tool's settings come straight under Layers, above
    /// the other lists, so they are never below the fold under a Library.
    @Test func withNothingPickedTheToolSectionLeadsTheOtherLists() {
        let shown = PanelToolSettings.arrange(["layers", "measurements", "library", "measureTool"],
                                              toolInHand: .measure)
        #expect(shown == ["layers", "measureTool", "measurements", "library"])
    }

    /// Where a timeline stands in for Layers, the tool's settings lead.
    @Test func withNoLayersListTheToolSectionLeads() {
        let shown = PanelToolSettings.arrange(["keys", "speed", "cropTool"], toolInHand: .crop)
        #expect(shown == ["cropTool", "keys", "speed"])
    }

    @Test func noToolSectionLeavesTheOrderAlone() {
        let order = ["layers", "measure", "color", "effects", "motion", "measurements"]
        #expect(PanelToolSettings.arrange(order, toolInHand: .select) == order)
    }

    // MARK: - Masked by and Key

    private static let canvas = CGSize(width: 400, height: 300)

    private func picture() -> Layer {
        Layer(name: "Picture", content: .image(ImageRef(pixelSize: CGSize(width: 400, height: 300))),
              frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    private func box() -> Layer {
        Layer(name: "Rectangle",
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF0000")),
              frame: CGRect(x: 20, y: 20, width: 100, height: 80))
    }

    private func caliper() -> Layer {
        Layer(name: "Measure",
              content: .measure(MeasureContent(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 10))),
              frame: CGRect(x: 10, y: 0, width: 100, height: 40))
    }

    /// A caliper is a note about the picture, not part of it: borrowing a
    /// shape from the layer under it means nothing (the user, 2026-10-13:
    /// "what's this for when i select a caliper?").
    @Test func aMeasurementIsNeverMaskedOrKeyed() {
        let measure = caliper()
        let doc = PhotonzDocument(canvasSize: Self.canvas, layers: [picture(), measure])
        let picked = doc.layerStyleSelection(layerIDs: [measure.id])
        #expect(picked.maskable.isEmpty)
        #expect(picked.keyable.isEmpty)
    }

    @Test func aShapeOverAPictureStillHasMaskedBy() {
        let shape = box()
        let doc = PhotonzDocument(canvasSize: Self.canvas, layers: [picture(), shape])
        #expect(!doc.layerStyleSelection(layerIDs: [shape.id]).maskable.isEmpty)
    }

    @Test func aPictureOverAPictureHasBoth() {
        let top = picture()
        let doc = PhotonzDocument(canvasSize: Self.canvas, layers: [picture(), top])
        let picked = doc.layerStyleSelection(layerIDs: [top.id])
        #expect(!picked.maskable.isEmpty)
        #expect(!picked.keyable.isEmpty)
    }
}
