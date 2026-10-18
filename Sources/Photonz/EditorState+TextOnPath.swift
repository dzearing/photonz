import Foundation
import PhotonzCore

// Words set along a drawn curve (Next, `next-text-on-path`): Put Text on a
// Path over a picked text and a picked path, and the Start row that moves the
// words along it. Everything that decides the answer is in PhotonzCore
// (`TextOnPathEditing.swift`); this hands it the selection and the playhead.

extension EditorState {

    /// What the Layer menu and the right-click call the command. The mock's
    /// words, set the way a Mac menu sets them.
    static let putTextOnPathTitle = "Put Text on a Path"

    /// Whether Layer > Put Text on a Path has its two things picked.
    var canPutTextOnPath: Bool { textOnPathPair(actionableLayerIDs) != nil }

    /// Whether a right click on `id` offers it: that row is one of exactly a
    /// text and a path picked together.
    func canPutTextOnPath(id: UUID) -> Bool { textOnPathPair(rowMenuTargets(id)) != nil }

    func putSelectionTextOnPath() { putTextOnPath(ids: actionableLayerIDs) }

    func putTextOnPath(id: UUID) { putTextOnPath(ids: rowMenuTargets(id)) }

    private func textOnPathPair(_ ids: Set<UUID>) -> (text: UUID, path: UUID)? {
        guard Experiments.shared.textOnPathEnabled else { return nil }
        return document?.textAndPath(in: ids)
    }

    /// One undo step, and the words are left picked with the curve's points on
    /// them, ready to reshape (`CanvasPathEdit.editablePath`).
    private func putTextOnPath(ids: Set<UUID>) {
        guard let pair = textOnPathPair(ids) else { return }
        discardDragPreview()
        perform { $0.putTextOnPath(textID: pair.text, pathID: pair.path) }
        multiSelectedLayerIDs = []
        selectedLayerID = pair.text
    }

    // MARK: - Start

    /// The one picked text on a curve the Start row speaks for, or nil.
    var textPathStartLayerID: UUID? {
        guard Experiments.shared.textOnPathEnabled, let document else { return nil }
        let ids = textSelection.layerIDs
        guard ids.count == 1, let id = ids.first, document.layer(id: id)?.text?.onPath != nil else { return nil }
        return id
    }

    /// Where the picked words start along their curve at the playhead.
    var textPathStart: Double? {
        textPathStartLayerID.flatMap { document?.textPathStart(layerID: $0, atDocumentTimeMS: documentTimeMS) }
    }

    /// A Start typed or stepped: a key at the playhead where Start is keyed.
    func setTextPathStart(_ percent: Double) {
        guard let id = textPathStartLayerID else { return }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        if documentHasTime { activeKeyProperty = .motion(.pathStart) }
        perform { $0.setTextPathStart(percent, layerIDs: [id], atDocumentTimeMS: time, ease: ease) }
    }
}
