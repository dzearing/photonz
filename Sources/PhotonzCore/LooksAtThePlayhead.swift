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
                                                  .cornerRadius, .shadow, .shadowDistance,
                                                  .shadowDirection, .shadowColor, .shadowOpacity,
                                                  .glow, .glowColor, .glowOpacity, .borderWidth,
                                                  .borderColor, .textSize]
}

extension Layer {

    /// The look values keyed on this layer, in `MotionProperty.looks` order,
    /// each with which shadow, glow or border it belongs to (nought for
    /// everything else, and for the first of those).
    var keyedLooks: [(MotionProperty, Int)] {
        guard let motions, !motions.isEmpty else { return [] }
        return MotionProperty.looks.flatMap { property in
            Set(motions.filter { $0.property == property }.map(\.effectOrdinal)).sorted().map { (property, $0) }
        }
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
            for (property, effect) in looks {
                guard let value = keyedValue(layerID: id, .motion(property, effect: effect),
                                             atDocumentTimeMS: ms) else { continue }
                worn = property.applied(value, to: worn, authored: worn, effect: effect)
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
            var keys: [(KeyedProperty, MotionValue)] = []
            for (property, effect) in kept.keyedLooks {
                if let now = property.current(of: after, effect: effect),
                   now != property.current(of: was, effect: effect) {
                    keys.append((.motion(property, effect: effect), now))
                }
                if let own = kept.keyStill(property, effect: effect),
                   property.current(of: restored, effect: effect) != property.current(of: kept, effect: effect) {
                    restored = property.applied(own, to: restored, authored: restored, effect: effect)
                }
            }
            if restored != after { updateLayer(id: id) { $0 = restored } }
            for (property, value) in keys {
                setKeyedValue(value, layerID: id, property, atDocumentTimeMS: ms, ease: ease)
            }
        }
    }
}

// MARK: - What the look rows can tell apart

extension Layer {

    /// This layer with every key on where it is, how big and how turned left
    /// out, its children's too, and the keys on how it looks kept. No keys
    /// and an empty list of them are the same thing here.
    var withoutPlacementKeys: Layer {
        var layer = self
        if let motions {
            let looks = motions.filter { MotionProperty.lookSet.contains($0.property) }
            layer.motions = looks.isEmpty ? nil : looks
        }
        if isGroup { layer.children = children.map(\.withoutPlacementKeys) }
        return layer
    }
}

extension MotionProperty {
    /// `looks`, for asking of every key on every layer.
    static let lookSet = Set(looks)
}

extension PhotonzDocument {

    /// Whether the two are the same apart from keys on where a layer is, how
    /// big and how turned (task `keying-a-value-redraws-only-what-the-key-changes`).
    ///
    /// The panel's look sections (Text, Appearance, Effects, Time) read the
    /// layers as they are, and their look values at the playhead
    /// (`lookPosed`), and nothing else about keys. A key on Position changes
    /// none of that, so a document that differs from the last one only there
    /// is one those sections have already drawn.
    ///
    /// Layer by layer, so a layer nothing touched costs one comparison, and
    /// only a layer that differs is compared again with its placement keys
    /// left out.
    public func sameApartFromPlacementKeys(_ other: PhotonzDocument) -> Bool {
        guard Self.layersMatchApartFromPlacementKeys(layers, other.layers),
              Self.layersMatchApartFromPlacementKeys(componentOriginals, other.componentOriginals)
        else { return false }
        var mine = self, theirs = other
        mine.layers = []
        theirs.layers = []
        mine.componentOriginals = []
        theirs.componentOriginals = []
        return mine == theirs
    }

    private static func layersMatchApartFromPlacementKeys(_ a: [Layer], _ b: [Layer]) -> Bool {
        guard a.count == b.count else { return false }
        for index in a.indices where a[index] != b[index] {
            guard a[index].withoutPlacementKeys == b[index].withoutPlacementKeys else { return false }
        }
        return true
    }
}
