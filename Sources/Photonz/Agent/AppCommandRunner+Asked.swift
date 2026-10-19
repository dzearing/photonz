import Foundation
import PhotonzCore

/// **What a person is asked for, an agent says.** Rename, Resize Image, Canvas
/// Size, Freeze Frame and the rest open a field, a sheet or a popover for a
/// person to answer. Their menu rows still do (`run` with the argument left
/// out); an agent's `run_command` must give the answer, and these are the same
/// edits those answers make, taking it as an argument
/// (`docs/design/agent-mcp.md`, the rest of the menu commands).
extension EditorState {

    // MARK: Save

    /// Whether Command S would ask where to put the document: a picture never
    /// saved that is not a History capture, or a recording history does not
    /// hold. An agent is told to export instead of being shown a save box.
    var saveAsksWhere: Bool {
        guard document != nil else { return true }
        if isRecordingDocument {
            guard let situation = historySaveSituation else { return true }
            return HistoryVideoSave.plan(situation) == .askWhere
        }
        if documentURL != nil { return false }
        if let sourceCaptureURL, let store = captureCenter?.store,
           store.entries.contains(where: { $0.url == sourceCaptureURL }) { return false }
        return true
    }

    // MARK: Names and words

    /// A clip's name, or a caption's words, as typing over its bar sets them.
    func renameClip(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if captionWords(of: id) != nil {
            setCaptionText(id: id, to: trimmed)
        } else if !trimmed.isEmpty {
            renameLayer(id: id, to: trimmed)
        }
    }

    /// One caption word as typed over it: two words typed are two words.
    func setCaptionWord(_ ref: CaptionWordRef, to text: String) {
        guard canEditCaptionWords, var probe = document, probe.setCaptionWord(ref, to: text) else { return }
        perform { _ = $0.setCaptionWord(ref, to: text) }
        documentMomentChanged()
    }

    // MARK: A click, a zoom, a freeze

    /// Whether a click can land at this point of the picture on this clip now.
    func canAddClick(toClip id: UUID, at point: CGPoint) -> Bool {
        guard canAddClick(toClip: id), var trial = document else { return false }
        return trial.addClick(toClip: id, atMS: documentTimeMS, canvasPoint: point) != nil
    }

    /// A click at the playhead, where the crosshair's click on the picture
    /// would have put it.
    func addClick(toClip id: UUID, at point: CGPoint) {
        guard canAddClick(toClip: id, at: point) else { return }
        let ms = documentTimeMS
        perform { _ = $0.addClick(toClip: id, atMS: ms, canvasPoint: point) }
        raiseCanvasNotice(.clickAdded(atMS: ms), action: .undo)
    }

    /// The zoom at the playhead on the recording in hand (any recording under
    /// the playhead when none is), picked as a click on its bar picks it.
    /// False when there is no zoom there.
    @discardableResult
    func pickZoomAtPlayhead() -> Bool {
        guard let document else { return false }
        let ms = documentTimeMS
        let clips = clipInHandID.map { [$0] } ?? document.allLayers.reversed().map(\.id)
        for id in clips {
            guard let layer = document.layer(id: id), let time = layer.time, time.contains(ms: ms),
                  let zoom = layer.zoom(atSourceMS: layer.motionClockMS(atDocumentTimeMS: ms)) else { continue }
            pickZoom(ClipZoomRef(layerID: id, zoomID: zoom.id))
            return true
        }
        return false
    }

    /// The gap at the playhead on a track, picked as a click in it picks it.
    @discardableResult
    func pickGap(onTrack trackID: UUID) -> Bool {
        guard documentHasTime, let gap = document?.gap(onTrack: trackID, atMS: documentTimeMS) else { return false }
        letGoOfTimelinePicks()
        if selectedLayerID != nil || !multiSelectedLayerIDs.isEmpty { selectLayer(nil) }
        if selectedEditPoint != nil { selectedEditPoint = nil }
        timelineGapInHand = gap
        return true
    }

    /// Freeze Frame with the length given rather than typed into its popover:
    /// a new freeze at the playhead, or the freeze in hand made this long.
    func freezeFrameInHand(ms: Int, everyTrack: Bool?) {
        let push: HoldPush = everyTrack.map { $0 ? .everything : .thisTrack } ?? holdPushChoice
        if let id = clipInHandID, let index = clipPieceInHand, clipPieceInHandPiece?.isHeld == true {
            holdPushChoice = push
            pauseDocument()
            perform { doc in
                _ = doc.setHoldPush(id, ofPiece: index, to: push)
                _ = doc.setHoldLength(id, ofPiece: index, toMS: ms)
            }
            selectClipPiece(layerID: id, index: index)
            documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
            documentMomentChanged()
            return
        }
        guard canHoldFrameAtPlayhead, let id = clipInHandID else { return }
        holdPushChoice = push
        selectLayer(id)
        holdFrameAtPlayhead(forMS: ms)
    }

    // MARK: Keys

    func easingCurve(named name: String?) -> EasingCurve? {
        guard let name else { return nil }
        return EasingCurve.named.first { $0.title.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The layer Animate ▸ acts on: the one picked, which a right click picks.
    var layerToAnimate: Layer? {
        keyLayer ?? selectedLayerID.flatMap { document?.layer(id: $0) }
    }

    /// A value the layer in hand is not animating yet, by the words its
    /// Animate row uses on that layer.
    func propertyToAnimate(named name: String?) -> KeyedProperty? {
        guard let name, let layer = layerToAnimate else { return nil }
        return animateGroups(layerID: layer.id).flatMap(\.properties)
            .first { $0.title(on: layer).caseInsensitiveCompare(name) == .orderedSame }
    }

    /// A value the layer in hand is animating, by its row's words; left
    /// unnamed, the one Stop Animating takes.
    func propertyAnimating(named name: String?) -> KeyedProperty? {
        guard let name else { return animatingPropertyInHand }
        guard let layer = keyLayer else { return nil }
        return animatingRows.first { $0.title(on: layer).caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: Titles

    /// The style a call names, the person's own first, as Insert lists them.
    func titlePreset(_ call: AppCommandCall) -> TitlePreset? {
        guard let kind = call.word("kind").flatMap(TitleKind.init(rawValue:)), let name = call.word("preset") else {
            return nil
        }
        if let own = TitlePresetStore.shared.presets(of: kind).first(where: { $0.name == name }) {
            return .saved(own)
        }
        return TitlePreset.builtIn(of: kind, movingBackdrops: Experiments.shared.titleBackgroundsEnabled)
            .first { $0.name == name }
    }

    /// Every style Insert lists for a kind, the person's own first.
    func titlePresetNames(_ kind: TitleKind) -> [String] {
        TitlePresetStore.shared.presets(of: kind).map(\.name)
            + TitlePreset.builtIn(of: kind, movingBackdrops: Experiments.shared.titleBackgroundsEnabled).map(\.name)
    }

    /// Save as Preset with the name given rather than typed into its sheet,
    /// filed under the kind the sheet would have offered first.
    func saveTitlePresetInHand(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = titlePresetLayerInHand,
              let preset = document?.savedTitlePreset(layerID: id, name: trimmed) else { return }
        TitlePresetStore.shared.keep(preset)
        raiseCanvasNotice(.titlePresetSaved(name: preset.name))
    }

    // MARK: Effects

    func savedEffect(named name: String?) -> EffectStyle? {
        guard let name else { return nil }
        return namedEffectStyles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The Effects list's row at this place, counted as read_document lists a
    /// layer's effects.
    func effectRow(_ index: Int?) -> LayerEffectRow? {
        guard let index else { return nil }
        return layerEffectRows.first { $0.index == index }
    }
}
