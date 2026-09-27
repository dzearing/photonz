import Foundation
import PhotonzCore

/// Between the keys, and the window's Animate commands
/// (task `a-moving-layer-shows-between-the-keys-in-propert`,
/// `docs/design/mocks/pages/video-move-wt.html`, `#secEase` and `#cmdMenu`).
///
/// A thin layer over `StretchCurve.swift`: the section asks which value it is
/// about and what curve the stretch under the playhead runs on, and every
/// change lands through `perform`, so one choice is one step to undo.
extension EditorState {

    /// The keyed value the section speaks for: the one last touched when it
    /// has two keys, else a move, else the first in the panel's order that has
    /// two. Nil when nothing on the picked layer has a stretch to shape.
    var betweenKeysProperty: MotionProperty? {
        guard let layer = keyLayer else { return nil }
        let moving = Set((layer.motions ?? []).filter { $0.keyframes.count > 1 }.map(\.property))
        guard !moving.isEmpty else { return nil }
        if case let .motion(active)? = activeKeyProperty, moving.contains(active) { return active }
        if moving.contains(.position) { return .position }
        for case let .motion(property) in keyRows where moving.contains(property) { return property }
        return nil
    }

    /// The curve of the stretch the playhead is in.
    var betweenKeysCurve: EasingCurve? {
        guard let layer = keyLayer, let property = betweenKeysProperty, let document else { return nil }
        return document.stretchCurve(layerID: layer.id, property, atDocumentTimeMS: documentTimeMS)
    }

    /// The Curve dropdown, and the Animate menu's Easing: the stretch under
    /// the playhead runs on `curve`.
    func curveBetweenKeys(_ curve: EasingCurve) {
        guard let layer = keyLayer, let property = betweenKeysProperty,
              betweenKeysCurve != curve else { return }
        let time = documentTimeMS
        perform { $0.curveStretch(layerID: layer.id, property, atDocumentTimeMS: time, curve) }
    }

    // MARK: Key at Playhead

    /// What Key at Playhead keys: every value already animating, or where
    /// nothing is yet, the layer's Position, the first key of a move.
    private var keyAtPlayheadProperties: [KeyedProperty] {
        guard keyLayer != nil else { return [] }
        if !animatingRows.isEmpty { return animatingRows }
        return keyRows.contains(.motion(.position)) ? [.motion(.position)] : []
    }

    /// Whether Key at Playhead has anything to write: a value that is not
    /// already on a key right here.
    var canKeyAtPlayhead: Bool {
        keyAtPlayheadProperties.contains { keyDiamond($0) != .onKey }
    }

    /// The Animate menu's Key at Playhead: a key here on each of them, holding
    /// the value it has now, as one step to undo. Nothing on screen moves: it
    /// gives the next change somewhere to travel from.
    func keyAtPlayhead() {
        guard let layer = keyLayer else { return }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        let wanted = keyAtPlayheadProperties.filter { keyDiamond($0) != .onKey }
        let values = wanted.map { ($0, keyedValue($0)) }
        guard !wanted.isEmpty else { return }
        if wanted.count == 1 { activeKeyProperty = wanted[0] }
        perform { document in
            for (property, value) in values {
                if document.keyCount(layerID: layer.id, property) == 0 {
                    document.startKeying(layerID: layer.id, property, atDocumentTimeMS: time, ease: ease)
                } else if let value {
                    document.setKeyedValue(value, layerID: layer.id, property, atDocumentTimeMS: time, ease: ease)
                }
            }
        }
    }
}
