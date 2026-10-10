import CoreGraphics
import Foundation

extension PhotonzDocument {

    /// The middle of the icon a layer is drawn in, as the pivot the Around
    /// menu's Artboard sets on it (`MotionPivot.artboard`), or nil where there
    /// is no icon to turn about: a layer loose on the canvas, a layer on a
    /// screen, and the icon frame itself.
    ///
    /// The place is stated where the layer's own box is stated, which for a
    /// shape straight inside the frame is from the frame's corner, so the
    /// middle of a 24 unit icon is (12, 12) wherever the frame sits on the
    /// canvas; inside a group in the icon it is counted from the group's
    /// corner instead.
    public func artboardPivot(for id: UUID) -> MotionPivot? {
        guard let frameID = iconFrameID(containing: id), frameID != id,
              let icon = canvasFrame(of: frameID), let layer = layer(id: id),
              let origin = parentOrigin(of: id) else { return nil }
        let middle = CGPoint(x: icon.midX - origin.x, y: icon.midY - origin.y)
        return .artboard(at: middle, in: layer.turnPivotBox)
    }
}
