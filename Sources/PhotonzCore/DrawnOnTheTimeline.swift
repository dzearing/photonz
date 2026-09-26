import CoreGraphics
import Foundation

/// **Anything drawn on a video is on the timeline**
/// (`anything-you-draw-on-a-video-gets-its-own-row-on`).
///
/// Drag a rectangle over a recording and it is a thing with a start and an
/// end, on a row of its own, the way After Effects and Premiere put every new
/// graphic on the timeline: its bar says when it is on screen, and it can be
/// keyed where it is and keyed again somewhere else to move between the two.
///
/// Before this, only words were given a stretch (`TitleTime.swift`); a shape,
/// a line, a picture or a lens drawn on a recording stood over the whole film
/// with no row, no in and no out, and nowhere its keys could show until it was
/// already moving.
public enum DrawnTime {
    /// How long something drawn with the playhead at the very end runs for,
    /// ending there. Premiere's default length for a still.
    public static let atTheEndMS = 5000
    /// Less than this left of the clip under the playhead counts as the end:
    /// a bar a frame long is a bar nobody can take hold of.
    public static let nearTheEndMS = 500
}

extension PhotonzDocument {

    /// The stretch something newly drawn at `ms` occupies, or nil in a
    /// document with no time in it (every screenshot and every drawing).
    ///
    /// **On a held frame it takes the hold**, the rule `HeldFrame` set for a
    /// mark on a frozen frame. **Anywhere else it runs from the playhead to the
    /// end of the clip under it**, so it stays up for the shot it was drawn on.
    /// With no clip under the playhead it runs five seconds, and drawn at the
    /// very end it takes the last five seconds, ending there, so it is still on
    /// screen where it was drawn.
    public func drawnSpan(atTimeMS ms: Int) -> LayerTime? {
        guard hasTime else { return nil }
        if let held = heldFrame(atTimeMS: ms) { return held.span }
        let end = documentDurationMS
        let start = min(max(0, ms), end)
        let until = pictureClipOut(atTimeMS: start) ?? min(end, start + DrawnTime.atTheEndMS)
        if until - start >= DrawnTime.nearTheEndMS {
            return LayerTime(inMS: start, outMS: until)
        }
        let finish = max(until, LayerTime.shortestMS)
        return LayerTime(inMS: max(0, finish - DrawnTime.atTheEndMS), outMS: finish)
    }

    /// Where the topmost picture clip playing at `ms` ends.
    func pictureClipOut(atTimeMS ms: Int) -> Int? {
        layers.last { layer in
            guard layer.hasMediaBehindIt, layer.clipTrackKind == .video,
                  let time = layer.time else { return false }
            return time.contains(ms: ms)
        }?.time?.outMS
    }

    /// A layer drawn on the picture at a moment (`addLayerDrawn`), and, where
    /// `placingInTime`, given the stretch `drawnSpan` says, which is what puts
    /// it on a row of the timeline. Something that already has a stretch keeps
    /// it. Without `placingInTime` this is exactly what it always was.
    public mutating func addLayerDrawn(_ layer: Layer, atTimeMS ms: Int, placingInTime: Bool) {
        var drawn = layer
        if placingInTime, drawn.time == nil, let span = drawnSpan(atTimeMS: ms) {
            drawn.time = span
        }
        addLayerDrawn(drawn, atTimeMS: ms)
    }
}

// MARK: - One press keys where it is

extension PhotonzDocument {

    /// What the key diamond on a row's header keys: where it is, how big, how
    /// turned and how faded, the four values After Effects puts under a
    /// layer's Transform.
    public static let transformKeyProperties: [MotionProperty] = [.position, .scale, .rotation, .opacity]

    private func transformKeyed(_ layerID: UUID) -> [KeyedProperty] {
        guard let layer = layer(id: layerID) else { return [] }
        let keyable = Set(layer.keyableProperties)
        return Self.transformKeyProperties.map { KeyedProperty.motion($0) }.filter { keyable.contains($0) }
    }

    /// The header diamond: on a key where any of the four has a key at the
    /// playhead, between keys where any of them is keyed, dormant otherwise.
    public func transformKeyDiamond(layerID: UUID, atDocumentTimeMS ms: Int) -> KeyDiamond {
        let states = transformKeyed(layerID).map { keyDiamond(layerID: layerID, $0, atDocumentTimeMS: ms) }
        if states.contains(.onKey) { return .onKey }
        if states.contains(.betweenKeys) { return .betweenKeys }
        return .dormant
    }

    /// The header diamond, pressed, as Premiere's diamond: on a key, the keys
    /// here go (the last one taking the keying with it and keeping the value);
    /// anywhere else, every one of the four gets a key here holding the value
    /// it has now. Once keyed, a drag or a resize on the canvas somewhere else
    /// makes the next key by itself (`foldEditIntoKeys`).
    @discardableResult
    public mutating func toggleTransformKey(layerID: UUID, atDocumentTimeMS ms: Int,
                                            ease: KeyEase? = nil) -> Bool {
        let properties = transformKeyed(layerID)
        guard !properties.isEmpty else { return false }
        var changed = false
        if transformKeyDiamond(layerID: layerID, atDocumentTimeMS: ms) == .onKey {
            for property in properties {
                changed = removeKey(layerID: layerID, property, atDocumentTimeMS: ms) || changed
            }
            return changed
        }
        for property in properties {
            if keyCount(layerID: layerID, property) == 0 {
                changed = startKeying(layerID: layerID, property, atDocumentTimeMS: ms, ease: ease) || changed
            } else if let value = keyedValue(layerID: layerID, property, atDocumentTimeMS: ms) {
                changed = setKeyedValue(value, layerID: layerID, property,
                                        atDocumentTimeMS: ms, ease: ease) || changed
            }
        }
        return changed
    }
}
