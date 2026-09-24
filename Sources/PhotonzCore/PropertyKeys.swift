import CoreGraphics
import Foundation

// Every value in the panel has a key diamond
// (task `every-value-in-the-panel-has-a-key-diamond`,
// `docs/design/mocks/pages/video.html`, "THE KEY TOGGLE").
//
// Premiere's stopwatch, said in this app's model. A diamond beside a value
// starts keying it, with one key at the playhead. From then on, changing that
// value at another moment, in the panel or on the canvas, puts a key there.
// The diamond reads its own state, and two arrows step to the key before and
// after.
//
// **There is no second model.** A keyed value IS a `LayerMotion` that plays
// once: its keys are its From, its stops and its To, which is exactly what a
// title's fade and a punch-in already are, so both read as keys here without a
// line converted. A keyed VOLUME is the level points the mixer already follows
// for playback and export (`AudioLevel`), because a second volume curve would
// be two answers to how loud something is.
//
// Keys are nailed to the layer's OWN clock: a clip's recording, a title's own
// start (`Layer.motionClockMS(atDocumentTimeMS:)`). So a key on a clip stays on
// the frame it was set on when the clip is trimmed, split or moved, the same
// promise a punch-in makes.

/// One value of a layer that can be keyed.
public enum KeyedProperty: Hashable, Sendable {
    /// Anything a motion can change: where it is, how big, how turned, how
    /// faded, how round, how soft, how big its type is.
    case motion(MotionProperty)
    /// How loud it plays, in decibels. Kept as the mixer's own level points.
    case volume

    /// What its row is called.
    public var title: String {
        switch self {
        case let .motion(property): property.title
        case .volume: "Volume"
        }
    }
}

/// What a key diamond shows, and the three have to be told apart at 8pt
/// (`video.html`, `.kfkey`).
public enum KeyDiamond: Hashable, Sendable {
    /// Not keyed at all: a dim outline, the quietest thing in the row.
    case dormant
    /// Keyed, with no key at the playhead: a coloured outline.
    case betweenKeys
    /// Keyed, and a key sits right here: filled.
    case onKey
}

public enum PropertyKeys {
    /// How near the playhead a key has to be to count as ON it. A little over
    /// one frame at 30 frames a second: a playhead parked by hand is never
    /// exactly on the millisecond a key was set at, and a diamond that goes
    /// hollow one frame off the key it is sitting on reads as broken.
    public static let nearMS = 20

    /// The curve a new key runs on to the next one. The mock's own default,
    /// and the one that reads as a camera move rather than a machine.
    public static let curve: EasingCurve = .easeInOut

    /// The quietest a volume row says: past this there is nothing to hear.
    public static let quietestDecibels: Double = -60
}

// MARK: - A motion read as keys

extension LayerMotion {

    /// Every key on this motion, first to last, in the layer's own clock.
    ///
    /// The same list as `keys`, except for a property keyed only ONCE. A
    /// motion always has a From and a To a millisecond apart at least
    /// (`MotionTiming`), so one key is written as a span of one millisecond
    /// whose two ends agree, and read back here as the one key it is.
    public var keyframes: [MotionStop] {
        let list = keys
        if list.count == 2, timing.durationMS <= 1, from == to {
            return [list[0]]
        }
        return list
    }

    /// This motion with key `index` (of `keyframes`) eased the way a right
    /// click on it says. Nothing else about it changes.
    public func easing(key index: Int, _ ease: KeyEase) -> LayerMotion {
        var list = keyframes
        guard list.indices.contains(index) else { return self }
        if ease == .bezier, list[index].handles == nil || list[index].ease != .bezier {
            // Bezier starts from the shape the key already makes, so choosing
            // it changes nothing until a handle is dragged.
            let now = list[index].ease ?? KeyEase(following: curve)
            list[index].handles = KeyHandles.implied(by: now == .bezier ? .easeInAndOut : now)
        } else if ease != .bezier {
            // Only a Bezier key keeps handles: any other ease draws its own.
            list[index].handles = nil
        }
        list[index].ease = ease
        return rebuilt(from: list)
    }

    /// This motion with one handle of key `index` (of `keyframes`) moved to
    /// `point`, in the unit square of the stretch that handle shapes. The key
    /// becomes a Bezier key, the way dragging a handle does in Premiere.
    public func settingHandle(key index: Int, _ side: KeyHandleSide, to point: CGPoint) -> LayerMotion {
        var shaped = easing(key: index, .bezier)
        var list = shaped.keyframes
        guard list.indices.contains(index), var handles = list[index].handles else { return self }
        switch side {
        case .arriving: handles.arriving = point
        case .leaving: handles.leaving = point
        }
        list[index].handles = KeyHandles(arriving: handles.arriving, leaving: handles.leaving)
        shaped = shaped.rebuilt(from: list)
        return shaped
    }

    /// A property keyed for the first time, with one key.
    public static func keyed(_ property: MotionProperty, atMS ms: Int,
                             value: MotionValue) -> LayerMotion {
        LayerMotion(property: property, from: value, to: value,
                    timing: MotionTiming(startMS: max(0, ms), durationMS: 1),
                    curve: PropertyKeys.curve, repeats: .once,
                    pivot: property == .rotation ? .centre : nil)
    }

    /// The key within `PropertyKeys.nearMS` of a moment, if there is one.
    public func keyIndex(near ms: Int) -> Int? {
        let list = keyframes
        let near = list.indices.filter { abs(list[$0].atMS - ms) <= PropertyKeys.nearMS }
        return near.min { abs(list[$0].atMS - ms) < abs(list[$1].atMS - ms) }
    }

    /// This motion with a key at `ms` holding `value`. A key already that
    /// close is rewritten where it stands rather than joined by a second one a
    /// few milliseconds away.
    public func settingKey(atMS ms: Int, value: MotionValue) -> LayerMotion {
        var list = keyframes
        if let index = keyIndex(near: ms) {
            list[index].value = value
        } else {
            list.append(MotionStop(atMS: max(0, ms), value: value))
        }
        return rebuilt(from: list)
    }

    /// This motion without the key near `ms`, or nil when that was its last.
    public func removingKey(atMS ms: Int) -> LayerMotion? {
        guard let index = keyIndex(near: ms) else { return self }
        var list = keyframes
        list.remove(at: index)
        return list.isEmpty ? nil : rebuilt(from: list)
    }

    /// The same motion carrying exactly these keys: the first is From, the
    /// last is To, the rest are stops. It plays once and holds either side,
    /// which is what a key means in a document that finishes.
    func rebuilt(from list: [MotionStop]) -> LayerMotion {
        let sorted = list.sorted { $0.atMS < $1.atMS }
        var made = self
        made.repeats = .once
        guard let first = sorted.first, let last = sorted.last else { return made }
        made.from = first.value
        made.fromEase = first.ease
        made.fromHandles = first.handles
        if sorted.count == 1 {
            made.to = first.value
            made.toEase = first.ease
            made.toHandles = first.handles
            made.timing = MotionTiming(startMS: first.atMS, durationMS: 1)
            made.stops = nil
            return made
        }
        made.to = last.value
        made.toEase = last.ease
        made.toHandles = last.handles
        made.timing = MotionTiming(startMS: first.atMS, durationMS: max(1, last.atMS - first.atMS))
        let middle = Array(sorted.dropFirst().dropLast())
        made.stops = middle.isEmpty ? nil : middle
        return made
    }
}

// MARK: - What a layer can key

extension Layer {

    /// The values this layer's panel offers a diamond for, in the order the
    /// mock lists them: where, how big, how turned, how faded, then how it
    /// looks, then how loud.
    ///
    /// Every one the layer HAS, keyed or not, so "how do I animate this?" has
    /// a visible answer on a layer nobody has touched: the dim diamond on its
    /// row (`video.html`, "Resolved - what the dock is for").
    public var keyableProperties: [KeyedProperty] {
        var list: [KeyedProperty] = []
        if !isSoundOnly {
            let order: [MotionProperty] = [.position, .scale, .rotation, .opacity, .cornerRadius,
                                           .strokeWidth, .color, .blur, .shadow, .textSize]
            for property in order where keyStill(property) != nil {
                list.append(.motion(property))
            }
        }
        if sound != nil { list.append(.volume) }
        return list
    }

    /// What a property reads when nothing keys it: the layer's own value, or
    /// nothing for an effect it has not got yet, which a key can bring in.
    func keyStill(_ property: MotionProperty) -> MotionValue? {
        if let value = property.current(of: self) { return value }
        switch property {
        case .blur, .shadow: return isSoundOnly ? nil : .number(0)
        default: return nil
        }
    }

    /// The motion that keys this property, if it is keyed.
    public func keyedMotion(_ property: MotionProperty) -> LayerMotion? {
        (motions ?? []).first { $0.property == property }
    }

    /// Writes a value as the layer's own, unkeyed. Scale has no value of its
    /// own to hold (a layer is always 100% of itself), so a still scale is the
    /// layer drawn that much larger about its middle.
    mutating func setKeyStill(_ property: MotionProperty, _ value: MotionValue) {
        if property == .scale {
            guard case let .number(percent) = value, percent > 0, percent != 100 else { return }
            let box = frame.standardized
            self = drawnLarger(by: CGFloat(percent) / 100, about: CGPoint(x: box.midX, y: box.midY))
            return
        }
        self = property.applied(value, to: self, authored: self)
    }

    /// The moment of the DOCUMENT a moment of this layer's own clock plays
    /// at, or nil where that part of it is not in the cut. The inverse of
    /// `motionClockMS(atDocumentTimeMS:)`, which is what lets an arrow step to
    /// a key and land the playhead on it.
    public func documentTimeMS(atMotionClockMS clock: Int) -> Int? {
        guard let time else { return clock }
        if let pieces = clipPieces {
            for piece in pieces.playback where piece.speedPercent > 0 {
                guard clock >= piece.sourceInMS,
                      clock <= piece.sourceInMS + piece.sourceLengthMS else { continue }
                let offset = (clock - piece.sourceInMS) * 100 / piece.speedPercent
                return time.inMS + piece.startMS + min(max(0, offset), max(0, piece.lengthMS - 1))
            }
            return nil
        }
        let moment = time.inMS + clock - time.sourceInMS
        guard moment >= time.inMS - PropertyKeys.nearMS,
              moment <= time.outMS + PropertyKeys.nearMS else { return nil }
        // A key on the very last moment (a fade's end) sits where the layer
        // has just gone; the last frame it is still on is the one to land on.
        return min(max(moment, time.inMS), time.outMS - 1)
    }

    /// Where a volume point is measured from: the layer's own in, which is
    /// what the mixer reads them against (`AudioLevel.gain(atLayerMS:)`).
    func volumeClockMS(atDocumentTimeMS ms: Int) -> Int { ms - (time?.inMS ?? 0) }
}

// MARK: - The document's answers, at the playhead

extension PhotonzDocument {

    private func keyClock(of layer: Layer, _ property: KeyedProperty, atDocumentTimeMS ms: Int) -> Int {
        switch property {
        case .motion: layer.motionClockMS(atDocumentTimeMS: ms)
        case .volume: layer.volumeClockMS(atDocumentTimeMS: ms)
        }
    }

    private func keyCycle(of layer: Layer) -> Int {
        layer.motionCycleMS(documentCycleMS: max(1, documentDurationMS))
    }

    /// The moments, in the layer's own clock, this property is keyed at.
    private func keyMoments(of layer: Layer, _ property: KeyedProperty) -> [Int] {
        switch property {
        case let .motion(motion): layer.keyedMotion(motion)?.keyframes.map(\.atMS) ?? []
        case .volume: layer.soundLevel?.points.map(\.atMS) ?? []
        }
    }

    /// How many keys this property has. Nought is not keyed.
    public func keyCount(layerID: UUID, _ property: KeyedProperty) -> Int {
        guard let layer = layer(id: layerID) else { return 0 }
        return keyMoments(of: layer, property).count
    }

    /// What the diamond beside this value shows with the playhead at `ms`.
    public func keyDiamond(layerID: UUID, _ property: KeyedProperty,
                           atDocumentTimeMS ms: Int) -> KeyDiamond {
        guard let layer = layer(id: layerID) else { return .dormant }
        let moments = keyMoments(of: layer, property)
        guard !moments.isEmpty else { return .dormant }
        let clock = keyClock(of: layer, property, atDocumentTimeMS: ms)
        return moments.contains { abs($0 - clock) <= PropertyKeys.nearMS } ? .onKey : .betweenKeys
    }

    /// The value this property has at `ms`: between keys, where it has got
    /// to; unkeyed, the layer's own. Volume is in decibels.
    public func keyedValue(layerID: UUID, _ property: KeyedProperty,
                           atDocumentTimeMS ms: Int) -> MotionValue? {
        guard let layer = layer(id: layerID) else { return nil }
        switch property {
        case let .motion(motion):
            guard let keyed = layer.keyedMotion(motion) else { return layer.keyStill(motion) }
            return keyed.value(atMS: keyClock(of: layer, property, atDocumentTimeMS: ms),
                               cycleMS: keyCycle(of: layer))
        case .volume:
            guard layer.sound != nil else { return nil }
            let level = layer.soundLevel ?? AudioLevel()
            let gain = level.gain(atLayerMS: layer.volumeClockMS(atDocumentTimeMS: ms))
            return .number(Self.decibels(gain))
        }
    }

    static func decibels(_ gain: Double) -> Double {
        max(PropertyKeys.quietestDecibels,
            AudioLevel.decibels(forGain: gain) ?? PropertyKeys.quietestDecibels)
    }

    static func gain(_ decibels: Double) -> Double {
        decibels <= PropertyKeys.quietestDecibels ? 0 : AudioLevel.gain(forDecibels: decibels)
    }

    // MARK: Starting and stopping

    /// The diamond on a value nobody has keyed: key it, with one key at the
    /// playhead holding the value it has now. False where it is already keyed
    /// or the layer has no such value.
    @discardableResult
    public mutating func startKeying(layerID: UUID, _ property: KeyedProperty,
                                     atDocumentTimeMS ms: Int) -> Bool {
        guard let layer = layer(id: layerID), keyCount(layerID: layerID, property) == 0,
              layer.keyableProperties.contains(property) else { return false }
        let clock = keyClock(of: layer, property, atDocumentTimeMS: ms)
        switch property {
        case let .motion(motion):
            guard let value = layer.keyStill(motion) else { return false }
            updateLayer(id: layerID) { edited in
                var motions = edited.motions ?? []
                motions.append(.keyed(motion, atMS: clock, value: value))
                edited.motions = motions
            }
        case .volume:
            updateLayer(id: layerID) { edited in
                var level = edited.soundLevel ?? AudioLevel()
                // The point holds the level where it is: the fader already
                // says how loud, so the shape starts at one.
                level.setPoint(atMS: clock, gain: 1)
                edited.soundLevel = level
            }
        }
        return true
    }

    /// The diamond on a keyed value, answered yes: every key goes, and the
    /// value it had at the playhead stays as the layer's own, so the picture
    /// under the playhead does not jump.
    @discardableResult
    public mutating func stopKeying(layerID: UUID, _ property: KeyedProperty,
                                    atDocumentTimeMS ms: Int) -> Bool {
        guard keyCount(layerID: layerID, property) > 0,
              let value = keyedValue(layerID: layerID, property, atDocumentTimeMS: ms) else { return false }
        switch property {
        case let .motion(motion):
            updateLayer(id: layerID) { edited in
                let kept = (edited.motions ?? []).filter { $0.property != motion }
                edited.motions = kept.isEmpty ? nil : kept
                edited.setKeyStill(motion, value)
            }
        case .volume:
            guard case let .number(decibels) = value else { return false }
            updateLayer(id: layerID) { edited in
                var level = edited.soundLevel ?? AudioLevel()
                level.clearPoints()
                level.gain = AudioLevel.bounded(Self.gain(decibels))
                edited.setSoundLevel(level)
            }
        }
        return true
    }

    // MARK: Changing a value

    /// A value changed at the playhead, in the panel. Keyed, that is a key
    /// here (rewriting one that is already here). Not keyed, it is simply the
    /// layer's own value, which is what every value in the app was before
    /// keys: the diamond is the only thing that starts keying.
    ///
    /// Scale is the one exception, because a layer has no scale of its own to
    /// hold: a scale typed into a row nobody has keyed starts keying it, with
    /// its one key holding what was typed.
    @discardableResult
    public mutating func setKeyedValue(_ value: MotionValue, layerID: UUID,
                                       _ property: KeyedProperty,
                                       atDocumentTimeMS ms: Int) -> Bool {
        guard let layer = layer(id: layerID), layer.keyableProperties.contains(property) else { return false }
        let clock = keyClock(of: layer, property, atDocumentTimeMS: ms)
        switch property {
        case let .motion(motion):
            if let keyed = layer.keyedMotion(motion) {
                let next = keyed.settingKey(atMS: clock, value: value)
                updateLayer(id: layerID) { edited in
                    edited.motions = (edited.motions ?? []).map { $0.id == keyed.id ? next : $0 }
                }
            } else if motion == .scale {
                updateLayer(id: layerID) { edited in
                    var motions = edited.motions ?? []
                    motions.append(.keyed(.scale, atMS: clock, value: value))
                    edited.motions = motions
                }
            } else {
                updateLayer(id: layerID) { $0.setKeyStill(motion, value) }
            }
        case .volume:
            guard case let .number(decibels) = value else { return false }
            let gain = Self.gain(decibels)
            updateLayer(id: layerID) { edited in
                var level = edited.soundLevel ?? AudioLevel()
                if level.points.isEmpty {
                    level.gain = AudioLevel.bounded(gain)
                } else {
                    // The points are the shape under the fader, so the point
                    // that makes THIS loudness is it divided by the fader.
                    let shape = level.gain > 0 ? gain / level.gain : 0
                    let near = level.points.first { abs($0.atMS - clock) <= PropertyKeys.nearMS }
                    level.setPoint(atMS: near?.atMS ?? clock, gain: shape)
                }
                edited.setSoundLevel(level)
            }
        }
        return true
    }

    /// Take away the key at the playhead. The last key going takes the
    /// keying with it, keeping the value it held.
    @discardableResult
    public mutating func removeKey(layerID: UUID, _ property: KeyedProperty,
                                   atDocumentTimeMS ms: Int) -> Bool {
        guard let layer = layer(id: layerID),
              keyDiamond(layerID: layerID, property, atDocumentTimeMS: ms) == .onKey else { return false }
        if keyCount(layerID: layerID, property) == 1 {
            return stopKeying(layerID: layerID, property, atDocumentTimeMS: ms)
        }
        let clock = keyClock(of: layer, property, atDocumentTimeMS: ms)
        switch property {
        case let .motion(motion):
            guard let keyed = layer.keyedMotion(motion) else { return false }
            let next = keyed.removingKey(atMS: clock)
            updateLayer(id: layerID) { edited in
                edited.motions = (edited.motions ?? []).compactMap { $0.id == keyed.id ? next : $0 }
            }
        case .volume:
            updateLayer(id: layerID) { edited in
                guard var level = edited.soundLevel,
                      let near = level.points.first(where: { abs($0.atMS - clock) <= PropertyKeys.nearMS })
                else { return }
                level.removePoint(atMS: near.atMS)
                edited.setSoundLevel(level)
            }
        }
        return true
    }

    // MARK: The arrows

    /// The moment of the document the key before (or after) `ms` plays at, or
    /// nil where there is none that way. Keys cut out of the clip are
    /// stepped over: there is no moment to land on.
    public func neighbourKeyTime(layerID: UUID, _ property: KeyedProperty,
                                 from ms: Int, forward: Bool) -> Int? {
        guard let layer = layer(id: layerID) else { return nil }
        let moments: [Int] = keyMoments(of: layer, property).compactMap { moment in
            switch property {
            case .motion: layer.documentTimeMS(atMotionClockMS: moment)
            case .volume: moment + (layer.time?.inMS ?? 0)
            }
        }
        if forward {
            return moments.filter { $0 > ms + PropertyKeys.nearMS }.min()
        }
        return moments.filter { $0 < ms - PropertyKeys.nearMS }.max()
    }

    // MARK: A hand on the canvas

    /// After the canvas has moved, resized or turned a layer: every change to
    /// a value that is KEYED becomes a key at the playhead, and the layer's
    /// own value goes back to what it was, so the picture is where the hand
    /// left it and the timeline says why.
    ///
    /// `before` is the layer as it was when the hand took hold. Nothing that is
    /// not keyed is touched, so an ordinary drag on an ordinary layer is
    /// exactly what it always was. True when anything became a key.
    ///
    /// `restoring` is the layer as it is STORED, where the hand worked on it as
    /// it is posed at the playhead (`posedForCanvas`): the hand's move is read
    /// against the pose, and what goes back is what was stored.
    @discardableResult
    public mutating func foldEditIntoKeys(layerID: UUID, before: Layer, restoring stored: Layer? = nil,
                                          atDocumentTimeMS ms: Int) -> Bool {
        let stored = stored ?? before
        guard let after = layer(id: layerID), after.hasMotion else { return false }
        let keyed = Set((after.motions ?? []).map(\.property))
        var restored = after
        var keys: [(MotionProperty, MotionValue)] = []

        let was = before.frame.standardized
        let now = after.frame.standardized
        var shift = CGPoint(x: now.minX - was.minX, y: now.minY - was.minY)
        // A keyed place, size or angle is ALWAYS put back to what is stored,
        // changed or not: the hand worked on the layer as posed at the
        // playhead, so even an edit that changed nothing (an Escape, a click
        // that never travelled) has written the pose over the stored value.
        if keyed.contains(.scale) {
            if was.width > 0, now.size != was.size,
               case let .number(percent)? = keyedValue(layerID: layerID, .motion(.scale), atDocumentTimeMS: ms) {
                // A resize is a growth about the middle, so how far the middle
                // travelled is what a place is told.
                keys.append((.scale, .number(percent * Double(now.width / was.width))))
                shift = CGPoint(x: now.midX - was.midX, y: now.midY - was.midY)
            }
            restored.frame = stored.frame
            restored.content = stored.content
            // With the place NOT keyed, a move is still the ordinary move it
            // always was: the stored layer goes where the hand took it.
            if !keyed.contains(.position) {
                restored.frame.origin.x += shift.x
                restored.frame.origin.y += shift.y
            }
        }
        if keyed.contains(.position) {
            if shift != .zero,
               case let .point(point)? = keyedValue(layerID: layerID, .motion(.position), atDocumentTimeMS: ms) {
                keys.append((.position, .point(CGPoint(x: point.x + shift.x, y: point.y + shift.y))))
            }
            restored.frame.origin = stored.frame.origin
            if now.size == was.size { restored.content = stored.content }
        }
        if keyed.contains(.rotation) {
            if after.transform.rotation != before.transform.rotation {
                keys.append((.rotation, .number(Double(after.transform.rotation) * 180 / .pi)))
            }
            restored.transform.rotation = stored.transform.rotation
        }
        for property in [MotionProperty.opacity, .color, .blur, .strokeWidth,
                         .cornerRadius, .shadow, .textSize] where keyed.contains(property) {
            guard let value = property.current(of: after), value != property.current(of: before),
                  let old = stored.keyStill(property) else { continue }
            keys.append((property, value))
            restored = property.applied(old, to: restored, authored: restored)
        }
        if restored != after { updateLayer(id: layerID) { $0 = restored } }
        guard !keys.isEmpty else { return false }
        for (property, value) in keys {
            setKeyedValue(value, layerID: layerID, .motion(property), atDocumentTimeMS: ms)
        }
        return true
    }

    // MARK: Where the handles go

    /// The document as the canvas should hit-test it and draw handles round
    /// it at `ms`: every layer whose place, size or angle is keyed wears the
    /// place, size and angle it has at that moment, and nothing else changes.
    ///
    /// Without it the handles sit where the layer was DRAWN while the picture
    /// is wherever its keys have taken it, and a drag would grab empty canvas.
    /// Only the box and the turn: that is all a handle needs, and it keeps
    /// this cheap enough to ask on every redraw.
    public func posedForCanvas(atTimeMS ms: Int) -> PhotonzDocument {
        let posing: Set<MotionProperty> = [.position, .scale, .rotation]
        guard hasTime, layers.contains(where: { layer in
            (layer.motions ?? []).contains { posing.contains($0.property) }
        }) else { return self }
        let cycle = max(1, documentDurationMS)
        var posed = self
        posed.layers = layers.map { layer in
            guard (layer.motions ?? []).contains(where: { posing.contains($0.property) }) else { return layer }
            let clock = layer.motionClockMS(atDocumentTimeMS: ms)
            let moved = layer.moved(toMotionTimeMS: clock,
                                    cycleMS: layer.motionCycleMS(documentCycleMS: cycle))
            var pose = layer
            pose.frame = moved.frame
            pose.transform.rotation = moved.transform.rotation
            return pose
        }
        return posed
    }
}
