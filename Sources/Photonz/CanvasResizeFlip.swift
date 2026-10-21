// A side handle taken past the side opposite flips the layer and keeps going,
// the way Photoshop's Free Transform and Figma do it, instead of the box
// stopping at nothing (the user, 2026-10-20: "I tried resizing it and dragging
// to reverse it but that didn't work").

import CoreGraphics
import PhotonzCore

extension CanvasNSView {

    /// The ways a resize drag on `layer` has crossed the side opposite its
    /// handle, or none where a flip is not this drag's to make: the switch
    /// off, a reading of the picture (a measurement, a lens, a callout, whose
    /// box says what it reads), or a layer seen in space, whose drag is read
    /// off its card's own plane.
    func resizeFlips(for layer: Layer?, start: CGRect, handle: ResizeHandle,
                     pointer p: CGPoint) -> Set<FlipAxis> {
        guard Experiments.shared.flipLayersEnabled, let layer, layer.canBeMirrored,
              layer.zoomCallout == nil, document?.isSeenInSpace != true else { return [] }
        return Handles.crossings(of: handle, in: start, pointer: handleSpacePoint(p, layer: layer))
    }
}
