import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A Border round a path survives the trip into a file.
///
/// The canvas draws the ring by baking the outline's own silhouette, so it
/// hugs whatever the path is. The exporter used to write a `<rect>` instead,
/// because a ring round any layer that was not an oval was a rounded rectangle
/// round its box. An icon drawn as a chevron and exported with a border came
/// out as a chevron in a picture frame, which is not the icon anybody drew.
///
/// SVG has no offset curve, so the band is written the way the path's own
/// inside and outside lines are already written: the outline stroked DOUBLE
/// wide with the half that should not be there masked off
/// (`SVGExport.path`).
@Suite("A border round a path, exported")
struct PathRingExportTests {

    private func chevron(closed: Bool) -> PathContent {
        var content = PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 0)),
                                            PathAnchor(point: CGPoint(x: 50, y: 100)),
                                            PathAnchor(point: CGPoint(x: 100, y: 0))],
                                  isClosed: closed)
        content.strokeWidth = 0
        content.fill = nil
        return content
    }

    private func file(closed: Bool, position: BorderPosition,
                      width: CGFloat = 8, offset: CGFloat = 0) -> String {
        var layer = SVGExportTests.pathLayer(chevron(closed: closed))
        layer.style.effects = [.border(BorderEffect(width: width, colorHex: "#FF0000",
                                                    position: position, offset: offset))]
        return SVGExportTests.write(SVGExportTests.document([layer])).text
    }

    // MARK: Never a box

    @Test("No rectangle is written for a border on a path",
          arguments: [true, false], BorderPosition.allCases)
    func neverARect(closed: Bool, position: BorderPosition) {
        let svg = file(closed: closed, position: position)
        // Nothing rectangular is ever PAINTED in the border's colour. A mask
        // holds a white sheet to cut the band out of, and that one is not the
        // ring: it is never inked and never seen.
        for line in svg.split(separator: "\n") where line.contains("<rect") {
            #expect(!line.contains("#FF0000"), "the ring came out as a rectangle: \(line)")
        }
        // ...and the ring really is there: a red stroke on the outline.
        #expect(svg.contains("stroke=\"#FF0000\""))
        for line in svg.split(separator: "\n") where line.contains("#FF0000") {
            #expect(line.contains("<path "), "the ring should be the outline: \(line)")
        }
    }

    // MARK: An open line

    @Test("An open line's border is one centred stroke of the width asked for")
    func anOpenLineIsStrokedOnce() {
        for position in BorderPosition.allCases {
            let svg = file(closed: false, position: position)
            // No mask and no clip: a line has no inside to cut anything away
            // against, so the stroke rides straight down it.
            #expect(!svg.contains("mask=\"url(#"), "\(position) should need no mask")
            #expect(!svg.contains("clip-path=\"url(#ring"), "\(position) should need no clip")
            #expect(svg.contains("stroke-width=\"8\""), "\(position) should be 8 wide")
        }
    }

    // MARK: A closed shape

    @Test("An inside border is stroked double wide and masked back to the shape")
    func insideIsMaskedIn() {
        let svg = file(closed: true, position: .inside)
        #expect(svg.contains("stroke-width=\"16\""))
        #expect(svg.contains("mask=\"url(#"))
    }

    @Test("An outside border is stroked double wide and masked off the shape")
    func outsideIsMaskedOut() {
        let svg = file(closed: true, position: .outside)
        #expect(svg.contains("stroke-width=\"16\""))
        #expect(svg.contains("mask=\"url(#"))
    }

    @Test("A centred border needs no mask at all")
    func centredIsPlain() {
        let svg = file(closed: true, position: .center)
        #expect(svg.contains("stroke-width=\"8\""))
        #expect(!svg.contains("mask=\"url(#"))
    }

    @Test("A border standing off the edge is stroked wide enough to reach it")
    func anOffsetRingReaches() {
        // Six points out, four wide: the band runs from 6 to 10 outside, so the
        // stroke has to be 20 wide and the first 12 of it masked away.
        let svg = file(closed: true, position: .outside, width: 4, offset: 6)
        #expect(svg.contains("stroke-width=\"20\""))
        #expect(svg.contains("stroke-width=\"12\""))
        #expect(svg.contains("mask=\"url(#"))
    }

    // MARK: Nothing else moved

    @Test("An oval still exports as an ellipse and a frame still as a rect")
    func everythingElseIsUntouched() {
        var oval = Layer(name: "Oval",
                         content: .annotation(AnnotationContent(shape: .ellipse,
                                                                strokeWidth: 0)),
                         frame: CGRect(x: 20, y: 20, width: 100, height: 60))
        oval.style.effects = [.border(BorderEffect(width: 8, colorHex: "#FF0000",
                                                   position: .outside))]
        #expect(SVGExportTests.write(SVGExportTests.document([oval])).text.contains("<ellipse "))

        var frame = Layer(name: "Frame",
                          content: .group(GroupContent(children: [], isFrame: true)),
                          frame: CGRect(x: 20, y: 20, width: 100, height: 60))
        frame.style.effects = [.border(BorderEffect(width: 8, colorHex: "#FF0000",
                                                    position: .outside))]
        #expect(SVGExportTests.write(SVGExportTests.document([frame])).text.contains("<rect "))
    }
}
