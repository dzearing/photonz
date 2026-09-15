import AppKit
import PhotonzCore

/// Copy Look and Paste Look: make one shape look like another without reading
/// every setting off it and typing it into the other.
///
/// The look itself is `LayerLook` in PhotonzCore, which decides WHAT a look is
/// and what happens when it lands on something that cannot wear all of it. This
/// is only the way in and out of it: which layer it comes off, where it is kept
/// between the two presses, and what the canvas says afterwards.
///
/// It is kept on a pasteboard of its own rather than the general one, so that
/// a look survives an ordinary Copy in between (which is the whole point: pick
/// up a look, go and find the shape you want it on, and copying anything on the
/// way must not take it away) and so that it crosses windows: a look lifted in
/// one document can be put on a shape in another.
enum LookPasteboard {
    static let name = NSPasteboard.Name("com.dzearing.photonz.look")
    private static let type = NSPasteboard.PasteboardType("com.dzearing.photonz.look")

    static var board: NSPasteboard { NSPasteboard(name: name) }

    static func write(_ look: LayerLook) {
        guard let data = try? JSONEncoder().encode(look) else { return }
        let board = board
        board.clearContents()
        board.setData(data, forType: type)
    }

    static func read() -> LayerLook? {
        guard let data = board.data(forType: type) else { return nil }
        return try? JSONDecoder().decode(LayerLook.self, from: data)
    }

    /// Whether there is a look waiting, without paying to decode it. Read by
    /// the menu to grey out Paste Look.
    static var isEmpty: Bool { board.data(forType: type) == nil }
}

extension EditorState {

    /// The layer whose look Copy Look takes: the topmost of what is picked, so
    /// the answer is the same twice running and the pill can name it.
    private var lookSourceID: UUID? { colorStyleTargetIDs.last }

    var canCopyLook: Bool {
        Experiments.shared.copyALookEnabled && lookSourceID != nil
    }

    var canPasteLook: Bool {
        Experiments.shared.copyALookEnabled && !colorStyleTargetIDs.isEmpty
            && !LookPasteboard.isEmpty
    }

    /// Picks up the look of the selected shape. Nothing on the canvas changes,
    /// so the pill is the only thing that says the key was taken.
    func copyLook() {
        guard Experiments.shared.copyALookEnabled else { return }
        guard let id = lookSourceID, let look = document?.look(ofLayer: id) else { return }
        LookPasteboard.write(look)
        raiseCanvasNotice(.lookCopied(layer: look.sourceName))
    }

    /// Puts the look you picked up on everything selected, in one step one undo
    /// puts back, and says what did not fit.
    func pasteLook() {
        guard Experiments.shared.copyALookEnabled else { return }
        guard let look = LookPasteboard.read() else { return }
        let targets = colorStyleTargetIDs
        guard !targets.isEmpty else { return }
        discardDragPreview()
        var report = LookPaste(layerCount: 0)
        perform { report = $0.applyLook(look, to: targets) }
        raiseCanvasNotice(.lookPasted(report))
    }

    // MARK: - The same two commands from a layer's own row

    /// Copy Look on a row takes THAT row's look, whatever else is picked: a
    /// right click names one layer, and the menu it opens should mean it.
    func copyLookOfRow(id: UUID) {
        guard Experiments.shared.copyALookEnabled else { return }
        guard let look = document?.look(ofLayer: id) else { return }
        LookPasteboard.write(look)
        raiseCanvasNotice(.lookCopied(layer: look.sourceName))
    }

    /// Paste Look on a row reaches the whole selection when that row is part of
    /// it, and that row alone when it is not. Right clicking one of five picked
    /// shapes and getting one of them restyled is the surprise this avoids.
    func pasteLookOntoRow(id: UUID) {
        guard Experiments.shared.copyALookEnabled else { return }
        guard let look = LookPasteboard.read() else { return }
        let targets = lookRowTargets(id: id)
        guard !targets.isEmpty else { return }
        discardDragPreview()
        var report = LookPaste(layerCount: 0)
        perform { report = $0.applyLook(look, to: targets) }
        raiseCanvasNotice(.lookPasted(report))
    }

    func canPasteLookOntoRow(id: UUID) -> Bool {
        Experiments.shared.copyALookEnabled && !LookPasteboard.isEmpty
            && !lookRowTargets(id: id).isEmpty
    }

    private func lookRowTargets(id: UUID) -> [UUID] {
        let picked = colorStyleTargetIDs
        return picked.contains(id) ? picked : [id]
    }
}
