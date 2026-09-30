import Foundation

/// The segmented control's colours (`SegmentedControl`, in the app), and the
/// rule they are held to: every word it draws is legible against what is drawn
/// behind it (`Legibility`), in every state, in light and dark, over anything.
/// The user, 2026-09-30: "I do not want white on white or black on black cases
/// EVER", and "I didn't ask specifically for 4.5. I asked specifically for
/// legible." The history bar's filter had shipped a white word on white glass
/// the day before.
///
/// What a word can sit on, and how each is kept readable:
///
/// * **The rail** is solid. A see-through rail took its shade from whatever
///   was behind the control, so a dark word on it over a black screenshot
///   under the history bar would have been black on black.
/// * **The chip** under the picked word is a pane of the system's Liquid
///   Glass tinted with the accent, and the accent laid over it at
///   `chipCover`. Tinted glass alone was measured in the app on 2026-09-30:
///   it veils whatever is under it in light, and drew the chip #B0CCE0, where
///   white reads 1.6:1. So the colour goes on top, the glass showing at its
///   rim and a little through it, and the rule is checked with the glass
///   under it as bright as white. The accent is the system's own, never taken
///   deeper, and the word on it is white, the system's own pairing; only an
///   accent white would vanish into (yellow) takes a dark word instead.
/// * **A word the chip is passing over** is drawn in the chip's ink inside the
///   chip and in its own outside it, so a moving chip never puts a grey word
///   on blue.
/// * **Disabled** greys the chip rather than fading the control.
public enum SegmentInk {
    public enum Scheme: CaseIterable, Sendable {
        case light, dark
    }

    /// How much of the chip's colour lies over its glass. The rest is the
    /// glass showing through, which is what makes it read as glass.
    public static let chipCover = 0.88

    /// The chip as drawn: its colour at `chipCover` over glass as bright as
    /// white, the worst the glass can do to a white word.
    public static func drawnChip(_ chip: RGBA) -> RGBA {
        over(RGBA(r: chip.r, g: chip.g, b: chip.b, a: chipCover), RGBA(r: 1, g: 1, b: 1))
    }

    /// The words on a grey chip, and on the accent wherever they read.
    public static let chipWord = RGBA(r: 1, g: 1, b: 1)

    /// The word on an accent white would vanish into: the kit's ink.
    public static let darkChipWord = hex(0x1A1C22)

    /// The picked word on the chip for an accent: white, the system's own
    /// pairing, unless white is not legible on it even at its most veiled
    /// (the yellow accent, 1.6:1), where it is dark.
    public static func pickedWord(on accent: RGBA) -> RGBA {
        Legibility.isLegible(ink: chipWord, on: drawnChip(chip(accent: accent))) ? chipWord : darkChipWord
    }

    /// The recessed track: darker than the panel and the title bar it sits on
    /// in light, darker than the dark panel in dark.
    public static func rail(_ scheme: Scheme) -> RGBA {
        scheme == .light ? hex(0xE1E4EA) : hex(0x0E1015)
    }

    /// An unpicked word.
    public static func word(_ scheme: Scheme) -> RGBA {
        scheme == .light ? hex(0x454B57) : hex(0xB0B6C2)
    }

    /// An unpicked word under the pointer, or pressed.
    public static func hoveredWord(_ scheme: Scheme) -> RGBA {
        scheme == .light ? hex(0x1A1C22) : hex(0xE7E9EE)
    }

    /// A word that cannot be picked right now: quieter than an unpicked one,
    /// never below legible.
    public static func unavailableWord(_ scheme: Scheme) -> RGBA {
        scheme == .light ? hex(0x5C6371) : hex(0x7E8594)
    }

    /// The faint plate behind an unpicked segment under the pointer.
    public static func hoverPlate(_ scheme: Scheme) -> RGBA {
        scheme == .light ? RGBA(r: 1, g: 1, b: 1, a: 0.55) : RGBA(r: 1, g: 1, b: 1, a: 0.10)
    }

    /// The chip of a disabled control: grey, whatever the accent.
    public static func disabledChip(_ scheme: Scheme) -> RGBA {
        scheme == .light ? hex(0x505662) : hex(0x4B515D)
    }

    /// The chip's colour for an accent: the accent itself, as the system
    /// draws it. Never taken deeper to chase a ratio (the user, 2026-09-30).
    public static func chip(accent: RGBA) -> RGBA {
        RGBA(r: accent.r, g: accent.g, b: accent.b)
    }

    /// One word and what is drawn behind it, named by the state it is drawn in.
    public struct Pair: Sendable {
        public var state: String
        public var word: RGBA
        public var behind: RGBA
    }

    /// Every word the control draws against what is behind it, with the rail
    /// laid over `backdrop`, in every state it can be in.
    public static func pairs(scheme: Scheme, accent: RGBA, backdrop: RGBA) -> [Pair] {
        let rail = over(rail(scheme), backdrop)
        let hoverGround = over(hoverPlate(scheme), rail)
        let chip = drawnChip(chip(accent: accent))
        let greyChip = drawnChip(disabledChip(scheme))
        return [
            Pair(state: "unpicked at rest", word: word(scheme), behind: rail),
            Pair(state: "unpicked hovered", word: hoveredWord(scheme), behind: hoverGround),
            Pair(state: "unpicked pressed", word: hoveredWord(scheme), behind: hoverGround),
            Pair(state: "unavailable", word: unavailableWord(scheme), behind: rail),
            Pair(state: "picked", word: pickedWord(on: accent), behind: chip),
            Pair(state: "picked pressed", word: pickedWord(on: accent), behind: chip),
            Pair(state: "under the moving chip", word: pickedWord(on: accent), behind: chip),
            Pair(state: "disabled unpicked", word: word(scheme), behind: rail),
            Pair(state: "disabled picked", word: chipWord, behind: greyChip),
        ]
    }

    // MARK: - Colour arithmetic

    /// WCAG's contrast ratio, 1 to 21, the same whichever way round.
    public static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let one = luminance(a), two = luminance(b)
        return (max(one, two) + 0.05) / (min(one, two) + 0.05)
    }

    /// WCAG's relative luminance of an sRGB colour, its opacity ignored.
    public static func luminance(_ color: RGBA) -> Double {
        func linear(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    /// `top` laid over a solid `bottom`, by `top`'s opacity.
    public static func over(_ top: RGBA, _ bottom: RGBA) -> RGBA {
        let a = min(max(top.a, 0), 1)
        return RGBA(r: top.r * a + bottom.r * (1 - a),
                    g: top.g * a + bottom.g * (1 - a),
                    b: top.b * a + bottom.b * (1 - a))
    }

    private static func hex(_ value: UInt32) -> RGBA {
        RGBA(r: Double((value >> 16) & 0xFF) / 255,
             g: Double((value >> 8) & 0xFF) / 255,
             b: Double(value & 0xFF) / 255)
    }
}
