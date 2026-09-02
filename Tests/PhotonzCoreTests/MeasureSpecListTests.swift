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

    /// An alignment guide whose scan came back aligned, down two left edges.
    private func alignedGuide(side: EdgeSide? = .after) -> Layer {
        var content = MeasureContent()
        content.mode = .vertical
        content.headOffset = 0
        content.alignment = AlignmentCheck(items: [
            AlignmentItem(edge: 40, spanStart: 10, spanEnd: 30, elementSide: side),
            AlignmentItem(edge: 40, spanStart: 50, spanEnd: 70, elementSide: side),
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
        var aligned = MeasureContent(mode: .vertical)
        aligned.alignment = AlignmentCheck(items: [], tolerance: 1)
        #expect(MeasureSpecList.derivedName(for: aligned) == "Vertical edges, no items")
    }

    /// A guide's name says which edges it judged and how many things it
    /// checked (the mock's "Left edge alignment, 4 items", shortened so the
    /// count survives the panel's default width). When the scan could not
    /// tell which side the elements sit on, it names the guide's axis rather
    /// than guess a side.
    @Test func guideNamesCarryTheEdgeAndTheCount() {
        func guide(_ mode: MeasureMode, _ side: EdgeSide?, count: Int) -> MeasureContent {
            var c = MeasureContent(headOffset: 0, mode: mode)
            c.alignment = AlignmentCheck(items: (0..<count).map {
                AlignmentItem(edge: 40, spanStart: CGFloat($0 * 20), spanEnd: CGFloat($0 * 20 + 10),
                              elementSide: side)
            }, tolerance: 1)
            return c
        }
        #expect(MeasureSpecList.derivedName(for: guide(.vertical, .after, count: 4)) == "Left edges, 4 items")
        #expect(MeasureSpecList.derivedName(for: guide(.vertical, .before, count: 2)) == "Right edges, 2 items")
        #expect(MeasureSpecList.derivedName(for: guide(.horizontal, .after, count: 3)) == "Top edges, 3 items")
        #expect(MeasureSpecList.derivedName(for: guide(.horizontal, .before, count: 2)) == "Bottom edges, 2 items")
        #expect(MeasureSpecList.derivedName(for: guide(.vertical, nil, count: 2)) == "Vertical edges, 2 items")
        #expect(MeasureSpecList.derivedName(for: guide(.horizontal, nil, count: 2)) == "Horizontal edges, 2 items")
        #expect(MeasureSpecList.derivedName(for: guide(.vertical, .after, count: 1)) == "Left edges, 1 item")
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
        #expect(MeasureSpecList.displayName(for: guide) == "Left edges, 2 items")
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
        // 128 raw device px at 2× reads 64 logical px under the points unit,
        // and the header reads the canvas the same way, naming the scale.
        #expect(text == """
        Retina · 50 × 50 px @2x
        - Save button: 64 px (size)
        """)
    }

    @Test func theHeaderFollowsTheRowsUnit() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), pixelScale: 2)
        // No rows: the app measures in logical pixels by default, so an empty
        // list on a Retina capture still heads with the logical size.
        #expect(MeasureSpecList.headerSize(document: doc) == "50 × 50 px @2x")
        // Every row in device pixels: the header is the device size, no suffix.
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10), unit: .pixels))
        #expect(MeasureSpecList.headerSize(document: doc) == "100 × 100 px")
        // A mix follows the logical rows, since that is the default unit.
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 20), to: CGPoint(x: 64, y: 20), unit: .points))
        #expect(MeasureSpecList.headerSize(document: doc) == "50 × 50 px @2x")
        // A hidden device-pixel row does not steer the header.
        var doc2 = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), pixelScale: 2)
        doc2.addLayer(caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10), unit: .pixels, visible: false))
        #expect(MeasureSpecList.headerSize(document: doc2) == "50 × 50 px @2x")
        // A 1x capture never carries a suffix.
        let flat = PhotonzDocument(canvasSize: CGSize(width: 640, height: 480))
        #expect(MeasureSpecList.headerSize(document: flat) == "640 × 480 px")
    }

    @Test func alignmentGuidesReadTheirVerdict() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.addLayer(alignedGuide())

        let text = MeasureSpecList.render(document: doc, name: "Panel")
        #expect(text == """
        Panel · 100 × 100 px
        - Left edges, 2 items: aligned (alignment)
        """)
    }

    @Test func aGuideThatCouldNotTellItsSideStillReadsItsCount() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.addLayer(alignedGuide(side: nil))
        let text = MeasureSpecList.render(document: doc, name: "Panel")
        #expect(text == """
        Panel · 100 × 100 px
        - Vertical edges, 2 items: aligned (alignment)
        """)
    }

    // MARK: - Copying a selection (Copy Measurement)

    @Test func selectedMeasurementsRenderTheirSpecLinesOnlyInPanelOrder() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 800))
        let width = caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10))
        let height = caliper(from: CGPoint(x: 20, y: 0), to: CGPoint(x: 20, y: 64))
        let gap = caliper(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 16, y: 50), role: .spacing)
        doc.addLayer(width)
        doc.addLayer(height)
        doc.addLayer(gap)

        // Ids in any order: the text keeps the panel's top-most-first order,
        // and carries no header (these are lines to paste into a thread).
        let text = MeasureSpecList.render(document: doc, ids: [width.id, gap.id])
        #expect(text == """
        - Gap: 16 px (spacing)
        - Width: 128 px (size)
        """)
    }

    @Test func aSelectedLineMatchesItsSpecListRow() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), pixelScale: 2)
        let named = caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10),
                            unit: .points, name: "Save button")
        doc.addLayer(named)
        doc.addLayer(alignedGuide())

        let one = MeasureSpecList.render(document: doc, ids: [named.id])
        let full = MeasureSpecList.render(document: doc, name: "Retina")
        #expect(one == "- Save button: 64 px (size)")
        #expect(full.split(separator: "\n").map(String.init).contains(one))
    }

    @Test func anExplicitlySelectedHiddenMeasurementStillCopies() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 100))
        let hidden = caliper(from: CGPoint(x: 0, y: 40), to: CGPoint(x: 64, y: 40), visible: false)
        doc.addLayer(hidden)

        #expect(MeasureSpecList.render(document: doc, ids: [hidden.id]) == "- Width: 64 px (size)")
    }

    @Test func selectingNothingOrOnlyOtherLayersRendersNothing() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 100))
        let picture = Layer(name: "Background",
                            content: .image(ImageRef(pixelSize: CGSize(width: 200, height: 100))),
                            frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        doc.addLayer(picture)
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10)))

        #expect(MeasureSpecList.render(document: doc, ids: []) == "")
        #expect(MeasureSpecList.render(document: doc, ids: [picture.id]) == "")
    }
}
