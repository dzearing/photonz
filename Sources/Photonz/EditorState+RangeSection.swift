import Foundation
import PhotonzCore

// A range held with things picked (`RangeSection.swift`).
//
// A range drawn on the ruler, or across some tracks, stays in hand when a
// clip, a sound, a title or a zoom is clicked: it stays drawn over the clips,
// and the click picks the thing as well, the way Premiere keeps its In and Out
// while clips are selected (the user, 2026-10-12). The two are then one
// question: what to do to the picked things over that stretch. A right click
// on a picked clip, on the stretch on the ruler, or on a lane under the range
// leads with the rows `SectionOperation` offers for what is picked; ⌫ and ⇧⌫
// take the picked clips' part of the range; Escape lets the range go first and
// the pick after.
//
// With nothing picked a range is what it always was, and acts on every track it
// covers (`EditorState+RulerRange`, `EditorState+TrackRange`).

extension EditorState {

    /// The range in hand, whichever kind, whether or not anything is picked as
    /// well: its stretch, and the tracks it covers (nil for every track).
    struct RangeKept: Equatable {
        let range: Range<Int>
        let trackIDs: Set<UUID>?
    }

    var rangeKept: RangeKept? {
        guard documentHasTime, let document else { return nil }
        if let range = rulerRangeInHand, document.markedRangeMS == range {
            return RangeKept(range: range, trackIDs: nil)
        }
        if let held = trackRangeInHand { return RangeKept(range: held.range, trackIDs: held.trackIDs) }
        return nil
    }

    /// The range drawn on the ruler while it is in hand, picks or no picks:
    /// what the wash down the tracks shows.
    var rulerRangeKept: Range<Int>? {
        guard let kept = rangeKept, kept.trackIDs == nil else { return nil }
        return kept.range
    }

    /// The range on some tracks while it is in hand, picks or no picks.
    var trackRangeKept: TrackRange? {
        guard let kept = rangeKept, let tracks = kept.trackIDs else { return nil }
        return TrackRange(range: kept.range, trackIDs: tracks)
    }

    /// A range in hand and the picked things it acts on: the clips and layers
    /// picked that run through it (on its own tracks, for a range on some
    /// tracks), and what kinds of thing they are. Nil with nothing picked, or
    /// nothing picked inside the range.
    struct RangeSectionInHand: Equatable {
        let range: Range<Int>
        let ids: [UUID]
        let kinds: Set<SectionKind>
    }

    var rangeSection: RangeSectionInHand? {
        guard let kept = rangeKept, let document, selectedEditPoint == nil,
              timelinePicksHeld == nil, !actionableLayerIDs.isEmpty else { return nil }
        let onTracks = kept.trackIDs.map { document.layerIDs(onTracks: $0) }
        var ids: [UUID] = []
        var kinds = Set<SectionKind>()
        for id in actionableLayerIDs.sorted(by: { $0.uuidString < $1.uuidString })
        where onTracks?.contains(id) ?? true {
            let these = document.sectionKinds(of: id, within: kept.range)
            guard !these.isEmpty else { continue }
            ids.append(id)
            kinds.formUnion(these)
        }
        guard !ids.isEmpty else { return nil }
        return RangeSectionInHand(range: kept.range, ids: ids, kinds: kinds)
    }

    /// Whether ⌫ and ⇧⌫ take the picked clips' part of the range rather than
    /// the clips: a range is in hand with a clip or sound picked inside it,
    /// and nothing smaller (a zoom, keys, a cut) was picked on top.
    var sectionTakesTheDelete: Bool {
        guard selectedZoom == nil, !canDeletePickedKeys, selectedClipCutIndex == nil,
              let section = rangeSection else { return false }
        return !section.kinds.isDisjoint(with: [.sound, .picture])
    }

    /// Escape: a range in hand goes before whatever is picked under it.
    /// False where there is no range to let go of.
    @discardableResult
    func letGoOfRangeKept() -> Bool {
        if trackRangeInHand != nil {
            trackRangeInHand = nil
            return true
        }
        guard rulerRangeKept != nil else { return false }
        clearMarkInOut()
        return true
    }

    // MARK: Doing them

    /// One section operation as one step to undo, tried on a copy first so a
    /// row that changes nothing writes nothing.
    @discardableResult
    private func editSection(sound: Bool = false,
                             _ edit: @escaping (inout PhotonzDocument, [UUID], Range<Int>) -> Bool) -> Bool {
        guard let section = rangeSection, var trial = document,
              edit(&trial, section.ids, section.range) else { return false }
        endTrimBeforeCutting()
        pauseDocument()
        perform { _ = edit(&$0, section.ids, section.range) }
        selectedClipPieceIndex = nil
        if documentTimeMS > lastDocumentTimeMS { documentTimeMS = lastDocumentTimeMS }
        if sound { followAudio() }
        documentMomentChanged()
        return true
    }

    /// Whether a section operation would change anything now.
    private func canEditSection(_ edit: (inout PhotonzDocument, [UUID], Range<Int>) -> Bool) -> Bool {
        guard let section = rangeSection, var trial = document else { return false }
        return edit(&trial, section.ids, section.range)
    }

    func muteRangeSection() {
        editSection(sound: true) { $0.changeSoundSection($1, within: $2, .set(0)) }
    }

    /// The picked sounds this many decibels quieter over the range.
    func lowerRangeSection(byDB dB: Double) {
        let scale = AudioLevel.gain(forDecibels: -abs(dB))
        editSection(sound: true) { $0.changeSoundSection($1, within: $2, .scaled(scale)) }
    }

    /// The decibel steps Lower Volume offers.
    static let sectionLowerStepsDB: [Double] = [3, 6, 12, 20]

    /// Normalize Section: each picked sound's loudest peak inside the range
    /// brought to -1 dBFS, as a level over just that stretch. The level line
    /// tops out at +6 dB, so a section quieter than that is brought up as far
    /// as the line goes.
    func normalizeRangeSection() async {
        guard let section = rangeSection, let document else { return }
        var gains: [UUID: Double] = [:]
        for id in section.ids where document.sectionKinds(of: id, within: section.range).contains(.sound) {
            guard let layer = document.layer(id: id), let played = layer.playedSound,
                  let wave = await measuredShape(of: played) else { continue }
            let loudest = document.soundSourceRanges(of: id, within: section.range)
                .map { wave.peak(fromSourceMS: $0.lowerBound, toSourceMS: $0.upperBound) }.max() ?? 0
            guard loudest > 0 else { continue }
            let peak = 20 * log10(Double(loudest)) + (layer.soundLevel?.clipGainDB ?? 0)
            gains[id] = AudioLevel.gain(forDecibels: AudioNormalize.peakTargetDBFS - peak)
        }
        guard !gains.isEmpty, rangeSection == section else { return }
        editSection(sound: true) { doc, _, range in
            var changed = false
            for (id, gain) in gains where doc.changeSoundSection([id], within: range, .set(gain)) { changed = true }
            return changed
        }
    }

    /// Clean Noise in Section: each picked sound's stretch inside the range
    /// plays a copy with its noise taken out, and the copy starts being made
    /// at once, the way Clean Noise on a whole sound starts it.
    func cleanNoiseRangeSection() {
        guard let ids = rangeSection?.ids,
              editSection(sound: true, { $0.cleanNoiseSection($1, within: $2) }) else { return }
        for id in ids {
            for ref in document?.layer(id: id)?.sectionCleanedSoundRefs ?? [] {
                SoundLibrary.shared.clean(ref, waitingFirst: false)
            }
        }
    }

    /// Hide Picture for Section: each picked recording drawn as nothing inside
    /// the range, its sound playing on.
    func hidePictureRangeSection() {
        editSection { $0.hidePictureSection($1, within: $2) }
    }

    func splitRangeSection() {
        editSection { $0.splitSection($1, within: $2) > 0 }
    }

    /// ⌫ with a range and a clip picked inside it: the clip's part of the
    /// range goes and leaves its gap. False where that is not what is in hand.
    @discardableResult
    func deleteRangeSection() -> Bool {
        guard sectionTakesTheDelete else { return false }
        editSection(sound: true) { $0.liftSection($1, within: $2) }
        return true
    }

    /// ⇧⌫: the same, and the gap closes on the clip's own track.
    @discardableResult
    func rippleDeleteRangeSection() -> Bool {
        guard sectionTakesTheDelete else { return false }
        editSection(sound: true) { $0.rippleDeleteSection($1, within: $2) }
        return true
    }

    func setRangeSectionSpeed(_ percent: Int) {
        editSection(sound: true) { $0.setSectionSpeed($1, within: $2, percent: percent) }
    }

    func freezeRangeSection() {
        editSection(sound: true) { $0.freezeSection($1, within: $2) }
    }

    func addZoomOverRangeSection() {
        var made: [UUID: UUID] = [:]
        guard editSection({ doc, ids, range in
            made = doc.addZoomOverSection(ids, within: range)
            return !made.isEmpty
        }) else { return }
        // The zoom just made is picked, so the panel shows it, as Add Zoom does.
        if made.count == 1, let (clip, zoom) = made.first { pickZoom(ClipZoomRef(layerID: clip, zoomID: zoom)) }
    }

    func trimRangeSection() {
        editSection { $0.trimToSection($1, within: $2) }
    }

    func deleteKeysInRangeSection() {
        guard editSection({ $0.deleteKeysInSection($1, within: $2) }) else { return }
        clearKeySelection()
    }

    // MARK: The rows

    /// One row of the table, as a menu row: a command, or a submenu for the
    /// two that take an amount. `keys` prints the shortcut where the row has
    /// one; nil where the row is a menu bar copy of a key printed elsewhere.
    private func sectionRow(_ operation: SectionOperation, enabled: Bool, keys: Bool) -> MenuRow {
        switch operation {
        case .muteSection:
            return .command(operation.title, enabled: enabled) { self.muteRangeSection() }
        case .lowerVolume:
            return .submenu(operation.title, Self.sectionLowerStepsDB.map { dB in
                .command(String(format: "-%.0f dB", dB), enabled: enabled) { self.lowerRangeSection(byDB: dB) }
            })
        case .normalizeSection:
            return .command(operation.title, enabled: enabled) { Task { await self.normalizeRangeSection() } }
        case .cleanNoiseInSection:
            return .command(operation.title, enabled: enabled) { self.cleanNoiseRangeSection() }
        case .hidePictureForSection:
            return .command(operation.title, enabled: enabled) { self.hidePictureRangeSection() }
        case .splitAtRangeEdges:
            return .command(operation.title, enabled: enabled) { self.splitRangeSection() }
        case .deleteSection:
            return .command(operation.title, keys ? TimelineMenuKeys.delete : nil, enabled: enabled) {
                self.deleteRangeSection()
            }
        case .rippleDeleteSection:
            return .command(operation.title, keys ? TimelineMenuKeys.rippleDelete : nil, enabled: enabled) {
                self.rippleDeleteRangeSection()
            }
        case .speedForSection:
            return .submenu(operation.title, ClipSpeed.stops.filter { $0 != ClipPiece.asRecordedPercent }.map { percent in
                .command(ClipSpeed.menuTitle(percent), enabled: enabled) { self.setRangeSectionSpeed(percent) }
            })
        case .freezeFrameForSection:
            return .command(operation.title, enabled: enabled) { self.freezeRangeSection() }
        case .addZoomOverRange:
            return .command(operation.title, enabled: enabled) { self.addZoomOverRangeSection() }
        case .trimToRange:
            return .command(operation.title, enabled: enabled) { self.trimRangeSection() }
        case .deleteKeysInRange:
            return .command(operation.title, enabled: enabled) { self.deleteKeysInRangeSection() }
        }
    }

    /// Whether a row would do anything to what is picked now.
    private func canDo(_ operation: SectionOperation) -> Bool {
        switch operation {
        case .muteSection: canEditSection { $0.changeSoundSection($1, within: $2, .set(0)) }
        case .lowerVolume, .normalizeSection: rangeSection?.kinds.contains(.sound) == true
        case .cleanNoiseInSection: canEditSection { $0.cleanNoiseSection($1, within: $2) }
        case .hidePictureForSection: canEditSection { $0.hidePictureSection($1, within: $2) }
        case .splitAtRangeEdges: canEditSection { $0.splitSection($1, within: $2) > 0 }
        case .deleteSection, .rippleDeleteSection: sectionTakesTheDelete
        case .speedForSection: rangeSection?.kinds.contains(.picture) == true
        case .freezeFrameForSection: canEditSection { $0.freezeSection($1, within: $2) }
        case .addZoomOverRange: canEditSection { !$0.addZoomOverSection($1, within: $2).isEmpty }
        case .trimToRange: canEditSection { $0.trimToSection($1, within: $2) }
        case .deleteKeysInRange: rangeSection?.kinds.contains(.keys) == true
        }
    }

    /// The rows a right click inside the range leads with when things are
    /// picked in it: what the table offers for their kinds, in its blocks,
    /// and Clear Range. Empty when there is no such pick.
    func rangeSectionMenuRows() -> [MenuRow] {
        guard let section = rangeSection else { return [] }
        var rows: [MenuRow] = []
        var block: Int?
        for operation in SectionOperation.offered(for: section.kinds) {
            if let block, block != operation.block { rows.append(.separator) }
            block = operation.block
            rows.append(sectionRow(operation, enabled: canDo(operation), keys: true))
        }
        rows.append(.separator)
        rows.append(.command("Clear Range", rulerRangeKept != nil ? TimelineMenuKeys.clearInOut : nil) {
            self.letGoOfRangeKept()
        })
        return rows
    }

    /// Sequence ▸ Section in the menu bar: every row the table can do, each
    /// lit only when a range and a pick it applies to are in hand. ⌫ and ⇧⌫
    /// are on Edit's Delete and Ripple Delete, which say Section then, so they
    /// are not printed twice.
    func rangeSectionMenuBarRows() -> [MenuRow] {
        let offered = Set(rangeSection.map { SectionOperation.offered(for: $0.kinds) } ?? [])
        var rows: [MenuRow] = []
        var block: Int?
        for operation in SectionOperation.allCases where operation.isAvailable
            && operation != .deleteSection && operation != .rippleDeleteSection {
            if let block, block != operation.block { rows.append(.separator) }
            block = operation.block
            rows.append(sectionRow(operation, enabled: offered.contains(operation) && canDo(operation), keys: false))
        }
        return rows
    }
}
