import CoreGraphics
import Foundation

// A layer's track shows only what is animated
// (task `a-layer-s-track-shows-only-what-is-animated-and`,
// `docs/design/mocks/pages/video-animate.html`, "A track lists only what is
// animated").
//
// Add Key used to key where a layer is, how big, how turned and how faded all
// at once, so one press put four rows under its track whether or not any of
// them would ever move. Now a layer's track lists a row only for a value that
// has keys, and values join the animation by being changed:
//
//  - **Add Key on a layer with nothing keyed is one hollow moment** on the
//    clip's key line and no rows. It is a key with nothing in it yet.
//  - **On a layer with keys (or a hollow moment), any change keys itself at
//    the playhead** (the user's answer on 2026-10-13: "Always: any change keys
//    itself"). A value that was not animating joins with its old value held at
//    the layer's key moments either side of the playhead, so the change
//    belongs to this moment only, and its row appears.
//  - **Animate ▸ adds one value back**, with one key at the playhead.
//
// The rule a 3D value followed when the layer's place was animating
// (`SpaceEditing.swift`, `placeAnchors`) and the one a recording's Centre
// followed when its Scale was (`reframeAnchors`) are this one rule now, asked
// of every key moment on the layer.

/// The groups the Animate menu lists values in, the panel's own sections.
public enum AnimateGroup: String, CaseIterable, Sendable {
    case transform, space, look, effects

    public var title: String {
        switch self {
        case .transform: "Transform"
        case .space: "3D"
        case .look: "Look"
        case .effects: "Effects"
        }
    }
}

extension KeyedProperty {

    /// Which of the Animate menu's groups a value is listed in. Nil for
    /// volume, which is a sound's line and never a row under a picture.
    public var animateGroup: AnimateGroup? {
        guard case let .motion(property, _) = self else { return nil }
        switch property {
        case .position, .scale, .rotation: return .transform
        case .shadow, .shadowDistance, .shadowDirection, .shadowColor, .shadowOpacity,
             .glow, .glowColor, .glowOpacity, .borderWidth, .borderColor:
            return .effects
        default:
            return property.isSpace ? .space : .look
        }
    }
}

extension Layer {

    /// What the Animate menu offers: every value the layer can key that is
    /// not in `animating`, in the panel's order, under its group. Groups with
    /// nothing left are left out.
    public func animateGroups(excluding animating: Set<KeyedProperty>)
        -> [(group: AnimateGroup, properties: [KeyedProperty])] {
        let offered = keyableProperties.filter { !animating.contains($0) }
        return AnimateGroup.allCases.compactMap { group in
            let properties = offered.filter { $0.animateGroup == group }
            return properties.isEmpty ? nil : (group, properties)
        }
    }
}

extension PhotonzDocument {

    // MARK: What is animating

    /// Whether a layer is animating: something on it keyed, or a hollow
    /// moment waiting for something to be. On such a layer every change
    /// keys itself.
    func isAnimating(_ layer: Layer) -> Bool {
        !keyedMotions(of: layer).isEmpty || !(layer.hollowKeyMoments ?? []).isEmpty
    }

    public func isAnimating(layerID: UUID) -> Bool {
        guard hasTime, let layer = layer(id: layerID) else { return false }
        return isAnimating(layer)
    }

    /// Where a layer's hollow moments sit, in the document's clock, first to
    /// last, leaving out any the cut has dropped.
    func hollowMomentsMS(of layer: Layer) -> [Int] {
        (layer.hollowKeyMoments ?? []).compactMap { clipKeyDocumentMS(layer, clock: $0) }.sorted()
    }

    /// The layer's key moments either side of `ms`, keys and hollow moments
    /// alike: where a value joining the animation holds its old value, so the
    /// layer stays as it was at every moment the change did not touch.
    func keyMomentAnchors(layerID: UUID, atDocumentTimeMS ms: Int) -> [Int] {
        let moments = clipKeyMarks(layerID: layerID).map(\.documentMS)
        let before = moments.filter { $0 < ms - PropertyKeys.nearMS }.max()
        let after = moments.filter { $0 > ms + PropertyKeys.nearMS }.min()
        return [before, after].compactMap { $0 }
    }

    /// The diamond on the clip's track header, and the Add Key / Remove Key
    /// row: on a key where any moment of the layer is at `ms`, hollow ones
    /// included; between keys where the layer is animating; dormant else.
    public func keyMomentDiamond(layerID: UUID, atDocumentTimeMS ms: Int) -> KeyDiamond {
        guard hasTime, let layer = layer(id: layerID), isAnimating(layer) else { return .dormant }
        let onKey = clipKeyMarks(layerID: layerID).contains { abs($0.documentMS - ms) <= PropertyKeys.nearMS }
        return onKey ? .onKey : .betweenKeys
    }

    // MARK: Add Key and Remove Key

    /// Add Key at `ms`: every value already animating gets a key here holding
    /// the value it has now, so nothing on screen moves. On a layer with
    /// nothing keyed that is a hollow moment and no rows: values join it as
    /// they are changed. False where there is a key here already.
    @discardableResult
    public mutating func addKeyMoment(layerID: UUID, atDocumentTimeMS ms: Int, ease: KeyEase? = nil) -> Bool {
        guard hasTime, let layer = layer(id: layerID),
              keyMomentDiamond(layerID: layerID, atDocumentTimeMS: ms) != .onKey else { return false }
        let animating = keyedMotions(of: layer).map { KeyedProperty.motion($0.property, effect: $0.effectOrdinal) }
        guard animating.isEmpty else {
            var changed = false
            for property in animating {
                guard let value = keyedValue(layerID: layerID, property, atDocumentTimeMS: ms) else { continue }
                changed = setKeyedValue(value, layerID: layerID, property, atDocumentTimeMS: ms, ease: ease) || changed
            }
            return changed
        }
        let clock = clipKeyClock(layer, atDocumentMS: ms)
        updateLayer(id: layerID) { edited in
            edited.hollowKeyMoments = ((edited.hollowKeyMoments ?? []) + [clock]).sorted()
        }
        return true
    }

    /// Remove Key at `ms`: every key there goes, and the hollow moment there.
    /// A value losing its last key stops animating and keeps the value it had.
    @discardableResult
    public mutating func removeKeyMoment(layerID: UUID, atDocumentTimeMS ms: Int) -> Bool {
        let keys = removeClipKeys(layerID: layerID, atMS: ms)
        let hollow = dropHollowMoments(layerID: layerID, near: [ms])
        return keys || hollow
    }

    /// The track header's diamond, pressed: Remove Key on a key, Add Key
    /// anywhere else.
    @discardableResult
    public mutating func toggleKeyMoment(layerID: UUID, atDocumentTimeMS ms: Int, ease: KeyEase? = nil) -> Bool {
        if keyMomentDiamond(layerID: layerID, atDocumentTimeMS: ms) == .onKey {
            return removeKeyMoment(layerID: layerID, atDocumentTimeMS: ms)
        }
        return addKeyMoment(layerID: layerID, atDocumentTimeMS: ms, ease: ease)
    }

    // MARK: Animate ▸

    /// Animate ▸ a value: it starts animating with one key at the playhead
    /// holding the value it has now, and its row appears. False where it is
    /// animating already.
    @discardableResult
    public mutating func animate(layerID: UUID, _ property: KeyedProperty,
                                 atDocumentTimeMS ms: Int, ease: KeyEase? = nil) -> Bool {
        guard hasTime else { return false }
        return startKeying(layerID: layerID, property, atDocumentTimeMS: ms, ease: ease)
    }

    // MARK: Joining

    /// A value nobody has keyed, changed at `ms` on a layer that is
    /// animating: it starts keying with its old value held at the layer's key
    /// moments either side, and the new value here. False where the layer has
    /// no such value.
    mutating func joinKeying(_ value: MotionValue, layerID: UUID, _ property: MotionProperty, effect: Int,
                             clock: Int, atDocumentTimeMS ms: Int, ease: KeyEase?) -> Bool {
        guard let layer = layer(id: layerID), let still = layer.keyStill(property, effect: effect) else { return false }
        var joined = LayerMotion.keyed(property, effect: effect, atMS: clock, value: value, ease: ease)
        let owner = clockOwner(of: layer)
        for anchor in keyMomentAnchors(layerID: layerID, atDocumentTimeMS: ms) {
            joined = joined.settingKey(atMS: owner.motionClockMS(atDocumentTimeMS: anchor), value: still, ease: ease)
        }
        updateLayer(id: layerID) { edited in
            edited.motions = (edited.motions ?? []) + [joined]
        }
        return true
    }

    /// Take the hollow moments that now have a key standing on them: they are
    /// real keys now. Cheap where the layer has none, which is nearly always.
    mutating func settleHollowMoments(layerID: UUID) {
        guard let layer = layer(id: layerID), !(layer.hollowKeyMoments ?? []).isEmpty else { return }
        let keyed = clipKeyMarks(layerID: layerID).filter { !$0.isHollow }.map(\.documentMS)
        dropHollowMoments(layerID: layerID, near: keyed)
    }

    /// Take away the hollow moments within a frame or so of any of `moments`.
    @discardableResult
    mutating func dropHollowMoments(layerID: UUID, near moments: [Int]) -> Bool {
        guard let layer = layer(id: layerID), let hollow = layer.hollowKeyMoments, !hollow.isEmpty,
              !moments.isEmpty else { return false }
        let kept = hollow.filter { clock in
            guard let at = clipKeyDocumentMS(layer, clock: clock) else { return true }
            return !moments.contains { abs($0 - at) <= PropertyKeys.nearMS }
        }
        guard kept.count != hollow.count else { return false }
        updateLayer(id: layerID) { $0.hollowKeyMoments = kept.isEmpty ? nil : kept }
        return true
    }
}
