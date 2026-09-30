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
///   Glass tinted with the accent, and nothing is painted over it (the user,
///   2026-09-30: "I see no liquid glass refraction on the edges" of the chip
///   that had the accent laid over its glass at 88%). Measured with the probe
///   in front the same day, tinted regular glass draws its tint at full
///   strength (system blue came out 0,121,255), so the word sits on the
///   accent itself. The word is the system's own label on glass, white in
///   dark and black in light; only where that label would not read on the
///   accent (white on yellow in dark) does it take the other scheme's.
/// * **A travelling chip** is a lens: clear glass with a hint of the accent
///   (`lensTint`) riding over the words, so they bend at its edges as it
///   passes. The words under it are their own ink, seen through it.
/// * **A window in the back** greys the chip's tint, as the Mac greys every
///   accent there, and the word keeps the window's own label on it.
/// * **Disabled** greys the chip rather than fading the control.
public enum SegmentInk {
    public enum Scheme: CaseIterable, Sendable {
        case light, dark
    }

    /// How much of the accent tints the clear glass of a travelling chip:
    /// enough to say it is the chip, little enough that the words it lenses
    /// read through it.
    public static let lensTint = 0.18

    /// The system's primary label on glass: white in dark, black in light
    /// (measured on tinted glass on 2026-09-30).
    public static func systemLabel(_ scheme: Scheme) -> RGBA {
        scheme == .dark ? RGBA(r: 1, g: 1, b: 1) : RGBA(r: 0, g: 0, b: 0)
    }

    /// Which scheme's label the picked word takes on a chip of this colour:
    /// the window's own, unless it would not read there, then the other.
    public static func pickedWordScheme(on chip: RGBA, in scheme: Scheme) -> Scheme {
        if Legibility.isLegible(ink: systemLabel(scheme), on: chip) { return scheme }
        let other: Scheme = scheme == .dark ? .light : .dark
        return Legibility.isLegible(ink: systemLabel(other), on: chip) ? other : scheme
    }

    /// The picked word on a chip of this colour.
    public static func pickedWord(on chip: RGBA, in scheme: Scheme) -> RGBA {
        systemLabel(pickedWordScheme(on: chip, in: scheme))
    }

    /// The chip as the system draws it while its window is in the back: its
    /// tint greyed, whatever the accent (measured 2026-09-30).
    public static func inactiveChip(_ scheme: Scheme) -> RGBA {
        scheme == .light ? RGBA(r: 119 / 255, g: 120 / 255, b: 123 / 255) : RGBA(r: 48 / 255, g: 49 / 255, b: 52 / 255)
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
        let chip = chip(accent: accent)
        let lens = over(RGBA(r: chip.r, g: chip.g, b: chip.b, a: lensTint), rail)
        let greyChip = disabledChip(scheme)
        return [
            Pair(state: "unpicked at rest", word: word(scheme), behind: rail),
            Pair(state: "unpicked hovered", word: hoveredWord(scheme), behind: hoverGround),
            Pair(state: "unpicked pressed", word: hoveredWord(scheme), behind: hoverGround),
            Pair(state: "unavailable", word: unavailableWord(scheme), behind: rail),
            Pair(state: "picked", word: pickedWord(on: chip, in: scheme), behind: chip),
            Pair(state: "picked pressed", word: pickedWord(on: chip, in: scheme), behind: chip),
            Pair(state: "under the moving chip", word: word(scheme), behind: lens),
            Pair(state: "picked, window in the back", word: systemLabel(scheme), behind: inactiveChip(scheme)),
            Pair(state: "disabled unpicked", word: word(scheme), behind: rail),
            Pair(state: "disabled picked", word: pickedWord(on: greyChip, in: scheme), behind: greyChip),
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
