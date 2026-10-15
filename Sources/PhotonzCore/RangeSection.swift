import Foundation

// A range held with things picked: what each picked thing does over just that
// stretch.
//
// Premiere keeps its In and Out while you pick clips, and what you then do
// with the marks acts on the clips you picked, between the marks. The range
// and the pick are two separate things in hand, so drawing a range and then
// clicking a sound keeps the range, and a right click inside it offers what
// can be done to that sound over that stretch: Mute Section, Lower Volume,
// Delete Section and so on (the user, 2026-10-12).
//
// Which operations a pick gets is ONE table, `SectionOperation`, read by kind:
// a sound is offered the sound rows, a recording its picture rows and its
// sound rows, a title Trim to Range, keys inside the range Delete Keys in
// Range. The menu, the menu bar and the audit's inventory all read the same
// table, so nothing offers a row another surface does not know.
//
// Every edit here is one document change the app wraps as one undo step, and
// every one leaves what is outside the range exactly as it was.

/// What a picked thing is, as far as a range's operations are concerned. One
/// layer can be several: a recording has a picture and a sound.
public enum SectionKind: String, CaseIterable, Hashable, Sendable {
    /// Something that plays a sound: a sound clip, or a recording's own sound.
    case sound
    /// Frames that play: a recording or a video clip.
    case picture
    /// A title, shape or picture placed in time, whose ends are free.
    case placed
    /// Keys standing inside the range.
    case keys
}

/// Every operation a range offers the things picked inside it, in menu order.
public enum SectionOperation: String, CaseIterable, Hashable, Sendable {
    case muteSection
    case lowerVolume
    case normalizeSection
    case cleanNoiseInSection
    case splitAtRangeEdges
    case deleteSection
    case rippleDeleteSection
    case speedForSection
    case freezeFrameForSection
    case addZoomOverRange
    case hidePictureForSection
    case trimToRange
    case deleteKeysInRange

    /// The row's name.
    public var title: String {
        switch self {
        case .muteSection: "Mute Section"
        case .lowerVolume: "Lower Volume"
        case .normalizeSection: "Normalize Section"
        case .cleanNoiseInSection: "Clean Noise in Section"
        case .splitAtRangeEdges: "Split at Range Edges"
        case .deleteSection: "Delete Section"
        case .rippleDeleteSection: "Ripple Delete Section"
        case .speedForSection: "Speed for Section"
        case .freezeFrameForSection: "Freeze Frame for Section"
        case .addZoomOverRange: "Add Zoom over Range"
        case .hidePictureForSection: "Hide Picture for Section"
        case .trimToRange: "Trim to Range"
        case .deleteKeysInRange: "Delete Keys in Range"
        }
    }

    /// The kinds of picked thing it is offered for.
    public var kinds: Set<SectionKind> {
        switch self {
        case .muteSection, .lowerVolume, .normalizeSection, .cleanNoiseInSection: [.sound]
        case .splitAtRangeEdges, .deleteSection, .rippleDeleteSection: [.sound, .picture]
        case .speedForSection, .freezeFrameForSection, .addZoomOverRange, .hidePictureForSection: [.picture]
        case .trimToRange: [.placed]
        case .deleteKeysInRange: [.keys]
        }
    }

    /// Which block of the menu it sits in; a line goes between blocks.
    public var block: Int {
        switch self {
        case .muteSection, .lowerVolume, .normalizeSection, .cleanNoiseInSection: 0
        case .splitAtRangeEdges, .deleteSection, .rippleDeleteSection: 1
        case .speedForSection, .freezeFrameForSection, .addZoomOverRange, .hidePictureForSection: 2
        case .trimToRange: 3
        case .deleteKeysInRange: 4
        }
    }

    /// Whether the app can do it yet. A row it cannot do is left out of every
    /// menu rather than shown dead. Every row can be done today; the gate
    /// stays so a row added to the table before its edit exists is never
    /// offered.
    public var isAvailable: Bool { true }

    /// The operations offered for a pick of these kinds, in menu order, only
    /// those the app can do.
    public static func offered(for kinds: Set<SectionKind>) -> [SectionOperation] {
        allCases.filter { $0.isAvailable && !$0.kinds.isDisjoint(with: kinds) }
    }
}

/// How a section's level changes.
public enum SectionLevelChange: Hashable, Sendable {
    /// Every moment of it at this gain: nought is silence.
    case set(Double)
    /// Every moment of it this many times as loud as it was.
    case scaled(Double)

    func applied(to gain: Double) -> Double {
        switch self {
        case .set(let to): to
        case .scaled(let by): gain * by
        }
    }
}

extension AudioLevel {

    /// How long the level takes to reach a section's new level, and to come
    /// back from it: short enough to be heard as a cut, long enough that the
    /// step makes no click.
    public static let sectionRampMS = 50

    /// The level between `fromMS` and `toMS` of the layer's own clock changed,
    /// and everything outside it left as it was. The level ramps into the new
    /// one over `rampMS` BEFORE the section starts and back out over `rampMS`
    /// after it ends, so the whole section is at its new level and nothing is
    /// heard as a click. The points already inside the section keep their
    /// shape where the change is a scaling.
    public mutating func changeSection(fromMS: Int, toMS: Int, _ change: SectionLevelChange,
                                       rampMS: Int = AudioLevel.sectionRampMS) {
        let from = max(0, fromMS)
        guard toMS > from else { return }
        let ramp = max(0, rampMS)
        let before = max(0, from - ramp)
        let after = toMS + ramp
        var kept = points.filter { $0.atMS < before || $0.atMS > after }
        if before < from { kept.append(AudioLevelPoint(atMS: before, gain: shape(atLayerMS: before))) }
        kept.append(AudioLevelPoint(atMS: from, gain: change.applied(to: shape(atLayerMS: from))))
        for point in points where point.atMS > from && point.atMS < toMS {
            kept.append(AudioLevelPoint(atMS: point.atMS, gain: change.applied(to: point.gain)))
        }
        kept.append(AudioLevelPoint(atMS: toMS, gain: change.applied(to: shape(atLayerMS: toMS))))
        kept.append(AudioLevelPoint(atMS: after, gain: shape(atLayerMS: after)))
        clearPoints()
        for point in kept { setPoint(atMS: point.atMS, gain: point.gain) }
    }
}

extension AudioLevel {

    /// The level with the stretch from `fromMS` to `toMS` of the layer's own
    /// clock taken out, the way the sound under it was: the points before it
    /// stay, the points after it move up by its length, and the level either
    /// side of the join is what it was either side of the stretch. What Lift
    /// and Extract do to a sound's pieces, done to its line.
    public mutating func removeStretch(fromMS: Int, toMS: Int) {
        let from = max(0, fromMS)
        guard toMS > from, !points.isEmpty else { return }
        let length = toMS - from
        let left = shape(atLayerMS: from), right = shape(atLayerMS: toMS)
        var kept = points.filter { $0.atMS < from }
        if left != right, from >= 1 { kept.append(AudioLevelPoint(atMS: from - 1, gain: left)) }
        kept.append(AudioLevelPoint(atMS: from, gain: right))
        kept += points.filter { $0.atMS > toMS }.map { AudioLevelPoint(atMS: $0.atMS - length, gain: $0.gain) }
        clearPoints()
        for point in kept { setPoint(atMS: point.atMS, gain: point.gain) }
    }
}

extension PhotonzDocument {

    // MARK: What a pick is

    /// What a layer is to a range over `range`: nothing where it is locked,
    /// a caption, or not in the range at all.
    public func sectionKinds(of id: UUID, within range: Range<Int>) -> Set<SectionKind> {
        guard let layer = layer(id: id), let time = layer.time, !layer.isCaption,
              time.inMS < range.upperBound, time.outMS > range.lowerBound,
              !layerIDsOnLockedTracks().contains(id) else { return [] }
        var kinds = Set<SectionKind>()
        if layer.sound != nil, layer.merged == nil { kinds.insert(.sound) }
        if layer.movie != nil, layer.clipPieces != nil { kinds.insert(.picture) }
        if layer.startIsFree { kinds.insert(.placed) }
        if !keysInSection(of: id, within: range).isEmpty { kinds.insert(.keys) }
        return kinds
    }

    /// The part of `range` a layer runs through, or nil where it runs through
    /// none of it.
    public func section(of id: UUID, within range: Range<Int>) -> Range<Int>? {
        guard let time = layer(id: id)?.time else { return nil }
        let lower = max(range.lowerBound, time.inMS), upper = min(range.upperBound, time.outMS)
        return upper > lower ? lower..<upper : nil
    }

    // MARK: Sound

    /// The sound of `ids` over `range` changed, and nowhere else. Answers
    /// whether anything changed.
    @discardableResult
    public mutating func changeSoundSection(_ ids: [UUID], within range: Range<Int>,
                                            _ change: SectionLevelChange) -> Bool {
        var changed = false
        for id in ids where sectionKinds(of: id, within: range).contains(.sound) {
            guard let layer = layer(id: id), let time = layer.time,
                  let span = section(of: id, within: range) else { continue }
            var level = layer.soundLevel ?? AudioLevel()
            let before = level
            level.changeSection(fromMS: span.lowerBound - time.inMS, toMS: span.upperBound - time.inMS, change)
            guard level != before else { continue }
            updateLayer(id: id) { $0.setSoundLevel(level) }
            changed = true
        }
        return changed
    }

    /// The stretches of a layer's sound file that play inside `range`, for
    /// measuring how loud that section is.
    public func soundSourceRanges(of id: UUID, within range: Range<Int>) -> [Range<Int>] {
        guard let layer = layer(id: id), let time = layer.time, let pieces = layer.clipPieces,
              let span = section(of: id, within: range) else { return [] }
        var out: [Range<Int>] = []
        for piece in pieces.playback where piece.playsSound && piece.sourceLengthMS > 0 {
            let start = time.inMS + piece.startMS, end = start + piece.lengthMS
            let lower = max(start, span.lowerBound), upper = min(end, span.upperBound)
            guard upper > lower else { continue }
            let rate = Double(piece.sourceLengthMS) / Double(max(1, piece.lengthMS))
            let sourceLower = piece.sourceInMS + Int((Double(lower - start) * rate).rounded())
            let sourceUpper = piece.sourceInMS + Int((Double(upper - start) * rate).rounded())
            if sourceUpper > sourceLower { out.append(sourceLower..<sourceUpper) }
        }
        return out
    }

    // MARK: Cutting

    /// A cut through each of `ids` at both ends of `range`. Answers how many.
    @discardableResult
    public mutating func splitSection(_ ids: [UUID], within range: Range<Int>) -> Int {
        var cuts = 0
        for id in ids where !sectionKinds(of: id, within: range).isDisjoint(with: [.sound, .picture]) {
            for ms in [range.lowerBound, range.upperBound] where splitClip(id, atMS: ms) { cuts += 1 }
        }
        return cuts
    }

    /// The part of each of `ids` inside `range` taken out, its gap left.
    @discardableResult
    public mutating func liftSection(_ ids: [UUID], within range: Range<Int>) -> Bool {
        let only = Set(ids.filter { !sectionKinds(of: $0, within: range).isDisjoint(with: [.sound, .picture]) })
        guard !only.isEmpty else { return false }
        return liftStretch(fromMS: range.lowerBound, toMS: range.upperBound, onlyLayers: only)
    }

    /// The part of each of `ids` inside `range` taken out, and the gap closed
    /// on its own track. Nothing else on that track inside the range is cut,
    /// because only the clip's own part of the range is taken.
    @discardableResult
    public mutating func rippleDeleteSection(_ ids: [UUID], within range: Range<Int>) -> Bool {
        let spans = ids.compactMap { id -> (UUID, Range<Int>)? in
            guard !sectionKinds(of: id, within: range).isDisjoint(with: [.sound, .picture]),
                  let span = section(of: id, within: range) else { return nil }
            return (id, span)
        }
        // Latest first: taking a later stretch out never moves an earlier one.
        var changed = false
        for (id, span) in spans.sorted(by: { $0.1.lowerBound > $1.1.lowerBound }) {
            guard let track = trackID(ofClip: id) else { continue }
            if extractStretch(fromMS: span.lowerBound, toMS: span.upperBound, onTracks: [track]) { changed = true }
        }
        return changed
    }

    /// Clean Noise in Section: each picked sound cut at both ends of its part
    /// of `range`, and the piece between played from a copy with its noise
    /// taken out (`NoiseCleaning.swift`). A sound already cleaned whole, or
    /// already cleaned over all of it, is left alone. Answers whether any was
    /// cleaned.
    @discardableResult
    public mutating func cleanNoiseSection(_ ids: [UUID], within range: Range<Int>,
                                           _ reduction: NoiseReduction = .standard) -> Bool {
        var changed = false
        for id in ids where sectionKinds(of: id, within: range).contains(.sound) {
            guard layer(id: id)?.soundLevel?.activeNoiseReduction == nil,
                  !sectionAlready(id, within: range, { $0.noiseReduction == reduction }),
                  let index = sectionPiece(id, within: range, kind: .sound) else { continue }
            if editClip(id, { pieces, _ in pieces.setNoiseReduction(ofPiece: index, reduction) }) { changed = true }
        }
        return changed
    }

    /// Every stretch of a layer's sound cleaned on its own put back to the
    /// file: what Remove Noise Cleaning does alongside the whole sound's.
    @discardableResult
    public mutating func clearSectionNoiseCleaning(_ id: UUID) -> Bool {
        guard layer(id: id)?.hasSectionNoiseCleaning == true else { return false }
        return editClip(id) { pieces, _ in
            var changed = false
            for index in 0..<pieces.count where pieces.setNoiseReduction(ofPiece: index, nil) { changed = true }
            return changed
        }
    }

    // MARK: Picture

    /// Whether every piece a layer plays inside its part of `range` already
    /// says `marked`, so a row would change nothing and cut nothing.
    private func sectionAlready(_ id: UUID, within range: Range<Int>,
                                _ marked: (ClipPiece) -> Bool) -> Bool {
        guard let time = layer(id: id)?.time, let pieces = layer(id: id)?.clipPieces,
              let span = section(of: id, within: range) else { return false }
        for index in 0..<pieces.count {
            guard let piece = pieces.piece(at: index), let at = pieces.rangeMS(ofPiece: index) else { continue }
            let lower = time.inMS + at.start, upper = time.inMS + at.end
            if lower < span.upperBound, upper > span.lowerBound, !marked(piece) { return false }
        }
        return true
    }

    /// The piece of a clip that starts where its part of `range` starts,
    /// once the clip has been cut at both ends of it.
    private mutating func sectionPiece(_ id: UUID, within range: Range<Int>,
                                       kind: SectionKind = .picture) -> Int? {
        guard sectionKinds(of: id, within: range).contains(kind),
              let span = section(of: id, within: range) else { return nil }
        splitClip(id, atMS: span.lowerBound)
        splitClip(id, atMS: span.upperBound)
        guard let time = layer(id: id)?.time, let pieces = layer(id: id)?.clipPieces,
              let index = pieces.pieceIndex(atMS: span.lowerBound - time.inMS),
              let piece = pieces.rangeMS(ofPiece: index),
              time.inMS + piece.start == span.lowerBound,
              time.inMS + piece.end == span.upperBound else { return nil }
        return index
    }

    /// Each of `ids` playing at `percent` inside `range`, cut at both ends of
    /// it. Answers whether any speed changed.
    @discardableResult
    public mutating func setSectionSpeed(_ ids: [UUID], within range: Range<Int>, percent: Int) -> Bool {
        var changed = false
        for id in ids {
            guard let index = sectionPiece(id, within: range) else { continue }
            if setClipSpeed(id, ofPiece: index, percent: percent) { changed = true }
        }
        return changed
    }

    /// Each of `ids` holding the frame it shows where `range` starts, for the
    /// length of the range, and playing on from where it was at the range's
    /// end. Nothing moves. Answers whether any clip was frozen.
    @discardableResult
    public mutating func freezeSection(_ ids: [UUID], within range: Range<Int>) -> Bool {
        var changed = false
        for id in ids {
            guard let index = sectionPiece(id, within: range) else { continue }
            if editClip(id, { pieces, _ in pieces.freeze(ofPiece: index) }) { changed = true }
        }
        return changed
    }

    /// Hide Picture for Section: each picked recording cut at both ends of its
    /// part of `range`, and the piece between drawn as nothing while its sound
    /// plays on. Nothing moves. Answers whether any picture was hidden.
    @discardableResult
    public mutating func hidePictureSection(_ ids: [UUID], within range: Range<Int>) -> Bool {
        var changed = false
        for id in ids where sectionKinds(of: id, within: range).contains(.picture) {
            guard !sectionAlready(id, within: range, \.pictureHidden),
                  let index = sectionPiece(id, within: range) else { continue }
            if setPictureHidden(id, ofPiece: index, true) { changed = true }
        }
        return changed
    }

    /// One piece of a clip with its picture taken off, or put back: Show
    /// Picture on a hidden piece's right click.
    @discardableResult
    public mutating func setPictureHidden(_ id: UUID, ofPiece index: Int, _ hidden: Bool) -> Bool {
        editClip(id) { pieces, _ in pieces.setPictureHidden(ofPiece: index, hidden) }
    }

    /// A zoom on each of `ids` from where the range starts to where it ends,
    /// cut short where the clip or a zoom after it comes first. Answers the
    /// zooms made, by the clip each is on.
    @discardableResult
    public mutating func addZoomOverSection(_ ids: [UUID], within range: Range<Int>) -> [UUID: UUID] {
        var made: [UUID: UUID] = [:]
        for id in ids where sectionKinds(of: id, within: range).contains(.picture) {
            guard let span = section(of: id, within: range),
                  let zoom = addZoom(toClip: id, atTimeMS: span.lowerBound, around: nil),
                  let end = layer(id: id)?.motionClockMS(atDocumentTimeMS: span.upperBound) else { continue }
            updateZoom(onClip: id, id: zoom.id) { $0.endMS = end }
            made[id] = zoom.id
        }
        return made
    }

    // MARK: Placed layers

    /// Each placed layer of `ids` coming on where the range starts and going
    /// where it ends, never longer than it was. Answers whether any moved.
    @discardableResult
    public mutating func trimToSection(_ ids: [UUID], within range: Range<Int>) -> Bool {
        var changed = false
        for id in ids where sectionKinds(of: id, within: range).contains(.placed) {
            guard let span = section(of: id, within: range), let time = layer(id: id)?.time else { continue }
            if span.upperBound < time.outMS, moveLayerEnd(id, toMS: span.upperBound) { changed = true }
            if span.lowerBound > time.inMS, moveLayerStart(id, toMS: span.lowerBound) { changed = true }
        }
        return changed
    }

    // MARK: Keys

    /// The keys on a layer's lanes standing inside `range`, either edge
    /// included, the way a box picks them.
    public func keysInSection(of id: UUID, within range: Range<Int>) -> Set<KeyRef> {
        let lanes = keyLanes(layerID: id)
        guard !lanes.isEmpty else { return [] }
        return marqueeKeys(within: range, layerID: id, motionIDs: Set(lanes.map(\.motionID)))
    }

    /// Every key of `ids` inside `range` deleted.
    @discardableResult
    public mutating func deleteKeysInSection(_ ids: [UUID], within range: Range<Int>) -> Bool {
        var changed = false
        for id in ids {
            let keys = keysInSection(of: id, within: range)
            if !keys.isEmpty, removeKeys(layerID: id, keys) { changed = true }
        }
        return changed
    }
}
