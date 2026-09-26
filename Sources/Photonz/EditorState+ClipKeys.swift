import Foundation
import PhotonzCore

/// Keys on a clip, and the title presets
/// (`move-a-layer-from-a-to-b-grow-it-shrink-it-fade`, `ClipKeys.swift`).
///
/// A thin layer over the model: every change goes through `perform`, so a
/// dragged key, an ease, a deleted key and a preset are each one undo step.
extension EditorState {

    // MARK: The diamonds

    /// The diamonds a layer's clip carries, as the timeline is showing it.
    func clipKeyMarks(layerID: UUID) -> [ClipKeyMark] {
        guard documentHasTime, let document = shownDocument ?? document else { return [] }
        return document.clipKeyMarks(layerID: layerID)
    }

    /// The same, for a clip's own bar, which only follows a drag it is in
    /// (`shownDocument(forClip:)`).
    func clipKeyMarks(onBarOf layerID: UUID) -> [ClipKeyMark] {
        guard documentHasTime, let document = shownDocument(forClip: layerID) else { return [] }
        return document.clipKeyMarks(layerID: layerID)
    }

    /// A diamond let go somewhere else in time.
    func moveClipKeys(layerID: UUID, fromMS: Int, toMS: Int) {
        guard fromMS != toMS, !isClipLocked(layerID) else { return }
        selectLayer(layerID)
        perform { $0.moveClipKeys(layerID: layerID, fromMS: fromMS, toMS: toMS) }
    }

    /// A diamond clicked: the layer picked, and the playhead on the key, so the
    /// panel's diamonds light up on exactly what is keyed there.
    func pickClipKey(layerID: UUID, atMS ms: Int) {
        selectLayer(layerID)
        if isDocumentPlaying { pauseDocument() }
        scrubDocument(toMS: ms)
    }

    /// What a right click on a diamond offers: Premiere's four ways a key
    /// moves, ticked where every key there agrees, and Delete.
    func clipKeyMenuRows(layerID: UUID, atMS ms: Int) -> [MenuRow] {
        guard let document, !isClipLocked(layerID) else { return [] }
        let current = document.clipKeyEase(layerID: layerID, atMS: ms)
        var rows: [MenuRow] = KeyEase.allCases.map { ease in
            .toggle(ease.title, isOn: current == ease) {
                self.selectLayer(layerID)
                self.perform { $0.easeClipKeys(layerID: layerID, atMS: ms, ease) }
            }
        }
        rows.append(.separator)
        rows.append(.command("Go to Key") { self.pickClipKey(layerID: layerID, atMS: ms) })
        rows.append(.separator)
        rows.append(.command("Delete Key", destructive: true) {
            self.selectLayer(layerID)
            self.perform { $0.removeClipKeys(layerID: layerID, atMS: ms) }
        })
        return rows
    }

    // MARK: Animate In and Out

    /// Animate In ▸ and Animate Out ▸, for anything placed in time: a title, a
    /// piece of clip art, a component. Empty for everything else.
    func titleAnimationMenuRows(layerID: UUID) -> [MenuRow] {
        guard documentHasTime, !isClipLocked(layerID),
              let layer = document?.layer(id: layerID), layer.isPlacedInTime else { return [] }
        return [
            .submenu("Animate In", TitleAnimation.allCases.map { kind in
                .command(kind.title) { self.animate(kind, isIn: true, layerID: layerID) }
            }),
            .submenu("Animate Out", TitleAnimation.allCases.map { kind in
                .command(kind.title) { self.animate(kind, isIn: false, layerID: layerID) }
            }),
        ]
    }

    func animate(_ kind: TitleAnimation, isIn: Bool, layerID: UUID) {
        selectLayer(layerID)
        perform { document in
            if isIn {
                document.animateIn(kind, layerID: layerID)
            } else {
                document.animateOut(kind, layerID: layerID)
            }
        }
    }
}
