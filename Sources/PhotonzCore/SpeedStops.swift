import Foundation

// The edits that put speed stops on a clip and take them off again
// (`SpeedRamp.swift` is what a stop means; this is the verbs). The menu rows
// are Add Speed Stop, Delete Speed Stop and Reset Ramp, and the panel sets a
// stop's speed and how the piece gets between stops.
//
// **Every one of them keeps the frames the piece reads.** A stop changes how
// long the recording takes to play, never which recording is played, so the
// piece's first and last frames stay where they were and its length on the
// timeline follows. Everything after it moves along, by the one gap rule,
// exactly as a plain speed change moves it.

extension ClipPieces {

    /// Put a speed stop on the frame playing at a moment of the clip.
    ///
    /// The first stop on a piece brings two more with it, on the piece's first
    /// and last frames, all three at the speed the piece already plays at. So
    /// adding a stop changes nothing you can see, and setting the new one to
    /// 4x ramps from normal up to fast and back down: the goal of the feature
    /// in one edit. A stop added inside a ramp takes the speed the ramp has
    /// reached there.
    ///
    /// Answers which piece and which of its stops, nil where nothing was
    /// added: a held frame, or a frame that already has a stop.
    public mutating func addSpeedStop(atMS ms: Int) -> (piece: Int, stop: Int)? {
        guard let index = pieceIndex(atMS: ms), let piece = piece(at: index), !piece.isHeld else { return nil }
        let moment = min(max(0, ms), totalLengthMS)
        let frame = piece.sourceMS(atOffsetMS: moment - startMS(ofPiece: index))
        let ramp: SpeedRamp?
        if let existing = piece.speedRamp {
            ramp = existing.adding(SpeedStop(sourceMS: frame,
                                             speedPercent: existing.speedPercent(atSourceMS: frame)))
        } else {
            let speed = piece.speedPercent
            ramp = SpeedRamp(stops: [SpeedStop(sourceMS: piece.sourceInMS, speedPercent: speed),
                                     SpeedStop(sourceMS: piece.sourceOutMS, speedPercent: speed),
                                     SpeedStop(sourceMS: frame, speedPercent: speed)])
        }
        guard let ramp, let stop = ramp.index(ofStopAtSourceMS: frame) else { return nil }
        replaceRamp(ofPiece: index, with: ramp)
        return (index, stop)
    }

    /// Take a stop off. The last one going takes the ramp with it, and the
    /// piece plays at its one speed again, the same as Reset Ramp.
    @discardableResult
    public mutating func deleteSpeedStop(ofPiece index: Int, stop: Int) -> Bool {
        guard let ramp = piece(at: index)?.speedRamp, ramp.stops.indices.contains(stop) else { return false }
        replaceRamp(ofPiece: index, with: ramp.removing(stop: stop))
        return true
    }

    /// Every stop off: the piece plays at the one speed it had before the
    /// first stop went on. False where it had none.
    @discardableResult
    public mutating func resetRamp(ofPiece index: Int) -> Bool {
        guard piece(at: index)?.speedRamp != nil else { return false }
        replaceRamp(ofPiece: index, with: nil)
        return true
    }

    /// A stop at another speed, brought inside what a piece may play at.
    /// Refused for nought (a freeze is Freeze Frame), for a stop that is not
    /// there, and for the speed it already has, so the panel never records an
    /// undo step that changed nothing.
    @discardableResult
    public mutating func setSpeedStop(ofPiece index: Int, stop: Int, percent: Int) -> Bool {
        guard percent > 0, let ramp = piece(at: index)?.speedRamp,
              ramp.stops.indices.contains(stop) else { return false }
        let changed = ramp.setting(stop: stop, toPercent: percent)
        guard changed != ramp else { return false }
        replaceRamp(ofPiece: index, with: changed)
        return true
    }

    /// Ease between the stops, or keep each stretch flat.
    @discardableResult
    public mutating func setRampBlend(ofPiece index: Int, _ blend: SpeedRampBlend) -> Bool {
        guard let ramp = piece(at: index)?.speedRamp, ramp.blend != blend else { return false }
        replaceRamp(ofPiece: index, with: ramp.blending(blend))
        return true
    }

    /// A stop dragged on the speed curve: to `percent`, and, given
    /// `toOffsetMS`, along the piece to land at that moment of it (measured
    /// from the piece's start). The stop stays between its neighbours, and
    /// the first and last stops only move up and down, the way the mock's
    /// ends do. Beside a freeze, nought is taken as the slowest speed. False
    /// for a drag that changes nothing, so a still click records no step.
    @discardableResult
    public mutating func moveSpeedStop(ofPiece index: Int, stop: Int, toOffsetMS target: Int?,
                                       percent: Int) -> Bool {
        guard let piece = piece(at: index), let ramp = piece.speedRamp,
              ramp.stops.indices.contains(stop) else { return false }
        let was = ramp.stops[stop]
        var speed = percent
        if speed <= 0, !ramp.canFreeze(stop: stop) { speed = ClipPiece.slowestPercent }
        let moved = was.atSpeed(speed)
        var frame = was.sourceMS
        if let target, stop > 0, stop < ramp.stops.count - 1 {
            let low = ramp.stops[stop - 1].sourceMS + 1
            let high = ramp.stops[stop + 1].sourceMS - 1
            if low <= high {
                frame = Self.frame(landing: moved, at: Double(target), between: low, and: high,
                                   in: ramp, stop: stop, from: piece.sourceInMS)
            }
        }
        guard let changed = ramp.replacing(stop: stop, with: moved.onFrame(frame)), changed != ramp else {
            return false
        }
        replaceRamp(ofPiece: index, with: changed)
        return true
    }

    /// The frame that puts a stop, at its new speed, at `target` of the
    /// piece's timeline: found by halving, since a stop further into the
    /// recording always plays later.
    private static func frame(landing stop: SpeedStop, at target: Double, between low: Int, and high: Int,
                              in ramp: SpeedRamp, stop index: Int, from sourceIn: Int) -> Int {
        func time(_ frame: Int) -> Double {
            guard let trial = ramp.replacing(stop: index, with: stop.onFrame(frame)) else { return target }
            return trial.timelineMS(fromSourceMS: Double(sourceIn), toSourceMS: Double(frame))
        }
        var low = low, high = high
        while high - low > 1 {
            let middle = (low + high) / 2
            if time(middle) < target { low = middle } else { high = middle }
        }
        return abs(time(low) - target) <= abs(time(high) - target) ? low : high
    }

    /// Whether a stop may become a freeze: not beside another one.
    public func canFreezeSpeedStop(ofPiece index: Int, stop: Int) -> Bool {
        guard let ramp = piece(at: index)?.speedRamp else { return false }
        return ramp.canFreeze(stop: stop)
    }

    /// The mock's Freeze: a stop taken to nought that holds its frame for
    /// `holdMS` before the picture moves off. Refused beside another freeze.
    @discardableResult
    public mutating func freezeSpeedStop(ofPiece index: Int, stop: Int, holdMS: Int) -> Bool {
        guard canFreezeSpeedStop(ofPiece: index, stop: stop), let ramp = piece(at: index)?.speedRamp,
              let changed = ramp.replacing(stop: stop, with: ramp.stops[stop].atSpeed(0).holding(holdMS)),
              changed != ramp else { return false }
        replaceRamp(ofPiece: index, with: changed)
        return true
    }

    /// How long a freeze holds its frame: the second zero dragged along.
    /// False for a stop that is not a freeze, and for the hold it has.
    @discardableResult
    public mutating func setSpeedStopHold(ofPiece index: Int, stop: Int, holdMS: Int) -> Bool {
        guard let ramp = piece(at: index)?.speedRamp, ramp.stops.indices.contains(stop),
              ramp.stops[stop].isFreeze,
              let changed = ramp.replacing(stop: stop, with: ramp.stops[stop].holding(holdMS)),
              changed != ramp else { return false }
        replaceRamp(ofPiece: index, with: changed)
        return true
    }

    /// Where on the clip's own clock a stop's frame plays, kept inside the
    /// piece: a stop a trim left outside it answers the nearer edge.
    public func timelineMS(ofStop stop: Int, inPiece index: Int) -> Int? {
        guard let piece = piece(at: index), let ramp = piece.speedRamp,
              ramp.stops.indices.contains(stop),
              let offset = piece.offsetMS(ofSourceMS: ramp.stops[stop].sourceMS) else { return nil }
        return startMS(ofPiece: index) + min(max(0, offset), piece.lengthMS)
    }

    private mutating func replaceRamp(ofPiece index: Int, with ramp: SpeedRamp?) {
        guard let piece = piece(at: index) else { return }
        var all = pieces
        all[index] = piece.reramped(ramp)
        self = ClipPieces(pieces: all, sourceLengthMS: sourceLengthMS)
    }
}

// MARK: - In the document

extension PhotonzDocument {

    /// Put a speed stop on a clip at a moment of the DOCUMENT's clock, where
    /// the playhead is. Nil outside the clip, on a held frame, and on a frame
    /// that already has one.
    public mutating func addSpeedStop(_ id: UUID, atMS ms: Int) -> (piece: Int, stop: Int)? {
        var added: (piece: Int, stop: Int)?
        _ = editClip(id) { pieces, time in
            guard ms >= time.inMS, ms < time.outMS else { return false }
            added = pieces.addSpeedStop(atMS: ms - time.inMS)
            return added != nil
        }
        return added
    }

    @discardableResult
    public mutating func deleteSpeedStop(_ id: UUID, ofPiece index: Int, stop: Int) -> Bool {
        editClip(id) { pieces, _ in pieces.deleteSpeedStop(ofPiece: index, stop: stop) }
    }

    @discardableResult
    public mutating func resetRamp(_ id: UUID, ofPiece index: Int) -> Bool {
        editClip(id) { pieces, _ in pieces.resetRamp(ofPiece: index) }
    }

    @discardableResult
    public mutating func setSpeedStop(_ id: UUID, ofPiece index: Int, stop: Int, percent: Int) -> Bool {
        editClip(id) { pieces, _ in pieces.setSpeedStop(ofPiece: index, stop: stop, percent: percent) }
    }

    @discardableResult
    public mutating func setRampBlend(_ id: UUID, ofPiece index: Int, _ blend: SpeedRampBlend) -> Bool {
        editClip(id) { pieces, _ in pieces.setRampBlend(ofPiece: index, blend) }
    }

    /// A stop dragged on the speed curve, `toClipMS` measured from the clip's
    /// start (`ClipPieces.moveSpeedStop`).
    @discardableResult
    public mutating func moveSpeedStop(_ id: UUID, ofPiece index: Int, stop: Int, toClipMS: Int?,
                                       percent: Int) -> Bool {
        editClip(id) { pieces, _ in
            let offset = toClipMS.map { $0 - pieces.startMS(ofPiece: index) }
            return pieces.moveSpeedStop(ofPiece: index, stop: stop, toOffsetMS: offset, percent: percent)
        }
    }

    @discardableResult
    public mutating func freezeSpeedStop(_ id: UUID, ofPiece index: Int, stop: Int, holdMS: Int) -> Bool {
        editClip(id) { pieces, _ in pieces.freezeSpeedStop(ofPiece: index, stop: stop, holdMS: holdMS) }
    }

    @discardableResult
    public mutating func setSpeedStopHold(_ id: UUID, ofPiece index: Int, stop: Int, holdMS: Int) -> Bool {
        editClip(id) { pieces, _ in pieces.setSpeedStopHold(ofPiece: index, stop: stop, holdMS: holdMS) }
    }
}

/// What the speed stop rows are called, in menus and walks alike: the mock's
/// rows, in the Mac's Title Case (UX-PATTERNS §7).
public enum SpeedStopNames {
    public static let add = "Add Speed Stop"
    public static let delete = "Delete Speed Stop"
    public static let reset = "Reset Ramp"

    /// The speeds a stop's Speed list offers: the mock's Freeze first, then
    /// every speed a piece can play at.
    public static let speeds: [Int] = [0] + ClipSpeed.stops

    /// How long Freeze holds the stop's frame when it is picked from the
    /// list: the mock's two zeros side by side, a second apart.
    public static let freezeHoldMS = 1000

    /// The mock's note under Between stops, word for word, behind the row's
    /// question mark: longer than a panel line may be (UX-PATTERNS §4).
    public static let betweenStopsHelp = "Ramp eases between stops for a smooth speed ramp. Hold keeps each section "
        + "flat. A stop at zero holds a single frame, so two zeros side by side make a freeze."

    /// A speed as the stop's Speed list says it.
    public static func speedTitle(_ percent: Int) -> String {
        percent == 0 ? "Freeze" : ClipSpeed.title(percent)
    }
}
