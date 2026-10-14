import CoreGraphics
import Foundation

// Dragging on the canvas with a row picked moves that whole animation
// (`dragging-on-the-canvas-with-a-row-picked-moves-t`,
// `docs/design/mocks/pages/video-animate.html`, the interaction table: "Drag
// on the canvas, a row picked | Canvas | Moves every key of that row by the
// same amount (for Position, the whole path), instead of keying the
// playhead").
//
// On a layer with keys every change keys itself, so this is the one way to
// move an animation that is already right somewhere else: pick the row by its
// name and drag. What the hand did to the row's value at the playhead is done
// to every key of the row instead. A path's bends are stated against its own
// chords (`MotionPathSegment.bend`), so they travel with it unchanged.

extension MotionValue {

    /// This value moved by however far `was` is from `now`, or nil where the
    /// three are not numbers or points alike. A colour has no amount.
    func shifted(from was: MotionValue, to now: MotionValue) -> MotionValue? {
        switch (self, was, now) {
        case let (.number(value), .number(from), .number(to)):
            return .number(value + (to - from))
        case let (.point(value), .point(from), .point(to)):
            return .point(CGPoint(x: value.x + (to.x - from.x), y: value.y + (to.y - from.y)))
        default:
            return nil
        }
    }
}

extension LayerMotion {

    /// This motion with every key's value moved by however far `was` is from
    /// `now`, and its moments, eases, handles, bends and curves as they were.
    /// Nil where the values cannot be moved by an amount (a colour).
    public func shiftingEveryKey(from was: MotionValue, to now: MotionValue) -> LayerMotion? {
        guard let from = from.shifted(from: was, to: now),
              let to = to.shifted(from: was, to: now) else { return nil }
        var moved = self
        moved.from = settled(from)
        moved.to = settled(to)
        if let stops {
            var shifted: [MotionStop] = []
            for stop in stops {
                guard let value = stop.value.shifted(from: was, to: now) else { return nil }
                var carried = stop
                carried.value = settled(value)
                shifted.append(carried)
            }
            moved.stops = shifted
        }
        return moved
    }

    /// A size never goes through nothing and out the other side: a shrink
    /// that would take the smallest key past zero leaves it at one per cent.
    private func settled(_ value: MotionValue) -> MotionValue {
        guard property == .scale, case let .number(percent) = value else { return value }
        return .number(max(1, percent))
    }
}

extension PhotonzDocument {

    /// A hand's edit on the canvas with one row of a layer picked by its
    /// name: whatever the edit does to that row's value at the playhead is
    /// done to EVERY key of the row, so a Position row's whole path moves, and
    /// no key is written at the playhead on it. Anything else the edit changes
    /// keys at the playhead as `editPosedForCanvas` always does (a resize with
    /// Position picked still keys Scale there), and an edit that leaves the
    /// row's value alone is exactly `editPosedForCanvas`.
    public mutating func editShiftingRow(layerID: UUID, motionID: UUID, atDocumentTimeMS ms: Int,
                                         ease: KeyEase? = nil,
                                         _ mutate: (inout PhotonzDocument) -> Void) {
        var edited = self
        edited.editPosedForCanvas(layerID: layerID, atDocumentTimeMS: ms, ease: ease, mutate)
        guard let row = layer(id: layerID)?.motions?.first(where: { $0.id == motionID }) else {
            self = edited
            return
        }
        let property = KeyedProperty.motion(row.property, effect: row.effectOrdinal)
        guard let was = keyedValue(layerID: layerID, property, atDocumentTimeMS: ms),
              let now = edited.keyedValue(layerID: layerID, property, atDocumentTimeMS: ms),
              was != now, let shifted = row.shiftingEveryKey(from: was, to: now) else {
            self = edited
            return
        }
        // The fold keyed the row at the playhead; the row as it was, moved
        // whole, goes in its place.
        edited.updateLayer(id: layerID) { layer in
            if layer.motions?.contains(where: { $0.id == motionID }) == true {
                layer.motions = layer.motions?.map { $0.id == motionID ? shifted : $0 }
            } else {
                layer.motions = (layer.motions ?? []) + [shifted]
            }
        }
        self = edited
    }
}
