import SwiftUI

/// **The video kit**: the pieces the video mocks are drawn with, built once.
///
/// `docs/design/mocks/pages/video.html` and its walkthroughs are made of a
/// handful of parts (a transport, clip bars, track headers, a ruler, a
/// playhead, a picker of tiles, a dropdown row, a key diamond). Before this
/// folder every video feature drew its own copy of whichever it needed, and no
/// two copies agreed. Everything in here is the mock's version, with the mock's
/// tokens, so a timeline assembled from these looks like the page it came from.
///
/// Two rules keep the kit useful:
///
/// * **Values in, closures out.** Nothing in this folder reads `EditorState` or
///   any other app type. A caller hands a piece its numbers and its words and
///   gets told when it is clicked or dragged. That is what lets the timeline,
///   the transition picker and whatever comes after all use the same pieces.
/// * **It compiles on its own.** `Scripts/video-kit-gallery.swift` builds these
///   files with nothing else and draws every piece next to the mock
///   (`docs/design/mocks/shared/video-kit/`). If a piece starts to lean on
///   the app, that script stops compiling, and `Scripts/test.sh` typechecks
///   the kit alone for the same reason. The one seam is hover: the kit calls
///   `kitHover`, which the app answers with `playtestHover` (so walks reach
///   it) and the gallery answers with a plain `.onHover`.
///
/// The catalogue, with which mock class each piece is, lives in
/// `docs/design/mocks/shared/UX-PATTERNS.md` under "The video kit".
enum VideoKit {}

// MARK: - Colour

extension VideoKit {
    /// A colour with a light and a dark value, resolved against the view's own
    /// colour scheme. A shape style rather than an `NSColor` so it follows
    /// `.environment(\.colorScheme, …)` too, which is how the gallery script
    /// draws both appearances.
    struct Tone: ShapeStyle {
        let light: Color
        let dark: Color

        func resolve(in environment: EnvironmentValues) -> Color.Resolved {
            (environment.colorScheme == .dark ? dark : light).resolve(in: environment)
        }

        /// The tone as a plain colour, for the places a `ShapeStyle` cannot go
        /// (a gradient stop, a shadow).
        func color(_ scheme: ColorScheme) -> Color { scheme == .dark ? dark : light }
    }

    /// A colour from a mock hex value.
    static func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: alpha)
    }

    /// The mock's tokens (`shared/components/tokens.css`, `glass.css`), light
    /// then dark. Accent is the one exception: the app already draws its
    /// accent in the system's, so the kit does too rather than bring in a
    /// second blue.
    enum Palette {
        static let panel = Tone(light: rgb(0xFBFCFE), dark: rgb(0x14161D))
        static let panel2 = Tone(light: rgb(0xF1F3F7), dark: rgb(0x181B22))
        static let ink = Tone(light: rgb(0x1A1C22), dark: rgb(0xE7E9EE))
        static let dim = Tone(light: rgb(0x5C6371), dark: rgb(0xB0B6C2))
        static let faint = Tone(light: rgb(0x8B92A1), dark: rgb(0x8B93A2))
        static let line = Tone(light: rgb(0xE2E4EA), dark: rgb(0x262A33))
        static let lineStrong = Tone(light: rgb(0xD4D7DF), dark: rgb(0x333846))
        /// Components, and anything keyed: key diamonds, animating rows.
        static let comp = Tone(light: rgb(0x9A5CFF), dark: rgb(0xB98CFF))
        static let compLine = Tone(light: rgb(0xD8C4FF), dark: rgb(0x3D2F63))
        /// The playhead.
        static let crit = Tone(light: rgb(0xD0453B), dark: rgb(0xF0685C))
        /// A picked cut or transition.
        static let warn = Tone(light: rgb(0xB7791F), dark: rgb(0xE0A53A))
        /// Marks on the scrubber (in and out).
        static let good = Tone(light: rgb(0x1A9E6A), dark: rgb(0x3ECF8E))
        static let glassThin = Tone(light: rgb(0xFFFFFF, 0.58), dark: rgb(0x1E222D, 0.6))
        static let glassChrome = Tone(light: rgb(0xFAFBFD, 0.88), dark: rgb(0x161922, 0.78))
        static let edgeLo = Tone(light: rgb(0x161A2A, 0.10), dark: rgb(0x000000, 0.45))
        static let edgeHi = Tone(light: rgb(0xFFFFFF, 0.9), dark: rgb(0xFFFFFF, 0.11))
        static var accent: Color { .accentColor }
    }
}

// MARK: - Size

extension VideoKit {
    /// The mock's measurements, in points (one CSS pixel is one point).
    enum Metrics {
        /// The track header column (`--tl-label`) and the gap to the lanes.
        static let trackHeaderWidth: CGFloat = 58
        static let trackGap: CGFloat = 8
        /// Space between one track and the next (`.track` margin 6px 0).
        static let trackSpacing: CGFloat = 6
        /// A lane, as `inspector.css` draws it, and as `video.html`'s timeline
        /// tightens it.
        static let laneHeight: CGFloat = 34
        static let compactLaneHeight: CGFloat = 28
        static let clipCornerRadius: CGFloat = 6
        static let rulerHeight: CGFloat = 16
        static let playheadWidth: CGFloat = 2
        /// Control heights (`--ctl-h-sm`, `--ctl-h`, `--ctl-h-lg`).
        static let controlSmall: CGFloat = 24
        static let control: CGFloat = 32
        /// The label column of a panel row (`.irow`, `--rl-w`).
        static let rowLabelWidth: CGFloat = 76
        /// The narrowest a picker tile gets before the grid drops a column.
        static let tileMinimumWidth: CGFloat = 96
    }
}
