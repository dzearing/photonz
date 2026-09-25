import Foundation
import PhotonzCore

/// A handle on a motion path, part way through being dragged: which stretch,
/// and where its middle is now, in canvas points.
struct MotionPathBendPreview: Equatable {
    let layerID: UUID
    let segment: Int
    var point: CGPoint
}

/// A moving layer draws its path on the canvas, and dragging the path bends it
/// into an arc (task `a-moving-layer-draws-its-path-on-the-canvas-and`,
/// `docs/design/mocks/pages/video-move-wt.html` steps 5, 7 and 8).
///
/// A thin layer over `MotionPath.swift`: the canvas asks what to draw, hands
/// back where a handle is, and every change lands through `perform`, so one
/// bend is one step to undo.
extension EditorState {

    /// The picked layer's path, with a handle under the hand standing in for
    /// the stored bend. Nil unless the picked layer moves from one place to
    /// another in a document that runs for a length of time.
    var motionPathOverlay: MotionPathOnCanvas? {
        guard let layer = keyLayer, var document else { return nil }
        if let preview = motionPathPreview, preview.layerID == layer.id {
            document.bendMotionPath(layerID: layer.id, segment: preview.segment,
                                    throughCanvasPoint: preview.point)
        }
        return document.motionPath(layerID: layer.id)
    }

    /// What the Path control in Properties shows: nil where there is no path.
    var motionPathShape: MotionPathShape? {
        guard let layer = keyLayer, let motion = layer.keyedMotion(.position),
              !motion.pathSegments.isEmpty else { return nil }
        if let preview = motionPathPreview, preview.layerID == layer.id {
            return .curved
        }
        return motion.pathShape
    }

    /// The document with the handle under the hand applied, so the picture
    /// follows the bend before it is written down.
    func withPreviewedMotionPath(_ document: PhotonzDocument) -> PhotonzDocument {
        guard let preview = motionPathPreview else { return document }
        var document = document
        document.bendMotionPath(layerID: preview.layerID, segment: preview.segment,
                                throughCanvasPoint: preview.point)
        return document
    }

    /// A handle moving under the hand.
    func previewMotionPathBend(layerID: UUID, segment: Int, to point: CGPoint) {
        motionPathPreview = MotionPathBendPreview(layerID: layerID, segment: segment, point: point)
        rerender()
    }

    /// The button up: one undo step for the whole bend.
    func commitMotionPathBend() {
        guard let preview = motionPathPreview else { return }
        motionPathPreview = nil
        perform { $0.bendMotionPath(layerID: preview.layerID, segment: preview.segment,
                                    throughCanvasPoint: preview.point) }
    }

    /// A press that went nowhere, or Escape part way: nothing is written.
    func cancelMotionPathBend() {
        guard motionPathPreview != nil else { return }
        motionPathPreview = nil
        rerender()
    }

    /// A double-click on a handle: that stretch snaps back to straight.
    func straightenMotionPath(layerID: UUID, segment: Int) {
        motionPathPreview = nil
        guard let motion = document?.layer(id: layerID)?.keyedMotion(.position),
              motion.pathSegments.indices.contains(segment),
              motion.pathSegments[segment].isCurved else { return }
        perform { $0.straightenMotionPath(layerID: layerID, segment: segment) }
    }

    /// The Path control, and the Animate menu's Curve the Path.
    func setMotionPathShape(_ shape: MotionPathShape) {
        guard let layer = keyLayer, motionPathShape != nil, motionPathShape != shape else { return }
        perform { $0.shapeMotionPath(layerID: layer.id, shape) }
    }

    /// A right click on a path's handle: the path's two shapes, and putting
    /// the stretch under the pointer back on its line. Nil anywhere else.
    func motionPathMenuRows(at point: CGPoint?) -> [MenuRow]? {
        guard let point, let path = motionPathOverlay,
              let shape = motionPathShape else { return nil }
        let reach = 12 / max(zoom, 0.01)
        guard let segment = path.segments.firstIndex(where: {
            hypot($0.middle.x - point.x, $0.middle.y - point.y) <= reach
        }) else { return nil }
        var rows: [MenuRow] = [
            .toggle("Straight", isOn: shape == .straight) { self.setMotionPathShape(.straight) },
            .toggle("Curved", isOn: shape == .curved) { self.setMotionPathShape(.curved) },
        ]
        if path.segments.count > 1, path.segments[segment].isCurved {
            rows.append(.separator)
            rows.append(.command("Straighten This Stretch") {
                self.straightenMotionPath(layerID: path.layerID, segment: segment)
            })
        }
        return rows
    }
}
