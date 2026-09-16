import AppKit
import PhotonzCore

// The box a self-arranging container shows while its handle is being dragged.
//
// Pull a handle on a stack and, until this, nothing on the canvas moved. Its
// rows are placed by the stack's own rules — a left aligned column keeps every
// row at its own width against the left edge — so they stay exactly where they
// were however wide the box gets, and a group has no edge of its own to follow
// the way a screen does. Both halves of the usual answer are also switched off
// for the whole of a resize: `refreshLayerSelectionDisplay` hides the blue
// outline AND the eight handles, so the edges being aligned stay unobstructed.
// The only sign anything was happening was the width in the right hand panel.
//
// So the container borrows the one piece of chrome it does not have. For as
// long as the button is down it wears the same grey hairline a screen wears at
// its edge, at the box the drag is MAKING, and the moment you let go it is
// gone again. One voice for "here is a container's edge", whether the container
// keeps one or not.
//
// Which box that is, and which containers need it at all, is
// `ContainerResizeBox` in PhotonzCore, where it is tested. The short version:
// a stack or a grid gets one, and it is drawn where the drag will LAND rather
// than where the pointer is, so a stack held at the widest it may be stops
// under the hairline as well as under the release.
extension CanvasNSView {

    /// The box the canvas is outlining for the container being resized right
    /// now, in canvas coordinates, or nil when there is nothing to outline.
    ///
    /// Read by a walk (`showsBox`), which is the only way to settle this: a
    /// picture taken mid-drag cannot tell a live outline from a dead one when
    /// nothing else in the frame moves.
    ///
    /// It is there from the PRESS rather than from the first move, unlike the
    /// reading on the pill: the outline and the handles go the instant the
    /// button goes down, so anything that waited for travel would leave a gap
    /// with no box on the canvas at all. A number that has not changed yet is
    /// noise; a box that has not changed yet is still the box.
    var liveResizeBox: CGRect? {
        guard Experiments.shared.autoLayoutEnabled,
              let drag = resizeDrag,
              let layer = document?.canvasLayer(id: drag.layerID) else { return nil }
        return ContainerResizeBox.box(of: layer, draggedTo: drag.frame)
    }

    func refreshResizeBox() {
        guard let viewport, let box = liveResizeBox, box.width > 0, box.height > 0 else {
            resizeBoxLayer.isHidden = true
            return
        }
        let path = CGMutablePath()
        // The same half-point inset the frame edges use, so a hairline lands on
        // a pixel rather than across two and comes out grey instead of soft.
        path.addRect(viewRect(forDocRect: box, in: viewport).insetBy(dx: 0.5, dy: 0.5))
        resizeBoxLayer.path = path
        resizeBoxLayer.isHidden = false
    }
}
