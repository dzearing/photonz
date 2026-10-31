import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A path's line painted with a brush (`docs/design/brushes.md`, decision 9):
/// the path stays exact anchors, and its line is walked into the same brush
/// strokes a person's pointer makes.
@Suite("A path's brushed line")
struct PathBrushTests {

    /// An S: a curve from the left to the right, open, a 12 point line.
    private func curve(brush: BrushMedium? = .charcoal, closed: Bool = false) -> PathContent {
        var path = PathContent(
            anchors: [PathAnchor(point: CGPoint(x: 0, y: 50), handleOut: CGPoint(x: 60, y: -60), kind: .smooth),
                      PathAnchor(point: CGPoint(x: 200, y: 50), handleIn: CGPoint(x: -60, y: 60), kind: .smooth),
                      PathAnchor(point: CGPoint(x: 200, y: 150))],
            isClosed: closed, strokeWidth: 12, fill: nil)
        path.brush = brush.map { PathBrush(settings: BrushSettings(medium: $0)) }
        return path
    }

    @Test("A path with no brush has a plain line and no brush strokes")
    func plain() {
        #expect(curve(brush: nil).brushStrokes.isEmpty)
        #expect(PathContent(anchors: [PathAnchor(point: .zero), PathAnchor(point: CGPoint(x: 9, y: 0))]).brush == nil)
    }

    @Test("The brushed line follows the curve: every sample sits on the path's own outline")
    func followsTheCurve() throws {
        let path = curve()
        let strokes = path.brushStrokes
        #expect(strokes.count == 1)
        let stroke = try #require(strokes.first)
        #expect(stroke.samples.first?.point == CGPoint(x: 0, y: 50))
        #expect(stroke.samples.last?.point == CGPoint(x: 200, y: 150))
        // Every sample lies on the curve: close to the outline flattened finely.
        let fine = PathContent.figures(of: path.cgPath, step: 0.25).flatMap(\.points)
        for sample in stroke.samples {
            let nearest = fine.map { hypot($0.x - sample.point.x, $0.y - sample.point.y) }.min() ?? .infinity
            #expect(nearest < 0.5)
        }
        // ...and no two are further apart than the walk's step.
        let step = PathContent.brushStep(width: 12)
        for (a, b) in zip(stroke.samples, stroke.samples.dropFirst()) {
            #expect(hypot(b.point.x - a.point.x, b.point.y - a.point.y) <= step + 0.01)
        }
    }

    @Test("The line wears the path's own Thickness and colour, painted not smudged")
    func widthAndColour() throws {
        var path = curve()
        path.paint = Paint(hex: "#2255AA")
        path.brush?.settings.mode = .smudge
        let stroke = try #require(path.brushStrokes.first)
        #expect(stroke.settings.size == 12)
        #expect(stroke.settings.medium == .charcoal)
        #expect(stroke.settings.mode == .paint)
        #expect(stroke.colorHex == "#2255AA")
        #expect(PathBrush(settings: BrushSettings(medium: .oil, mode: .smudge)).settings.mode == .paint)
    }

    @Test("An open line is walked like a mouse, so its ends taper; a closed one is pressed all round")
    func tapersAtOpenEnds() throws {
        let open = try #require(curve().brushStrokes.first)
        #expect(open.samples.allSatisfy { $0.pressure == nil })
        let dabs = BrushPlacement.dabs(for: open)
        let middle = dabs[dabs.count / 2].diameter
        #expect(try #require(dabs.first).diameter < middle * 0.7)
        #expect(try #require(dabs.last).diameter < middle * 0.7)

        let closed = try #require(curve(closed: true).brushStrokes.first)
        #expect(closed.samples.allSatisfy { $0.pressure == BrushDynamics.steadyPress })
        #expect(closed.samples.first?.point == closed.samples.last?.point)
        let ring = BrushPlacement.dabs(for: closed)
        #expect(try #require(ring.first).diameter > middle * 0.9)
    }

    @Test("Moving an anchor moves the brushed line with it")
    func movingAnAnchorRepaints() throws {
        var path = curve()
        let before = try #require(path.brushStrokes.first)
        path.anchors[1].point = CGPoint(x: 260, y: 20)
        let after = try #require(path.brushStrokes.first)
        #expect(after.samples != before.samples)
        #expect(after.bounds.maxX > before.bounds.maxX + 40)
        // ...in the same brush, with the same grain.
        #expect(after.settings == before.settings)
        #expect(after.seed == before.seed)
    }

    @Test("A dashed brushed line is one stroke a dash, each tapering; a trim walks only what is drawn")
    func dashesAndTrim() {
        var dashed = curve()
        dashed.linePattern = .dashed
        #expect(dashed.brushStrokes.count > 3)
        #expect(dashed.brushStrokes.allSatisfy { $0.samples.allSatisfy { $0.pressure == nil } })

        var trimmed = curve()
        trimmed.trim = StrokeTrim(start: 0, end: 0.5)
        let whole = curve().brushStrokes.first?.bounds ?? .null
        let half = trimmed.brushStrokes.first?.bounds ?? .null
        #expect(half.width < whole.width)
    }

    @Test("Each ring of a ring-shaped path is its own closed stroke")
    func rings() {
        var path = PathContent(
            anchors: [PathAnchor(point: .zero), PathAnchor(point: CGPoint(x: 100, y: 0)),
                      PathAnchor(point: CGPoint(x: 100, y: 100)), PathAnchor(point: CGPoint(x: 0, y: 100)),
                      PathAnchor(point: CGPoint(x: 30, y: 30)), PathAnchor(point: CGPoint(x: 70, y: 30)),
                      PathAnchor(point: CGPoint(x: 70, y: 70))],
            isClosed: true, ringStarts: [4], strokeWidth: 6)
        path.brush = PathBrush(settings: BrushSettings(medium: .marker))
        let strokes = path.brushStrokes
        #expect(strokes.count == 2)
        #expect(Set(strokes.map(\.seed)).count == 2)
        #expect(strokes.allSatisfy { $0.samples.first?.point == $0.samples.last?.point })
    }

    @Test("No line, no strokes: a brush on a path with its outline off paints nothing")
    func noLine() {
        var path = curve()
        path.strokeWidth = 0
        #expect(path.brushStrokes.isEmpty)
    }

    @Test("A brushed line's bitmap reaches as far as the medium marks past its Size")
    func outset() {
        let plain = curve(brush: nil)
        let charcoal = curve(brush: .charcoal)
        #expect(charcoal.strokeOutset >= (6 * CGFloat(BrushMedium.charcoal.reach)).rounded(.down))
        #expect(charcoal.strokeOutset > plain.strokeOutset)
    }

    @Test("The brush is saved with the path and a file from before it opens plain")
    func codable() throws {
        let path = curve(brush: .watercolour)
        let data = try JSONEncoder().encode(path)
        let back = try JSONDecoder().decode(PathContent.self, from: data)
        #expect(back == path)
        #expect(back.brush?.medium == .watercolour)

        let plain = try JSONEncoder().encode(curve(brush: nil))
        #expect(String(decoding: plain, as: UTF8.self).contains("brush") == false)
        #expect(try JSONDecoder().decode(PathContent.self, from: plain).brush == nil)
    }

    // MARK: Setting it on the document

    private func document() -> (PhotonzDocument, [UUID], UUID) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let a = PathBuilder.layer(curve(brush: nil), at: .zero)
        let b = PathBuilder.layer(curve(brush: nil), at: CGPoint(x: 0, y: 100))
        let group = Layer(name: "Drawing", content: .group(GroupContent(children: [a, b])), frame: .zero)
        document.layers.append(group)
        return (document, [a.id, b.id], group.id)
    }

    @Test("Choosing a brush for a group restyles every path in it at once, in one change")
    func groupSwap() throws {
        var (doc, paths, group) = document()
        #expect(doc.pathLayerIDs(reaching: [group]) == paths)
        #expect(doc.setPathBrush(layerIDs: [group], to: BrushSettings(medium: .marker)) == 2)
        #expect(paths.allSatisfy { doc.layer(id: $0)?.path?.brush?.medium == .marker })
        // Swapped again: every line follows.
        #expect(doc.setPathBrush(layerIDs: [group], to: BrushSettings(medium: .chalk)) == 2)
        #expect(paths.allSatisfy { doc.layer(id: $0)?.path?.brush?.medium == .chalk })
        // The same choice twice is no change, so no undo step is filed.
        #expect(doc.setPathBrush(layerIDs: [group], to: BrushSettings(medium: .chalk)) == 0)
        // And back to a plain line.
        #expect(doc.setPathBrush(layerIDs: paths, to: nil) == 2)
        #expect(paths.allSatisfy { doc.layer(id: $0)?.path?.brush == nil })
    }

    @Test("A brush's own setting reaches every brushed path that has it, clamped to its range")
    func ownSetting() throws {
        var (doc, paths, group) = document()
        doc.setPathBrush(layerIDs: [group], to: BrushSettings(medium: .marker))
        #expect(doc.setPathBrushSetting(layerIDs: [group], id: "flow", to: 250) == 2)
        let flow = try #require(BrushMedium.marker.spec("flow"))
        #expect(paths.allSatisfy { doc.layer(id: $0)?.path?.brush?.settings.value("flow") == flow.range.upperBound })
        #expect(doc.setPathBrushSetting(layerIDs: [group], id: "wetness", to: 50) == 0)
    }

    @Test("A path with its line off is given one when it is brushed, and a locked one is left alone")
    func lineAndLock() throws {
        var (doc, paths, _) = document()
        doc.updateLayer(id: paths[0]) { layer in
            var path = layer.path!
            path.strokeWidth = 0
            layer.content = .path(path)
        }
        doc.updateLayer(id: paths[1]) { $0.isLocked = true }
        #expect(doc.setPathBrush(layerIDs: paths, to: BrushSettings(medium: .pencil)) == 1)
        #expect((doc.layer(id: paths[0])?.path?.strokeWidth ?? 0) > 0)
        #expect(doc.layer(id: paths[1])?.path?.brush == nil)
    }
}
