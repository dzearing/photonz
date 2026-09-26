import CoreGraphics
import Foundation

// A layer's LOOK edited in the panel, at the playhead
// (task `opacity-changes-a-shape-on-a-video-and-animates`).
//
// The canvas has turned a hand's move into keys since keys arrived
// (`foldEditIntoKeys`). The panel's look rows (Opacity, a blur's Amount, a
// shadow's or a glow's Size, Corner Radius, Thickness) did not: they wrote the
// layer's own value, which a keyed value never reads, so on a rectangle keyed
// with its timeline row's diamond the Opacity slider moved and the picture did
// not (reported 2026-09-26).
//
// Premiere's stopwatch, for those rows: a value that is KEYED changes by a key
// at the playhead (rewriting the one there); a value that is not changes the
// whole layer, exactly as it always did. And the rows read the value AT the
// playhead, so the knob follows it between keys.

extension MotionProperty {

    /// The keyable values that are how a layer LOOKS rather than where it is:
    /// the ones a panel row changes. Place, size and angle are the canvas's.
    public static let looks: [MotionProperty] = [.opacity, .color, .blur, .strokeWidth,
                                                  .cornerRadius, .shadow, .glow, .textSize]
}

extension Layer {

    /// The look values keyed on this layer, in `MotionProperty.looks` order.
    var keyedLooks: [MotionProperty] {
        guard let motions, !motions.isEmpty else { return [] }
        let keyed = Set(motions.map(\.property))
        return MotionProperty.looks.filter { keyed.contains($0) }
    }
}

extension PhotonzDocument {

    /// The document with each of these layers wearing its keyed look values
    /// as they are at `ms`: what the panel's rows read, so the Opacity row says
    /// 50 half way through a fade from 100 to 0. Place, size and angle are
    /// left alone (`posedForCanvas` is theirs), and a layer with no keyed look
    /// is left exactly as it is.
    public func lookPosed(layerIDs: [UUID], atDocumentTimeMS ms: Int) -> PhotonzDocument {
        guard hasTime else { return self }
        var posed = self
        for id in layerIDs {
            guard let layer = layer(id: id) else { continue }
            let looks = layer.keyedLooks
            guard !looks.isEmpty else { continue }
            var worn = layer
            for property in looks {
                guard let value = keyedValue(layerID: id, .motion(property), atDocumentTimeMS: ms) else { continue }
                worn = property.applied(value, to: worn, authored: worn)
            }
            if worn != layer { posed.updateLayer(id: id) { $0 = worn } }
        }
        return posed
    }

    /// A panel edit to the look of these layers, made at `ms`.
    ///
    /// `mutate` is the edit exactly as it is made on a still picture, and it
    /// is made against the layers as they LOOK at the playhead
    /// (`lookPosed`). Then, for each layer, every keyed look value the edit
    /// changed becomes a key at the playhead, and every keyed look value goes
    /// back to what the layer holds as its own, so the posing never leaks into
    /// the file. Anything not keyed keeps what the edit did to it, which is the
    /// whole layer's value, as before keys.
    ///
    /// A document with no time, or layers with no keyed look, is simply
    /// `mutate`: nothing about a still picture changes.
    public mutating func editLooks(layerIDs: [UUID], atDocumentTimeMS ms: Int,
                                   ease: KeyEase? = nil,
                                   _ mutate: (inout PhotonzDocument) -> Void) {
        guard hasTime else { return mutate(&self) }
        var stored: [UUID: Layer] = [:]
        for id in layerIDs {
            if let layer = layer(id: id), !layer.keyedLooks.isEmpty { stored[id] = layer }
        }
        guard !stored.isEmpty else { return mutate(&self) }
        let posedDocument = lookPosed(layerIDs: Array(stored.keys), atDocumentTimeMS: ms)
        var posed: [UUID: Layer] = [:]
        for id in stored.keys {
            guard let layer = posedDocument.layer(id: id) else { continue }
            posed[id] = layer
            updateLayer(id: id) { $0 = layer }
        }
        mutate(&self)
        for id in layerIDs {
            guard let kept = stored[id], let was = posed[id], let after = layer(id: id) else { continue }
            var restored = after
            var keys: [(MotionProperty, MotionValue)] = []
            for property in kept.keyedLooks {
                if let now = property.current(of: after), now != property.current(of: was) {
                    keys.append((property, now))
                }
                if let own = kept.keyStill(property), property.current(of: restored) != property.current(of: kept) {
                    restored = property.applied(own, to: restored, authored: restored)
                }
            }
            if restored != after { updateLayer(id: id) { $0 = restored } }
            for (property, value) in keys {
                setKeyedValue(value, layerID: id, .motion(property), atDocumentTimeMS: ms, ease: ease)
            }
        }
    }
}
