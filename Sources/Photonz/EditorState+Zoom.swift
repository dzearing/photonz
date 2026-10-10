import AppKit
import Foundation
import PhotonzCore

// Zoom regions on a recording, in the hand (`ClipZoom.swift`).
//
// Add Zoom on a clip's right-click menu, the ruler's, or the Clip menu puts a
// zoom at the playhead: a bar on the clip's Zoom lane for WHEN, and a box on
// the picture for WHERE. Picked, the bar's ends and its two ramps drag on the
// lane. Picking a zoom (adding it, clicking its bar, or clicking the picture
// while it is picked) puts its box up: the canvas shows the whole picture with
// the box on it to move, resize or draw again. Moving the playhead takes the
// box down, so a scrub shows exactly what the zoom does at every frame, the
// same as playing and exporting. Follow Cursor makes the box
// ride the pointer the recorder took down; Suggest Zooms puts one round every
// run of clicks. Every change is one undo step.

/// Which zoom on which clip.
struct ClipZoomRef: Hashable {
    let layerID: UUID
    let zoomID: UUID
}

/// What a hand has hold of on a zoom.
enum ZoomGrab: Hashable {
    /// The bar, carried along the lane.
    case body
    /// One end of the bar.
    case start, end
    /// The handle where the way in stops, or where the way out begins.
    case easeIn, easeOut
    /// The box on the picture, carried.
    case boxMove
    /// The box drawn again from a corner that stays put, as fractions of the
    /// picture seen. A press beside the box draws a new one from where it landed;
    /// a press on a corner handle resizes from the opposite corner.
    case boxFrom(CGPoint)
}

/// A press the zoom's box took: where it landed, as fractions of the picture
/// seen and in document points, what it took hold of, and whether it has become a
/// drag yet.
struct ZoomBoxPress {
    let start: CGPoint
    let startInDocument: CGPoint
    let grab: ZoomGrab
    let onTheBox: Bool
    var dragging = false
}

/// A zoom under a hand: what it was when the hand took hold, and what it is
/// now. Nothing is written down until the hand lets go.
struct ZoomDragSession {
    let ref: ClipZoomRef
    let grab: ZoomGrab
    let before: ClipZoom
    var landed: ClipZoom
    var moved = false
}

extension EditorState {

    /// Whether this window offers zooms at all: Next, with a timeline.
    var canWorkWithZooms: Bool { Experiments.shared.zoomRegionsEnabled && documentHasTime }

    /// A zoom as the document has it now.
    func zoom(_ ref: ClipZoomRef) -> ClipZoom? {
        document?.layer(id: ref.layerID)?.zooms?.first { $0.id == ref.zoomID }
    }

    /// A clip's zooms as the hand has them: the one being dragged where the
    /// hand has it.
    func zoomsShown(onClip id: UUID) -> [ClipZoom] {
        let zooms = document?.layer(id: id)?.zooms ?? []
        guard let drag = zoomDrag, drag.ref.layerID == id else { return zooms }
        return zooms.map { $0.id == drag.ref.zoomID ? drag.landed : $0 }
    }

    /// The zoom picked, as the hand has it.
    var zoomInHand: (layer: Layer, zoom: ClipZoom)? {
        guard let ref = selectedZoom, let layer = document?.layer(id: ref.layerID),
              let zoom = zoomsShown(onClip: ref.layerID).first(where: { $0.id == ref.zoomID }) else { return nil }
        return (layer, zoom)
    }

    // MARK: Adding

    /// Whether Add Zoom would put one on this clip at this moment.
    func canAddZoom(toClip id: UUID, atMS ms: Int) -> Bool {
        guard canWorkWithZooms, !isClipLocked(id), var trial = document else { return false }
        return trial.addZoom(toClip: id, atTimeMS: ms, around: nil) != nil
    }

    /// The recording Add Zoom acts on at a moment: the clip in hand when it
    /// can take one there, otherwise the top recording under that moment.
    func clipToAddZoom(atMS ms: Int) -> UUID? {
        if let clip = clipInHandID, canAddZoom(toClip: clip, atMS: ms) { return clip }
        return document?.allLayers.last { $0.takesAZoom && canAddZoom(toClip: $0.id, atMS: ms) }?.id
    }

    /// Put a zoom on a clip at a moment, framed on where the pointer was then
    /// when the recording kept it, and pick it so its box is up to move.
    func addZoom(toClip id: UUID, atMS ms: Int) {
        guard canAddZoom(toClip: id, atMS: ms), let layer = document?.layer(id: id) else { return }
        pauseDocument()
        let point = pointerUnitPoint(onClip: id, atSourceMS: layer.motionClockMS(atDocumentTimeMS: ms))
        var added: ClipZoom?
        perform { added = $0.addZoom(toClip: id, atTimeMS: ms, around: point) }
        guard let added else { return }
        pickZoom(ClipZoomRef(layerID: id, zoomID: added.id))
        raiseCanvasNotice(.zoomsAdded(count: 1), action: .undo)
    }

    /// Where the recorded pointer was at a moment of a clip's recording, as
    /// fractions of the recording.
    func pointerUnitPoint(onClip id: UUID, atSourceMS ms: Int) -> CGPoint? {
        guard let track = recordedPointerTrack(ofClip: id), track.pixelSize.width > 0,
              track.pixelSize.height > 0, let p = track.position(atMS: ms) else { return nil }
        return CGPoint(x: p.x / track.pixelSize.width, y: p.y / track.pixelSize.height)
    }

    /// Whether Suggest Zooms has anything to go on: clicks on the clip, and
    /// room for a zoom round at least one run of them.
    func canSuggestZooms(onClip id: UUID) -> Bool {
        guard canWorkWithZooms, !isClipLocked(id), var trial = document else { return false }
        return !trial.addSuggestedZooms(toClip: id, clicks: clicks(ofClip: id)).isEmpty
    }

    func suggestZooms(onClip id: UUID) {
        guard canSuggestZooms(onClip: id) else { return }
        let clicks = clicks(ofClip: id)
        var made: [ClipZoom] = []
        perform { made = $0.addSuggestedZooms(toClip: id, clicks: clicks) }
        guard let first = made.first else { return }
        pickZoom(ClipZoomRef(layerID: id, zoomID: first.id))
        raiseCanvasNotice(.zoomsAdded(count: made.count), action: .undo)
    }

    // MARK: Picking

    /// Pick a zoom, and only that one, with its box up to frame it.
    func pickZoom(_ ref: ClipZoomRef) {
        if selectedLayerID != ref.layerID { selectLayer(ref.layerID) }
        if pickedZooms.count > 1 { pickedZooms = [ref] }
        if selectedZoom != ref { selectedZoom = ref }
        if !zoomFraming { zoomFraming = true }
        documentMomentChanged()
    }

    /// Shift or Command click on a bar: into the pick, or out of it. A zoom on
    /// another clip starts a new pick, because one clip is in hand at a time.
    func togglePickedZoom(_ ref: ClipZoomRef) {
        guard selectedZoom?.layerID == ref.layerID, !pickedZooms.isEmpty else {
            pickZoom(ref)
            return
        }
        if pickedZooms.contains(ref) {
            guard pickedZooms.count > 1 else {
                letGoOfZoom()
                return
            }
            pickedZooms.remove(ref)
            if selectedZoom == ref { selectedZoom = earliest(of: pickedZooms) }
        } else {
            pickedZooms.insert(ref)
            selectedZoom = ref
        }
        documentMomentChanged()
    }

    /// The Zoom lane's label: every zoom on the clip, picked together.
    func pickAllZooms(onClip id: UUID) {
        guard let zooms = document?.layer(id: id)?.zooms, let first = zooms.first else { return }
        guard zooms.count > 1 else {
            pickZoom(ClipZoomRef(layerID: id, zoomID: first.id))
            return
        }
        if selectedLayerID != id { selectLayer(id) }
        pickedZooms = Set(zooms.map { ClipZoomRef(layerID: id, zoomID: $0.id) })
        selectedZoom = ClipZoomRef(layerID: id, zoomID: first.id)
        documentMomentChanged()
    }

    /// Whether a zoom is one of those picked.
    func isZoomPicked(_ ref: ClipZoomRef) -> Bool { pickedZooms.contains(ref) }

    /// The picked zooms as the hand has them, in the order they run.
    var pickedZoomsShown: [ClipZoom] {
        let clips = Set(pickedZooms.map(\.layerID))
        return clips.flatMap { clip in
            zoomsShown(onClip: clip).filter { pickedZooms.contains(ClipZoomRef(layerID: clip, zoomID: $0.id)) }
        }
        .sorted { $0.startMS < $1.startMS }
    }

    /// What the picked zooms agree on.
    var pickedZoomsReading: ClipZoomsReading { ClipZoomsReading(pickedZoomsShown) }

    /// The one of `refs` that runs first.
    private func earliest(of refs: Set<ClipZoomRef>) -> ClipZoomRef? {
        refs.min { (zoom($0)?.startMS ?? .max, $0.zoomID.uuidString) < (zoom($1)?.startMS ?? .max, $1.zoomID.uuidString) }
    }

    /// What a verb on a zoom's bar acts on: every zoom picked when the bar is
    /// one of them, otherwise that bar alone.
    func zoomsActedOn(from ref: ClipZoomRef) -> Set<ClipZoomRef> {
        pickedZooms.contains(ref) ? pickedZooms : [ref]
    }

    func letGoOfZoom() {
        guard selectedZoom != nil else { return }
        selectedZoom = nil
        zoomFraming = false
        documentMomentChanged()
    }

    // MARK: Changing

    func removeZoom(_ ref: ClipZoomRef) { removeZooms([ref]) }

    /// Take zooms away, all in one undo step. Those left picked stay picked.
    func removeZooms(_ refs: Set<ClipZoomRef>) {
        let refs = refs.filter { zoom($0) != nil && !isClipLocked($0.layerID) }
        guard !refs.isEmpty else { return }
        let left = pickedZooms.subtracting(refs)
        if left.isEmpty {
            if selectedZoom != nil { selectedZoom = nil }
            zoomFraming = false
        } else if left != pickedZooms {
            pickedZooms = left
            if let anchor = selectedZoom, refs.contains(anchor) { selectedZoom = earliest(of: left) }
        }
        let byClip = Dictionary(grouping: refs, by: \.layerID).mapValues { Set($0.map(\.zoomID)) }
        perform { document in
            for (clip, ids) in byClip { document.removeZooms(onClip: clip, ids: ids) }
        }
        documentMomentChanged()
    }

    /// Delete with zooms picked: every one of them.
    func removeZoomInHand() {
        removeZooms(pickedZooms)
    }

    /// Whether this clip's recording kept where the pointer went, which is
    /// what Follow Cursor follows.
    func canFollowCursor(onClip id: UUID) -> Bool {
        recordedPointerTrack(ofClip: id)?.samples.isEmpty == false
    }

    /// Change a zoom in one undo step, keeping it sensible
    /// (`PhotonzDocument.updateZoom`).
    func changeZoom(_ ref: ClipZoomRef, _ change: @escaping (inout ClipZoom) -> Void) {
        changeZooms([ref], change)
    }

    /// Change several zooms the same way, in one undo step.
    func changeZooms(_ refs: Set<ClipZoomRef>, _ change: @escaping (inout ClipZoom) -> Void) {
        let refs = refs.filter { zoom($0) != nil && !isClipLocked($0.layerID) }
        guard !refs.isEmpty else { return }
        let byClip = Dictionary(grouping: refs, by: \.layerID).map {
            (clip: $0.key, ids: Set($0.value.map(\.zoomID)), track: recordedPointerTrack(ofClip: $0.key))
        }
        perform { document in
            for group in byClip {
                document.updateZooms(onClip: group.clip, ids: group.ids, cursorTrack: group.track, change)
            }
        }
        documentMomentChanged()
    }

    /// Whether any of these zooms can follow the pointer: their recordings
    /// kept where it went, or they already follow it.
    func canFollowCursor(_ refs: Set<ClipZoomRef>) -> Bool {
        refs.contains { zoom($0)?.followsCursor == true || canFollowCursor(onClip: $0.layerID) }
    }

    func setZoomFollowsCursor(_ ref: ClipZoomRef, _ on: Bool) { setZoomFollowsCursor([ref], on) }

    /// Turning it on reaches only the zooms whose recordings kept the pointer.
    func setZoomFollowsCursor(_ refs: Set<ClipZoomRef>, _ on: Bool) {
        let refs = on ? refs.filter { canFollowCursor(onClip: $0.layerID) } : refs
        changeZooms(refs) { $0.followsCursor = on }
    }

    func setZoomScale(_ ref: ClipZoomRef, percent: Int) { setZoomScale([ref], percent: percent) }

    func setZoomScale(_ refs: Set<ClipZoomRef>, percent: Int) {
        changeZooms(refs) { $0.scale = Double(percent) / 100 }
    }

    func setZoomEase(_ ref: ClipZoomRef, easeIn: Bool, ms: Int) { setZoomEase([ref], easeIn: easeIn, ms: ms) }

    func setZoomEase(_ refs: Set<ClipZoomRef>, easeIn: Bool, ms: Int) {
        changeZooms(refs) { zoom in
            if easeIn { zoom.easeInMS = ms } else { zoom.easeOutMS = ms }
        }
    }

    /// How far in a zoom can be set from its menu and the panel, in percent.
    static let zoomScaleStops = [125, 150, 200, 250, 300, 400]
    /// How long a way in or out can be set to from the panel, in ms.
    static let zoomEaseStops = [0, 300, 500, 700, 1000, 1500, 2000]

    static func zoomPercent(_ zoom: ClipZoom) -> Int { Int((zoom.scale * 100).rounded()) }

    static func easeTitle(_ ms: Int) -> String {
        ms == 0 ? "None" : String(format: "%.1fs", Double(ms) / 1000)
    }

    // MARK: Menus

    /// Add Zoom and Suggest Zooms, for a recording's right-click menu.
    func addZoomMenuRows(layerID: UUID, atMS ms: Int) -> [MenuRow] {
        guard canWorkWithZooms, document?.layer(id: layerID)?.takesAZoom == true else { return [] }
        return [
            .command("Add Zoom", enabled: canAddZoom(toClip: layerID, atMS: ms)) {
                self.addZoom(toClip: layerID, atMS: ms)
            },
            .command("Suggest Zooms", enabled: canSuggestZooms(onClip: layerID)) {
                self.suggestZooms(onClip: layerID)
            },
        ]
    }

    /// The menu on a zoom's bar: how it frames, and taking it away. On a bar
    /// that is one of several picked, every row acts on all of them.
    func zoomMenuRows(_ ref: ClipZoomRef) -> [MenuRow] {
        guard zoom(ref) != nil else { return [] }
        let refs = zoomsActedOn(from: ref)
        let reading = ClipZoomsReading(refs.compactMap { zoom($0) })
        let allFollow = reading.followsCursor == true
        var follow = MenuRow.toggle("Follow Cursor", isOn: allFollow) {
            self.setZoomFollowsCursor(refs, !allFollow)
        }
        follow.isEnabled = canFollowCursor(refs)
        return [
            follow,
            .submenu("Zoom", Self.zoomScaleStops.map { stop in
                .toggle("\(stop)%", isOn: stop == reading.scalePercent) { self.setZoomScale(refs, percent: stop) }
            }),
            .separator,
            .command("Delete Zoom", TimelineMenuKeys.delete, destructive: true) { self.removeZooms(refs) },
        ]
    }

    // MARK: A hand on the bar or the box

    func beginZoomDrag(_ ref: ClipZoomRef, grab: ZoomGrab) {
        guard let zoom = zoom(ref), !isClipLocked(ref.layerID) else { return }
        pauseDocument()
        // A bar among several picked is carried alone and leaves the rest picked.
        if !pickedZooms.contains(ref) {
            pickZoom(ref)
        } else if selectedZoom != ref {
            selectedZoom = ref
        }
        zoomDrag = ZoomDragSession(ref: ref, grab: grab, before: zoom, landed: zoom)
    }

    /// The hand on the lane moved `delta` ms of the timeline from where it
    /// pressed. Read on the clip's own clock at the moment it lands, so a
    /// retimed clip still puts the edge under the hand.
    func updateZoomDrag(byMS delta: Int) {
        guard var session = zoomDrag, let layer = document?.layer(id: session.ref.layerID),
              let span = spanOnTimeline(session.before, of: layer) else { return }
        let before = session.before
        var zoom = before
        func clock(_ ms: Int) -> Int { layer.motionClockMS(atDocumentTimeMS: ms) }
        switch session.grab {
        case .body:
            zoom.startMS = clock(span.start + delta)
            zoom.endMS = zoom.startMS + before.lengthMS
        case .start:
            zoom.startMS = min(clock(span.start + delta), before.endMS - ClipZoom.shortestMS)
        case .end:
            zoom.endMS = max(clock(span.end + delta), before.startMS + ClipZoom.shortestMS)
        case .easeIn:
            zoom.easeInMS = min(max(0, before.eases.inMS + delta), before.lengthMS - before.eases.outMS)
        case .easeOut:
            zoom.easeOutMS = min(max(0, before.eases.outMS - delta), before.lengthMS - before.eases.inMS)
        case .boxMove, .boxFrom:
            return
        }
        session.landed = settled(zoom, ref: session.ref)
        session.moved = session.moved || delta != 0
        zoomDrag = session
        documentMomentChanged()
    }

    /// The hand on the picture moved: `from` is where it pressed and `to`
    /// where it is, both as fractions of the part of the clip that is seen
    /// (`ZoomStage.swift`). The zoom keeps its spot as a point of the
    /// recording, so it is written back through the same stage.
    func updateZoomBox(from: CGPoint, to: CGPoint) {
        guard var session = zoomDrag, let stage = zoomStageInHand else { return }
        let before = session.before
        var zoom = before
        switch session.grab {
        case .boxMove:
            let region = before.region(on: stage)
            zoom.center = stage.fromStage(CGPoint(x: region.midX + to.x - from.x,
                                                  y: region.midY + to.y - from.y))
        case .boxFrom(let anchor):
            // Square in the seen picture's fractions, which is its own shape:
            // the larger of the two distances, so the box always reaches the
            // hand on one side.
            let size = min(1, max(abs(to.x - anchor.x), abs(to.y - anchor.y), 1 / ClipZoom.mostScale))
            let x = to.x >= anchor.x ? anchor.x : anchor.x - size
            let y = to.y >= anchor.y ? anchor.y : anchor.y - size
            zoom.scale = Double(1 / size)
            zoom.center = stage.fromStage(CGPoint(x: x + size / 2, y: y + size / 2))
        default:
            return
        }
        session.landed = settled(zoom, ref: session.ref)
        session.moved = session.moved || from != to
        zoomDrag = session
        documentMomentChanged()
    }

    /// Let go: one undo step for the whole drag.
    func commitZoomDrag() {
        guard let session = zoomDrag else { return }
        zoomDrag = nil
        guard session.moved, session.landed != session.before else {
            documentMomentChanged()
            return
        }
        let landed = session.landed
        changeZoom(session.ref) { $0 = landed }
    }

    func cancelZoomDrag() {
        guard zoomDrag != nil else { return }
        zoomDrag = nil
        documentMomentChanged()
    }

    /// A zoom as the document would keep it, worked out on a copy.
    private func settled(_ zoom: ClipZoom, ref: ClipZoomRef) -> ClipZoom {
        guard var trial = document else { return zoom }
        trial.updateZoom(onClip: ref.layerID, id: ref.zoomID,
                         cursorTrack: recordedPointerTrack(ofClip: ref.layerID)) { $0 = zoom }
        return trial.layer(id: ref.layerID)?.zooms?.first { $0.id == ref.zoomID } ?? zoom
    }

    /// Where a zoom sits on the timeline.
    func spanOnTimeline(_ zoom: ClipZoom, of layer: Layer) -> (start: Int, end: Int)? {
        var probe = layer
        probe.zooms = [zoom]
        return probe.timelineSpanMS(of: zoom.id)
    }

    // MARK: What the canvas draws

    /// The document with the zoom under a hand where the hand has it.
    func withDraggedZoom(_ document: PhotonzDocument) -> PhotonzDocument {
        guard let session = zoomDrag else { return document }
        var document = document
        document.updateLayer(id: session.ref.layerID) { layer in
            layer.zooms = layer.zooms?.map { $0.id == session.ref.zoomID ? session.landed : $0 }
        }
        return document
    }

    /// Whether a picked zoom owns presses on the picture: picked, and
    /// nothing playing. The clip's own outline and handles step aside, so
    /// there is one thing a press can be about.
    ///
    /// Several picked own nothing there: several boxes over one picture would
    /// leave nobody sure which a press moves, so the canvas shows the picture
    /// as it plays at the playhead and the clip keeps its own handles.
    var zoomOwnsPicture: Bool {
        selectedZoom != nil && pickedZooms.count <= 1 && !isDocumentPlaying && zoomInHand != nil
    }

    /// Whether the canvas is showing a picked zoom's box over the whole
    /// picture rather than the zoom itself: picked, being framed, and nothing
    /// playing. Otherwise the picture is what the zoom shows at the playhead.
    var showsZoomBox: Bool { zoomOwnsPicture && zoomFraming }

    /// Whether a press at `p` (document points) would put the picked zoom's
    /// box up: the zoom owns the picture, its box is down, and the press is
    /// on its clip.
    func zoomFramesOnPress(at p: CGPoint) -> Bool {
        guard zoomOwnsPicture, !zoomFraming, let seen = zoomStageInHand?.onCanvas else { return false }
        return seen.contains(p)
    }

    /// The part of the picked zoom's clip a person can see at the playhead:
    /// what its box is drawn on and fills (`ZoomStage.swift`). The canvas, the
    /// clip's own crop and its keyed crop edges all take part of a clip away.
    var zoomStageInHand: ZoomStage? {
        guard let ref = selectedZoom else { return nil }
        return document?.zoomStage(ofClip: ref.layerID, atTimeMS: documentTimeMS)
    }

    /// A drawn document with the picked zoom's clip shown whole, so its box
    /// can be seen over what it frames.
    func withZoomInHandUnzoomed(_ document: PhotonzDocument) -> PhotonzDocument {
        guard showsZoomBox, let ref = selectedZoom else { return document }
        var document = document
        document.updateLayer(id: ref.layerID) { $0.zoomWindow = nil }
        return document
    }

    /// The picked zoom's box at the playhead, in document points: where the
    /// zoom is on once it has arrived (for a following zoom, where the
    /// pointer has it now). Always on the part of the clip that is seen.
    var zoomBoxInDocument: CGRect? {
        guard showsZoomBox, let (layer, zoom) = zoomInHand, let stage = zoomStageInHand else { return nil }
        return stage.onCanvas(zoom.target(atMS: layer.motionClockMS(atDocumentTimeMS: documentTimeMS), on: stage))
    }

    /// The part of the picked zoom's clip that is seen, in document points:
    /// what the box is drawn over and kept inside.
    var zoomClipFrameInDocument: CGRect? {
        guard showsZoomBox else { return nil }
        return zoomStageInHand?.onCanvas
    }

    // MARK: A hand on the box

    /// How near a corner a press takes hold of it, in view points.
    static let zoomBoxCornerReach: CGFloat = 10

    /// A press on the picture while the box is up: the box takes it when it
    /// lands on the clip (or just beside a corner), and says what it holds.
    func zoomBoxDown(at p: CGPoint) -> Bool {
        // The zoom shown, its box down: a press on the picture puts the box
        // back up to frame, and a press off it lets the zoom go.
        if zoomOwnsPicture, !zoomFraming {
            if zoomFramesOnPress(at: p), let ref = selectedZoom {
                pickZoom(ref)
            } else {
                letGoOfZoom()
            }
            return true
        }
        guard let box = zoomBoxInDocument, let start = zoomUnitPoint(fromDocument: p) else { return false }
        guard let hit = zoomBoxHit(at: p) else {
            // Off the clip: done framing, the way a click off a crop is. The
            // press goes no further, because the clip's own handles are not
            // on screen and must not be grabbed blind.
            letGoOfZoom()
            return true
        }
        let grab: ZoomGrab
        switch hit {
        case .corner:
            // The opposite corner stays put.
            grab = .boxFrom(hit.anchor(of: box).flatMap { zoomUnitPoint(fromDocument: $0) } ?? start)
        case .body:
            grab = .boxMove
        case .beside:
            grab = .boxFrom(start)
        }
        zoomBoxPress = ZoomBoxPress(start: start, startInDocument: p, grab: grab, onTheBox: hit != .beside)
        return true
    }

    /// What a press at `p` (document points) would take on the box, or nil
    /// when the box is down or the press is off its clip. The pointer reads
    /// the same answer (`CanvasNSView.refreshGrabCursor`).
    func zoomBoxHit(at p: CGPoint) -> ZoomBoxHit? {
        guard let box = zoomBoxInDocument, let frame = zoomClipFrameInDocument else { return nil }
        let reach = Self.zoomBoxCornerReach / max(0.01, viewport?.zoom ?? 1)
        return ZoomBoxHit.at(p, box: box, clip: frame, reach: reach)
    }

    func zoomBoxDragged(to p: CGPoint) {
        guard var press = zoomBoxPress, let ref = selectedZoom, let here = zoomUnitPoint(fromDocument: p) else { return }
        if !press.dragging {
            let travel = hypot(p.x - press.startInDocument.x, p.y - press.startInDocument.y) * (viewport?.zoom ?? 1)
            guard travel >= 3 else { return }
            press.dragging = true
            zoomBoxPress = press
            beginZoomDrag(ref, grab: press.grab)
        }
        updateZoomBox(from: press.start, to: here)
    }

    func zoomBoxReleased(at p: CGPoint) {
        guard let press = zoomBoxPress else { return }
        zoomBoxPress = nil
        if press.dragging {
            commitZoomDrag()
        } else if !press.onTheBox {
            // A click beside the box, not a drag: done framing.
            letGoOfZoom()
        }
    }

    /// ⎋ while the box is up: a drag on the box goes back where it started;
    /// otherwise the zoom is let go and its clip stays picked, one step back
    /// at a time. False when there was nothing to step back from.
    func zoomBoxEscape() -> Bool {
        if let press = zoomBoxPress {
            zoomBoxPress = nil
            if press.dragging { cancelZoomDrag() }
            return true
        }
        guard selectedZoom != nil else { return false }
        letGoOfZoom()
        return true
    }

    /// A point of the document as fractions of the part of the picked zoom's
    /// clip that is seen.
    func zoomUnitPoint(fromDocument p: CGPoint) -> CGPoint? {
        zoomStageInHand?.stagePoint(fromDocument: p)
    }
}
