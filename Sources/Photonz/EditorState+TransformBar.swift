import CoreGraphics
import Foundation
import PhotonzCore

/// What the transform bar is holding while it is up: the layers it is about,
/// the side of them it sits on, the values the hand is changing, and whether
/// a 3D handle has been used on them.
struct TransformBarHold: Equatable {
    var layerIDs: Set<UUID>
    var side: TransformBar.Side
    var live: Set<TransformBar.Field>
    var usedSpace: Bool
}

/// The small glass bar of transform values beside the layer in hand (Next,
/// `next-transform-bar`; `TransformBar.swift`; `pages/video-animate.html`).
///
/// It comes up when a transform starts on the canvas (a drag on the layer, a
/// handle, the knob or its 3D arcs, an arrow-key nudge) or from Layer, Show
/// Transform Values, and it stays while that layer stays picked and nothing
/// else is done. Another tool, typing, picking something else, opening a menu,
/// Play, Escape or a click on empty canvas take it down. Every value it lands
/// goes through `perform`, keyed at the playhead wherever a canvas drag on the
/// same layer would key, so the bar and the hand never disagree.
@MainActor
extension EditorState {

    // MARK: Up and down

    /// The layers the bar speaks for: everything picked that a number can
    /// land on (`placeableLayerIDs`).
    private var transformBarTargets: Set<UUID> { placeableLayerIDs }

    /// Whether the bar is on screen right now.
    var showsTransformBar: Bool {
        guard Experiments.shared.transformBarEnabled, let hold = transformBar,
              activeTool == .select, !isDocumentPlaying, !isWatching,
              editingTextLayerID == nil else { return false }
        return !hold.layerIDs.isEmpty && hold.layerIDs == transformBarTargets
    }

    /// A transform starting on the canvas: brings the bar up, or keeps it up
    /// for the same layers, on the side this gesture wants and outlining what
    /// it changes. A bar already up for a nudge keeps its side: arrow keys
    /// have no hand to get out of the way of.
    func raiseTransformBar(_ gesture: TransformBar.Gesture) {
        guard Experiments.shared.transformBarEnabled else { return }
        let ids = transformBarTargets
        guard !ids.isEmpty else { return }
        let space = gesture.usesSpace && Experiments.shared.turnInDepthEnabled
        if var hold = transformBar, hold.layerIDs == ids {
            if gesture != .nudge, gesture != .command { hold.side = TransformBar.side(for: gesture) }
            hold.live = TransformBar.liveFields(for: gesture)
            hold.usedSpace = hold.usedSpace || space
            if hold != transformBar { transformBar = hold }
            return
        }
        transformBar = TransformBarHold(layerIDs: ids, side: TransformBar.side(for: gesture),
                                        live: TransformBar.liveFields(for: gesture),
                                        usedSpace: space)
    }

    /// The hand let go: nothing is outlined any more, and the bar stays.
    func endTransformBarGesture() {
        guard var hold = transformBar, !hold.live.isEmpty else { return }
        hold.live = []
        transformBar = hold
    }

    /// Takes the bar down.
    func dropTransformBar() {
        if transformBar != nil { transformBar = nil }
    }

    /// Escape on the canvas: takes the bar down and nothing else, so the next
    /// Escape lets go of the layer the way it always has. False when there was
    /// no bar to take down.
    func escapeTransformBar() -> Bool {
        guard showsTransformBar else { return false }
        dropTransformBar()
        return true
    }

    /// Layer, Show Transform Values: the bar without a drag.
    var canShowTransformValues: Bool {
        Experiments.shared.transformBarEnabled && !transformBarTargets.isEmpty
            && activeTool == .select
    }

    func showTransformValues() {
        guard canShowTransformValues else { return }
        raiseTransformBar(.command)
    }

    // MARK: What it shows

    /// The values on the bar: the box and the angle, then the space values
    /// once a picked layer is in space or a 3D handle was used on it.
    var transformBarFields: [TransformBar.Field] {
        let inSpace = Experiments.shared.turnInDepthEnabled
            && ((transformBar?.usedSpace ?? false) || transformBarInSpace)
        return TransformBar.fields(inSpace: inSpace, turned: inSpace && spaceSelectionIsTurned)
    }

    /// Whether any picked layer is turned or pushed in space, or has a space
    /// value keyed.
    private var transformBarInSpace: Bool {
        guard let document else { return false }
        let ids = spaceTargetIDs
        let time = documentTimeMS
        return ids.contains { id in
            guard let layer = document.layer(id: id) else { return false }
            return MotionProperty.spaceProperties.contains { property in
                layer.keyedMotion(property) != nil
                    || abs(document.spaceValue(property, layerID: id, atDocumentTimeMS: time) ?? 0) > 1e-6
            }
        }
    }

    /// The picked layers' boxes and angles as they are at the playhead, keyed
    /// layers included, following a drag in flight. The panel's Position and
    /// Size reads the layers' own boxes; the bar is about the layer the hand
    /// is holding, which is where its keys have taken it.
    var transformBarSelection: LayerGeometrySelection {
        guard let document else { return LayerGeometrySelection([]) }
        let picked = transformBarTargets
        guard !picked.isEmpty else { return LayerGeometrySelection([]) }
        let posed = documentHasTime ? document.posedForCanvas(atTimeMS: documentTimeMS) : document
        let members = document.allLayers.compactMap { stored -> LayerGeometrySelection.Member? in
            guard picked.contains(stored.id) else { return nil }
            var parent = document.parentID(of: stored.id)
            while let up = parent {
                if picked.contains(up) { return nil }
                parent = document.parentID(of: up)
            }
            let layer = posed.layer(id: stored.id) ?? stored
            let frame: CGRect
            if let moving = previewMoves[stored.id], let inParent = document.parentSpaceFrame(moving, of: stored.id) {
                frame = inParent
            } else {
                frame = layer.shownBox
            }
            let angle = previewRotations[stored.id].map(LayerAngle.degrees(fromRadians:))
                ?? LayerAngle.degrees(fromRadians: layer.transform.rotation)
            let holder = document.parentID(of: stored.id).flatMap { document.layer(id: $0) }
            return LayerGeometrySelection.Member(
                id: stored.id, frame: layer.withoutSlack(frame),
                editing: LayerGeometryEditing(layer: layer, in: holder,
                                              textTakesAHeight: Experiments.shared.placementEnabled),
                slack: layer.boxSlack, angle: angle)
        }
        return LayerGeometrySelection(members)
    }

    /// What one field shows.
    func transformBarShowing(_ field: TransformBar.Field) -> NumberBox.Showing {
        if let geometry = field.geometryField {
            let showing = transformBarSelection.reading(geometry).showing(for: geometry)
            // The bar draws the angle's unit after the box, as the mock does,
            // so the number in the box goes without it.
            if case .number(let text) = showing, field.unit != nil {
                return .number(text.replacingOccurrences(of: LayerAngle.unitSuffix, with: "")
                    .trimmingCharacters(in: .whitespaces))
            }
            return showing
        }
        return spaceValue(field.property).map { .number(SpaceRowText.text($0)) }
            ?? .standIn(MixedValue.text)
    }

    /// Whether a field takes typing for this selection: a box a stack decides,
    /// or a locked layer, is shown and not typed into.
    func transformBarTakesTyping(_ field: TransformBar.Field) -> Bool {
        guard let geometry = field.geometryField else { return !spaceTargetIDs.isEmpty }
        let selection = transformBarSelection
        return !selection.isEmpty && !selection.isReadOnly(geometry)
    }

    /// The key diamond a field wears once its property animates: filled on a
    /// key, hollow between keys, none at all where nothing keys it. One layer
    /// only, like every diamond in the panel.
    func transformBarKey(_ field: TransformBar.Field) -> KeyDiamond {
        guard documentHasTime, keyLayer != nil, transformBarTargets.count == 1 else { return .dormant }
        return keyDiamond(.motion(field.property))
    }

    // MARK: Typing

    /// A number landing in a field: every picked layer takes it in one undo
    /// step, keyed at the playhead wherever a drag would key. Hands back what
    /// the field reads once it has landed.
    @discardableResult
    func setTransformBarValue(_ field: TransformBar.Field, _ value: CGFloat) -> NumberBox.Showing? {
        if let geometry = field.geometryField {
            let selection = transformBarSelection
            if geometry.isFrameNumber {
                commitTransformBarFrames(selection.applying(value, to: geometry))
            } else {
                commitTransformBarTurns(selection.turning(to: value))
            }
        } else {
            if field.isSpace, transformBar != nil { transformBar?.usedSpace = true }
            setSpaceValue(field.property, Double(value))
        }
        return transformBarShowing(field)
    }

    /// An arrow key in a field with no one number in it: each layer steps
    /// from its own value.
    func stepTransformBarValue(_ field: TransformBar.Field, direction: Int, coarse: Bool) {
        if let geometry = field.geometryField {
            let selection = transformBarSelection
            if geometry.isFrameNumber {
                commitTransformBarFrames(selection.stepping(geometry, direction: direction, coarse: coarse))
            } else {
                commitTransformBarTurns(selection.steppingRotation(direction: direction, coarse: coarse))
            }
        } else {
            nudgeSpaceValue(field.property, by: Double(direction) * (coarse ? 10 : 1))
        }
    }

    private func commitTransformBarFrames(_ moves: [UUID: CGRect]) {
        guard !moves.isEmpty, let document else { return }
        previewMoves = [:]
        dragPreviewGeneration += 1
        clearPreviewAfterNextFrame = dragPreview != nil
        let ordered = document.allLayers.compactMap { layer in moves[layer.id].map { (layer.id, $0) } }
        let byHand = Experiments.shared.placementEnabled
        perform { document in
            let canvas = document.canvasSize
            document.holdingTurnedPivots(above: ordered.map(\.0)) { document in
                for (id, frame) in ordered {
                    self.foldingIntoKeys(id, in: &document) { document in
                        document.updateLayer(id: id) {
                            $0 = $0.geometrySet(to: frame, canvas: canvas, byHand: byHand,
                                                captionPillSize: $0.measuredCaptionPillSize)
                        }
                    }
                }
            }
        }
    }

    private func commitTransformBarTurns(_ turns: [UUID: CGFloat]) {
        guard !turns.isEmpty, let document else { return }
        previewRotations = [:]
        dragPreviewGeneration += 1
        clearPreviewAfterNextFrame = dragPreview != nil
        let ordered = document.allLayers.compactMap { layer in
            turns[layer.id].map { (layer.id, LayerAngle.radians(fromDegrees: $0)) }
        }
        perform { document in
            for (id, radians) in ordered {
                self.foldingIntoKeys(id, in: &document) { document in
                    document.updateLayer(id: id) { $0.transform.rotation = radians }
                }
            }
        }
    }

    // MARK: Reset

    /// Whether Reset has anything to put back: a turn, a slant, a tilt, a
    /// depth, or a size an animation has changed.
    var canResetTransformBar: Bool {
        guard let document else { return false }
        let posed = documentHasTime ? document.posedForCanvas(atTimeMS: documentTimeMS) : document
        let time = documentTimeMS
        return transformBarTargets.contains { id in
            guard let stored = document.layer(id: id) else { return false }
            let shown = posed.layer(id: id) ?? stored
            let t = shown.transform
            if t.rotation != 0 || t.skewX != 0 || t.skewY != 0 { return true }
            if shown.frame.size != stored.frame.size { return true }
            return MotionProperty.spaceProperties.contains {
                abs(document.spaceValue($0, layerID: id, atDocumentTimeMS: time) ?? 0) > 1e-6
            }
        }
    }

    /// Reset: size, turn, tilt and depth go back to their defaults and the
    /// position stays, in one undo step. A layer whose size an animation has
    /// changed gets its own size back around the middle it has now; a key at
    /// the playhead where the value is keyed, the layer's own value where not.
    func resetTransformBar() {
        guard let document, canResetTransformBar else { return }
        let ids = document.allLayers.map(\.id).filter(transformBarTargets.contains)
        let posed = documentHasTime ? document.posedForCanvas(atTimeMS: documentTimeMS) : document
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        let ownSizes = Dictionary(uniqueKeysWithValues: ids.compactMap { id -> (UUID, CGSize)? in
            guard let stored = document.layer(id: id), let shown = posed.layer(id: id),
                  shown.frame.size != stored.frame.size else { return nil }
            return (id, stored.frame.size)
        })
        let space = Experiments.shared.turnInDepthEnabled
        previewMoves = [:]
        previewRotations = [:]
        dragPreviewGeneration += 1
        clearPreviewAfterNextFrame = dragPreview != nil
        perform { document in
            for id in ids {
                self.foldingIntoKeys(id, in: &document) { document in
                    document.updateLayer(id: id) { layer in
                        layer.transform.rotation = 0
                        layer.transform.skewX = 0
                        layer.transform.skewY = 0
                        if let own = ownSizes[id] {
                            layer.frame = TransformBar.resetFrame(shown: layer.frame, own: own)
                        }
                    }
                }
                guard space else { continue }
                for property in MotionProperty.spaceProperties
                where abs(document.spaceValue(property, layerID: id, atDocumentTimeMS: time) ?? 0) > 1e-6 {
                    document.setSpaceValue(property, 0, layerIDs: [id], atDocumentTimeMS: time, ease: ease)
                }
            }
        }
        transformBar?.usedSpace = false
    }

    // MARK: Where it sits

    /// The box the picked layers make on screen, in the canvas view's own
    /// points: every corner as it is drawn, turned and tilted ones included.
    var transformBarBox: CGRect? {
        guard let viewport, let posed = canvasGeometryDocument else { return nil }
        let corners = transformBarTargets.flatMap { id -> [CGPoint] in
            if let quad = posed.drawnQuad(of: id) { return quad }
            return canvasLayer(id: id)?.transformedCorners ?? []
        }
        guard !corners.isEmpty else { return nil }
        let points = corners.map { viewport.viewPoint(fromDocument: $0) }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
        else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension TransformBar.Field {
    /// The Position and Size field this value shares its rules with, for the
    /// box and the angle; nil for the space values.
    var geometryField: LayerGeometryField? {
        switch self {
        case .x: .x
        case .y: .y
        case .width: .width
        case .height: .height
        case .angle: .rotation
        case .tiltX, .tiltY, .depth, .pivotDepth: nil
        }
    }
}
