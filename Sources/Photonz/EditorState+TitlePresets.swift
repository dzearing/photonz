import Foundation
import Observation
import PhotonzCore

// Title pages and name cards (`docs/design/video-titles.md`,
// `TitlePresets.swift`).
//
// Inserting is a verb, so it lives where verbs live: Sequence in the menu bar
// (beside Add Sound, which also adds to the time) and the right-click menu of
// an empty track (beside Add Text and Add Rectangle). Saving your own acts on
// the clip, so it is on the clip's right-click and in Clip. No panel, no tool,
// no window: what lands is one group of ordinary layers, and everything about
// it is edited with the controls that already edit text and shapes.

/// The presets a person saved, shared by every window and kept in the app's
/// settings.
@MainActor @Observable
final class TitlePresetStore {
    static let shared = TitlePresetStore()

    private static let key = "experiments.next.titlePresets"

    private(set) var saved: [SavedTitlePreset] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let list = try? JSONDecoder().decode([SavedTitlePreset].self, from: data) {
            saved = list
        }
    }

    func presets(of kind: TitleKind) -> [SavedTitlePreset] {
        saved.filter { $0.kind == kind }
    }

    /// Keeps a preset, replacing one of the same kind and name so saving twice
    /// under one name updates it rather than listing it twice.
    func keep(_ preset: SavedTitlePreset) {
        saved.removeAll {
            $0.kind == preset.kind && $0.name.caseInsensitiveCompare(preset.name) == .orderedSame
        }
        saved.append(preset)
        write()
    }

    func forget(_ id: UUID) {
        saved.removeAll { $0.id == id }
        write()
    }

    /// Everything a walk saved, gone, so a walk leaves the person's list as
    /// it found it.
    func forgetAll() {
        saved = []
        write()
    }

    private func write() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

extension EditorState {

    // MARK: Reading

    /// Whether a preset can go on the timeline in this window right now.
    var canInsertTitle: Bool {
        Experiments.shared.titlePresetsEnabled && documentHasTime
    }

    /// The layer Save as Preset would keep: the picked one where it can be,
    /// else the clip the timeline's edits act on, the way Clip's fade rows
    /// choose (`pictureFadeLayerInHand`).
    var titlePresetLayerInHand: UUID? {
        guard Experiments.shared.titlePresetsEnabled, documentHasTime, let document else { return nil }
        return [selectedLayerID, clipInHandID].compactMap { $0 }
            .first { document.canSaveTitlePreset(layerID: $0) && !isClipLocked($0) }
    }

    // MARK: Inserting

    /// One kind's presets, the person's own first, as menu rows.
    func titlePresetRows(_ kind: TitleKind, onTrack trackID: UUID? = nil) -> [MenuRow] {
        let own = TitlePresetStore.shared.presets(of: kind).map { saved in
            MenuRow.command(saved.name) { self.insertTitle(saved: saved, onTrack: trackID) }
        }
        let builtIn = BuiltInTitle.presets(of: kind).map { preset in
            MenuRow.command(preset.name) { self.insertTitle(preset, onTrack: trackID) }
        }
        return own.isEmpty ? builtIn : own + [.separator] + builtIn
    }

    /// `Insert Title Page ▸`, `Insert Name Card ▸`, one per kind, for the menu
    /// bar; `Add Title Page ▸` and so on for a track's right-click, where the
    /// rows beside them already say Add.
    func titleInsertMenuRows(verb: String = "Insert", onTrack trackID: UUID? = nil) -> [MenuRow] {
        guard canInsertTitle else { return [] }
        return TitleKind.allCases.map { kind in
            .submenu("\(verb) \(kind.name)", titlePresetRows(kind, onTrack: trackID))
        }
    }

    func insertTitle(_ preset: BuiltInTitle, onTrack trackID: UUID? = nil) {
        landTitle(onTrack: trackID) { $0.insertTitle(preset, atTimeMS: $1) }
    }

    func insertTitle(saved: SavedTitlePreset, onTrack trackID: UUID? = nil) {
        landTitle(onTrack: trackID) { $0.insertTitle(saved, atTimeMS: $1) }
    }

    /// Puts it in at the playhead, picks it, moves the playhead on to where it
    /// has finished arriving (at its first frame a fade is invisible and a
    /// slide is off the picture), and opens its main line for typing.
    private func landTitle(onTrack trackID: UUID?,
                           _ insert: @escaping (inout PhotonzDocument, Int) -> InsertedTitle?) {
        guard canInsertTitle else { return }
        pauseDocument()
        let moment = documentTimeMS
        var inserted: InsertedTitle?
        if let trackID { landingTrack = (trackID, moment) }
        perform { inserted = insert(&$0, moment) }
        landingTrack = nil
        guard let inserted, let time = document?.layer(id: inserted.layerID)?.time else { return }
        selectLayer(inserted.layerID)
        switchToEditForAnEdit()
        moveDocumentPlayhead(toMS: min(time.inMS + TitleAnimation.lengthMS, time.outMS))
        // The caret waits for the picture to be drawn at that moment: the
        // canvas places its field on what it has drawn, and until then that
        // is the card at the start of its slide.
        typeInOnceShown = (inserted.wordsID, documentTimeMS)
        rerender()
    }

    // MARK: Saving your own

    /// `Save as Preset…` for a clip's right-click.
    func titlePresetSaveMenuRows(layerID: UUID) -> [MenuRow] {
        guard Experiments.shared.titlePresetsEnabled, documentHasTime, !isClipLocked(layerID),
              document?.canSaveTitlePreset(layerID: layerID) == true else { return [] }
        return [.command("Save as Preset…") { self.beginSavingTitlePreset(layerID) }]
    }

    func beginSavingTitlePreset(_ layerID: UUID? = nil) {
        guard let id = layerID ?? titlePresetLayerInHand,
              document?.canSaveTitlePreset(layerID: id) == true else { return }
        selectLayer(id)
        pauseDocument()
        titlePresetSaving = id
    }

    /// The kind a save would file it under before anybody chooses, read from
    /// how much of the frame it covers.
    var titlePresetSavingKind: TitleKind {
        guard let id = titlePresetSaving,
              let preset = document?.savedTitlePreset(layerID: id, name: "Preset") else { return .nameCard }
        return preset.kind
    }

    /// A name nobody has used yet for this kind: `My Name Card`, `My Name Card 2`.
    func titlePresetSuggestedName(for kind: TitleKind) -> String {
        let taken = Set(TitlePresetStore.shared.presets(of: kind).map { $0.name.lowercased() })
        let base = "My \(kind.name)"
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    /// Keeps the layer the sheet is about under this name and kind. False when
    /// there is nothing to keep, so the sheet stays up.
    @discardableResult
    func saveTitlePreset(name: String, kind: TitleKind) -> Bool {
        guard let id = titlePresetSaving,
              var preset = document?.savedTitlePreset(layerID: id, name: name) else { return false }
        preset.kind = kind
        TitlePresetStore.shared.keep(preset)
        titlePresetSaving = nil
        raiseCanvasNotice(.titlePresetSaved(name: preset.name))
        return true
    }
}
