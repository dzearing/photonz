import Testing
@testable import PhotonzCore

/// The segmented control's colours, held to the user's rule (2026-09-30): "I do
/// not want white on white or black on black cases EVER", and legible is the
/// bar, not a WCAG grade ("I asked specifically for legible"): the accent is
/// the system's own tinted glass, never deepened or painted over, with the
/// system's own label on it.
///
/// Every word the control draws sits on something this file names: an unpicked
/// word on the rail, a hovered or pressed one on the hover plate over the rail,
/// a picked one on the tinted glass chip, a word the chip is passing over in
/// its own ink through the lens the travelling chip becomes. The rail is
/// opaque, so what lies behind the control (a white title bar, a black
/// screenshot under the history bar) never reaches a word; the tests still lay
/// every pair over white, black and mid grey to prove it.
@Suite("Every word on a segmented control is readable")
struct SegmentInkTests {

    /// The Mac's accent colours as the system draws them, light then dark,
    /// plus a pale custom accent, the hardest case for white words.
    static let accents: [RGBA] = [
        "007AFF", "0A84FF", // blue
        "953D96", "A550A7", // purple
        "F74F9E", "F74F9E", // pink
        "E0383E", "FF5257", // red
        "F7821B", "F7821B", // orange
        "FFC600", "FFC600", // yellow
        "62BA46", "62BA46", // green
        "8C8C8C", "8C8C8C", // graphite
        "C7F0FF",           // a pale custom accent
    ].compactMap { RGBA(hex: $0) }

    static let backdrops: [RGBA] = ["FFFFFF", "000000", "808080"].compactMap { RGBA(hex: $0) }

    @Test("Contrast is WCAG's: white on black is 21, a colour on itself is 1")
    func contrastIsWCAG() throws {
        let white = try #require(RGBA(hex: "FFFFFF")), black = try #require(RGBA(hex: "000000"))
        #expect(abs(SegmentInk.contrast(white, black) - 21) < 0.01)
        #expect(abs(SegmentInk.contrast(black, white) - 21) < 0.01)
        #expect(abs(SegmentInk.contrast(white, white) - 1) < 0.001)
        let blue = try #require(RGBA(hex: "007AFF"))
        #expect(abs(SegmentInk.contrast(white, blue) - 4.02) < 0.01)
    }

    @Test("Laying a see-through colour over another mixes them by its opacity")
    func over() throws {
        let black = try #require(RGBA(hex: "000000"))
        let halfWhite = RGBA(r: 1, g: 1, b: 1, a: 0.5)
        let mixed = SegmentInk.over(halfWhite, black)
        #expect(abs(mixed.r - 0.5) < 0.001 && abs(mixed.g - 0.5) < 0.001 && abs(mixed.b - 0.5) < 0.001)
        #expect(mixed.a == 1)
    }

    @Test("The chip is the accent itself, as the system draws it, never taken deeper")
    func chipIsTheAccent() {
        for accent in Self.accents {
            #expect(SegmentInk.chip(accent: accent) == RGBA(r: accent.r, g: accent.g, b: accent.b))
        }
    }

    @Test("The picked word is the system's own label for the window, white in dark and black in light")
    func pickedWordIsTheSystemsLabel() throws {
        let white = try #require(RGBA(hex: "FFFFFF")), black = try #require(RGBA(hex: "000000"))
        #expect(SegmentInk.systemLabel(.dark) == white)
        #expect(SegmentInk.systemLabel(.light) == black)
        // Measured in the app on 2026-09-30 with the probe in front: on blue,
        // pink, red and graphite glass the system inks its primary label
        // white in dark and black in light, and both read.
        for hex in ["007AFF", "0A84FF", "F74F9E", "E0383E", "FF5257", "8C8C8C"] {
            let accent = try #require(RGBA(hex: hex))
            #expect(SegmentInk.pickedWordScheme(on: accent, in: .dark) == .dark, "dark keeps white on \(hex)")
            #expect(SegmentInk.pickedWordScheme(on: accent, in: .light) == .light, "light keeps black on \(hex)")
        }
    }

    @Test("Where the window's own label would not read on the chip, the word takes the other scheme's")
    func pickedWordFlipsOnlyWhereItMust() throws {
        // The system put white on yellow glass in dark (measured 2026-09-30):
        // white on white. Yellow and a pale accent take the light label.
        for hex in ["FFC600", "C7F0FF"] {
            let accent = try #require(RGBA(hex: hex))
            #expect(SegmentInk.pickedWordScheme(on: accent, in: .dark) == .light, "dark word on \(hex)")
            #expect(SegmentInk.pickedWord(on: accent, in: .dark) == SegmentInk.systemLabel(.light))
        }
        // A disabled chip is a dark grey: black would vanish into it in light.
        #expect(SegmentInk.pickedWordScheme(on: SegmentInk.disabledChip(.light), in: .light) == .dark)
    }

    @Test("A window in the back greys the chip, and the window's own label reads on it in both schemes")
    func windowInTheBack() {
        for scheme in SegmentInk.Scheme.allCases {
            let chip = SegmentInk.inactiveChip(scheme)
            #expect(abs(chip.r - chip.b) < 0.05, "the system's grey")
            #expect(Legibility.isLegible(ink: SegmentInk.systemLabel(scheme), on: chip))
        }
    }

    @Test("Every word the control draws is legible against what is behind it, for every accent, scheme and backdrop")
    func everyWordIsReadable() {
        var failures: [String] = []
        for scheme in SegmentInk.Scheme.allCases {
            for accent in Self.accents {
                for backdrop in Self.backdrops {
                    for pair in SegmentInk.pairs(scheme: scheme, accent: accent, backdrop: backdrop)
                    where !Legibility.isLegible(ink: pair.word, on: pair.behind) {
                        failures.append(String(format: "%@ %@ accent %@ over %@: %.2f:1", pair.state,
                                               "\(scheme)", accent.hexString, backdrop.hexString,
                                               SegmentInk.contrast(pair.word, pair.behind)))
                    }
                }
            }
        }
        #expect(failures.isEmpty, "unreadable words:\n\(failures.joined(separator: "\n"))")
    }

    @Test("Every state the control can be in is on the list the contrast is checked over")
    func everyStateIsChecked() throws {
        let blue = try #require(RGBA(hex: "007AFF"))
        let white = try #require(RGBA(hex: "FFFFFF"))
        let states = Set(SegmentInk.pairs(scheme: .light, accent: blue, backdrop: white).map(\.state))
        for state in ["unpicked at rest", "unpicked hovered", "unpicked pressed", "unavailable",
                      "picked", "picked pressed", "picked, moving", "picked, window in the back",
                      "disabled unpicked", "disabled picked"] {
            #expect(states.contains(state), "\(state) is not checked")
        }
    }

    @Test("The chip is one material: the accent's glass over the rail at one strength, at rest and moving alike")
    func chipIsOneMaterial() throws {
        // The user, 2026-10-01: "There should be no snapping to solid, or
        // transitioning of materials! If it's glass, it's glass." A full
        // tint read as solid blue paint; a separate lens glass while moving
        // read as murky. One glass, one tint, everywhere.
        #expect(SegmentInk.chipGlassTint >= 0.35 && SegmentInk.chipGlassTint <= 0.75)
        let white = try #require(RGBA(hex: "FFFFFF")), black = try #require(RGBA(hex: "000000"))
        for scheme in SegmentInk.Scheme.allCases {
            for accent in Self.accents {
                for backdrop in [white, black] {
                    let pairs = SegmentInk.pairs(scheme: scheme, accent: accent, backdrop: backdrop)
                    let rail = SegmentInk.over(SegmentInk.rail(scheme), backdrop)
                    let expected = SegmentInk.chipDrawn(accent: accent, over: rail)
                    let rest = pairs.first { $0.state == "picked" }
                    let moving = pairs.first { $0.state == "picked, moving" }
                    #expect(rest?.behind == expected)
                    #expect(moving?.behind == expected)
                    #expect(rest?.word == moving?.word)
                }
            }
        }
    }

    @Test("The chip's glass is the accent laid over the rail at the chip's tint")
    func chipDrawnIsTheTintOverTheRail() throws {
        let blue = try #require(RGBA(hex: "007AFF"))
        for scheme in SegmentInk.Scheme.allCases {
            let rail = SegmentInk.rail(scheme)
            #expect(SegmentInk.chipDrawn(accent: blue, over: rail)
                    == SegmentInk.over(RGBA(r: blue.r, g: blue.g, b: blue.b, a: SegmentInk.chipGlassTint), rail))
        }
    }

    @Test("The rail is solid, so nothing behind the control reaches its words")
    func railIsOpaque() {
        for scheme in SegmentInk.Scheme.allCases {
            #expect(SegmentInk.rail(scheme).a == 1)
        }
    }

    @Test("An unavailable word reads quieter than an unpicked one, and a hovered one louder")
    func hierarchy() {
        for scheme in SegmentInk.Scheme.allCases {
            let rail = SegmentInk.rail(scheme)
            let hoverGround = SegmentInk.over(SegmentInk.hoverPlate(scheme), rail)
            let unpicked = SegmentInk.contrast(SegmentInk.word(scheme), rail)
            let unavailable = SegmentInk.contrast(SegmentInk.unavailableWord(scheme), rail)
            let hovered = SegmentInk.contrast(SegmentInk.hoveredWord(scheme), hoverGround)
            #expect(unavailable < unpicked)
            #expect(hovered > unpicked)
        }
    }

    @Test("A disabled control's chip is grey, whatever the accent")
    func disabledChipIsGrey() {
        for scheme in SegmentInk.Scheme.allCases {
            let chip = SegmentInk.disabledChip(scheme)
            #expect(abs(chip.r - chip.b) < 0.1 && abs(chip.g - chip.b) < 0.1)
        }
    }
}
