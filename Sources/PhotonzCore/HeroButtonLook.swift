import Foundation

/// The hero button: the one control on a surface that opens the agent, and so
/// the only one that does not wear the accent. It wears a spectrum, and no
/// state may take the spectrum away (`docs/design/mocks/shared/components/
/// button.css`, `.btn.hero`, and `.askbtn[aria-expanded]` in `ask.css`).
///
/// At rest the narrow spectrum runs blue to violet; hover opens a wider one
/// toward pink, lights the top gloss and grows the bloom underneath; pressed
/// keeps it open and tucks the bloom back under. Open (the agent's surface is
/// up) reads as held down, and a pointer on it lifts the bloom one rung.
public struct HeroButtonLook: Sendable, Equatable {
    public enum Pose: Sendable, Equatable, CaseIterable {
        case rest, hovered, pressed, open, openHovered
    }

    public let pose: Pose

    public init(pose: Pose) {
        self.pose = pose
    }

    /// - Parameters:
    ///   - enabled: whether it can be pressed. A disabled one rests.
    ///   - hovering: whether the pointer is on it.
    ///   - pressed: whether it is held down.
    ///   - open: whether what it opens is up.
    public init(enabled: Bool, hovering: Bool, pressed: Bool, open: Bool) {
        if !enabled {
            pose = .rest
        } else if pressed {
            pose = .pressed
        } else if open {
            pose = hovering ? .openHovered : .open
        } else {
            pose = hovering ? .hovered : .rest
        }
    }

    /// Whether the wider blue, violet, pink spectrum is over the resting one.
    public var spectrumOpen: Bool { pose != .rest }

    /// The bloom underneath.
    public var glow: HeroGlow {
        switch pose {
        case .rest, .openHovered: .resting
        case .hovered: .lifted
        case .pressed, .open: .tucked
        }
    }

    /// The white line along the inside of the top edge, as an opacity. Held
    /// down, the press shadow takes its place.
    public var gloss: Double {
        switch pose {
        case .rest: 0.40
        case .hovered: 0.58
        case .pressed, .open, .openHovered: 0
        }
    }

    /// The deep violet shadow pressed in along the inside of the top edge, as
    /// an opacity.
    public var tuck: Double {
        switch pose {
        case .rest, .hovered: 0
        case .pressed, .open: 0.34
        case .openHovered: 0.26
        }
    }
}

/// One rung of the bloom under a lit control, in the design's own terms: a
/// box shadow `0 <drop> <blur> <spread>` of the hero violet at `strength`.
public struct HeroGlow: Sendable, Equatable {
    /// How far it falls below the control, in points.
    public var drop: Double
    /// The CSS blur length. The Gaussian's deviation is half of it.
    public var blur: Double
    /// Negative: the bloom is narrower than the control, so it shows beneath
    /// it rather than round it.
    public var spread: Double
    /// The violet's opacity.
    public var strength: Double

    public init(drop: Double, blur: Double, spread: Double, strength: Double) {
        self.drop = drop
        self.blur = blur
        self.spread = spread
        self.strength = strength
    }

    public static let tucked = HeroGlow(drop: 4, blur: 12, spread: -4, strength: 0.55)
    public static let resting = HeroGlow(drop: 6, blur: 16, spread: -6, strength: 0.60)
    public static let lifted = HeroGlow(drop: 8, blur: 22, spread: -6, strength: 0.66)
}

/// The single light sheen a hover sweeps across the hero button: a soft white
/// band a little over half the button wide, parked off the leading edge,
/// carried past the trailing edge once on `cubic-bezier(.32,.72,.3,1)`,
/// fully lit by 22% of the way and gone by the end (`@keyframes hero-sheen`).
public enum HeroSheen {
    public static let duration = 0.66
    /// The band's width as a share of the button's.
    public static let bandWidth = 0.55
    /// Where the band's leading edge is parked, as a share of the button's
    /// width from its leading edge.
    public static let parkedLead = -0.40
    /// How far it travels: 260% of its own width.
    public static let travel = 2.6 * bandWidth
    /// How far through the sweep it is fully lit.
    public static let litAt = 0.22

    public struct Frame: Sendable, Equatable {
        /// The band's leading edge, as a share of the button's width.
        public var lead: Double
        /// 0 unseen, 1 fully lit.
        public var opacity: Double
    }

    /// Whether the pointer coming onto the button (`arriving`) or leaving it
    /// sweeps the band: every arrival does, from the start, however many came
    /// before and even while the last sweep is still crossing. Leaving never
    /// does; Reduce Motion keeps the colour change and skips the sweep, and a
    /// dimmed button does not answer the pointer.
    public static func sweeps(arriving: Bool, enabled: Bool, reduceMotion: Bool) -> Bool {
        arriving && enabled && !reduceMotion
    }

    /// The band `elapsed` seconds after the pointer arrived.
    public static func frame(at elapsed: Double) -> Frame {
        let t = min(max(elapsed / duration, 0), 1)
        let moved = eased(t)
        let opacity = t <= litAt ? eased(t / litAt) : 1 - eased((t - litAt) / (1 - litAt))
        return Frame(lead: parkedLead + travel * moved, opacity: min(max(opacity, 0), 1))
    }

    private static func eased(_ t: Double) -> Double {
        CubicBezier.value(t, 0.32, 0.72, 0.3, 1)
    }
}

/// The hero button's colours: blue, violet and pink, and the two gradients
/// they make. At rest a 120 degree line runs blue to violet; open, the wider
/// blue at -12%, violet at 46%, pink at 112% is cut to the button's own ends,
/// so its leading edge is already a little violet and its trailing edge most
/// of the way to pink.
public struct HeroSpectrum: Sendable, Equatable {
    public static let blue = RGBA(r: 0x6E / 255.0, g: 0x8B / 255.0, b: 1)
    public static let violet = RGBA(r: 0xC5 / 255.0, g: 0x6C / 255.0, b: 1)
    public static let pink = RGBA(r: 1, g: 0x7A / 255.0, b: 0xB8 / 255.0)

    /// The colour at the leading end of the line.
    public var first: RGBA
    /// Where violet sits between the ends, when it is a stop of its own.
    public var violetAt: Double?
    /// The colour at the trailing end.
    public var last: RGBA

    public static let resting = HeroSpectrum(first: blue, violetAt: nil, last: violet)
    public static let open = HeroSpectrum(first: mix(blue, violet, 0.12 / 0.58), violetAt: 0.46,
                                          last: mix(violet, pink, 0.54 / 0.66))

    /// `share` of the way from one colour to the other, in sRGB, the way a
    /// browser blends a gradient between two stops.
    public static func mix(_ from: RGBA, _ to: RGBA, _ share: Double) -> RGBA {
        RGBA(r: from.r + (to.r - from.r) * share,
             g: from.g + (to.g - from.g) * share,
             b: from.b + (to.b - from.b) * share,
             a: from.a + (to.a - from.a) * share)
    }

    /// A CSS `linear-gradient(<degrees>deg, …)` line on a box of this size,
    /// as unit points: through the middle, at the angle measured in points
    /// rather than in the unit square, and long enough that the corners land
    /// on its ends.
    public static func line(width: Double, height: Double,
                            degrees: Double) -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        guard width > 0, height > 0 else { return ((0, 0.5), (1, 0.5)) }
        let radians = degrees * .pi / 180
        // CSS: 0deg points up, 90deg right; y grows downward.
        let dx = sin(radians), dy = -cos(radians)
        let half = (abs(width * dx) + abs(height * dy)) / 2
        let ux = dx * half / width, uy = dy * half / height
        return ((0.5 - ux, 0.5 - uy), (0.5 + ux, 0.5 + uy))
    }
}
