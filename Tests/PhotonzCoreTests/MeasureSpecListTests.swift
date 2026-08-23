import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Pins the "Copy as spec list" text format (§7, `next-measure-panel`) and the
/// derived row names the Measurements panel shows (§6, decision D3: derived
/// automatic names, custom names survive a rename).
@Suite("MeasureSpecList")
struct MeasureSpecListTests {

    // MARK: - Fixtures

    /// A caliper layer whose feet run `from → to` in document space.
    private func caliper(from start: CGPoint, to end: CGPoint,
                         role: MeasureRole = .size,
                         unit: MeasureUnit = .pixels,
                         name: String? = nil,
                         visible: Bool = true) -> Layer {
        var content = MeasureContent(role: role)
        content.unit = unit
        content.mode = MeasureContent.dominantAxis(from: start, to: end)
        var layer = MeasureBuilder.layer(content: content, from: start, to: end)
        if let name { layer.name = name }
        layer.isVisible = visible
        return layer
    }

    /// An alignment guide whose scan came back aligned.
    private func alignedGuide() -> Layer {
        var content = MeasureContent()
        content.mode = .vertical
        content.headOffset = 0
        content.alignment = AlignmentCheck(items: [
            AlignmentItem(edge: 40, spanStart: 10, spanEnd: 30),
            AlignmentItem(edge: 40, spanStart: 50, spanEnd: 70),
        ], tolerance: 1)
        return MeasureBuilder.layer(content: content,
                                    from: CGPoint(x: 40, y: 0), to: CGPoint(x: 40, y: 100))
    }

    // MARK: - Derived names

    @Test func derivedNamesFollowAxisAndRole() {
        #expect(MeasureSpecList.derivedName(for: MeasureContent(mode: .horizontal, role: .size)) == "Width")
        #expect(MeasureSpecList.derivedName(for: MeasureContent(mode: .vertical, role: .size)) == "Height")
        #expect(MeasureSpecList.derivedName(for: MeasureContent(mode: .horizontal, role: .spacing)) == "Gap")
        #expect(MeasureSpecList.derivedName(for: MeasureContent(mode: .vertical, role: .spacing)) == "Gap")
        var aligned = MeasureContent()
        aligned.alignment = AlignmentCheck(items: [], tolerance: 1)
        #expect(MeasureSpecList.derivedName(for: aligned) == "Alignment")
    }

    @Test func displayNameDerivesUntilRenamedThenKeepsTheCustomName() {
        let fresh = caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10))
        #expect(fresh.name == "Measure") // builder default → derived name wins
        #expect(MeasureSpecList.displayName(for: fresh) == "Width")

        let renamed = caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10),
                              name: "Save button")
        #expect(MeasureSpecList.displayName(for: renamed) == "Save button")

        let guide = alignedGuide()
        #expect(guide.name == "Alignment") // builder default → derived
        #expect(MeasureSpecList.displayName(for: guide) == "Alignment")
    }

    // MARK: - Panel order

    @Test func measureLayersListTopMostFirstAndKeepHiddenOnes() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.addLayer(Layer(name: "Background",
                           content: .image(ImageRef(pixelSize: CGSize(width: 100, height: 100))),
                           frame: CGRect(x: 0, y: 0, width: 100, height: 100)))
        let bottom = caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10))
        let hidden = caliper(from: CGPoint(x: 0, y: 40), to: CGPoint(x: 64, y: 40), visible: false)
        let top = caliper(from: CGPoint(x: 20, y: 0), to: CGPoint(x: 20, y: 64))
        doc.addLayer(bottom)
        doc.addLayer(hidden)
        doc.addLayer(top)

        let listed = MeasureSpecList.measureLayers(in: doc)
        #expect(listed.map(\.id) == [top.id, hidden.id, bottom.id])
    }

    // MARK: - The pinned text format

    @Test func rendersHeaderAndOneLinePerVisibleMeasureInPanelOrder() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 800))
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10)))
        doc.addLayer(caliper(from: CGPoint(x: 20, y: 0), to: CGPoint(x: 20, y: 64)))
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 16, y: 50), role: .spacing))

        let text = MeasureSpecList.render(document: doc, name: "Capture")
        #expect(text == """
        Capture · 1280 × 800 px
        - Gap: 16 px (spacing)
        - Height: 64 px (size)
        - Width: 128 px (size)
        """)
    }

    @Test func hiddenMeasuresAndOtherLayersStayOut() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 100))
        doc.addLayer(Layer(name: "Background",
                           content: .image(ImageRef(pixelSize: CGSize(width: 200, height: 100))),
                           frame: CGRect(x: 0, y: 0, width: 200, height: 100)))
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10)))
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 40), to: CGPoint(x: 64, y: 40), visible: false))

        let text = MeasureSpecList.render(document: doc, name: "Shot")
        #expect(text == """
        Shot · 200 × 100 px
        - Width: 128 px (size)
        """)
    }

    @Test func emptyDocumentRendersJustTheHeader() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 640, height: 480))
        #expect(MeasureSpecList.render(document: doc, name: "Empty") == "Empty · 640 × 480 px")
    }

    @Test func customNamesAndUnitsCarryIntoTheLines() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), pixelScale: 2)
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10),
                             unit: .points, name: "Save button"))

        let text = MeasureSpecList.render(document: doc, name: "Retina")
        // 128 raw device px at 2× reads 64 logical px under the points unit.
        #expect(text == """
        Retina · 100 × 100 px
        - Save button: 64 px (size)
        """)
    }

    @Test func alignmentGuidesReadTheirVerdict() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.addLayer(alignedGuide())

        let text = MeasureSpecList.render(document: doc, name: "Panel")
        #expect(text == """
        Panel · 100 × 100 px
        - Alignment: aligned (alignment)
        """)
    }
}
