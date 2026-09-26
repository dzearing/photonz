import CoreGraphics
import Foundation

// A transition at a cut (`docs/design/video-transitions.md`).
//
// **A transition is not a filter on a clip. It is a relationship between the
// two pieces either side of a join**, so everything here is asked by naming the
// CUT, and what it costs is taken from both sides.
//
// Where it is written down is the one thing that reads like a compromise and is
// not: it is stored on the piece that ARRIVES at the cut. A cut in this model
// has no object of its own — it is the moment one piece stops and the next
// starts (`ClipPieces`, "a split adds a piece to a clip, never a second clip")
// — and a piece carried somewhere else in the order has to take how it arrives
// with it. Keyed by a join NUMBER instead, every reorder, split and delete
// would have to renumber a second list, and the day one of them forgot, a
// dissolve would appear at a cut nobody put it at. Read, drawn, selected and
// paid for, it is a property of the cut; the piece is only where it lives.
//
// The other rule worth stating once: **an overlap is paid for with spare media,
// never with position.** Putting a dissolve on a cut moves no piece, changes no
// length and shifts nothing after it. What it spends is frames the recording
// already has and the clip is not playing.

/// What happens at a cut.
///
/// The six the picker draws (`video-transition-wt.html`): two dips that need
/// nothing but the time each shot already has, and four that put both shots
/// on screen together and so spend spare media either side of the cut.
public enum ClipTransitionKind: String, CaseIterable, Hashable, Codable, Sendable {
    /// Both shots on screen together, one coming up as the other goes down.
    case dissolve
    /// The picture goes through black and comes back.
    case dipToBlack
    /// ...and through white.
    case dipToWhite
    /// The incoming shot slides in from the right and pushes the outgoing one
    /// off to the left.
    case push
    /// The incoming shot is uncovered from the left edge across.
    case wipe
    /// A dissolve that goes out of focus on the way through and comes back.
    case blurThrough

    public var title: String {
        switch self {
        case .dissolve: "Cross dissolve"
        case .dipToBlack: "Dip to black"
        case .dipToWhite: "Dip to white"
        case .push: "Push"
        case .wipe: "Wipe"
        case .blurThrough: "Blur through"
        }
    }

    /// **The distinction the whole feature turns on.** The ones that need an
    /// overlap put both pieces on screen together, so they spend spare media.
    /// The dips do not: each piece plays the frames it already had and the
    /// picture fades through a colour between them.
    public var needsOverlap: Bool { dipColorHex == nil }

    /// The colour the picture goes through, or nil where it goes through no
    /// colour at all.
    public var dipColorHex: String? {
        switch self {
        case .dipToBlack: "#000000"
        case .dipToWhite: "#FFFFFF"
        case .dissolve, .push, .wipe, .blurThrough: nil
        }
    }

    /// The few words under its name in the picker, saying what it costs;
    /// nothing for one that costs nothing, never a "no overlap".
    public var note: String? {
        needsOverlap ? "needs overlap" : nil
    }
}

/// A transition, as it is written down: what it does and how long it takes.
///
/// Nothing about WHERE, because where is the cut it is on.
public struct ClipTransition: Hashable, Codable, Sendable {

    /// How long one is when nobody has said: four tenths of a second, which is
    /// long enough to read as a transition and short enough not to be the
    /// thing you remember about the edit.
    public static let defaultLengthMS = 400

    /// The shortest one worth having. Below about a tenth of a second a
    /// dissolve is a flicker and a dip is a blink.
    public static let shortestMS = 100

    public var kind: ClipTransitionKind
    /// How long it takes, in milliseconds, measured across the cut.
    public var lengthMS: Int

    public init(kind: ClipTransitionKind, lengthMS: Int = ClipTransition.defaultLengthMS) {
        self.kind = kind
        self.lengthMS = max(Self.shortestMS, lengthMS)
    }

    /// How much of it falls before the cut, and how much after. An odd number
    /// of milliseconds puts the spare one on the far side, so the two halves
    /// always add back up to the length somebody asked for.
    public var beforeMS: Int { lengthMS / 2 }
    public var afterMS: Int { lengthMS - beforeMS }

    /// How far through a transition on a cut at `cutAtMS` a moment is, nought
    /// at its first frame and one at the frame after its last.
    public static func progress(atMS ms: Int, cutAtMS: Int, _ transition: ClipTransition) -> Double {
        let raw = Double(ms - (cutAtMS - transition.beforeMS)) / Double(max(1, transition.lengthMS))
        return min(max(raw, 0), 1)
    }

    /// How much of a dip's colour is up at a moment: rising to all of it on
    /// the cut and falling away again after.
    public static func dipAmount(atMS ms: Int, cutAtMS: Int, _ transition: ClipTransition) -> Double {
        let amount = ms < cutAtMS
            ? Double(ms - (cutAtMS - transition.beforeMS)) / Double(max(1, transition.beforeMS))
            : 1 - Double(ms - cutAtMS) / Double(max(1, transition.afterMS))
        return min(max(amount, 0), 1)
    }

    /// The lengths the Length dropdown offers, before a cut says how long it
    /// can afford.
    public static let lengthStopsMS = [200, 400, 600, 800, 1000, 1500, 2000, 3000]
}

/// One cut of a clip, and everything it can afford.
///
/// Handed out rather than stored: every number on it is read off the two pieces
/// at the moment it is asked for, so a piece that was just trimmed cannot leave
/// a stale bill on screen.
public struct ClipCut: Hashable, Sendable {

    /// The piece that ARRIVES here. A cut is the arrival of a piece, so this
    /// number names it, and it is never nought: nothing arrives at the start.
    public let index: Int
    /// Where the cut is, measured from the clip's own start.
    public let atMS: Int
    /// The piece going out and the piece coming in.
    public let outgoing: ClipPiece
    public let incoming: ClipPiece
    /// Frames the recording still has after the outgoing piece's last one, in
    /// timeline milliseconds. Nil where nothing stops it at all: a held frame
    /// can be held as long as you like.
    public let spareAfterOutMS: Int?
    /// Frames the recording has before the incoming piece's first one.
    public let spareBeforeInMS: Int?
    /// Whether both sides read one recording. Always so inside one clip;
    /// between two clips only when they are two stretches of the same file.
    public let readsOneRecording: Bool

    public init(index: Int, atMS: Int, outgoing: ClipPiece, incoming: ClipPiece,
                spareAfterOutMS: Int?, spareBeforeInMS: Int?, readsOneRecording: Bool = true) {
        self.readsOneRecording = readsOneRecording
        self.index = index
        self.atMS = atMS
        self.outgoing = outgoing
        self.incoming = incoming
        self.spareAfterOutMS = spareAfterOutMS
        self.spareBeforeInMS = spareBeforeInMS
    }

    /// What is on this cut, if anything. Nothing is a hard cut, which is what
    /// every cut is until somebody says otherwise.
    public var transition: ClipTransition? { incoming.transitionIn }

    /// Whether the two sides read the same frames of the recording — which is
    /// what a plain split leaves, and the one case where a dissolve would blend
    /// a picture with itself and NOTHING VISIBLE WOULD HAPPEN.
    ///
    /// Said out loud rather than quietly allowed, because a feature that looks
    /// broken on the first press is worse than one that is not there.
    public var isContinuous: Bool {
        readsOneRecording && !outgoing.isHeld && !incoming.isHeld
            && outgoing.speedPercent == incoming.speedPercent
            && outgoing.sourceOutMS == incoming.sourceInMS
    }

    /// The longest a transition of this kind may be here.
    ///
    /// Two limits, and the smaller one wins. **It may not reach past the middle
    /// of either piece it joins**, so two cuts on one piece can never fight
    /// over the same frames; and one that needs an overlap may not spend spare
    /// media that is not there.
    public func longestMS(of kind: ClipTransitionKind) -> Int {
        let middles = min(outgoing.lengthMS, incoming.lengthMS)
        guard kind.needsOverlap else { return middles }
        guard let spare = smallestSpareMS else { return middles }
        return min(middles, 2 * spare)
    }

    /// The smaller of the two sides' spare, or nil when neither side has
    /// anything stopping it.
    public var smallestSpareMS: Int? {
        switch (spareAfterOutMS, spareBeforeInMS) {
        case (nil, nil): return nil
        case let (after?, nil): return after
        case let (nil, before?): return before
        case let (after?, before?): return Swift.min(after, before)
        }
    }

    /// Whether this cut can take a transition of this kind at all.
    public func canAfford(_ kind: ClipTransitionKind) -> Bool {
        longestMS(of: kind) >= ClipTransition.shortestMS
    }

    /// What is actually drawn: what was asked for, never longer than this cut
    /// can pay for. The two are the same every time a length went through
    /// `setTransition`, and they part company only when a later trim ate the
    /// spare the transition was already spending — which the panel says out
    /// loud rather than leaving somebody to notice.
    public var drawnTransition: ClipTransition? {
        guard var asked = transition else { return nil }
        let longest = longestMS(of: asked.kind)
        guard longest >= ClipTransition.shortestMS else { return nil }
        asked.lengthMS = Swift.min(asked.lengthMS, longest)
        return asked
    }

    /// How much of the spare each side is spending, for the bill on the panel.
    /// Nought for anything that needs no overlap.
    public var spentEachSideMS: Int {
        guard let drawn = drawnTransition, drawn.kind.needsOverlap else { return 0 }
        return drawn.beforeMS
    }
}

/// What one clip looks like at one moment: the frame it is playing, the frame
/// dissolving into it, and the colour it is going through.
///
/// **One answer, two readers.** The canvas draws this and the exporter
/// photographs it, so what plays and what is written to a file cannot be two
/// different pictures.
public struct ClipMoment: Hashable, Sendable {
    /// Where in the recording the frame on screen comes from.
    public let sourceMS: Int
    /// The frame coming in over it, while a dissolve is running.
    public let incomingSourceMS: Int?
    /// How far up that incoming frame is, nought to one.
    public let incomingOpacity: Double
    /// The colour the picture is going through, while a dip is running.
    public let dipColorHex: String?
    /// How far through it, nought to one, one being all the way.
    public let dipOpacity: Double
    /// Which transition is running, and how far through it, nought at its
    /// first frame and one at the frame after its last. Nil and nought when
    /// none is.
    public let kind: ClipTransitionKind?
    public let progress: Double

    public init(sourceMS: Int, incomingSourceMS: Int? = nil, incomingOpacity: Double = 0,
                dipColorHex: String? = nil, dipOpacity: Double = 0,
                kind: ClipTransitionKind? = nil, progress: Double = 0) {
        self.sourceMS = sourceMS
        self.incomingSourceMS = incomingSourceMS
        self.incomingOpacity = incomingOpacity
        self.dipColorHex = dipColorHex
        self.dipOpacity = dipOpacity
        self.kind = kind
        self.progress = progress
    }

    /// Whether anything at all is happening here beyond one frame playing.
    public var isMidTransition: Bool { incomingSourceMS != nil || dipColorHex != nil }
}

// MARK: - What a clip's pieces say about their cuts

extension ClipPieces {

    /// Every cut in this clip, named by the piece that arrives at it. Empty for
    /// a clip nobody has cut, which has no cuts to put anything on.
    public var cutIndices: [Int] { count > 1 ? Array(1..<count) : [] }

    /// Whether anything at all is on any of them.
    public var hasAnyTransition: Bool { cutIndices.contains { transition(atCut: $0) != nil } }

    /// One cut, with what it can afford worked out.
    public func cut(at index: Int) -> ClipCut? {
        guard cutIndices.contains(index),
              let outgoing = piece(at: index - 1), let incoming = piece(at: index) else { return nil }
        return ClipCut(index: index, atMS: startMS(ofPiece: index),
                       outgoing: outgoing, incoming: incoming,
                       // The same two questions a trim asks, answered by the
                       // same arithmetic: how much recording is left past this
                       // edge. A transition spends exactly what a trim would.
                       spareAfterOutMS: trimEndRange(ofPiece: index - 1)?.out,
                       spareBeforeInMS: trimStartRange(ofPiece: index)?.out.map { abs($0) })
    }

    /// Every cut, in order.
    public var cuts: [ClipCut] { cutIndices.compactMap { cut(at: $0) } }

    /// What is on a cut.
    public func transition(atCut index: Int) -> ClipTransition? { cut(at: index)?.transition }

    /// Put a transition on a cut, or take one off with nil.
    ///
    /// **Refused rather than shortened** when the cut cannot pay for the length
    /// asked for: a dissolve that quietly came out half as long as the number
    /// somebody typed is the app deciding something and not saying so. The
    /// caller clamps with `ClipCut.longestMS(of:)` and then asks.
    @discardableResult
    public mutating func setTransition(_ transition: ClipTransition?, atCut index: Int) -> Bool {
        guard let cut = cut(at: index) else { return false }
        if let transition {
            guard transition.lengthMS >= ClipTransition.shortestMS,
                  transition.lengthMS <= cut.longestMS(of: transition.kind) else { return false }
        }
        guard transition != cut.transition else { return false }
        setTransitionIn(transition, ofPiece: index)
        return true
    }

    // MARK: What is on screen at a moment

    /// The cut whose transition is running at this moment, if one is.
    ///
    /// At most one can be: a transition may not reach past the middle of either
    /// piece it joins (`ClipCut.longestMS(of:)`), so two of them can touch and
    /// never overlap.
    public func transitionCut(atMS ms: Int) -> (cut: ClipCut, transition: ClipTransition)? {
        for cut in cuts {
            guard let drawn = cut.drawnTransition else { continue }
            if ms >= cut.atMS - drawn.beforeMS && ms < cut.atMS + drawn.afterMS {
                return (cut, drawn)
            }
        }
        return nil
    }

    /// **What this clip looks like at a moment of its own clock.** The one
    /// answer the canvas draws and the exporter photographs.
    public func moment(atMS ms: Int) -> ClipMoment? {
        guard let index = pieceIndex(atMS: ms) else { return nil }
        let moment = min(max(0, ms), totalLengthMS)
        let plain = pieces[index].sourceMS(atOffsetMS: moment - startMS(ofPiece: index))
        guard let (cut, transition) = transitionCut(atMS: moment) else {
            return ClipMoment(sourceMS: plain)
        }
        // How far through the transition we are, nought at its first frame and
        // one at the frame after its last.
        let progress = ClipTransition.progress(atMS: moment, cutAtMS: cut.atMS, transition)
        if transition.kind.needsOverlap {
            // Both pieces are playing, each from its own clock. Before the cut
            // the INCOMING one is reading early, out of the spare before its in
            // point; after it the OUTGOING one is running on, out of the spare
            // after its out point. Neither piece moved and neither got longer.
            let out = readingOn(piece: cut.index - 1, atMS: moment)
            let into = readingOn(piece: cut.index, atMS: moment)
            return ClipMoment(sourceMS: out, incomingSourceMS: into,
                              incomingOpacity: progress, kind: transition.kind, progress: progress)
        }
        // A dip spends nothing: each piece plays the frames it already had, and
        // the picture goes through a colour and comes back. All the way through
        // at the cut itself.
        return ClipMoment(sourceMS: plain, dipColorHex: transition.kind.dipColorHex,
                          dipOpacity: ClipTransition.dipAmount(atMS: moment, cutAtMS: cut.atMS, transition),
                          kind: transition.kind, progress: progress)
    }

    /// Where in the recording a piece is reading at a moment of the clip, with
    /// that piece allowed to run on past its own edges into the spare either
    /// side of it. Never outside the recording itself.
    private func readingOn(piece index: Int, atMS ms: Int) -> Int {
        guard let piece = piece(at: index) else { return 0 }
        let raw = piece.sourceMS(atOffsetMS: ms - startMS(ofPiece: index), runningOn: true)
        guard let length = sourceLengthMS else { return max(0, raw) }
        return min(max(0, raw), length)
    }
}

// MARK: - What a layer says about the transitions on it

extension Layer {

    /// What this clip looks like at a moment of the DOCUMENT's clock, or nil at
    /// a moment it is not on screen for.
    public func clipMoment(atTimeMS ms: Int) -> ClipMoment? {
        guard let time, time.contains(ms: ms), let pieces = clipPieces else { return nil }
        return pieces.moment(atMS: ms - time.inMS)
    }

    /// The cuts of this layer's clip, empty for anything that is not one.
    public var clipCuts: [ClipCut] { clipPieces?.cuts ?? [] }

    /// This layer and whatever a transition on it puts on screen beside it, at
    /// a moment.
    ///
    /// One picture becomes two while a dissolve runs, and a picture plus a
    /// panel of colour while a dip does. Both of them are ORDINARY LAYERS, so
    /// the renderer draws a transition without having been told transitions
    /// exist — the same trick that let a clip be a picture layer in the first
    /// place (`MovieClip.swift`).
    func withTransitionDrawn(atTimeMS ms: Int, framesInHand: MovieFramesInHand? = nil) -> [Layer] {
        var drawn = self
        if isGroup {
            drawn.children = children.flatMap {
                $0.withTransitionDrawn(atTimeMS: ms, framesInHand: framesInHand)
            }
        }
        guard isVisible, let movie, let moment = clipMoment(atTimeMS: ms),
              moment.isMidTransition else { return [drawn] }
        if let incoming = moment.incomingSourceMS, let kind = moment.kind {
            // The same layer, wearing the other frame. It carries the clip's
            // own look — its corners, its effects, its blend mode — because it
            // IS the clip, on a different frame, and a dissolve where only one
            // side had the corner radius would be a dissolve into a
            // different-shaped picture.
            let over = drawn.transitionPartner(standingFor: id,
                                               showing: .image(movie.frameRef(atSourceMS: incoming,
                                                                              holding: framesInHand)))
            return Layer.transitionDrawn(kind, progress: moment.progress,
                                         outgoing: drawn, incoming: over)
        }
        guard let hex = moment.dipColorHex else { return [drawn] }
        return [drawn, drawn.dipPanel(hex: hex, amount: moment.dipOpacity)]
    }

    /// This layer as the second picture of a transition: the same look and
    /// the same place, showing `content`, under the partner id of the layer
    /// on screen (`transitionPartnerID`). Locked and timeless, since it exists
    /// for one frame of one render and nobody can pick it.
    func transitionPartner(standingFor onScreen: UUID, showing content: LayerContent) -> Layer {
        Layer(id: Layer.transitionPartnerID(of: onScreen), name: name, content: content,
              frame: frame, crop: crop, transform: transform, style: style,
              isVisible: true, isLocked: true, placement: placement)
    }

    /// A panel of colour over this layer and nothing else, `amount` of the
    /// way up: what a dip draws. A title over the picture is still over the
    /// picture while the picture dips.
    ///
    /// Its two corners are stated in the layer's OWN coordinates, which is
    /// where a shape's box lives (`AnnotationRasterizer`): a rectangle whose
    /// start and end are both nought is a rectangle of no size, and nothing at
    /// all is drawn. That is not a theory — it shipped that way for one walk,
    /// and the frame on the cut came out as the incoming shot rather than as
    /// black.
    func dipPanel(hex: String, amount: Double) -> Layer {
        var dip = Layer(id: Layer.transitionPartnerID(of: id),
                        name: "\(name) dip",
                        content: .annotation(AnnotationContent(
                            shape: .rectangle, strokeWidth: 0,
                            start: .zero,
                            end: CGPoint(x: frame.width, y: frame.height),
                            fillColorHex: hex)),
                        frame: frame)
        dip.style.opacity = amount
        return dip
    }

    /// **The two pictures of a transition that needs an overlap, drawn**: the
    /// outgoing shot and the incoming one, `progress` of the way from the
    /// first to the second. One answer for a cut inside a clip and a cut
    /// between two clips, so the four behaviours look the same wherever the
    /// cut is.
    ///
    /// Everything comes back as ordinary layers, in the order they are drawn,
    /// to stand where the one on screen stood. A push and a wipe are drawn
    /// through windows, so neither shot ever spills past the frame it had.
    static func transitionDrawn(_ kind: ClipTransitionKind, progress p: Double,
                                outgoing: Layer, incoming: Layer) -> [Layer] {
        let p = min(max(p, 0), 1)
        switch kind {
        case .dissolve, .dipToBlack, .dipToWhite:
            var into = incoming
            into.style.opacity = incoming.style.opacity * p
            return [outgoing, into]
        case .blurThrough:
            // Softest on the cut, sharp at both ends.
            let peak = 1 - abs(2 * p - 1)
            var out = outgoing, into = incoming
            out.style.blurRadius = max(out.style.blurRadius, Self.blurThroughRadius(out.frame) * peak)
            into.style.blurRadius = max(into.style.blurRadius, Self.blurThroughRadius(into.frame) * peak)
            into.style.opacity = incoming.style.opacity * p
            return [out, into]
        case .push:
            // The outgoing shot slides off to the left and the incoming one
            // follows it in from the right, each cut off where it leaves the
            // frame.
            return [outgoing.slice(from: p, to: 1, shiftedBy: -p * outgoing.frame.width),
                    incoming.slice(from: 0, to: p, shiftedBy: (1 - p) * incoming.frame.width)]
                .compactMap { $0 }
        case .wipe:
            return [outgoing] + [incoming.slice(from: 0, to: p, shiftedBy: 0)].compactMap { $0 }
        }
    }

    /// How soft blur through gets on the cut: a few percent of the picture,
    /// enough that the two shots melt rather than cross.
    static func blurThroughRadius(_ frame: CGRect) -> CGFloat {
        max(4, min(frame.width, frame.height) * 0.03)
    }

    /// The part of this layer between two fractions of its width, moved `dx`
    /// along: the whole layer, shifted, inside a window that cuts off the rest.
    /// Nil for a part too thin to draw.
    ///
    /// A window rather than a crop, because a crop is measured in the units of
    /// whatever the layer's picture was drawn at, which a transition has no
    /// business knowing; a window that clips what leaves it is the same
    /// picture however it was drawn, and the layer inside keeps its own box,
    /// corners and turn.
    func slice(from a: Double, to b: Double, shiftedBy dx: CGFloat) -> Layer? {
        let a = CGFloat(min(max(a, 0), 1)), b = CGFloat(min(max(b, 0), 1))
        guard (b - a) * frame.width >= 0.5 else { return nil }
        let window = CGRect(x: frame.minX + a * frame.width + dx, y: frame.minY,
                            width: (b - a) * frame.width, height: frame.height)
        var inside = self
        inside.frame = frame.offsetBy(dx: dx - window.minX, dy: -window.minY)
        return Layer(id: Layer.transitionWindowID(of: id), name: name,
                     content: .group(GroupContent(children: [inside], isFrame: true)),
                     frame: window, isVisible: true, isLocked: true)
    }

    /// The id the window round a slice of a transition is drawn under.
    static func transitionWindowID(of id: UUID) -> UUID {
        var bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        bytes[1] ^= 0x5A
        bytes[14] ^= 0x5A
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// The id the second picture of a transition is drawn under.
    ///
    /// Derived from the clip's own id the way a frame's reference is derived
    /// from the recording's (`MovieRef.frameID`), so it is the same id in every
    /// render of the same moment and can never be the id of a layer somebody
    /// actually has.
    static func transitionPartnerID(of id: UUID) -> UUID {
        var bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        bytes[0] ^= 0x7E
        bytes[15] ^= 0x7E
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - The few words the surface says

public enum ClipTransitionCopy {

    /// A length the way the panel's rows and the picker say it: seconds, to
    /// one place (`video-transition-wt.html`, "0.6s", "spare 2.0s / 1.5s").
    public static func seconds(_ ms: Int) -> String {
        String(format: "%.1fs", Double(ms) / 1000)
    }

    /// What a cut has to spend, the few words along the top of the picker.
    /// A side with nothing stopping it says "any".
    public static func spareShort(_ cut: ClipCut) -> String {
        "spare \(cut.spareAfterOutMS.map(seconds) ?? "any") / \(cut.spareBeforeInMS.map(seconds) ?? "any")"
    }

    /// What the transition on a cut is spending, for the Paid with row.
    public static func paidWith(_ cut: ClipCut) -> String {
        let each = seconds(cut.spentEachSideMS)
        return "\(each) + \(each) of spare"
    }

    /// A length, said the way somebody would say it.
    public static func length(_ ms: Int) -> String {
        let seconds = Double(ms) / 1000
        return seconds >= 1
            ? String(format: "%.2gs", seconds)
            : "\(ms) ms"
    }

    /// What a cut has to spend, in one line.
    public static func spare(_ cut: ClipCut) -> String {
        let after = cut.spareAfterOutMS.map(length) ?? "as much as you like"
        let before = cut.spareBeforeInMS.map(length) ?? "as much as you like"
        return "Spare \(after) after the outgoing piece, \(before) before the incoming one"
    }

    /// What the transition on a cut is costing, or why it costs nothing.
    public static func bill(_ cut: ClipCut) -> String {
        guard let drawn = cut.drawnTransition else {
            return "A hard cut. Nothing is drawn here and it takes no time."
        }
        if drawn.kind.needsOverlap {
            let each = length(cut.spentEachSideMS)
            return "Both pieces are on screen together for \(length(drawn.lengthMS)), "
                + "paid for with \(each) of spare either side. Nothing on the timeline moved."
        }
        return "Each piece fades inside the time it already has, so no spare media is spent "
            + "and nothing on the timeline moved."
    }

    /// Said when the length being drawn is not the length somebody asked for,
    /// because a later trim ate the spare it was spending.
    public static func shortened(_ cut: ClipCut) -> String? {
        guard let asked = cut.transition else { return nil }
        guard let drawn = cut.drawnTransition else {
            return "There is no longer enough spare media here for a \(asked.kind.title.lowercased()), "
                + "so this cut is playing hard."
        }
        guard drawn.lengthMS < asked.lengthMS else { return nil }
        return "Playing at \(length(drawn.lengthMS)) rather than the \(length(asked.lengthMS)) "
            + "asked for: a trim since took the spare it was spending."
    }

    /// Said on a cut whose two sides read the same frames, where a dissolve
    /// would blend a picture with itself.
    public static let continuousCut =
        "Both sides of this cut read the same frames, so a cross dissolve here would blend the "
        + "picture with itself and show nothing. A dip goes through a colour and does show."

    /// Why a kind is not on offer at this cut.
    public static func cannotAfford(_ kind: ClipTransitionKind, at cut: ClipCut) -> String {
        guard kind.needsOverlap else { return "" }
        return "\(kind.title) needs both pieces on screen at once, and there are no spare frames "
            + "either side of this cut to pay for it."
    }
}
