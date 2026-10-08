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
        /// The mock's #8B92A1 in light, taken a step deeper: on a hovered
        /// tile's plate and on the transport's glass the mock's value read
        /// 2.6:1, grey on grey (`LegibilitySheet`, the user 2026-09-30: "I do
        /// not want white on white or black on black cases EVER").
        static let faint = Tone(light: rgb(0x7C8392), dark: rgb(0x8B93A2))
        static let line = Tone(light: rgb(0xE2E4EA), dark: rgb(0x262A33))
        static let lineStrong = Tone(light: rgb(0xD4D7DF), dark: rgb(0x333846))
        /// Components, and anything keyed: key diamonds, animating rows.
        static let comp = Tone(light: rgb(0x9A5CFF), dark: rgb(0xB98CFF))
        static let compLine = Tone(light: rgb(0xD8C4FF), dark: rgb(0x3D2F63))
        /// A sound lane's own colour, by which sound track it is from the top
        /// (`video-audio.html`'s `col`): cyan for the first, purple for the
        /// second, and round again. Its fade diamonds are ringed in it and its
        /// level points filled with it.
        static func soundTrack(_ number: Int) -> Color {
            number % 2 == 0 ? rgb(0x12C2E9) : rgb(0xC56CFF)
        }
        /// The playhead.
        static let crit = Tone(light: rgb(0xD0453B), dark: rgb(0xF0685C))
        /// A picked cut or transition.
        static let warn = Tone(light: rgb(0xB7791F), dark: rgb(0xE0A53A))
        /// Marks on the scrubber (in and out).
        static let good = Tone(light: rgb(0x1A9E6A), dark: rgb(0x3ECF8E))
        /// A raised plate: the selected segment (`--raised`).
        static let raised = Tone(light: rgb(0xFFFFFF), dark: rgb(0x252A36))
        /// A box you type into (`--well`): sunk below the panel, where a
        /// dropdown's face is raised above it.
        static let well = Tone(light: rgb(0xEEF0F5), dark: rgb(0x0E1015))
        /// A transition on the timeline (`.xband`): one picture becoming
        /// another, cyan into orange at 75%, with a dark icon on it. The mock
        /// draws it over its dark timeline; the band carries that dark under
        /// it as its own base, so it looks as the mock's does over any clip and
        /// a clip's name under it never shows through.
        static let transitionFrom = Tone(light: rgb(0x12C2E9, 0.75), dark: rgb(0x12C2E9, 0.75))
        static let transitionTo = Tone(light: rgb(0xFF9D5C, 0.75), dark: rgb(0xFF9D5C, 0.75))
        static let transitionBase = Tone(light: rgb(0x14161D), dark: rgb(0x14161D))
        static let transitionInk = Tone(light: rgb(0x0B0D18), dark: rgb(0x0B0D18))
        /// A held frame on the timeline (`video-freeze-wt.html`, `.clip.frz`):
        /// blue stripes on a deeper blue, a solid blue edge and pale blue
        /// words. The mock's own values in both appearances, because the
        /// still carries its own dark ground under its words, as the
        /// transition band does.
        static let stillStripe = Tone(light: rgb(0x3A4A7D), dark: rgb(0x3A4A7D))
        static let stillGround = Tone(light: rgb(0x2B3763), dark: rgb(0x2B3763))
        static let stillEdge = Tone(light: rgb(0x55689F), dark: rgb(0x55689F))
        static let stillInk = Tone(light: rgb(0xDBE4FF), dark: rgb(0xDBE4FF))
        static let glassThin = Tone(light: rgb(0xFFFFFF, 0.58), dark: rgb(0x1E222D, 0.6))
        static let glassChrome = Tone(light: rgb(0xFAFBFD, 0.88), dark: rgb(0x161922, 0.78))
        static let edgeLo = Tone(light: rgb(0x161A2A, 0.10), dark: rgb(0x000000, 0.45))
        /// A list that opens over the panel (`--glass-3`): solid, so the rows
        /// it covers never read through the words on it.
        static let plate = Tone(light: rgb(0xFFFFFF), dark: rgb(0x2E3342))
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

// MARK: - Drawn for the legibility check

extension VideoKit {
    /// How a piece is drawn when nobody is pointing at it. Always `.live` in
    /// the app; the legibility check (`LegibilitySheet`) draws every piece
    /// hovered and pressed this way, because a hover is `@State` inside the
    /// piece and an offscreen picture has no pointer. The app's hover seam
    /// (`playtestHover`, which `kitHover` answers with) reports a hover for
    /// anything other than `.live`, and the button styles read `.pressed`.
    enum ShownPointer: Sendable { case live, hovered, pressed }

    /// Which of the legibility check's three drawings this is. The check
    /// draws a control as shipped, then with its words and icons left out
    /// (what lies behind them), then with only them, in one flat colour (where
    /// they are, even a white word on white). Words are `Text` and the check
    /// reaches them itself; anything else that carries ink (an SF Symbol
    /// drawn as an `Image`, words drawn into a bitmap) says so with
    /// `measuredInk()`.
    enum InkPass: Sendable { case shown, bare, mask }

    /// The flat colour of the mask drawing. Nothing in the app is this colour.
    static let maskInk = Color(.sRGB, red: 1, green: 0, blue: 1)
}

private struct ShownPointerKey: EnvironmentKey {
    static let defaultValue = VideoKit.ShownPointer.live
}

private struct InkPassKey: EnvironmentKey {
    static let defaultValue = VideoKit.InkPass.shown
}

private struct DrawnOffscreenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var shownPointer: VideoKit.ShownPointer {
        get { self[ShownPointerKey.self] }
        set { self[ShownPointerKey.self] = newValue }
    }

    var inkPass: VideoKit.InkPass {
        get { self[InkPassKey.self] }
        set { self[InkPassKey.self] = newValue }
    }

    /// True while the legibility check draws a control into a picture, where
    /// an AppKit view (a tooltip's tracking anchor) cannot be drawn and would
    /// leave SwiftUI's placeholder over the words. Never true in the app.
    var drawnOffscreen: Bool {
        get { self[DrawnOffscreenKey.self] }
        set { self[DrawnOffscreenKey.self] = newValue }
    }
}

extension View {
    /// Marks this view as ink (an icon, a bitmap of words) the legibility
    /// check measures against what is behind it. Does nothing in the app.
    func measuredInk() -> some View { modifier(MeasuredInk()) }
}

private struct MeasuredInk: ViewModifier {
    @Environment(\.inkPass) private var pass

    func body(content: Content) -> some View {
        switch pass {
        case .shown: content
        case .bare: content.opacity(0)
        case .mask: content.brightness(1).colorMultiply(VideoKit.maskInk)
        }
    }
}
