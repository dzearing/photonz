import Foundation
import PhotonzCore

// An effect at each click of a recording (`ClickEffect.swift`): the Clicks row
// on the clip's Properties turns it on and picks its look, and each click is a
// tick on the clip's bar that can be hidden or slid to when it really happened.
// Every change is an ordinary edit, so Command Z takes it back.
extension EditorState {

    /// Whether this window offers click effects at all: Next, with time.
    var canWorkWithClickEffects: Bool { Experiments.shared.clickEffectsEnabled && documentHasTime }

    /// The recording clip the Clicks row speaks for: the one picked clip,
    /// when it plays a recording.
    var clickEffectClip: Layer? {
        guard canWorkWithClickEffects, let layer = keyLayer, layer.movie != nil, layer.time != nil else { return nil }
        return layer
    }

    /// The clip's effect as it stands, or how a new one starts.
    func clickEffect(ofClip id: UUID) -> ClickEffect {
        document?.layer(id: id)?.clickEffect ?? ClickEffect()
    }

    /// Every click on the clip as it shows them, hidden ones included.
    func clickMarks(ofClip id: UUID) -> [ClickMark] {
        guard let layer = document?.layer(id: id) else { return [] }
        return layer.clickMarks(recorded: recordedPointerTrack(ofClip: id)?.clicks)
    }

    /// Whether the clip has a click an effect could be drawn at.
    func hasClicksToShow(onClip id: UUID) -> Bool {
        guard let layer = document?.layer(id: id) else { return false }
        return layer.hasClicksToShow(recorded: recordedPointerTrack(ofClip: id)?.clicks)
    }

    /// Change the clip's effect: one edit, keeping the recorded clicks in the
    /// document the first time it is turned on.
    func changeClickEffect(onClip id: UUID, _ change: @escaping (inout ClickEffect) -> Void) {
        guard !isClipLocked(id) else { return }
        let recorded = recordedPointerTrack(ofClip: id)?.clicks
        perform { $0.setClickEffect(onClip: id, recorded: recorded, change) }
    }

    func setClickEffectOn(_ on: Bool, onClip id: UUID) {
        guard !on || hasClicksToShow(onClip: id) else { return }
        changeClickEffect(onClip: id) { $0.isOn = on }
    }

    /// Hide a click, or show it again.
    func setClickHidden(_ hidden: Bool, clickID: UUID, onClip id: UUID) {
        guard !isClipLocked(id) else { return }
        perform { $0.setClickHidden(onClip: id, clickID: clickID, hidden) }
    }

    /// Slide a click to a moment of the document, on the clip.
    func moveClick(_ clickID: UUID, onClip id: UUID, toTimelineMS ms: Int) {
        guard !isClipLocked(id), let layer = document?.layer(id: id), let time = layer.time else { return }
        let onClip = min(max(ms, time.inMS), time.outMS - 1)
        guard let source = layer.sourceMS(ofClickAtTimelineMS: onClip) else { return }
        perform { $0.moveClick(onClip: id, clickID: clickID, toSourceMS: source) }
    }

    /// Where each click lands on the document's timeline, for the ticks on
    /// the clip's bar. A click the clip does not play is not ticked.
    func clickTicks(ofClip id: UUID) -> [(mark: ClickMark, ms: Int)] {
        guard let layer = document?.layer(id: id) else { return [] }
        return clickMarks(ofClip: id).compactMap { mark in
            layer.timelineMS(ofClickAtSourceMS: mark.click.downMS).map { (mark, $0) }
        }
    }

    /// What a tick's right-click offers.
    func clickTickMenuRows(clickID: UUID, onClip id: UUID) -> [MenuRow] {
        let hidden = clickMarks(ofClip: id).first { $0.id == clickID }?.isHidden ?? false
        let locked = isClipLocked(id)
        var rows: [MenuRow] = [
            .command(hidden ? "Show This Click" : "Hide This Click", enabled: !locked) {
                self.setClickHidden(!hidden, clickID: clickID, onClip: id)
            },
        ]
        if let ms = clickTicks(ofClip: id).first(where: { $0.mark.id == clickID })?.ms {
            rows.append(.command("Move Playhead to Click") { self.moveDocumentPlayhead(toMS: ms) })
        }
        return rows
    }

    /// Why the Clicks row cannot be turned on, for its tooltip, or nil when it can.
    func clickEffectUnavailableReason(onClip id: UUID) -> String? {
        if hasClicksToShow(onClip: id) { return nil }
        return "This recording kept no clicks. Add one with Add Click at Playhead."
    }

    // MARK: From the menu bar

    /// The recording the Clip menu's click rows act on: the clip in hand when
    /// it has clicks, else the topmost recording under the playhead that does.
    var clipForClickMenu: UUID? {
        guard canWorkWithClickEffects, let document else { return nil }
        if let clip = clipInHandID ?? selectedLayerID, !clickTicks(ofClip: clip).isEmpty { return clip }
        return document.allLayers.last { layer in
            layer.movie != nil && (layer.time?.contains(ms: documentTimeMS) ?? false)
                && !clickTicks(ofClip: layer.id).isEmpty
        }?.id
    }

    /// The click whose effect is playing at the playhead, or whose tick the
    /// playhead is on.
    var clickAtPlayhead: (clip: UUID, mark: ClickMark)? {
        guard let clip = clipForClickMenu else { return nil }
        let now = documentTimeMS
        let tick = clickTicks(ofClip: clip).last { $0.ms <= now + 20 && now < $0.ms + ClickEffect.lengthMS }
        return tick.map { (clip, $0.mark) }
    }

    /// The first click after the playhead on that recording, on the timeline.
    var nextClickMS: Int? {
        guard let clip = clipForClickMenu else { return nil }
        return clickTicks(ofClip: clip).map(\.ms).filter { $0 > documentTimeMS + 20 }.min()
    }
}
