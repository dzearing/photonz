import Foundation

// Compositing is layers with a rule for how they combine
// (`docs/design/mocks/pages/video-compositing.html`).
//
// There are three such rules and they answer three different questions:
//
//   - **Blending** (`BlendMode.swift`) — how this layer's colours are mixed
//     with the colours under it.
//   - **Key** (here) — which of this layer's OWN pixels survive at all, decided
//     by their colour.
//   - **Matte** (here) — what shape this layer is allowed to be, borrowed from
//     the layer under it.
//
// All three are properties of the selected layer, set where its other
// properties are set, because there is no compositing MODE: a layer over
// another layer is compositing, and these are the knobs on it. The stack the
// rules read is the same stack the layers list shows and the timeline draws,
// which is why reordering is the one gesture that changes all three at once.
//
// What is deliberately NOT here: light wrap, garbage mattes, a second blend
// control. The first two are looks rather than keys, and the third already
// exists.

// MARK: - Keying a colour out

/// A colour made transparent wherever it appears in a layer, and the two
/// numbers that decide how forgiving that is.
///
/// **Why it measures colour and not brightness.** A wall of flat green is never
/// flat: it is lit from one side, it falls off into the corners, and a fold in
/// it is the same green two stops down. Comparing the three stored numbers
/// straight would call the lit half a match and the shaded half a miss, which
/// is exactly the key that leaves a ragged grey rind round everything. So the
/// pixel and the key colour are both taken apart into brightness and colour
/// (Rec. 601, the same split every video file is already stored in), and only
/// the COLOUR halves are compared. Brightness is thrown away, so a shadow on
/// the wall keys out with the wall.
///
/// Three numbers, and each one is a sentence:
///
///   - `tolerance` — how far from the colour still counts as it. Wider takes
///     more of the wall, and eventually takes some of the subject.
///   - `softness` — the width of the band that comes out PART transparent, which
///     is what makes the edge a fade rather than a staircase.
///   - `spill` — how much of the key's own colour is pulled back out of what
///     survives, which is what takes the green rim off somebody's shoulder.
///
/// The maths is here, in a pure function over one pixel, rather than in the
/// renderer: `DocumentRenderer` builds a colour cube by asking this for every
/// colour there is, so what the GPU does to a frame is exactly what the tests
/// above check one pixel at a time.
public struct ChromaKey: Hashable, Codable, Sendable {

    /// The colour being removed, as it is written everywhere else in the
    /// document: `#RRGGBB`.
    public var colorHex: String
    /// How far from that colour still counts as it, as a distance in the
    /// colour plane. Nought keys the one exact colour; by one it has taken
    /// everything up to white with it.
    public var tolerance: Double
    /// The width of the part-transparent band just outside the tolerance.
    public var softness: Double
    /// How much of the key's colour is taken back out of what survives.
    public var spill: Double
    /// Off leaves every pixel exactly as it was, so switching a key off is one
    /// click rather than remembering what its numbers used to be.
    public var isOn: Bool

    /// What one click of Key it starts from. Wide enough to take a real wall
    /// with its lighting, narrow enough to leave skin, hair and a blue shirt
    /// standing.
    public static let startingTolerance = 0.18
    public static let startingSoftness = 0.10
    public static let startingSpill = 0.60

    /// How far round from the key's own hue the spill correction still
    /// reaches, as the cosine of the angle between them: 1 is exactly the
    /// key's hue and 0.5 is sixty degrees off it, where the correction has
    /// faded to nothing. Without this gate a blue shirt is corrected too,
    /// because blue and green share half the colour plane between them.
    static let spillHorizon = 0.5

    public init(colorHex: String,
                tolerance: Double = ChromaKey.startingTolerance,
                softness: Double = ChromaKey.startingSoftness,
                spill: Double = ChromaKey.startingSpill,
                isOn: Bool = true) {
        self.colorHex = colorHex
        self.tolerance = min(max(0, tolerance), 1)
        self.softness = min(max(0, softness), 1)
        self.spill = min(max(0, spill), 1)
        self.isOn = isOn
    }

    /// What this key leaves of one pixel: the colour after spill has been taken
    /// out of it, and how much of it is still there.
    ///
    /// Straight alpha, not premultiplied. Whoever needs it premultiplied says so
    /// where they need it, which for the renderer is the one line that packs a
    /// colour cube.
    public func applied(to pixel: RGBA) -> KeyedPixel {
        guard isOn, let key = RGBA(hex: colorHex) else {
            return KeyedPixel(r: pixel.r, g: pixel.g, b: pixel.b, alpha: 1)
        }
        let keyChroma = ChromaKey.chroma(of: key)
        // A key on grey or white has no colour to look for: every pixel is the
        // same distance from the middle of the plane, so keying on it would
        // take the whole picture. Leave it be rather than empty the canvas.
        let keyStrength = (keyChroma.cb * keyChroma.cb + keyChroma.cr * keyChroma.cr).squareRoot()
        guard keyStrength > 0.02 else {
            return KeyedPixel(r: pixel.r, g: pixel.g, b: pixel.b, alpha: 1)
        }

        let here = ChromaKey.chroma(of: pixel)
        // Compared with the brightness divided back out of both. The colour
        // numbers a video is stored in shrink towards nothing as a pixel gets
        // darker, so the SAME green in shadow sits measurably nearer neutral
        // than the lit green beside it — near enough to fall outside any
        // tolerance tight enough to be useful, which is the ragged rind along
        // the bottom of every cheap key. Divided through, the shaded wall and
        // the lit wall are the same point.
        let mine = ChromaKey.evenly(here)
        let theirs = ChromaKey.evenly(keyChroma)
        let dcb = mine.cb - theirs.cb
        let dcr = mine.cr - theirs.cr
        let distance = (dcb * dcb + dcr * dcr).squareRoot()

        // Inside the tolerance the pixel IS the wall; across the softness band
        // it is part wall and part subject; past that it is the subject.
        // Smoothstepped, so the two ends of the band meet the flat either side
        // without a crease in them.
        let inner = tolerance
        let band = max(softness, 0.0001)
        let t = min(max((distance - inner) / band, 0), 1)
        let alpha = t * t * (3 - 2 * t)

        // Spill: the amount this pixel leans TOWARDS the key's colour, taken
        // back out along that same direction. Brightness is not touched, so the
        // rim loses its green without the shoulder going dark.
        var cb = here.cb
        var cr = here.cr
        let strength = (here.cb * here.cb + here.cr * here.cr).squareRoot()
        if spill > 0, strength > 0.0001 {
            let ux = keyChroma.cb / keyStrength
            let uy = keyChroma.cr / keyStrength
            let lean = here.cb * ux + here.cr * uy
            // How nearly this pixel's colour IS the key's colour, regardless of
            // how much of it there is: a faint green cast and a bright green
            // wall point the same way.
            let sameWay = lean / strength
            if lean > 0, sameWay > ChromaKey.spillHorizon {
                let fade = (sameWay - ChromaKey.spillHorizon) / (1 - ChromaKey.spillHorizon)
                let take = lean * spill * fade
                cb -= take * ux
                cr -= take * uy
            }
        }

        let out = ChromaKey.colour(brightness: here.y, cb: cb, cr: cr)
        return KeyedPixel(r: out.r, g: out.g, b: out.b, alpha: alpha)
    }

    // MARK: The colour plane

    /// A colour split into brightness and the two numbers that say which colour
    /// it is, Rec. 601. The two colour numbers are stated as offsets from
    /// neutral, so grey is (0, 0) and the distance between two colours is
    /// simply the distance between two points.
    static func chroma(of colour: RGBA) -> (y: Double, cb: Double, cr: Double) {
        let y = 0.299 * colour.r + 0.587 * colour.g + 0.114 * colour.b
        return (y, (colour.b - y) / 1.772, (colour.r - y) / 1.402)
    }

    /// The same colour with its brightness divided back out, so two shades of
    /// one colour land on one point.
    ///
    /// The floor under the division is what stops the near-black corners of a
    /// picture being amplified into whatever colour their last bit of noise
    /// happens to be.
    static func evenly(_ c: (y: Double, cb: Double, cr: Double)) -> (cb: Double, cr: Double) {
        let scale = max(c.y, 0.2)
        return (c.cb / scale, c.cr / scale)
    }

    /// The way back, clamped: spill can push a colour past what a screen can
    /// show, and a channel over one wraps round to black in a byte.
    static func colour(brightness y: Double, cb: Double, cr: Double) -> RGBA {
        let r = y + 1.402 * cr
        let b = y + 1.772 * cb
        let g = (y - 0.299 * r - 0.114 * b) / 0.587
        func held(_ value: Double) -> Double { min(max(value, 0), 1) }
        return RGBA(r: held(r), g: held(g), b: held(b))
    }
}

/// One pixel after a key has been through it.
public struct KeyedPixel: Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    /// Straight alpha: nought where the key took it, one where it did not.
    public var alpha: Double

    public init(r: Double, g: Double, b: Double, alpha: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.alpha = alpha
    }
}

// MARK: - Borrowing a shape from the layer below

/// What a layer takes from the one directly under it when it is masked by it.
///
/// **Why the layer BELOW, and not a layer picked from a list.** A stored id can
/// point at a layer somebody deleted, renamed or dragged into a group, and then
/// the mask is a setting that silently stopped meaning anything. Under it is
/// where Photoshop's clipping mask has always looked, it needs nothing stored
/// but the kind, and it makes reordering change the mask exactly the way
/// reordering changes the composite — which is the whole thesis: the stack is
/// the rule.
///
/// A layer spent as somebody's matte stops drawing on its own. It is not in the
/// picture any more, it is the shape of the picture.
public enum LayerMatte: String, Hashable, Codable, Sendable, CaseIterable {
    /// Its shape: wherever the layer below is solid, this one shows; where it
    /// is transparent, this one is gone. A hard edge, letterforms included.
    case shape
    /// Its brightness: white shows this layer completely, black hides it, and
    /// everything between fades. A gradient below becomes a fade above.
    case brightness

    /// The word in the control.
    public var title: String {
        switch self {
        case .shape: "Its shape"
        case .brightness: "Its brightness"
        }
    }

    /// The thing being borrowed, as a noun that drops into the middle of a
    /// sentence: "cut to the shape of Rectangle".
    public var borrowedThing: String {
        switch self {
        case .shape: "shape"
        case .brightness: "brightness"
        }
    }

    /// What it does, for somebody who has never masked anything. One sentence,
    /// and no vocabulary from another tool.
    public var explanation: String {
        switch self {
        case .shape:
            "Shows this layer only where the layer below has something drawn, edges and all."
        case .brightness:
            "Shows this layer where the layer below is light and hides it where it is dark, so a fade below fades this one."
        }
    }

    /// A kind written by a build that knows more of them than this one does.
    /// Unknown means no matte, never a document that refuses to open.
    public static func named(_ raw: String?) -> LayerMatte? {
        guard let raw else { return nil }
        return LayerMatte(rawValue: raw)
    }
}

// MARK: - Which layer supplies which mask

extension PhotonzDocument {

    /// The layer that gives `id` its shape: the one directly under it among its
    /// own siblings, inside a group or at the top level.
    ///
    /// Nil when there is nothing under it, when it is not asking to be masked,
    /// or when the layer under it is hidden — a layer nobody can see must not
    /// be quietly cutting somebody else's shape out.
    public func matteSource(for id: UUID) -> Layer? {
        guard let found = siblings(of: id), found.layer.style.matte != nil else { return nil }
        return Self.matteSource(in: found.list, at: found.index)
    }

    /// Whether this layer is being spent as the layer above's mask, so it draws
    /// no pixels of its own.
    public func isSpentAsAMatte(_ id: UUID) -> Bool {
        guard let found = siblings(of: id), found.layer.isVisible else { return false }
        return Self.matteUser(in: found.list, at: found.index) != nil
    }

    /// The same two questions asked of a sibling list directly, which is how
    /// the layers panel asks them: it already has the list in its hand from its
    /// own walk of the tree, and looking each row up by id again would search
    /// the whole document once per row.
    ///
    /// The rule lives here, once, because three places act on it — the
    /// renderer skips the lower layer, the panel marks both rows, and the
    /// inspector names what a Masked by row would borrow from — and any drift
    /// between them is a row that lies about the picture.

    /// The layer directly under `index` whose shape this one would borrow, or
    /// nil when there is nothing under it or that layer is hidden. It does not
    /// ask whether `index` wants a mask: the inspector asks this to name what a
    /// Masked by set to Nothing WOULD borrow from.
    static func matteSource(in list: [Layer], at index: Int) -> Layer? {
        guard index > 0 else { return nil }
        let below = list[index - 1]
        return below.isVisible ? below : nil
    }

    /// The layer directly above `index` that is spending it as a mask, or nil
    /// when nothing is.
    static func matteUser(in list: [Layer], at index: Int) -> Layer? {
        guard index + 1 < list.count else { return nil }
        let above = list[index + 1]
        return above.isVisible && above.style.matte != nil ? above : nil
    }

    /// The list a layer sits in, and where in it. The top level or a group's
    /// children, whichever holds it. Public because the panel asks it what a
    /// Masked by row would borrow from.
    public func siblings(of id: UUID) -> (list: [Layer], index: Int, layer: Layer)? {
        func search(_ list: [Layer]) -> (list: [Layer], index: Int, layer: Layer)? {
            for (index, layer) in list.enumerated() {
                if layer.id == id { return (list, index, layer) }
                if layer.isGroup, let found = search(layer.children) { return found }
            }
            return nil
        }
        return search(layers)
    }
}

// MARK: - Which layers the Key and Masked by rows speak for

extension Layer {

    /// Whether this layer is made of pixels somebody could key a colour out of.
    ///
    /// A photo, a capture, a frame of a recording: things whose colours came
    /// from the world and cannot simply be edited. A shape, a label or an
    /// arrow has a colour you would change rather than key, so offering a Key
    /// on one would be a control whose job another control already does
    /// better.
    public var canBeKeyed: Bool {
        if case .image = content { return true }
        return false
    }
}

extension LayerStyleSelection {

    /// The picked layers a key can be set on.
    public var keyable: LayerStyleSelection {
        LayerStyleSelection(members: members.filter(\.hasPixelsToKey),
                            selectionCount: selectionCount)
    }

    /// The picked layers that have something under them to borrow a shape from.
    public var maskable: LayerStyleSelection {
        LayerStyleSelection(members: members.filter(\.hasSomethingBelow),
                            selectionCount: selectionCount)
    }
}
