import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Where a drawn path's outline sits: inside the shape, centred on its edge,
/// or outside it. The Align row under a path's outline, as the icon drawing
/// mock draws it (`docs/design/mocks/pages/icon-draw-wt.html`, Stroke).
///
/// The model and the drawing already knew all three; what these pin is the
/// one choice a person makes and what the row reads back.
@Suite("Where a path's outline sits")
struct PathStrokeAlignTests {

    private func closedPath() -> PathContent {
        PathContent(anchors: [PathAnchor(point: .zero),
                              PathAnchor(point: CGPoint(x: 100, y: 0)),
                              PathAnchor(point: CGPoint(x: 100, y: 60))],
                    isClosed: true, strokeWidth: 4)
    }

    private func openPath() -> PathContent {
        var path = closedPath()
        path.isClosed = false
        return path
    }

    private func document(_ paths: PathContent...) -> (PhotonzDocument, [UUID]) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        var ids: [UUID] = []
        for path in paths {
            let layer = Layer(name: "Path", content: .path(path),
                              frame: CGRect(x: 0, y: 0, width: 100, height: 60))
            doc.layers.append(layer)
            ids.append(layer.id)
        }
        return (doc, ids)
    }

    // MARK: Setting it

    @Test("One choice reaches every picked closed path and says how many it reached")
    func setsEveryClosedPath() {
        var (doc, ids) = document(closedPath(), closedPath())
        #expect(doc.setPathStrokePosition(layerIDs: ids, to: .outside) == 2)
        #expect(ids.allSatisfy { doc.layer(id: $0)?.path?.strokePosition == .outside })
    }

    @Test("An open path is left centred: a line has no inside to be within")
    func openPathStaysCentred() {
        var (doc, ids) = document(openPath(), closedPath())
        #expect(doc.setPathStrokePosition(layerIDs: ids, to: .inside) == 1)
        #expect(doc.layer(id: ids[0])?.path?.strokePosition == .center)
        #expect(doc.layer(id: ids[1])?.path?.strokePosition == .inside)
    }

    @Test("Picking what it already is changes nothing, so no undo step is filed")
    func sameChoiceIsANoOp() {
        var (doc, ids) = document(closedPath())
        #expect(doc.setPathStrokePosition(layerIDs: ids, to: .center) == 0)
    }

    @Test("A locked path is left exactly as it is")
    func lockedPathIsLeftAlone() {
        var (doc, ids) = document(closedPath())
        doc.updateLayer(id: ids[0]) { $0.isLocked = true }
        #expect(doc.setPathStrokePosition(layerIDs: ids, to: .outside) == 0)
        #expect(doc.layer(id: ids[0])?.path?.strokePosition == .center)
    }

    // MARK: What the row reads

    @Test("A fresh path reads Center, which is what every vector tool draws")
    func freshPathReadsCenter() {
        let (doc, ids) = document(closedPath())
        let reading = doc.pathLineStyleSelection(layerIDs: ids).alignReading
        #expect(reading == StyleReading(value: .center, isMixed: false))
    }

    @Test("Two closed paths that differ read as mixed")
    func differingPathsReadMixed() {
        var outside = closedPath()
        outside.strokePosition = .outside
        let (doc, ids) = document(closedPath(), outside)
        #expect(doc.pathLineStyleSelection(layerIDs: ids).alignReading.isMixed)
    }

    @Test("An open path picked with a closed one does not make the row read mixed")
    func openPathsDoNotMuddyTheReading() {
        var inside = closedPath()
        inside.strokePosition = .inside
        let (doc, ids) = document(openPath(), inside)
        let reading = doc.pathLineStyleSelection(layerIDs: ids).alignReading
        #expect(reading == StyleReading(value: .inside, isMixed: false))
    }

    @Test("Only open paths read Center, whatever they carry, and offer nothing else")
    func onlyOpenPathsOfferCenterAlone() {
        var carried = openPath()
        carried.strokePosition = .outside
        let (doc, ids) = document(carried)
        let selection = doc.pathLineStyleSelection(layerIDs: ids)
        #expect(selection.alignReading == StyleReading(value: .center, isMixed: false))
        #expect(!selection.hasAnInside)
    }

    @Test("A closed path offers all three")
    func closedPathOffersAll() {
        let (doc, ids) = document(openPath(), closedPath())
        #expect(doc.pathLineStyleSelection(layerIDs: ids).hasAnInside)
    }

    // MARK: Existing documents

    @Test("A path saved before the row existed opens centred, as it was drawn")
    func oldFilesOpenCentred() throws {
        let json = """
        {"anchors":[{"point":[0,0],"kind":"corner"},{"point":[10,0],"kind":"corner"},\
        {"point":[10,10],"kind":"corner"}],"closed":true,"strokeWidth":4,"fillRule":"nonZero"}
        """
        let back = try JSONDecoder().decode(PathContent.self, from: Data(json.utf8))
        #expect(back.strokePosition == .center)
    }
}

/// What the file says for each of the three, so a browser draws the outline
/// where the canvas does. SVG has no outline alignment of its own: an inside
/// line is drawn twice as wide and clipped to the shape, an outside one is
/// drawn twice as wide with the shape masked out of it. That the pictures
/// match is pinned by `SVGExportRenderTests`; this pins the words.
@Suite("Where a path's outline sits, exported")
struct PathStrokeAlignSVGTests {

    private func svg(_ position: BorderPosition, closed: Bool = true) -> String {
        var content = SVGExportTests.bowedSquare()
        content.isClosed = closed
        content.strokeWidth = 6
        content.colorHex = "#112233"
        content.strokePosition = position
        return SVGExportTests.write(
            SVGExportTests.document([SVGExportTests.pathLayer(content)])).text
    }

    @Test("A centred outline is one plain stroke at its own width")
    func centerIsAPlainStroke() {
        let file = svg(.center)
        #expect(file.contains("stroke-width=\"6\""))
        #expect(!file.contains("clip-path=\"url(#edge-"))
        #expect(!file.contains("mask=\"url(#edge-"))
    }

    @Test("An inside outline is drawn double and clipped to the shape")
    func insideIsClipped() {
        let file = svg(.inside)
        #expect(file.contains("<clipPath id=\"edge-"))
        #expect(file.contains("stroke-width=\"12\""))
        #expect(file.contains("clip-path=\"url(#edge-"))
    }

    @Test("An outside outline is drawn double with the shape masked out")
    func outsideIsMasked() {
        let file = svg(.outside)
        #expect(file.contains("<mask id=\"edge-"))
        #expect(file.contains("stroke-width=\"12\""))
        #expect(file.contains("mask=\"url(#edge-"))
    }

    @Test("An open path's outline comes out centred whatever it carries")
    func openPathIsCentredInTheFile() {
        let file = svg(.outside, closed: false)
        #expect(file.contains("stroke-width=\"6\""))
        #expect(!file.contains("mask=\"url(#edge-"))
    }
}
