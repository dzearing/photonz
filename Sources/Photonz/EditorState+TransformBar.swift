import CoreGraphics
import Foundation
import PhotonzCore

/// What the transform values popover is holding while it is open: the layers
/// it is about, the values the hand is changing, and whether a 3D handle has
/// been used on them.
struct TransformBarHold: Equatable {
    var layerIDs: Set<UUID>
    var live: Set<TransformBar.Field>
    var usedSpace: Bool
}

/// The picked layer's transform values, in the popover the tool bar's Info
/// button opens (Next, `next-transform-bar`; `TransformBar.swift`;
/// `TransformValuesPopover`).
///
/// It opens only when asked: the Info button, Layer, Show Transform Values, or
/// F8. It never comes up by itself, so nothing about a transform is ever
/// drawn over the picture. While it is open a drag, a handle, the knob, its 3D
/// arcs or an arrow key outline the value they change and the numbers follow
/// the hand. Another tool, typing, picking something else, opening a menu,
/// Play, Escape or a click on empty canvas close it. Every value it lands goes
/// through `perform`, keyed at the playhead wherever a canvas drag on the same
/// layer would key, so the popover and the hand never disagree.
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

    /// A transform starting on the canvas. With the popover open for these
    /// layers it outlines what the gesture changes; with it closed it does
    /// nothing at all, because the values never come up by themselves (the
    /// user, 2026-10-12: the bar that did covered the handles).
    func noteTransformGesture(_ gesture: TransformBar.Gesture) {
        guard Experiments.shared.transformBarEnabled, var hold = transformBar,
              hold.layerIDs == transformBarTargets else { return }
        hold.live = TransformBar.liveFields(for: gesture)
        hold.usedSpace = hold.usedSpace || (gesture.usesSpace && Experiments.shared.turnInDepthEnabled)
        if hold != transformBar { transformBar = hold }
    }

    /// Opens the popover for what is picked, nothing outlined.
    func openTransformValues() {
        guard canShowTransformValues else { return }
        if let hold = transformBar, hold.layerIDs == transformBarTargets { return }
        transformBar = TransformBarHold(layerIDs: transformBarTargets, live: [], usedSpace: false)
    }

    /// The Info button, the menu row and F8: open it, or close it when open.
    func toggleTransformValues() {
        if showsTransformBar { dropTransformBar() } else { openTransformValues() }
    }

    /// The hand let go: nothing is outlined any more, and the popover stays.
    func endTransformBarGesture() {
        guard var hold = transformBar, !hold.live.isEmpty else { return }
        hold.live = []
        transformBar = hold
    }

    /// Closes the popover.
    func dropTransformBar() {
        if transformBar != nil { transformBar = nil }
    }

    /// Escape on the canvas or in one of its boxes: closes the popover and
    /// nothing else, so the next Escape lets go of the layer the way it always
    /// has. False when there was nothing open to close.
    func escapeTransformBar() -> Bool {
        guard showsTransformBar else { return false }
        dropTransformBar()
        return true
    }

    /// Whether there is anything for the popover to list: something picked
    /// that a number can land on, with Select in hand. It is also when the
    /// tool bar carries its Info button.
    var canShowTransformValues: Bool {
        Experiments.shared.transformBarEnabled && !transformBarTargets.isEmpty
            && activeTool == .select && !isDocumentPlaying && !isWatching
            && editingTextLayerID == nil
    }

    // MARK: What it shows

    /// The values in the popover: the box and the angle, then the space values
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

    /// What the popover keeps off, in the canvas view's own points: every
    /// picked layer's eight squares as drawn, turned and tilted ones included,
    /// its turn knob, and its 3D arcs and depth arrow where it wears them
    /// (`TransformBar.handleKeepOut`).
    var transformValuesKeepOut: [CGRect] {
        guard let viewport, let posed = canvasGeometryDocument else { return [] }
        return transformBarTargets.flatMap { id -> [CGRect] in
            let corners = posed.drawnQuad(of: id) ?? canvasLayer(id: id)?.transformedCorners ?? []
            guard corners.count == 4 else { return [] }
            let quad = corners.map { viewport.viewPoint(fromDocument: $0) }
            let topMid = CGPoint(x: (quad[0].x + quad[1].x) / 2, y: (quad[0].y + quad[1].y) / 2)
            let middle = CGPoint(x: quad.map(\.x).reduce(0, +) / 4, y: quad.map(\.y).reduce(0, +) / 4)
            let handles = SpaceHandles(topMid: topMid, middle: middle, pivot: middle)
            let space = Experiments.shared.turnInDepthEnabled ? handles : nil
            return TransformBar.handleKeepOut(quad: quad, knob: handles.knob, space: space)
        }
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
