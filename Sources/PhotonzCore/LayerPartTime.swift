import CoreGraphics
import Foundation

// A part of something placed in time, with a stretch of its own (task
// `any-timeline-row-that-holds-sub-layers-expands-a`).
//
// **The timeline is the layers list with a time axis.** Every row it lists has
// a bar for when that layer is on screen, and a part of a logo, a group or a
// component is a row like any other: dragging its bar's ends or middle changes
// when that part is on screen and nothing else.
//
// A part has no `LayerTime` of its own, and must not: a stretch written on the
// document's clock is left behind when the thing it is inside moves, which is
// how a part goes missing while its parent is on screen (`placeInTime`). So a
// part's stretch is written on the CLOCK OF THE THING IT IS INSIDE, the same
// clock its motions already run on (`DocumentTime.movedTree`): it travels with
// its parent, and it is never drawn outside its parent's stretch.

/// A part's own stretch, on the clock of the layer it is inside.
public struct LayerPartTime: Hashable, Codable, Sendable {
    /// When it comes on, on its parent's clock.
    public var fromMS: Int
    /// When it goes.
    public var toMS: Int
    /// How far the part's own clock runs behind its parent's. Sliding a bar's
    /// middle moves this with it, so the part's keys travel with its bar the
    /// way a layer's do in After Effects; trimming an end leaves it, so a key
    /// stays where it happens.
    public var shiftMS: Int

    public init(fromMS: Int, toMS: Int, shiftMS: Int = 0) {
        self.fromMS = fromMS
        self.toMS = max(toMS, fromMS + LayerTime.shortestMS)
        self.shiftMS = shiftMS
    }

    func contains(clockMS ms: Int) -> Bool { ms >= fromMS && ms < toMS }
}

/// Where a part's bar is on the document's clock, and the stretch it has to
/// stay inside: the thing it is inside, on screen.
public struct LayerPartStretch: Hashable, Sendable {
    public var layerID: UUID
    public var startMS: Int
    public var endMS: Int
    public var boundsStartMS: Int
    public var boundsEndMS: Int
    /// The part has a stretch of its own, rather than running across its
    /// parent's.
    public var hasOwnTime: Bool
    /// Inside a copy of a component, whose contents are its original's: drawn,
    /// never retimed, since the next sync would undo it.
    public var isInsideACopy: Bool
}

extension PhotonzDocument {

    /// Where part `id`'s bar runs, on the document's clock. Nil for anything
    /// that is not a part of something placed in time: a layer at the top, a
    /// layer with a stretch of its own (a clip in a group), a part of a group
    /// that is simply there the whole way through.
    public func partStretch(of id: UUID) -> LayerPartStretch? {
        guard let path = path(of: id), path.count > 1 else { return nil }
        var list = layers
        // The clock of the layer being walked: the document moment its clock
        // reads nought at, and where it is on screen.
        var origin = 0
        var bounds: (Int, Int)?
        var insideCopy = false
        for (depth, index) in path.enumerated() {
            guard list.indices.contains(index) else { return nil }
            let layer = list[index]
            let isTarget = depth == path.count - 1
            if isTarget {
                guard layer.time == nil, let window = bounds else { return nil }
                let own = Self.partWindow(layer, parentOrigin: origin, parentBounds: window)
                return LayerPartStretch(layerID: id, startMS: own.0, endMS: own.1,
                                        boundsStartMS: window.0, boundsEndMS: window.1,
                                        hasOwnTime: layer.partTime != nil, isInsideACopy: insideCopy)
            }
            if let time = layer.time {
                origin = time.inMS - time.sourceInMS
                let start = max(time.inMS, bounds?.0 ?? time.inMS)
                bounds = (start, max(start, min(time.outMS, bounds?.1 ?? time.outMS)))
            } else if let window = bounds {
                bounds = Self.partWindow(layer, parentOrigin: origin, parentBounds: window)
                origin += layer.partTime?.shiftMS ?? 0
            }
            if layer.isComponentInstance { insideCopy = true }
            list = layer.children
        }
        return nil
    }

    /// A part's stretch on the document's clock, inside its parent's.
    private static func partWindow(_ layer: Layer, parentOrigin: Int,
                                   parentBounds: (Int, Int)) -> (Int, Int) {
        guard let part = layer.partTime else { return parentBounds }
        let start = min(max(parentOrigin + part.fromMS, parentBounds.0), parentBounds.1)
        let end = max(min(parentOrigin + part.toMS, parentBounds.1), start)
        return (start, end)
    }

    /// The document moment part `id`'s PARENT's clock reads nought at.
    private func parentClockOrigin(of id: UUID) -> Int? {
        guard let path = path(of: id), path.count > 1 else { return nil }
        var list = layers
        var origin = 0
        for index in path.dropLast() {
            guard list.indices.contains(index) else { return nil }
            let layer = list[index]
            if let time = layer.time {
                origin = time.inMS - time.sourceInMS
            } else {
                origin += layer.partTime?.shiftMS ?? 0
            }
            list = layer.children
        }
        return origin
    }

    /// Drag part `id`'s bar: its start or its end by `byMS`, or the whole bar,
    /// inside the thing it is inside and never shorter than a frame. Nothing
    /// else in the document changes. False, leaving everything as it was,
    /// where nothing would change or the part is not one that can be retimed.
    @discardableResult
    public mutating func retimePart(_ id: UUID, grab: TitlePartGrab, byMS delta: Int) -> Bool {
        guard let stretch = partStretch(of: id), !stretch.isInsideACopy,
              let origin = parentClockOrigin(of: id), let layer = layer(id: id), !layer.isLocked
        else { return false }
        let shortest = LayerTime.shortestMS
        var start = stretch.startMS
        var end = stretch.endMS
        var slid = 0
        switch grab {
        case .start:
            start = min(max(stretch.startMS + delta, stretch.boundsStartMS), stretch.endMS - shortest)
        case .end:
            end = max(min(stretch.endMS + delta, stretch.boundsEndMS), stretch.startMS + shortest)
        case .body:
            slid = min(max(delta, stretch.boundsStartMS - stretch.startMS), stretch.boundsEndMS - stretch.endMS)
            start += slid
            end += slid
        }
        guard start != stretch.startMS || end != stretch.endMS else { return false }
        let shift = (layer.partTime?.shiftMS ?? 0) + slid
        let whole = start == stretch.boundsStartMS && end == stretch.boundsEndMS && shift == 0
        updateLayer(id: id) {
            $0.partTime = whole ? nil : LayerPartTime(fromMS: start - origin, toMS: end - origin, shiftMS: shift)
        }
        return true
    }
}
