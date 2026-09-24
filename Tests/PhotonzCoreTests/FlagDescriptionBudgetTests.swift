import Testing
@testable import PhotonzCore

/// The description under an Experiments switch is short
/// (`panel-copy-and-flag-descriptions-have-a-length-b`, 2026-09-24).
///
/// On the day this arrived, 92 of the 95 switches were over
/// `CopyBudget.flagDescriptionWords`, the median at 179 words and the longest
/// at 557. `allowed` holds each of those at the length it had, so none may
/// grow, a new switch may not join them, and a rewrite that brings one under
/// the budget has to strike it off (`experiments-switches-say-what-they-do-in-a-sente`).
@Suite("Experiments switch descriptions fit the word budget")
struct FlagDescriptionBudgetTests {

    static let allowed: [String: Int] = [
        "next-a-box-says-what-it-picks": 128,
        "next-a-component-on-the-timeline": 254,
        "next-a-drag-says-its-numbers": 253,
        "next-a-layer-is-its-pixels": 213,
        "next-a-recording-is-a-document": 251,
        "next-a-row-says-its-words": 232,
        "next-a-separated-row-says-its-words": 290,
        "next-a-separation-arrives-shut": 173,
        "next-a-title-has-an-in-and-an-out": 281,
        "next-align-layers": 113,
        "next-arrow-captions": 53,
        "next-auto-layout": 520,
        "next-blank-canvas": 96,
        "next-blend-mode": 158,
        "next-callout-magnification": 160,
        "next-callout-shape": 83,
        "next-canvas-grid": 340,
        "next-canvas-menu": 106,
        "next-captions-from-the-sound": 264,
        "next-capture-toast-edit": 42,
        "next-color-drag": 384,
        "next-color-picker": 257,
        "next-components": 103,
        "next-copy-a-look": 242,
        "next-copy-picks-your-layer": 253,
        "next-corner-handles": 114,
        "next-crisp-zoom": 120,
        "next-cut-a-recording": 295,
        "next-cut-says-what-it-cannot-do": 174,
        "next-double-click-reads-a-label": 172,
        "next-dropping-a-sound-or-a-video": 257,
        "next-edge-grab": 126,
        "next-export-animated-svg": 238,
        "next-export-quality": 262,
        "next-export-svg": 274,
        "next-export-the-video": 251,
        "next-export-webp": 195,
        "next-find-a-layer": 250,
        "next-frames": 125,
        "next-geometry-fields": 211,
        "next-grab-cue": 139,
        "next-hear-the-scrub": 197,
        "next-icon-frames": 226,
        "next-icon-previews": 317,
        "next-layer-groups": 91,
        "next-layers-combine": 236,
        "next-layers-follow-pick": 121,
        "next-lens": 236,
        "next-library": 100,
        "next-line-ends": 268,
        "next-measure-guide-snap": 59,
        "next-measure-layer-snap": 57,
        "next-measure-modes": 68,
        "next-measure-panel": 53,
        "next-measure-readout-slide": 45,
        "next-measure-roles": 47,
        "next-motion": 339,
        "next-motion-strip": 255,
        "next-new-layer-via-cut": 211,
        "next-open-out-the-timeline": 300,
        "next-opening-a-recording": 315,
        "next-panel-sections": 160,
        "next-paste-hands-you-the-pointer": 175,
        "next-pen": 538,
        "next-placement": 156,
        "next-punch-in-and-hold": 311,
        "next-read-every-label": 211,
        "next-recording-export-sheet": 414,
        "next-reshape-a-path": 227,
        "next-saving-a-recording-says-so": 225,
        "next-separate-into-layers": 283,
        "next-settings-window": 179,
        "next-setup-takes-no-for-an-answer": 106,
        "next-shape-parts": 170,
        "next-shared-library": 174,
        "next-sound-on-the-timeline": 285,
        "next-starter-components": 127,
        "next-styles": 195,
        "next-the-mix-says-how-loud-it-is": 250,
        "next-tool-bar-feedback": 55,
        "next-tool-groups": 67,
        "next-tool-options": 75,
        "next-tool-settings": 132,
        "next-tool-tips": 105,
        "next-transitions-at-a-cut": 241,
        "next-turn-into-path": 557,
        "next-tutorials": 107,
        "next-undo-puts-back-your-marquee": 179,
        "next-what-a-separation-left-behind": 261,
        "next-where-the-point-will-land": 255,
        "next-window-capture": 64,
        "next-window-modes": 173,
    ]

    static var flags: [FeatureFlag] {
        var seen: [String: FeatureFlag] = [:]
        for release in Release.allCases {
            for flag in FeatureCatalog.flags(for: release) where seen[flag.name] == nil {
                seen[flag.name] = flag
            }
        }
        return seen.values.sorted { $0.name < $1.name }
    }

    @Test func noDescriptionOutgrowsItsBudget() {
        for flag in Self.flags {
            let words = CopyBudget.words(in: flag.description)
            let limit = Self.allowed[flag.name] ?? CopyBudget.flagDescriptionWords
            #expect(words <= limit, """
                \(flag.name) says \(words) words; the budget is \(limit). Say what the switch \
                changes in a sentence or two.
                """)
        }
    }

    @Test func theAllowanceOnlyShrinks() {
        let byName = Dictionary(uniqueKeysWithValues: Self.flags.map { ($0.name, $0) })
        for (name, words) in Self.allowed {
            guard let flag = byName[name] else {
                Issue.record("\(name) is no longer a switch; strike it off `allowed`")
                continue
            }
            let now = CopyBudget.words(in: flag.description)
            #expect(now > CopyBudget.flagDescriptionWords,
                    "\(name) is \(now) words now, inside the budget; strike it off `allowed`")
            #expect(now >= words || now <= CopyBudget.flagDescriptionWords,
                    "\(name) shrank to \(now) words; lower its allowance to match")
        }
    }
}
