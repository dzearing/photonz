import Testing
@testable import PhotonzCore

/// The segmented control's colours, held to the user's rule (2026-09-30): "I do
/// not want white on white or black on black cases EVER."
///
/// Every word the control draws sits on something this file names: an unpicked
/// word on the rail, a hovered or pressed one on the hover plate over the rail,
/// a picked one on the tinted chip, a word the chip is passing over on the chip
/// too (it is drawn in the chip's ink wherever the chip covers it). The rail is
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
        // The system blue, which white on it misses 4.5 by: the reason the
        // chip is a deeper shade of the accent than the accent itself.
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

    @Test("The chip is the accent itself when white already reads on it, and a deeper shade of it when not")
    func chipKeepsTheAccentsHue() throws {
        let deep = try #require(RGBA(hex: "1F3A8A"))
        #expect(SegmentInk.chip(accent: deep) == deep)
        let blue = try #require(RGBA(hex: "007AFF"))
        let chip = SegmentInk.chip(accent: blue)
        #expect(SegmentInk.contrast(SegmentInk.chipWord, SegmentInk.drawnChip(chip)) >= SegmentInk.chipMargin)
        // Deeper, the same hue: blue stays the strongest channel.
        #expect(chip.b > chip.g && chip.g > chip.r)
        #expect(chip.b < blue.b + 0.0001)
    }

    @Test("Every word the control draws clears 4.5:1 against what is behind it, for every accent, scheme and backdrop")
    func everyWordIsReadable() {
        var failures: [String] = []
        for scheme in SegmentInk.Scheme.allCases {
            for accent in Self.accents {
                for backdrop in Self.backdrops {
                    for pair in SegmentInk.pairs(scheme: scheme, accent: accent, backdrop: backdrop) {
                        let ratio = SegmentInk.contrast(pair.word, pair.behind)
                        if ratio < SegmentInk.minimum {
                            failures.append(String(format: "%@ %@ accent %@ over %@: %.2f:1", pair.state,
                                                   "\(scheme)", accent.hexString, backdrop.hexString, ratio))
                        }
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
                      "picked", "picked pressed", "under the moving chip", "disabled unpicked",
                      "disabled picked"] {
            #expect(states.contains(state), "\(state) is not checked")
        }
    }

    @Test("The chip reads as its colour even where the glass under it is as bright as white")
    func chipHoldsOverBrightGlass() throws {
        // Measured on the app on 2026-09-30: tinted glass alone, over a solid
        // capsule of the chip's colour, drew #B0CCE0 (regular) and #7B92BA
        // (clear) in light, where white reads 1.6:1 and 3.3:1. So the chip's
        // colour is laid over the glass, and is held to the rule with the
        // glass under it as bright as it can be.
        #expect(SegmentInk.chipCover >= 0.8 && SegmentInk.chipCover < 1)
        let white = try #require(RGBA(hex: "FFFFFF"))
        for accent in Self.accents {
            let drawn = SegmentInk.drawnChip(SegmentInk.chip(accent: accent))
            #expect(drawn == SegmentInk.over(RGBA(r: SegmentInk.chip(accent: accent).r,
                                                  g: SegmentInk.chip(accent: accent).g,
                                                  b: SegmentInk.chip(accent: accent).b,
                                                  a: SegmentInk.chipCover), white))
            #expect(SegmentInk.contrast(SegmentInk.chipWord, drawn) >= SegmentInk.minimum)
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
