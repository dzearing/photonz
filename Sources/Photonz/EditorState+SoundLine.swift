import AppKit
import Foundation
import PhotonzCore

/// What is picked on a sound's volume line: its level points and the
/// segments between them, each named by the moment (from the layer's own
/// start) of the point it starts at.
struct SoundLinePick: Equatable {
    var layerID: UUID
    var pick: AnimatedLinePick<Int>

    init?(layerID: UUID, _ pick: AnimatedLinePick<Int>) {
        guard !pick.isEmpty else { return nil }
        self.layerID = layerID
        self.pick = pick
    }
}

/// A sound's volume line follows the rule every animated line on the timeline
/// follows (`AnimatedLine`, UX-PATTERNS D21; task
/// `an-audio-clip-answers-right-click-and-its-volume`): a click picks a level
/// point or the segment between two, ⌘-click on the line adds a point, Shift
/// adds to the pick, ⌫ deletes the picked points, and a segment's right click
/// offers the shared curve list. A thin layer over `AudioLevelSegments.swift`:
/// every change goes through `perform`, so each costs one undo step.
extension EditorState {

    // MARK: Picking

    func soundLinePick(layerID: UUID) -> AnimatedLinePick<Int> {
        guard let soundLinePick, soundLinePick.layerID == layerID else { return AnimatedLinePick() }
        return soundLinePick.pick
    }

    /// Where a moment of a sound layer's own clock is on the document's.
    private func documentMS(layerID: UUID, atLayerMS ms: Int) -> Int? {
        document?.layer(id: layerID)?.time.map { $0.inMS + ms }
    }

    /// The layer picked first, then the line's pick, so picking the layer
    /// (which lets go of whatever was picked on another) never undoes it.
    private func holdSoundLine(layerID: UUID, _ change: (inout AnimatedLinePick<Int>) -> Void) {
        if selectedLayerID != layerID { selectLayer(layerID) }
        if keySelection != nil { keySelection = nil }
        var pick = soundLinePick(layerID: layerID)
        change(&pick)
        soundLinePick = SoundLinePick(layerID: layerID, pick)
    }

    /// A click on a level point: it alone is picked, or with Shift it joins
    /// the pick or leaves it. A plain click puts the playhead on it.
    func pickSoundPoint(layerID: UUID, atLayerMS ms: Int, extending: Bool, movingPlayhead: Bool = true) {
        holdSoundLine(layerID: layerID) { $0.pick(dot: ms, extending: extending) }
        guard !extending, movingPlayhead, let at = documentMS(layerID: layerID, atLayerMS: ms) else { return }
        playheadToTimelineClick(atMS: at)
    }

    /// A click on a segment, the same way; the playhead goes where it landed.
    func pickSoundSegment(layerID: UUID, startMS: Int, atLayerMS ms: Int, extending: Bool,
                          movingPlayhead: Bool = true) {
        holdSoundLine(layerID: layerID) { $0.pick(segment: startMS, extending: extending) }
        guard !extending, movingPlayhead, let at = documentMS(layerID: layerID, atLayerMS: ms) else { return }
        playheadToTimelineClick(atMS: at)
    }

    func clearSoundLinePick() {
        if soundLinePick != nil { soundLinePick = nil }
    }

    // MARK: Changing the line

    private func changeSoundLine(layerID: UUID, _ change: (inout AudioLevel) -> Bool) {
        guard let layer = document?.layer(id: layerID), layer.sound != nil, !isClipLocked(layerID) else { return }
        var level = layer.soundLevel ?? AudioLevel()
        guard change(&level), level != layer.soundLevel else { return }
        perform { document in
            document.updateLayer(id: layerID) { $0.setSoundLevel(level) }
        }
        followAudio()
    }

    /// ⌘-click on the line, or Add Point Here: a point holding the level the
    /// line has there, so nothing you hear changes. It is what is picked
    /// afterwards. One undo step.
    func addSoundPointOnLine(layerID: UUID, atLayerMS ms: Int) {
        var added = false
        changeSoundLine(layerID: layerID) { level in
            added = level.addPointOnLine(atMS: ms)
            return added
        }
        guard added else { return }
        holdSoundLine(layerID: layerID) { $0 = AnimatedLinePick(dots: [max(0, ms)]) }
    }

    /// A point let go of after a drag: carried in time and level, keeping its
    /// segment's curve, as one undo step. It stays picked.
    func moveSoundPoint(layerID: UUID, fromMS: Int, to point: AudioLevelPoint) {
        changeSoundLine(layerID: layerID) { level in
            level.movePoint(fromMS: fromMS, toMS: point.atMS, gain: point.gain)
            return true
        }
        holdSoundLine(layerID: layerID) { $0 = AnimatedLinePick(dots: [point.atMS]) }
    }

    /// The picked segments, or the one right clicked where it is not among
    /// them.
    private func soundSegmentsInHand(layerID: UUID, _ startMS: Int) -> Set<Int> {
        let picked = soundLinePick(layerID: layerID).segments
        return picked.contains(startMS) ? picked : [startMS]
    }

    func curveSoundSegments(layerID: UUID, _ starts: Set<Int>, _ curve: EasingCurve) {
        changeSoundLine(layerID: layerID) { $0.setSegmentsCurve(curve, startingAt: starts) }
    }

    /// A picked segment's bend handle let go: the segment's middle lands
    /// `middle` of the way from its first level to its second.
    func bendSoundSegment(layerID: UUID, startMS: Int, middle: Double) {
        curveSoundSegments(layerID: layerID, [startMS], AudioLevel.bentCurve(middle: middle))
    }

    /// The curve every picked segment on a sound shares, for Draw a Curve.
    func pickedSoundSegmentsCurve(layerID: UUID) -> EasingCurve? {
        let starts = soundLinePick(layerID: layerID).segments
        guard !starts.isEmpty else { return nil }
        return document?.layer(id: layerID)?.soundLevel?.segmentsCurve(starts)
    }

    /// A curve drawn for the segments a sound's Draw a Curve was chosen for.
    func finishDrawingSoundCurve(_ curve: EasingCurve?) {
        guard let drawing = drawingSoundCurve else { return }
        drawingSoundCurve = nil
        guard let curve else { return }
        curveSoundSegments(layerID: drawing.layerID, drawing.pick.segments, curve)
    }

    // MARK: Deleting

    /// Whether ⌫ means the volume line: a point or a segment is picked on the
    /// sound in hand. A segment alone deletes nothing, and never reaches past
    /// it to the clip.
    var canDeletePickedSoundPoints: Bool {
        guard documentHasTime, let soundLinePick, selectedLayerID == soundLinePick.layerID,
              !isClipLocked(soundLinePick.layerID) else { return false }
        return true
    }

    /// ⌫ with points picked on a volume line: they go, in one undo step.
    @discardableResult
    func deletePickedSoundPoints() -> Bool {
        guard canDeletePickedSoundPoints, let held = soundLinePick else { return false }
        guard !held.pick.dots.isEmpty else { return true }
        soundLinePick = SoundLinePick(layerID: held.layerID, AnimatedLinePick(segments: held.pick.segments))
        changeSoundLine(layerID: held.layerID) { level in
            level.removePoints(held.pick.dots)
            return true
        }
        if let segments = soundLinePick?.pick.segments, let level = document?.layer(id: held.layerID)?.soundLevel {
            let starts = Set(level.points.dropLast().map(\.atMS))
            soundLinePick = SoundLinePick(layerID: held.layerID, AnimatedLinePick(segments: segments.intersection(starts)))
        }
        return true
    }

    // MARK: Right click

    /// What a right click picks waits for the menu to be built, and for the
    /// clip menu built beside it to pick the clip first, so the clip's pick
    /// never lets go of the point or segment (`EditorState+TimelinePointing`).
    private func afterTheMenuIsBuilt(_ run: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { DispatchQueue.main.async { MainActor.assumeIsolated { run() } } }
    }

    /// The segments a menu row acts on, worked out as the row RUNS. SwiftUI
    /// keeps a context menu's row actions from an earlier build of the same
    /// menu while it shows the new titles (measured 2026-10-13: Hold chosen on
    /// a second segment ran the first right click's row), so a row never
    /// carries what it is about; by the time anyone chooses, the right click
    /// has picked it.
    private func soundSegmentsForMenu(layerID: UUID) -> Set<Int> {
        soundLinePick(layerID: layerID).segments
    }

    /// The moment, along the layer, of the right click that opened the menu.
    private func soundMenuMS(layerID: UUID) -> Int? {
        guard let ms = timelineLastRightPressMS, let inMS = document?.layer(id: layerID)?.time?.inMS else { return nil }
        return ms - inMS
    }

    /// A right click on a segment: the shared curve list (D21), then Add
    /// Point Here and Delete for the points picked with it. The segment is
    /// picked unless it already is; the playhead stays where it was parked.
    func soundSegmentMenuRows(layerID: UUID, startMS: Int, atLayerMS ms: Int) -> [MenuRow] {
        guard let level = document?.layer(id: layerID)?.soundLevel, !isClipLocked(layerID) else { return [] }
        if servesThisRightPress(), !soundLinePick(layerID: layerID).segments.contains(startMS) {
            afterTheMenuIsBuilt { [weak self] in
                self?.pickSoundSegment(layerID: layerID, startMS: startMS, atLayerMS: ms,
                                       extending: false, movingPlayhead: false)
            }
        }
        let starts = soundSegmentsInHand(layerID: layerID, startMS)
        var rows = segmentCurveRows(current: level.segmentsCurve(starts)) { curve in
            self.curveSoundSegments(layerID: layerID, self.soundSegmentsForMenu(layerID: layerID), curve)
        } draw: {
            self.drawingSoundCurve = SoundLinePick(layerID: layerID,
                                                   AnimatedLinePick(segments: self.soundSegmentsForMenu(layerID: layerID)))
        }
        rows.append(.separator)
        rows.append(.command("Add Point Here") {
            guard let at = self.soundMenuMS(layerID: layerID) else { return }
            self.addSoundPointOnLine(layerID: layerID, atLayerMS: at)
        })
        // The points picked WITH this segment: none, when the right click is
        // about to pick it alone.
        let pick = soundLinePick(layerID: layerID)
        let points = pick.segments.contains(startMS) ? pick.dots : []
        rows.append(.command(points.count > 1 ? "Delete \(points.count) Points" : "Delete Point",
                             enabled: !points.isEmpty, destructive: true) {
            self.deletePickedSoundPoints()
        })
        return rows
    }

    /// A right click on a level point: Delete, for it or every point picked
    /// with it. It is picked unless it already is.
    func soundPointMenuRows(layerID: UUID, atLayerMS ms: Int) -> [MenuRow] {
        guard document?.layer(id: layerID)?.soundLevel != nil, !isClipLocked(layerID) else { return [] }
        let picked = soundLinePick(layerID: layerID).dots
        let inHand = picked.contains(ms) ? picked : [ms]
        if servesThisRightPress(), !picked.contains(ms) {
            afterTheMenuIsBuilt { [weak self] in
                self?.pickSoundPoint(layerID: layerID, atLayerMS: ms, extending: false, movingPlayhead: false)
            }
        }
        // The points it deletes are the ones picked when it runs (see
        // `soundSegmentsForMenu`), which the right click has made this one.
        return [.command(inHand.count > 1 ? "Delete \(inHand.count) Points" : "Delete Point", destructive: true) {
            self.deletePickedSoundPoints()
        }]
    }
}
