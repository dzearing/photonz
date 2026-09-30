import Foundation
import PhotonzCore

// What the menu bar's rows act on.
//
// A right-click acts on the thing under the pointer. The menu bar has no
// pointer, so every one of its rows acts on the thing IN HAND: the one picked,
// else the one the playhead is standing on, the rule the Clip menu already
// keeps for a clip (`clipInHandID`). These are the same readings for a track, a
// marker, a caption word, a key lane and a stretch of a path, so a command that
// was only a right-click away is also a row of the menu bar
// (`EveryCommandIsInTheMenuBarTests`, UX-PATTERNS.md's menu bar row).
extension EditorState {

    // MARK: A track

    /// The track in hand: the one picked on its header, else the track of the
    /// clip in hand, else the first track.
    var trackInHandID: UUID? {
        guard let document, documentHasTime else { return nil }
        let tracks = document.timelineTracks
        if let picked = tracks.first(where: { selectedTrackIDs.contains($0.id) }) { return picked.id }
        if let clip = clipInHandID, let track = document.trackID(ofClip: clip) { return track }
        return tracks.first?.id
    }

    var trackInHand: DocumentTrack? {
        trackInHandID.flatMap { document?.track(id: $0) }
    }

    /// Where the track in hand sits, top first, for Add Track Above and Below.
    var trackInHandIndex: Int? {
        guard let id = trackInHandID else { return nil }
        return document?.timelineTracks.firstIndex { $0.id == id }
    }

    /// Sequence ▸ Track ▸ Rename Track…: picks the track and opens its name,
    /// the way the header's own Rename… does.
    func renameTrackInHand() {
        guard let id = trackInHandID else { return }
        if !isMotionStripOpen { pressTimelineToggle() }
        beginRenamingTrack(id)
    }

    // MARK: A marker

    /// A frame at thirty frames a second: how near the playhead a marker has to
    /// be to count as the one it is standing on.
    static let markerReachMS = 34

    /// The marker the playhead is standing on.
    var markerAtPlayhead: UUID? {
        document?.marker(nearMS: documentTimeMS, withinMS: Self.markerReachMS)
    }

    // MARK: A caption word

    /// The word being said at the playhead.
    var captionWordInHand: CaptionWordRef? {
        guard Experiments.shared.captionsFromTheSoundEnabled, canEditCaptionWords else { return nil }
        return document?.captionWord(atMS: documentTimeMS)
    }

    /// Sequence ▸ Caption Word ▸ Start Here: the caption in hand, picked, with
    /// the playhead at its first frame.
    func goToStartOfCaptionInHand() {
        guard let ref = captionWordInHand,
              let start = document?.layer(id: ref.cueID)?.time?.inMS else { return }
        selectLayer(ref.cueID)
        moveDocumentPlayhead(toMS: start)
    }

    // MARK: Keys and the path

    /// The lane of the keys in hand, else the lane of the value being keyed in
    /// the panel, else the layer's only lane.
    var keyLaneInHand: KeyLane? {
        guard let layer = keyLayer else { return nil }
        let lanes = keyLanes(layerID: layer.id)
        if let picked = keySelection, picked.layerID == layer.id,
           let lane = lanes.first(where: { lane in lane.keys.contains { picked.refs.contains($0.ref) } }) {
            return lane
        }
        if case let .motion(property)? = activeKeyProperty,
           let lane = lanes.first(where: { $0.property == property }) {
            return lane
        }
        return lanes.count == 1 ? lanes[0] : nil
    }

    /// Clip ▸ Select All Keys: every key the picked layer has, on every lane.
    var canSelectAllKeys: Bool {
        guard let layer = keyLayer, !isClipLocked(layer.id) else { return false }
        return keyLanes(layerID: layer.id).contains { !$0.keys.isEmpty }
    }

    func selectAllKeysInHand() {
        guard let layer = keyLayer, canSelectAllKeys else { return }
        let refs = keyLanes(layerID: layer.id).flatMap { $0.keys.map(\.ref) }
        pickKeys(layerID: layer.id, Set(refs), extending: false)
    }

    /// Whether the lane in hand has a graph to show.
    var canGraphKeyLaneInHand: Bool {
        guard let layer = keyLayer, let lane = keyLaneInHand else { return false }
        return document?.keyGraph(layerID: layer.id, motionID: lane.motionID) != nil
    }

    /// The value Clip ▸ Stop Animating stops: the one being keyed in the panel,
    /// else the only one animating.
    var animatingPropertyInHand: KeyedProperty? {
        let moving = animatingRows
        if let active = activeKeyProperty, moving.contains(active) { return active }
        return moving.count == 1 ? moving[0] : nil
    }

    /// Clip ▸ Remove Key at Playhead: the keys at the playhead on the picked
    /// layer's values, the header diamond's verb when it is lit.
    var canRemoveKeyAtPlayhead: Bool {
        guard let layer = keyLayer, !isClipLocked(layer.id) else { return false }
        return headerKeyDiamond(layer.id) == .onKey
    }

    func removeKeyAtPlayhead() {
        guard let layer = keyLayer, canRemoveKeyAtPlayhead else { return }
        toggleHeaderKey(layer.id)
    }

    /// The stretch of the picked layer's path the playhead is in, when it
    /// bends: what Clip ▸ Straighten This Stretch puts back on its line.
    var curvedStretchInHand: Int? {
        guard let layer = keyLayer, let motion = layer.keyedMotion(.position),
              let index = motion.stretch(atMS: layer.motionClockMS(atDocumentTimeMS: documentTimeMS)),
              motion.pathSegments.indices.contains(index), motion.pathSegments[index].isCurved else { return nil }
        return index
    }

    func straightenStretchInHand() {
        guard let layer = keyLayer, let index = curvedStretchInHand else { return }
        straightenMotionPath(layerID: layer.id, segment: index)
    }

    // MARK: A cut and a transition

    /// Clip ▸ Roll Edit to Playhead: whether the cut in hand can roll to the
    /// playhead.
    var canRollCutInHand: Bool {
        guard var trial = document, case let .join(clip, index)? = cutInHand?.place,
              !isClipLocked(clip) else { return false }
        return trial.rollClipCut(clip, atCut: index, toMS: documentTimeMS)
    }

    func rollCutInHand() {
        guard case let .join(clip, index)? = cutInHand?.place, canRollCutInHand else { return }
        rollCutToPlayhead(layerID: clip, cut: index)
    }

    /// The transition Apply to Every Cut and Set as Default Transition act on:
    /// the one on the cut in hand, else the tile picked in Transitions.
    var transitionKindInHand: ClipTransitionKind {
        cutInHand?.cut.transition?.kind ?? transitionsGroupKind
    }

    // MARK: A layer

    /// Layer ▸ Rename Layer…: the name opens where the layer is listed, the
    /// panel coming up for it if it was put away.
    func renameLayerInHand() {
        guard let id = selectedLayerID else { return }
        if !isLayersPanelVisible { setInspectorVisible(true) }
        layerAwaitingRename = id
    }

    /// Clip ▸ Reveal in Finder: the file behind the clip in hand.
    var mediaURLInHand: URL? {
        clipInHandID.flatMap { mediaURL(ofLayer: $0) }
    }
}
