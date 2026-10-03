import CoreGraphics
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

    func insertTitle(_ preset: TitlePreset, onTrack trackID: UUID? = nil) {
        switch preset {
        case .builtIn(let builtIn): insertTitle(builtIn, onTrack: trackID)
        case .saved(let saved): insertTitle(saved: saved, onTrack: trackID)
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
    private func landTitle(onTrack trackID: UUID?, atMS ms: Int? = nil,
                           _ insert: @escaping (inout PhotonzDocument, Int) -> InsertedTitle?) {
        guard canInsertTitle else { return }
        pauseDocument()
        let moment = ms ?? documentTimeMS
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

    // MARK: On the Library shelf

    /// Every preset as a Library tile, in a document that can take one:
    /// title pages then name cards, your own first in each
    /// (`TitlePresetShelf.swift`).
    var titleShelf: [TitlePreset] {
        guard canInsertTitle else { return [] }
        return TitlePreset.shelf(saved: TitlePresetStore.shared.saved)
    }

    /// The preset behind a shelf id, nil for any other kind of tile.
    func titlePreset(entryID: String) -> TitlePreset? {
        guard canInsertTitle else { return nil }
        return TitlePreset(entryID: entryID, saved: TitlePresetStore.shared.saved)
    }

    /// The preset behind the picked Library tile.
    var selectedTitlePreset: TitlePreset? {
        selectedLibraryItemID.flatMap { titlePreset(entryID: $0) }
    }

    /// One of your own off the shelf and out of the menus, from its tile's
    /// right-click. Nothing already on a timeline changes: what landed was a
    /// copy.
    func forgetTitlePreset(_ id: UUID) {
        if selectedLibraryItemID == TitlePreset.id(ofSaved: id) { selectedLibraryItemID = nil }
        TitlePresetStore.shared.forget(id)
    }

    /// The picture on a preset's tile, `pixelsWide` across: the preset at
    /// rest on this document's frame (`TitlePreset.preview`). Drawn once off
    /// the main thread and kept; nil until it has been.
    func titlePresetPicture(_ preset: TitlePreset, pixelsWide: CGFloat) -> CGImage? {
        guard let frame = document?.canvasSize, frame.width > 0, frame.height > 0 else { return nil }
        let width = max(1, pixelsWide.rounded())
        let own = if case .saved(let saved) = preset { saved.hashValue } else { 0 }
        let key = "\(preset.id)|\(Int(frame.width))x\(Int(frame.height))|\(Int(width))|\(own)"
        if let picture = titlePresetPictures[key] { return picture }
        guard !titlePresetPicturesInFlight.contains(key) else { return nil }
        titlePresetPicturesInFlight.insert(key)
        let renderer = previewRenderer
        let store = store
        Task { @MainActor [weak self] in
            let image = await Task.detached(priority: .utility) {
                preset.preview(frame: frame, width: width).flatMap { renderer.render($0, store: store) }
            }.value
            guard let self else { return }
            self.titlePresetPicturesInFlight.remove(key)
            if let image { self.titlePresetPictures[key] = image }
        }
        return nil
    }

    // MARK: Let go over the timeline

    /// Where a title tile let go at `point` (the tracks' own space) would
    /// land: the moment under the pointer, pulled onto a nearby clip edge or
    /// the playhead, on the track under it when that track is free, else on a
    /// new track of its own (`PhotonzDocument.titleLanding`).
    func titleLanding(_ preset: TitlePreset, at point: CGPoint) -> ClipLanding? {
        guard canInsertTitle, let document, timelineLaneWidth > 0 else { return nil }
        let ruler = motionStripRuler
        let fraction = min(max(0, (point.x - TimelineDock.lanesLeading) / timelineLaneWidth), 1)
        let raw = Int(ruler.ms(atFraction: Double(fraction)).rounded())
        let reach = Int(ruler.msSpanning(fraction: Double(Self.timelineDropSnapPoints / timelineLaneWidth))
            .rounded())
        let start = ClipLanding.snapped(startMS: raw, lengthMS: preset.lengthMS,
                                        to: document.timelineEdgesMS + [documentTimeMS],
                                        withinMS: isTimelineSnapping ? max(0, reach) : 0)
        return document.titleLanding(lengthMS: preset.lengthMS, atMS: start, over: trackDrop(atY: point.y))
    }

    /// A title tile has arrived over the timeline, or moved across it: the
    /// ghost a file draws, saying the preset's kind, its track and its time.
    func moveTitleHover(_ preset: TitlePreset, to point: CGPoint) {
        timelineTitleInAir = preset
        // Room past the end for it, so one let go after the last clip has a
        // lane to be drawn on.
        if timelineDropRoomMS != preset.lengthMS { timelineDropRoomMS = preset.lengthMS }
        guard let landing = titleLanding(preset, at: point) else {
            if timelineFileHover != nil { timelineFileHover = nil }
            return
        }
        let next = TimelineFileHover(name: preset.name, landing: landing, verb: preset.kind.name)
        if timelineFileHover != next { timelineFileHover = next }
    }

    /// The tile has left the timeline without landing.
    func endTitleHover() {
        timelineTitleInAir = nil
        titleTileLifted = nil
        endTimelineFileHover()
    }

    /// Let go over the timeline: the preset lands where the ghost said, as
    /// one step to undo, picked with its words open, the way an insert lands.
    @discardableResult
    func dropTitle(_ preset: TitlePreset, at point: CGPoint) -> Bool {
        // Read before the room made for it goes, since taking the room away
        // moves the lane under the pointer.
        let landing = titleLanding(preset, at: point)
        endTitleHover()
        guard let landing, landing.allowed else { return false }
        landTitle(onTrack: nil, atMS: landing.startMS) { $0.insertTitle(preset, atTimeMS: $1, landing: landing) }
        return true
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
