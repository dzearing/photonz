import Foundation
import PhotonzCore
import PhotonzRender

// Keying a colour out, and cutting a layer to the shape of the one below it
// (`PhotonzCore/LayerCompositing.swift`, `next-layers-combine`).
//
// Both are ordinary style edits — they go through `setLayerStyle`, so they are
// one undo step and they render the way every other style change renders. The
// only thing here that is not a one-liner is **Key it**, which has to look at
// the picture before it can offer a colour.

extension EditorState {

    /// The layers a Key row speaks for, and the layers a Masked by row speaks
    /// for. Both read the selection the other style rows read, so a preview in
    /// flight is what they report.
    var keyableSelection: LayerStyleSelection { layerStyleSelection.keyable }
    var maskableSelection: LayerStyleSelection { layerStyleSelection.maskable }

    /// **Key it**: the wall colour read off the picture, and the key switched
    /// on over it in one step.
    ///
    /// The colour comes from the edges of the frame the layer is showing right
    /// now, because that is where a backdrop is (`ChromaKeySampler`). For a
    /// clip that is the frame under the playhead, so keying at a moment where
    /// the subject fills the screen gives a worse answer than keying at a wide
    /// moment — which is true of every keyer and is why the colour is a well
    /// you can then change.
    ///
    /// Returns false when there was no wall to find, so the caller can say so
    /// rather than switching on a key that does nothing.
    @discardableResult
    func keyOutTheWall(ids: [UUID]) -> Bool {
        let colours = ids.compactMap { wallColour(ofLayer: $0) }
        guard let colour = colours.first else { return false }
        setLayerStyle(ids: ids) { style in
            if style.key != nil {
                style.key?.colorHex = colour.hexString
                style.key?.isOn = true
            } else {
                style.key = ChromaKey(colorHex: colour.hexString)
            }
        }
        return true
    }

    /// The colour round the edges of what this layer is showing, or nil when
    /// its edges are not one colour.
    func wallColour(ofLayer id: UUID) -> RGBA? {
        // What is ON SCREEN, so a clip is sampled at the frame under the
        // playhead rather than at its first frame.
        guard let layer = (shownDocument ?? document)?.layer(id: id),
              case .image(let ref) = layer.content,
              let bitmap = store.image(for: ref) else { return nil }
        return ChromaKeySampler.wallColour(of: bitmap)
    }

    /// Switching the key off, or back on, without forgetting its numbers.
    func setKeyIsOn(_ on: Bool, ids: [UUID]) {
        setLayerStyle(ids: ids) { $0.key?.isOn = on }
    }

    /// Taking the key off the layer entirely.
    func clearKey(ids: [UUID]) {
        setLayerStyle(ids: ids) { $0.key = nil }
    }

    /// What this layer borrows from the one under it, or nothing.
    func setMatte(_ matte: LayerMatte?, ids: [UUID]) {
        setLayerStyle(ids: ids) { $0.matte = matte }
    }

    /// The name of the layer a Masked by row would borrow its shape from, for
    /// the sentence under the control. Nil when the picked layers do not agree
    /// on one, which over a multiple selection is usually.
    var matteSourceName: String? {
        let ids = maskableSelection.layerIDs
        guard ids.count == 1, let id = ids.first, let doc = document,
              let below = doc.siblings(of: id).flatMap({ found -> Layer? in
                  guard found.index > 0 else { return nil }
                  return found.list[found.index - 1]
              })
        else { return nil }
        return below.displayName(readWords: [:])
    }
}
