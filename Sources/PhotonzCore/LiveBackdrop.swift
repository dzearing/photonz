import CoreGraphics
import Foundation

// Title backgrounds that are alive (task
// `title-backgrounds-that-are-alive-auroras-energy`): auroras rippling, streams
// of light, bubbles blooming, rays sweeping, a sketch drawing itself in. Each
// look is worked out every frame on the graphics card (`LiveBackdrops.swift`
// in PhotonzRender), never a video file, and is a kind of paint so it fills a
// title's background shape exactly as a gradient does.
//
// What lives here is what a look IS and what its knobs mean, in plain numbers:
// which looks there are, how far each knob turns, and the colours a look is lit
// with, worked out from the title's theme so the words over it stay legible.

/// One of the moving looks a title's background can wear.
public enum LiveLook: String, CaseIterable, Hashable, Codable, Sendable {
    case aurora
    case energyStreams
    case colorBubbles
    case lightRays
    case lightLeaks
    case windStreams
    case sketch
    case particles
    case liquidGradient
    case gridHorizon

    public var title: String {
        switch self {
        case .aurora: "Aurora"
        case .energyStreams: "Energy Streams"
        case .colorBubbles: "Color Bubbles"
        case .lightRays: "Light Rays"
        case .lightLeaks: "Light Leaks"
        case .windStreams: "Wind Streams"
        case .sketch: "Architectural Sketch"
        case .particles: "Particles"
        case .liquidGradient: "Liquid Gradient"
        case .gridHorizon: "Grid Horizon"
        }
    }

    /// The one knob that is this look's own, beside Speed, Strength and Scale.
    public var shapeKnob: String {
        switch self {
        case .aurora: "Height"
        case .energyStreams: "Trail"
        case .colorBubbles: "Softness"
        case .lightRays: "Angle"
        case .lightLeaks: "Warmth"
        case .windStreams: "Line Weight"
        case .sketch: "Line Weight"
        case .particles: "Depth"
        case .liquidGradient: "Gloss"
        case .gridHorizon: "Horizon"
        }
    }

    /// Where this look's own knob starts.
    public var startingShape: Double {
        switch self {
        case .aurora: 60
        case .energyStreams: 50
        case .colorBubbles: 60
        case .lightRays: 30
        case .lightLeaks: 70
        case .windStreams: 35
        case .sketch: 35
        case .particles: 60
        case .liquidGradient: 50
        case .gridHorizon: 45
        }
    }

    /// Whether the look is soft enough to be worked out at half the frame's
    /// size and enlarged with nothing lost: a look made of glows and blends.
    /// A look made of thin lines or points is worked out at full size.
    public var drawnAtHalfSize: Bool {
        switch self {
        case .aurora, .colorBubbles, .lightRays, .lightLeaks, .liquidGradient: true
        case .energyStreams, .windStreams, .sketch, .particles, .gridHorizon: false
        }
    }
}

/// A moving look and where its knobs stand. Its colours are the paint's stops
/// (`LivePalette`), so a theme recolours it the way it recolours a gradient.
public struct LiveBackdrop: Hashable, Codable, Sendable {
    public var look: LiveLook
    /// How fast it moves, as a percent: 100 is the look as designed, nought
    /// holds it still.
    public var speed: Double
    /// How much light it puts out (or for a sparse look, how much of it there
    /// is), as a percent: 100 is Normal.
    public var strength: Double
    /// How big its parts are, as a percent: 100 is the look as designed.
    public var scale: Double
    /// The look's own knob (`LiveLook.shapeKnob`), nought to 100.
    public var shape: Double

    public static let speedRange: ClosedRange<Double> = 0...300
    public static let strengthRange: ClosedRange<Double> = 0...200
    public static let scaleRange: ClosedRange<Double> = 25...400
    public static let shapeRange: ClosedRange<Double> = 0...100

    public init(look: LiveLook, speed: Double = 100, strength: Double = 100,
                scale: Double = 100, shape: Double? = nil) {
        self.look = look
        self.speed = speed.clamped(to: Self.speedRange)
        self.strength = strength.clamped(to: Self.strengthRange)
        self.scale = scale.clamped(to: Self.scaleRange)
        self.shape = (shape ?? look.startingShape).clamped(to: Self.shapeRange)
    }

    /// The look's own clock at `ms` into the clip, in seconds: the clip's time
    /// at this speed.
    public func seconds(atMS ms: Int) -> Double {
        Double(ms) / 1000 * speed / 100
    }

    /// Every knob of this look, by name and where it stands, in the order the
    /// panel shows them.
    public var knobs: [LiveKnob] {
        [LiveKnob(id: .speed, label: "Speed", value: speed, range: Self.speedRange),
         LiveKnob(id: .strength, label: "Strength", value: strength, range: Self.strengthRange),
         LiveKnob(id: .scale, label: "Scale", value: scale, range: Self.scaleRange),
         LiveKnob(id: .shape, label: look.shapeKnob, value: shape, range: Self.shapeRange)]
    }

    /// The same look with one knob turned, held inside its range.
    public func with(_ knob: LiveKnob.ID, at value: Double) -> LiveBackdrop {
        var turned = self
        switch knob {
        case .speed: turned.speed = value.clamped(to: Self.speedRange)
        case .strength: turned.strength = value.clamped(to: Self.strengthRange)
        case .scale: turned.scale = value.clamped(to: Self.scaleRange)
        case .shape: turned.shape = value.clamped(to: Self.shapeRange)
        }
        return turned
    }

    // A document written before a knob existed still opens: any knob it does
    // not say starts where a new look starts it.
    private enum CodingKeys: String, CodingKey { case look, speed, strength, scale, shape }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let look = try c.decode(LiveLook.self, forKey: .look)
        self.init(look: look,
                  speed: try c.decodeIfPresent(Double.self, forKey: .speed) ?? 100,
                  strength: try c.decodeIfPresent(Double.self, forKey: .strength) ?? 100,
                  scale: try c.decodeIfPresent(Double.self, forKey: .scale) ?? 100,
                  shape: try c.decodeIfPresent(Double.self, forKey: .shape))
    }
}

/// One knob of a moving look, as the panel shows it.
public struct LiveKnob: Hashable, Sendable, Identifiable {
    public enum ID: String, Hashable, Sendable, CaseIterable { case speed, strength, scale, shape }
    public var id: ID
    public var label: String
    public var value: Double
    public var range: ClosedRange<Double>
}

/// The colours a moving look is lit with: the ground it moves over, three
/// lights, and which way round the words over it are.
///
/// Taken from the paint's stops in order: the first is the ground, the rest
/// the lights. A theme's background colours are dark (or pale) on purpose, so
/// that words read over a flat fill of them; lights that dim would not read as
/// light at all, so each is lifted: brightened over a dark ground, deepened a
/// little and made more colourful over a pale one. Their hue is the theme's.
public struct LivePalette: Hashable, Sendable {
    public var ground: RGBA
    public var lights: [RGBA]
    /// True when the ground is light, so the words over it are dark: the look
    /// is then laid on as tints that keep the frame light, never as glows.
    public var lightGround: Bool
    /// Over a dark ground, the brightest any part of the frame may get, as
    /// light (linear luminance): white words read over every part of it.
    /// Over a light ground, the darkest.
    public var limit: Double

    /// Linear luminance a dark ground's look never goes above. White headline
    /// words over it keep better than four to one (`LiveBackdropLegibilityTests`).
    public static let darkGroundCeiling = 0.18
    /// Linear luminance a light ground's look never goes below, unless the
    /// ground itself is darker than that.
    public static let lightGroundFloor = 0.42
    /// A ground brighter than this, as light, is a light ground.
    public static let lightGroundAbove = 0.18

    public init(_ paint: Paint) {
        let colours = paint.orderedStops.compactMap { RGBA(hex: $0.hex) }
        let ground = colours.first ?? RGBA(hex: paint.hex) ?? RGBA(r: 0, g: 0, b: 0)
        self.ground = RGBA(r: ground.r, g: ground.g, b: ground.b)
        let groundLight = ground.linearLuminance
        lightGround = groundLight > Self.lightGroundAbove
        // A grey light is no light at all: the theme's own colours stand in
        // for its greys, and a theme with no colour anywhere borrows a night
        // sky's teal, violet and blue.
        var sources = Array(colours.dropFirst()).filter(Self.hasColour)
        if sources.isEmpty {
            sources = Self.colourless.compactMap(RGBA.init(hex:))
        }
        // Three lights, always: fewer stops go round again, turned a little so
        // two lights are never the same colour.
        var lights: [RGBA] = []
        for index in 0..<3 {
            let source = sources[index % sources.count]
            let turn = Double(index / sources.count) * 40
            lights.append(Self.lifted(source, turnedBy: turn, overLight: lightGround))
        }
        self.lights = lights
        limit = lightGround ? min(Self.lightGroundFloor, groundLight * 0.85) : Self.darkGroundCeiling
    }

    /// Whether a colour reads as a colour rather than a grey: its channels
    /// far enough apart. Saturation alone calls a near white like #F5F5F7
    /// colourful, which it is not to an eye.
    static func hasColour(_ color: RGBA) -> Bool {
        max(color.r, color.g, color.b) - min(color.r, color.g, color.b) > 0.06
    }

    /// The lights a theme with no colour in it is given.
    static let colourless = ["#2EC4B6", "#7B5CFF", "#3D8BFF"]

    /// The grey at `limit`: over a dark ground the brightest the look can
    /// draw, over a light one the darkest. What words over it are read against.
    public var extreme: RGBA {
        let c = limit <= 0.0031308 ? limit * 12.92 : 1.055 * pow(limit, 1 / 2.4) - 0.055
        return RGBA(r: c, g: c, b: c)
    }

    /// A light made to read as light over its ground, keeping its hue.
    static func lifted(_ color: RGBA, turnedBy turn: Double, overLight: Bool) -> RGBA {
        var hsl = color.hsl
        hsl.hue = (hsl.hue + turn).truncatingRemainder(dividingBy: 360)
        let colourful = hasColour(color)
        if overLight {
            hsl.saturation = colourful ? max(hsl.saturation, 0.5) : hsl.saturation
            hsl.lightness = min(max(hsl.lightness, 0.5), 0.68)
        } else {
            hsl.saturation = colourful ? max(hsl.saturation, 0.6) : hsl.saturation
            hsl.lightness = max(hsl.lightness, colourful ? 0.6 : 0.75)
        }
        return RGBA(hsl: hsl)
    }
}

extension RGBA {
    /// Luminance as light: each channel taken off the sRGB curve first, the
    /// number a contrast ratio is worked out from.
    public var linearLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// The contrast ratio between two luminances as light, one to 21.
    public static func contrast(_ one: Double, _ other: Double) -> Double {
        (max(one, other) + 0.05) / (min(one, other) + 0.05)
    }

    /// How far apart words read from what is behind them, as the eye sees
    /// it: the lightness contrast of APCA (the method WCAG 3 drafts), 0 for
    /// none to about 106 for black on white. Unlike the ratio it knows that
    /// a difference between two dark colours is harder to see than the same
    /// ratio between two light ones: #007AFF words on #0056CC have a ratio
    /// of 1.64 and read about 14, while Apple's faint #C7C7CC disabled label
    /// on white has 1.69 and reads about 30.
    public static func lightnessContrast(text: RGBA, on ground: RGBA) -> Double {
        func y(_ colour: RGBA) -> Double {
            let raw = 0.2126729 * pow(colour.r, 2.4) + 0.7151522 * pow(colour.g, 2.4) + 0.0721750 * pow(colour.b, 2.4)
            return raw < 0.022 ? raw + pow(0.022 - raw, 1.414) : raw
        }
        let ink = y(text), back = y(ground)
        let signed = back > ink
            ? (pow(back, 0.56) - pow(ink, 0.57)) * 1.14
            : (pow(back, 0.65) - pow(ink, 0.62)) * 1.14
        return abs(signed) < 0.1 ? 0 : (abs(signed) - 0.027) * 100
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        guard isFinite else { return range.lowerBound }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
