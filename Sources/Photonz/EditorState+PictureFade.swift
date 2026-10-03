import Foundation
import PhotonzCore

// Fading a clip's picture in at its start and out at its end
// (`PictureFade.swift`).
//
// One fade for everything on the timeline: a recording, a title, a shape, a
// picture, a component. It is offered where a Final Cut or Premiere editor
// reaches for it: a right click on the bar (Fade In ▸, Fade Out ▸, a few
// lengths each), the Clip menu with a key for each end, and a handle at each
// top corner of the bar to drag to any length (`ClipPiecesBar`).
extension EditorState {

    /// The length the keys fade over: a second, the default transition length
    /// in both Premiere and Final Cut.
    static let pictureFadeKeyMS = 1000

    /// ⌃⌥I and ⌃⌥O: In and Out, the ends Premiere's marks already name, on a
    /// chord nothing else in the app uses.
    static func pictureFadeKey(_ end: FadeEnd) -> MenuShortcut {
        MenuShortcut(key: end == .in ? "i" : "o", modifiers: [.control, .option])
    }

    /// A layer whose picture the timeline's fade verbs may act on, whichever
    /// layer happens to be picked: the one a right click was opened on.
    func pictureFadeLayer(_ id: UUID) -> Layer? {
        guard Experiments.shared.pictureFadesEnabled, documentHasTime, !isClipLocked(id),
              let layer = document?.layer(id: id), layer.canFadePicture else { return nil }
        return layer
    }

    /// What the Clip menu's fade rows act on: the picked layer where it can
    /// fade, else the clip the timeline's edits act on.
    var pictureFadeLayerInHand: Layer? {
        if let id = selectedLayerID, let layer = pictureFadeLayer(id) { return layer }
        return clipInHandID.flatMap { pictureFadeLayer($0) }
    }

    func canSetPictureFade(_ end: FadeEnd, toMS ms: Int, layerID id: UUID) -> Bool {
        pictureFadeLayer(id)?.canSetPictureFade(end, toMS: ms) == true
    }

    /// Fade one end of a layer's picture over `ms`, nought taking it away.
    func setPictureFade(_ end: FadeEnd, toMS ms: Int, layerID id: UUID) {
        guard canSetPictureFade(end, toMS: ms, layerID: id) else { return }
        selectLayer(id)
        perform { $0.setPictureFade(id, end, toMS: ms) }
        documentMomentChanged()
    }

    /// What a length row does: that length, or, on the length it already has,
    /// no fade, so a checked row unchecks like every other toggle.
    func choosePictureFade(_ end: FadeEnd, ms: Int, layerID id: UUID) {
        let now = document?.layer(id: id)?.pictureFadeMS(end) ?? 0
        setPictureFade(end, toMS: ms == now ? 0 : ms, layerID: id)
    }

    /// The lengths one end offers on this layer: the one it has, and every
    /// other that leaves the other end its room.
    func pictureFadeStops(_ end: FadeEnd, layer: Layer) -> [Int] {
        let now = layer.pictureFadeMS(end)
        return PictureFade.stopsMS.filter { $0 == now || layer.canSetPictureFade(end, toMS: $0) }
    }

    /// **Fade In ▸** and **Fade Out ▸**, each a few lengths with the one it
    /// has checked. The one-second row prints the key that toggles it.
    func pictureFadeMenuRows(layerID id: UUID) -> [MenuRow] {
        guard let layer = pictureFadeLayer(id) else { return [] }
        return FadeEnd.allCases.map { end in
            let now = layer.pictureFadeMS(end)
            return .submenu(end.title, pictureFadeStops(end, layer: layer).map { ms in
                .toggle(PictureFade.title(ms), isOn: ms == now,
                        shortcut: ms == Self.pictureFadeKeyMS ? Self.pictureFadeKey(end) : nil) {
                    self.choosePictureFade(end, ms: ms, layerID: id)
                }
            })
        }
    }
}
