import CoreGraphics
import Foundation

// Motion blur on what moves fast (`MotionBlurEffect`, task
// `motion-blur-on-titles-that-move-fast`).
//
// A frame of film is not an instant: the shutter is open for part of it, and
// anything moving while it is open is smeared along the way it went. Here that
// is worked out where everything else about a moment is, in the drawn copy of
// the document (`drawn(atTimeMS:)`), and handed to the renderer as a plain
// list: for each part that moved far enough, where it was at evenly spaced
// moments across the shutter, stated relative to where it is drawn. The
// renderer averages the part's own finished picture over those places
// (`MotionSmearFilter`), so a slide smears along its line, a scale-from
// smears outwards about its middle and a turn smears round its pivot, all by
// the one rule. Nothing is baked: the list is only ever on the frame drawn.
//
// The shutter is centred on the frame, so the smear sits on the part rather
// than trailing behind it, and a part that holds still across the whole
// shutter is handed nothing at all: a held frame is pixel for pixel the frame
// it is without motion blur.

/// Where a part was across the shutter, relative to where it is drawn.
public struct MotionSmear: Codable, Sendable {
    /// One per moment, evenly spaced across the shutter from when it opened to
    /// when it closed: each maps a point of the part as it is drawn now to
    /// where that point was at that moment, in canvas points, top-left origin.
    public var samples: [CGAffineTransform]
    /// The farthest any corner of the part travelled while the shutter was
    /// open, along the way it went, in canvas points.
    public var span: CGFloat

    public init(samples: [CGAffineTransform], span: CGFloat) {
        self.samples = samples
        self.span = span
    }

    /// How far a part must travel while the shutter is open before it is
    /// smeared at all, in canvas points. Under it the smear is less than a
    /// pixel and drawing it would only cost time.
    public static let threshold: CGFloat = 1

    /// How many places a smear of `span` points is drawn at: enough that the
    /// copies sit no more than about a point and a half apart, from a short
    /// list, so the renderer only ever builds a handful of shapes of picture.
    public static func sampleCount(forSpan span: CGFloat) -> Int {
        for count in [8, 16, 32] where span / CGFloat(count - 1) <= 1.5 { return count }
        return 64
    }

    /// The same smear, measured in a unit `scale` times smaller: the turns
    /// and growths are the same, the distances are `scale` times as long.
    public func magnified(by scale: CGFloat) -> MotionSmear {
        guard scale > 0, scale != 1, scale.isFinite else { return self }
        return MotionSmear(samples: samples.map {
            CGAffineTransform(a: $0.a, b: $0.b, c: $0.c, d: $0.d, tx: $0.tx * scale, ty: $0.ty * scale)
        }, span: span * scale)
    }
}

extension MotionSmear: Hashable {
    public static func == (lhs: MotionSmear, rhs: MotionSmear) -> Bool {
        lhs.span == rhs.span && lhs.samples.count == rhs.samples.count
            && zip(lhs.samples, rhs.samples).allSatisfy { $0 == $1 }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(span)
        for sample in samples {
            for value in [sample.a, sample.b, sample.c, sample.d, sample.tx, sample.ty] { hasher.combine(value) }
        }
    }
}

// MARK: - Which parts, and how long the shutter is open over them

extension Layer {

    /// Whether this layer or anything inside it asks for a motion blur that
    /// smears, which is what decides whether a frame pays for working any out.
    var carriesMotionBlur: Bool {
        if style.motionBlur?.smears == true { return true }
        guard let group else { return false }
        return group.children.contains { $0.carriesMotionBlur }
    }

    /// How long the shutter is open over this layer, given what holds it: its
    /// own Motion Blur, on or off, where it has one, and otherwise its
    /// container's. Nil where nothing smears it.
    func shutterMS(inheriting inherited: Double?) -> Double? {
        guard let own = style.motionBlur else { return inherited }
        return own.smears ? own.shutterMS : nil
    }

    /// Whether the renderer draws this group's contents straight onto what is
    /// under it rather than into a picture of its own (`DocumentRenderer`'s
    /// compositeLayers asks the same question). A smear is worked out per
    /// picture the renderer makes, so the two have to agree.
    var drawsThrough: Bool {
        guard let group else { return false }
        return !group.isFrame && !clipsToBounds && style.isPlain && transform.isIdentity
    }
}

extension PhotonzDocument {

    /// Whether anything in the document asks for motion blur.
    var hasMotionBlur: Bool { layers.contains { $0.carriesMotionBlur } }

    /// `shown`, the document's top-level layers as drawn at `moment`, with
    /// every part that moved far enough while the shutter was open told where
    /// it went (`Layer.motionSmear`), and every revealing text under a motion
    /// blur told how long the shutter is open (`TextContent.revealShutterMS`).
    ///
    /// Each top-level layer that asks for it is read again at every whole
    /// millisecond the widest shutter over it covers, by the same motion path
    /// that drew it, and the places in between are read off those in a
    /// straight line: a 180 degree shutter is under seventeen milliseconds,
    /// and keys are read on whole ones.
    func withMotionSmears(_ shown: [Layer], atMS moment: Int, cycleMS cycle: Int) -> [Layer] {
        shown.map { drawn in
            guard drawn.isVisible, let authored = layer(id: drawn.id), authored.carriesMotionBlur else {
                return drawn
            }
            let widest = authored.widestShutterMS(inheriting: nil)
            guard widest > 0 else { return drawn }
            let from = Int((Double(moment) - widest / 2).rounded(.down))
            let to = Int((Double(moment) + widest / 2).rounded(.up))
            let reads = (from...to).map {
                authored.movedTree(atDocumentTimeMS: $0, documentCycleMS: cycle)
            }
            let clock = SmearClock(fromMS: from, moment: moment)
            return drawn.smeared(reads: reads, origins: reads.map { _ in .zero },
                                 clock: clock, inherited: nil)
        }
    }
}

/// The whole milliseconds a layer was read at, and the moment being drawn.
struct SmearClock {
    let fromMS: Int
    let moment: Int
    var nowIndex: Int { moment - fromMS }
}

extension Layer {

    /// The longest shutter anywhere in this layer.
    func widestShutterMS(inheriting inherited: Double?) -> Double {
        let mine = shutterMS(inheriting: inherited)
        var widest = mine ?? 0
        for child in group?.children ?? [] {
            widest = max(widest, child.widestShutterMS(inheriting: mine))
        }
        return widest
    }

    /// This drawn layer with its smear worked out, and its contents'.
    ///
    /// `reads` is this same layer read at each whole millisecond of the
    /// clock, and `origins` where its space starts on the canvas in each.
    func smeared(reads: [Layer], origins: [CGPoint], clock: SmearClock, inherited: Double?) -> Layer {
        guard isVisible else { return self }
        var out = self
        let shutter = shutterMS(inheriting: inherited)
        if case .text(var text) = content, text.reveal != nil, let shutter {
            text.revealShutterMS = shutter
            out.content = .text(text)
        }
        if drawsThrough {
            // Its contents draw straight onto the canvas, each its own picture,
            // so each is smeared by its own move, measured from wherever the
            // group has carried them at that moment.
            let inner = zip(reads, origins).map { read, origin in
                CGPoint(x: origin.x + read.frame.origin.x, y: origin.y + read.frame.origin.y)
            }
            out.children = smearedChildren(reads: reads, origins: inner, clock: clock, inherited: shutter)
            return out
        }
        if let shutter, clock.nowIndex < reads.count {
            let quads = zip(reads, origins).map { read, origin in
                read.drawnQuad(origin: origin, sizedLike: reads[clock.nowIndex])
            }
            out.motionSmear = MotionSmear.across(quads: quads, clock: clock, shutterMS: shutter)
        }
        if isGroup, clock.nowIndex < reads.count {
            // A group drawn as one picture: what moves inside it is smeared
            // inside that picture, measured from where the group is NOW. The
            // group's own move is its own smear, just above.
            let now = reads[clock.nowIndex]
            let anchor = CGPoint(x: origins[clock.nowIndex].x + now.frame.origin.x,
                                 y: origins[clock.nowIndex].y + now.frame.origin.y)
            out.children = smearedChildren(reads: reads, origins: reads.map { _ in anchor },
                                           clock: clock, inherited: shutter)
        }
        return out
    }

    private func smearedChildren(reads: [Layer], origins: [CGPoint], clock: SmearClock,
                                 inherited: Double?) -> [Layer] {
        children.enumerated().map { index, child in
            // The same child in every read: in the same place in the list
            // where nothing has rearranged it, and found by name where it has.
            let childReads = reads.map { read -> Layer in
                let kids = read.children
                if index < kids.count, kids[index].id == child.id { return kids[index] }
                return kids.first { $0.id == child.id } ?? child
            }
            return child.smeared(reads: childReads, origins: origins, clock: clock, inherited: inherited)
        }
    }

    /// The four corners of what this layer draws, on the canvas, clockwise
    /// from top left, where its space starts at `origin`.
    ///
    /// A leaf is the box you can see, turned the way it is turned. A group is
    /// measured by the box its contents make NOW (`reference`), carried by
    /// its own anchor and turned the way it is turned: what moves inside it is
    /// that thing's own smear, not the group's.
    func drawnQuad(origin: CGPoint, sizedLike reference: Layer) -> [CGPoint] {
        let corners: [CGPoint]
        if isGroup {
            let box = reference.localBounds.offsetBy(dx: frame.origin.x - reference.frame.origin.x,
                                                     dy: frame.origin.y - reference.frame.origin.y)
            let plain = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                         CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            corners = transform.isIdentity
                ? plain : plain.map { $0.applying(transform.affineTransform(around: turnPivot)) }
        } else {
            corners = transformedCorners
        }
        return corners.map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
    }
}

extension MotionSmear {

    /// The smear of a part whose corners were at `quads`, one per whole
    /// millisecond of `clock`, under a shutter open for `shutterMS` centred on
    /// the moment drawn. Nil where it moved less than `threshold`.
    static func across(quads: [[CGPoint]], clock: SmearClock, shutterMS: Double) -> MotionSmear? {
        guard shutterMS > 0, clock.nowIndex < quads.count, quads.allSatisfy({ $0.count == 4 }) else {
            return nil
        }
        let now = quads[clock.nowIndex]
        let opens = Double(clock.moment) - shutterMS / 2
        let closes = Double(clock.moment) + shutterMS / 2

        /// The corners at any moment inside the reads, in a straight line
        /// between the two whole milliseconds either side.
        func quad(at ms: Double) -> [CGPoint] {
            let at = min(max(ms - Double(clock.fromMS), 0), Double(quads.count - 1))
            let below = Int(at.rounded(.down))
            let above = min(below + 1, quads.count - 1)
            let part = CGFloat(at - Double(below))
            return zip(quads[below], quads[above]).map { a, b in
                CGPoint(x: a.x + (b.x - a.x) * part, y: a.y + (b.y - a.y) * part)
            }
        }

        // How far each corner went, along the way it went: through every
        // whole millisecond inside the shutter, from where it opened to where
        // it closed.
        var stops = [opens]
        var whole = opens.rounded(.down) + 1
        while whole < closes {
            stops.append(whole)
            whole += 1
        }
        stops.append(closes)
        let path = stops.map(quad(at:))
        var span: CGFloat = 0
        for corner in 0..<4 {
            var length: CGFloat = 0
            for (a, b) in zip(path, path.dropFirst()) {
                length += hypot(b[corner].x - a[corner].x, b[corner].y - a[corner].y)
            }
            span = max(span, length)
        }
        guard span > threshold, span.isFinite else { return nil }

        let count = sampleCount(forSpan: span)
        let samples = (0..<count).map { index -> CGAffineTransform in
            let ms = opens + shutterMS * Double(index) / Double(count - 1)
            return mapping(now, onto: quad(at: ms))
        }
        return MotionSmear(samples: samples, span: span)
    }

    /// The transform taking the corners `from` onto the corners `to`: exact
    /// for any slide, growth, turn or lean, which is everything a layer's
    /// motion can do to its box. A box with no area left to measure by (a
    /// line seen edge on) is carried by its middle instead.
    static func mapping(_ from: [CGPoint], onto to: [CGPoint]) -> CGAffineTransform {
        let u = CGPoint(x: from[1].x - from[0].x, y: from[1].y - from[0].y)
        let v = CGPoint(x: from[3].x - from[0].x, y: from[3].y - from[0].y)
        let determinant = u.x * v.y - v.x * u.y
        guard abs(determinant) > 0.5 else {
            let a = middle(from), b = middle(to)
            return CGAffineTransform(translationX: b.x - a.x, y: b.y - a.y)
        }
        let uu = CGPoint(x: to[1].x - to[0].x, y: to[1].y - to[0].y)
        let vv = CGPoint(x: to[3].x - to[0].x, y: to[3].y - to[0].y)
        // M [u v] = [uu vv], so M = [uu vv] [u v]^-1.
        let inverse = (a: v.y / determinant, b: -u.y / determinant,
                       c: -v.x / determinant, d: u.x / determinant)
        // Columns of [u v]^-1 laid out as x' = a x + c y, y' = b x + d y.
        let a = uu.x * inverse.a + vv.x * inverse.b
        let c = uu.x * inverse.c + vv.x * inverse.d
        let b = uu.y * inverse.a + vv.y * inverse.b
        let d = uu.y * inverse.c + vv.y * inverse.d
        let tx = to[0].x - (a * from[0].x + c * from[0].y)
        let ty = to[0].y - (b * from[0].x + d * from[0].y)
        return CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    private static func middle(_ quad: [CGPoint]) -> CGPoint {
        CGPoint(x: quad.map(\.x).reduce(0, +) / 4, y: quad.map(\.y).reduce(0, +) / 4)
    }
}
