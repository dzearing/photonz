import CoreGraphics
import Foundation

/// Every control the caption panels show, and the one setting of the look
/// each reads and writes: the Captions section's Show, Lines, Said, Coming and
/// the word being said, and the Text section's type, colours and shadow.
///
/// The panels write through here rather than each row reaching into the look
/// on its own, so one list says what every control does and a test can drive
/// every one of them (`CaptionLookControlTests`). On 2026-09-28 the user found
/// every caption style control dead; the cause was the dropdowns' hit target,
/// but nothing at the time could say which controls reached the caption.
public enum CaptionLookControl: String, CaseIterable, Hashable, Sendable {
    // The Captions section.
    case show, lines, said, coming
    case wordColour, wordPill, wordGlow, wordStroke, wordShadow, wordScale, animation, speed
    // The Text section.
    case font, size, weight, textColour, background, glow, stroke, shadow, align

    /// What kind of control shows it.
    public enum Kind: Hashable, Sendable {
        case menu, segments, colour, toggle, slider
    }

    public var kind: Kind {
        switch self {
        case .show, .said, .coming, .animation, .font, .size, .weight, .shadow: .menu
        case .lines, .align: .segments
        case .wordColour, .wordPill, .wordGlow, .wordStroke, .textColour, .background, .glow, .stroke: .colour
        case .wordShadow: .toggle
        case .wordScale, .speed: .slider
        }
    }

    /// The row's label.
    public var title: String {
        switch self {
        case .show: "Show"
        case .lines: "Lines"
        case .said: "Said"
        case .coming: "Coming"
        case .wordColour, .textColour: "Colour"
        case .wordPill: "Pill"
        case .wordGlow, .glow: "Glow"
        case .wordStroke, .stroke: "Stroke"
        case .wordShadow, .shadow: "Shadow"
        case .wordScale: "Scale"
        case .animation: "Animation"
        case .speed: "Speed"
        case .font: "Font"
        case .size: "Size"
        case .weight: "Weight"
        case .background: "Background"
        case .align: "Align"
        }
    }

    /// Whether a colour control may hold no colour at all. The words always
    /// have an ink; a pill, a glow, an outline or a plate can be switched off.
    public var allowsNone: Bool {
        kind == .colour && self != .textColour
    }

    /// Other controls a change here moves too: picking a grow gives a word
    /// at full size somewhere to grow to (`CaptionWordLook.pick`).
    public var alsoMoves: Set<CaptionLookControl> {
        self == .animation ? [.wordScale] : []
    }

    public func value(in look: CaptionLook) -> CaptionLookValue {
        switch self {
        case .show: .grouping(look.show)
        case .lines: .count(look.lines)
        case .said: .shade(look.said)
        case .coming: .shade(look.coming)
        case .wordColour: .colour(look.word.colorHex)
        case .wordPill: .colour(look.word.pillHex)
        case .wordGlow: .colour(look.word.glowHex)
        case .wordStroke: .colour(look.word.strokeHex)
        case .wordShadow: .on(look.word.shadow)
        case .wordScale: .amount(look.word.scale)
        case .animation: .motion(look.word.motion)
        case .speed: .ms(look.word.speedMS)
        case .font: .font(look.fontName)
        case .size: .size(look.fontSize)
        case .weight: .weight(look.weight)
        case .textColour: .colour(look.colorHex)
        case .background: .colour(look.backgroundHex)
        case .glow: .colour(look.glowHex)
        case .stroke: .colour(look.strokeHex)
        case .shadow: .shadow(look.shadow)
        case .align: .align(look.alignment)
        }
    }

    /// Write `value` into `look`. A value of the wrong kind for this control,
    /// or none where the control must hold a colour, changes nothing.
    public func set(_ value: CaptionLookValue, in look: inout CaptionLook) {
        switch (self, value) {
        case (.show, .grouping(let show)): look.show = show
        case (.lines, .count(let lines)): look.lines = min(2, max(1, lines))
        case (.said, .shade(let shade)): look.said = shade
        case (.coming, .shade(let shade)): look.coming = shade
        case (.wordColour, .colour(let hex)): look.word.colorHex = hex
        case (.wordPill, .colour(let hex)): look.word.pillHex = hex
        case (.wordGlow, .colour(let hex)): look.word.glowHex = hex
        case (.wordStroke, .colour(let hex)): look.word.strokeHex = hex
        case (.wordShadow, .on(let on)): look.word.shadow = on
        case (.wordScale, .amount(let scale)):
            let range = CaptionWordLook.scaleRange
            look.word.scale = min(range.upperBound, max(range.lowerBound, scale))
        case (.animation, .motion(let motion)): look.word.pick(motion)
        case (.speed, .ms(let ms)):
            let range = CaptionWordLook.speedRange
            look.word.speedMS = min(range.upperBound, max(range.lowerBound, ms))
        case (.font, .font(let name)): look.fontName = name
        case (.size, .size(let size)): look.fontSize = size
        case (.weight, .weight(let weight)): look.weight = weight
        case (.textColour, .colour(let hex?)): look.colorHex = hex
        case (.background, .colour(let hex)): look.backgroundHex = hex
        case (.glow, .colour(let hex)): look.glowHex = hex
        case (.stroke, .colour(let hex)): look.strokeHex = hex
        case (.shadow, .shadow(let shadow)): look.shadow = shadow
        case (.align, .align(let align)): look.alignment = align
        default: break
        }
    }

    /// What a colour well opens its picker on: the colour it holds, or for a
    /// well holding none, a colour that shows on a picture.
    public func openingHex(in look: CaptionLook) -> String {
        if case .colour(let hex?) = value(in: look) { return hex }
        switch self {
        case .background: return CaptionLook.plate
        case .wordStroke, .stroke: return "#000000"
        case .textColour: return "#FFFFFF"
        default: return CaptionLook.activeYellow
        }
    }

    /// A handful of values each control offers: what a test drives every
    /// control through. Menus offer every choice they list.
    public var samples: [CaptionLookValue] {
        switch self {
        case .show: CaptionGrouping.allCases.map { .grouping($0) }
        case .lines: [.count(1), .count(2)]
        case .said: CaptionWordShade.saidChoices.map { .shade($0) }
        case .coming: CaptionWordShade.comingChoices.map { .shade($0) }
        case .wordColour, .wordPill, .wordGlow, .wordStroke, .background, .glow, .stroke:
            [.colour(nil), .colour("#FF4FD8"), .colour("#3ECF8E80")]
        case .textColour: [.colour("#FFFFFF"), .colour("#FFD76A"), .colour("#000000")]
        case .wordShadow: [.on(false), .on(true)]
        case .wordScale: [.amount(1), .amount(1.3), .amount(1.6)]
        case .animation: CaptionWordMotion.allCases.map { .motion($0) }
        case .speed: [.ms(80), .ms(220), .ms(600)]
        case .font: [.font("SF Pro"), .font("New York"), .font("Menlo")]
        case .size: [.size(nil), .size(24), .size(48)]
        case .weight: TextWeight.allCases.map { .weight($0) }
        case .shadow: CaptionShadow.allCases.map { .shadow($0) }
        case .align: TextAlign.allCases.map { .align($0) }
        }
    }

    /// A look where this control has something to act on: several words on
    /// screen for Said and Coming, a motion for Speed, words straight on the
    /// picture for the text's own shadow.
    public var liveBase: CaptionLook {
        var look = CaptionLook.preset(.caption)
        look.show = .line
        switch self {
        case .speed: look.word.pick(.grow)
        case .shadow: look.backgroundHex = nil
        default: break
        }
        return look
    }
}

/// A value one caption control holds.
public enum CaptionLookValue: Hashable, Sendable {
    case grouping(CaptionGrouping)
    case count(Int)
    case shade(CaptionWordShade)
    /// A colour, or nil for none.
    case colour(String?)
    case on(Bool)
    case amount(CGFloat)
    case motion(CaptionWordMotion)
    case ms(Int)
    case font(String)
    /// A size, or nil for the size that reads the same on any picture.
    case size(CGFloat?)
    case weight(TextWeight)
    case shadow(CaptionShadow)
    case align(TextAlign)
}
