import CoreGraphics
import Foundation

/// The look of the chip an arrow's caption sits on: ten premade styles, picked
/// from picture tiles the way an arrow's own style is.
///
/// The user, 2026-10-24, on the one dark pill with a bright outline every label
/// had: "I would love to have some style options for the chip, just like we
/// have for the arrow ... Each option should look professional." The set and
/// its rules were approved from a prototype on 2026-10-31 and are written down
/// in `docs/design/markup.md` (section 4), with the design system's own copy in
/// `docs/design/mocks/shared/components/markup.css`. When one changes, the
/// other changes with it.
///
/// A style is how the chip is PAINTED, never what it says: the words, the
/// arrow's colour and the chip's size stay what they are whichever it wears.
public enum ChipStyle: String, CaseIterable, Codable, Hashable, Sendable {
    /// The pill every caption wore before there were styles: a dark plate in
    /// the ink, a bright ink outline.
    case today
    /// A lit fill, lighter at the top, a soft inner highlight, no edge.
    case solid
    /// A flat plate with continuous corners: no edge, no shadow.
    case squircle
    /// A white plate ringed by a hairline of the ink, words in the ink.
    case hairline
    /// A frosted, see-through plate with a rim that catches the light.
    case glass
    /// A light card on a soft layered shadow, with an ink stripe.
    case paper
    /// A graphite plate with its own lit rim, an ink dot, monospaced words.
    case spec
    /// A lit fill like Solid, with small square corners.
    case tag
    /// An ink tab on the left holding the accent or marker, words on white.
    case twotone
    /// A swipe of ink behind dark words on a white plate.
    case highlight

    /// What a new caption wears in Next. Chose Solid over Paper because it
    /// keeps the arrow's colour on the chip, which is what a person already
    /// expects of a coloured arrow, and drops only the outline the user
    /// disliked.
    public static let standard: ChipStyle = .solid

    /// The tile's name.
    public var title: String {
        switch self {
        case .today: "Today"
        case .solid: "Solid pill"
        case .squircle: "Flat squircle"
        case .hairline: "Hairline plate"
        case .glass: "Glass"
        case .paper: "Paper"
        case .spec: "Spec badge"
        case .tag: "Lit tag"
        case .twotone: "Two-tone badge"
        case .highlight: "Highlighter"
        }
    }

    /// The tile's tooltip: what it looks like, in a few words.
    public var help: String {
        switch self {
        case .today: "A dark pill with an outline in the colour"
        case .solid: "A lit pill in the colour, no outline"
        case .squircle: "A flat plate with soft corners"
        case .hairline: "A white plate with a fine outline"
        case .glass: "A frosted plate with a bright rim"
        case .paper: "A light card with a colour stripe"
        case .spec: "A graphite badge with a colour dot"
        case .tag: "A lit tag with small corners"
        case .twotone: "A colour tab beside white"
        case .highlight: "A highlighter swipe behind the words"
        }
    }

    /// How round the chip's corners are, as a share of half its height (the
    /// caption's own `captionRoundness` scale). Measured off the design
    /// system's chips, which are 22 to 24 px tall at 12 px type.
    public var roundness: CGFloat {
        switch self {
        case .today, .solid: 1
        case .squircle: 7.0 / 12
        case .hairline: 5.0 / 11
        case .glass: 10.0 / 12
        case .paper: 6.0 / 12
        case .spec: 6.0 / 11
        case .tag: 3.0 / 12
        case .twotone: 6.0 / 12
        case .highlight: 4.0 / 12
        }
    }

    /// Whether the plate is filled with the ink, which decides how a status
    /// marker sits on it (markup.md section 6).
    public var isInkFilled: Bool {
        switch self {
        case .today, .solid, .squircle, .glass, .tag, .twotone: true
        case .hairline, .paper, .spec, .highlight: false
        }
    }

    /// The submenu the styles are listed under on an arrow's right-click menu.
    public static let menuTitle = "Chip Style"

    /// The three colours a chip in this style is painted with for `ink`:
    /// the plate, the edge (nil for none) and the words. They are written onto
    /// the caption (`captionFill`, `captionBorder`, `captionTextColorHex`) so
    /// every reader of those three, the parts list and the SVG export
    /// included, sees what is drawn.
    public func parts(forInk ink: String) -> (fill: String?, edge: String?, text: String) {
        parts(forInk: ink, reading: InkPlate.reading(forInk: ink))
    }

    func parts(forInk ink: String, reading: InkPlate.Reading) -> (fill: String?, edge: String?, text: String) {
        let inkHex = InkPlate.canonical(ink)
        switch self {
        case .today:
            return (LabelPlate.toneHex(from: inkHex), inkHex, "#FFFFFF")
        case .solid, .squircle, .tag:
            return (reading.plateHex, nil, reading.onPlateHex)
        case .hairline:
            // A white ink would ring a white plate invisibly; its edge takes the
            // darkened ink its words are written in instead.
            let inkRGBA = RGBA(hex: inkHex) ?? RGBA(r: 0, g: 0, b: 0)
            let edge = InkPlate.contrast(inkRGBA, RGBA(r: 1, g: 1, b: 1)) < 1.5 ? reading.inkTextHex : inkHex
            return ("#FFFFFF", edge, reading.inkTextHex)
        case .glass:
            return (reading.glassHex, nil, reading.onGlassHex)
        case .paper:
            return ("#FFFFFD", nil, InkPlate.darkWordsHex)
        case .spec:
            return ("#2F2F32", nil, "#F5F5F7")
        case .twotone, .highlight:
            return ("#FFFFFF", nil, InkPlate.darkWordsHex)
        }
    }
}

/// What sits at the front of a chip: the style's own accent, nothing, or a
/// status icon (markup.md section 6).
public enum ChipMarker: String, CaseIterable, Codable, Hashable, Sendable {
    case none
    /// The style's own stripe (Paper), dot (Spec, Two-tone) or nothing.
    case accent
    /// An x in a red circle.
    case error
    /// A ! in a yellow triangle.
    case warning
    /// A check in a green circle.
    case success
    /// An i in a blue circle.
    case info

    public static let standard: ChipMarker = .accent

    public var title: String {
        switch self {
        case .none: "None"
        case .accent: "Accent"
        case .error: "Error"
        case .warning: "Warning"
        case .success: "Done"
        case .info: "Info"
        }
    }

    /// Whether this marker draws a status icon.
    public var isStatus: Bool {
        switch self {
        case .error, .warning, .success, .info: true
        case .none, .accent: false
        }
    }

    /// The status colour, as the Mac's own system colours say it.
    var meaningHex: String? {
        switch self {
        case .error: "#FF3B30"
        case .warning: "#FFCC00"
        case .success: "#34C759"
        case .info: "#0A84FF"
        case .none, .accent: nil
        }
    }

    /// The same colour where it is a glyph on white, which yellow cannot be.
    var meaningOnWhiteHex: String? {
        switch self {
        case .error: "#FF3B30"
        case .warning: "#FF9500"
        case .success: "#28A745"
        case .info: "#0A84FF"
        case .none, .accent: nil
        }
    }
}

/// A part of the caption's chip a person can paint by hand under Advanced.
public enum CaptionPart: String, CaseIterable, Codable, Hashable, Sendable {
    case fill, edge, text
}

/// The ink to plate rule (markup.md section 3): the line keeps the ink as
/// picked, and the plate behind the words is derived from it so they read.
///
/// A port of `PZ.markup.plateFor` in the design system's `markup.js`, step for
/// step and with the same floating point, so the two agree to the hex digit
/// (`ChipStyleTests.plateTable`).
public enum InkPlate {

    public struct Reading: Hashable, Sendable {
        public var plateHex: String
        public var onPlateHex: String
        /// The ink darkened until it reads on white at 4.6:1, for words in the
        /// ink on a white plate.
        public var inkTextHex: String
        /// Words on the plate, WCAG.
        public var contrast: Double
        /// Glass's own tint and its words: judged over a pure white and a
        /// pure black picture at `glassOpacity` (markup.md section 3).
        public var glassHex: String
        public var onGlassHex: String
        public var glassContrast: Double
    }

    /// The dark the words take on a light plate.
    public static let darkWordsHex = "#1D1D1F"

    /// Ink-coloured words on white aim a little over 4.5:1, so rounding the
    /// colour to a whole byte cannot take them under it.
    static let inkTextTarget = 4.6

    /// The colour row's swatches, in the design system's order.
    public static let palette = ["#ff375f", "#ff9f0a", "#ffd60a", "#30d158",
                                 "#0a84ff", "#bf5af2", "#1d1d1f", "#ffffff"]

    /// How far a darkening may go before a light ink keeps its colour and takes
    /// dark words instead.
    static let darkeningLimit = 0.22

    public static func reading(forInk hex: String) -> Reading {
        let ink = components(hex)
        let white = [1.0, 1.0, 1.0]
        let dark = components(darkWordsHex)
        let (darkened, k) = darkenUntil(ink, against: white, target: 4.8)
        let darkWords = k > darkeningLimit && ratio(ink, dark) >= 4.5
        let plate = darkWords ? ink : darkened
        let glass = glassFor(ink)
        return Reading(plateHex: hexString(plate),
                       onPlateHex: darkWords ? darkWordsHex : "#FFFFFF",
                       inkTextHex: hexString(darkenUntil(ink, against: white, target: inkTextTarget).0),
                       contrast: ratio(plate, darkWords ? dark : white),
                       glassHex: hexString(glass.tint), onGlassHex: glass.darkWords ? darkWordsHex : "#FFFFFF",
                       glassContrast: glass.worst)
    }

    /// `glassFor` in markup.js, step for step: white words take a darkened
    /// tint, dark words a lightened one, whichever moves the colour less, so
    /// that at `glassOpacity` the words reach 4.8:1 over white AND black.
    static func glassFor(_ ink: [Double]) -> (tint: [Double], darkWords: Bool, worst: Double) {
        let white = [1.0, 1.0, 1.0], black = [0.0, 0.0, 0.0]
        let dark = components(darkWordsHex)
        func over(_ c: [Double], _ bg: [Double]) -> [Double] {
            (0..<3).map { c[$0] * glassOpacity + bg[$0] * (1 - glassOpacity) }
        }
        func okWhite(_ g: [Double]) -> Bool {
            ratio(over(g, white), white) >= 4.8 && ratio(over(g, black), white) >= 4.8
        }
        func okDark(_ g: [Double]) -> Bool {
            ratio(over(g, white), dark) >= 4.8 && ratio(over(g, black), dark) >= 4.8
        }
        var a: ([Double], Double)?
        var b: ([Double], Double)?
        var k = 0.0
        while k <= 1.0001, a == nil {
            let g = ink.map { $0 * (1 - k) }
            if okWhite(g) { a = (g, k) }
            k += 0.01
        }
        var m = 0.0
        while m <= 1.0001, b == nil {
            let g = ink.map { $0 + (1 - $0) * m }
            if okDark(g) { b = (g, m) }
            m += 0.01
        }
        let darkWords: Bool
        if let b { darkWords = a.map { b.1 < $0.1 } ?? true } else { darkWords = false }
        let tint = (darkWords ? b?.0 : a?.0) ?? black
        let words = darkWords ? dark : white
        let worst = min(ratio(over(tint, white), words), ratio(over(tint, black), words))
        return (tint, darkWords, worst)
    }

    /// How opaque the Glass plate is in the design system's rule: the tint is
    /// chosen so its words read at this opacity over white and black.
    public static let glassOpacity = 0.82

    /// How opaque the app DRAWS Glass. Higher than the rule's 82 percent
    /// because the app composites in linear light, where 82 percent lets more
    /// of a white picture through than the design system's sRGB blend does;
    /// over the 5,472-colour sweep, 95 percent is the least that keeps every
    /// colour at 4.5:1 over white and black that way, so it is drawn at 95 to
    /// 97 top to bottom (`ChipStyleTests.sweepIsLegibleInEveryStyle`). The
    /// tint and its words are the rule's to the hex digit.
    public static let glassDrawnOpacity = 0.96

    /// WCAG contrast between two colours, alpha ignored.
    public static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        ratio([a.r, a.g, a.b], [b.r, b.g, b.b])
    }

    /// `#RRGGBB`, upper case, of whatever hex the ink was given as.
    public static func canonical(_ hex: String) -> String {
        hexString(components(hex))
    }

    // MARK: The arithmetic markup.js does

    static func components(_ hex: String) -> [Double] {
        guard let rgba = RGBA(hex: hex) else { return [0, 0, 0] }
        return [rgba.r, rgba.g, rgba.b]
    }

    static func hexString(_ c: [Double]) -> String {
        func byte(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c[0]), byte(c[1]), byte(c[2]))
    }

    static func decode(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func encode(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    static func luminance(_ c: [Double]) -> Double {
        let l = c.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
    }

    static func ratio(_ a: [Double], _ b: [Double]) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Darkens in steps of one percent, accumulated exactly the way the
    /// script's `k += .01` accumulates, so the step that passes is the same.
    static func darkenUntil(_ c: [Double], against: [Double], target: Double) -> ([Double], Double) {
        var k = 0.0
        while k <= 1.0001 {
            let d = c.map { $0 * (1 - k) }
            if ratio(d, against) >= target { return (d, k) }
            k += 0.01
        }
        return ([0, 0, 0], 1)
    }
}

/// Everything a chip is drawn with, worked out from its style, the arrow's
/// ink, its three part colours and its marker. Pure, so the legibility of
/// every style can be measured without drawing (`ChipStyleTests`), and the
/// rasterizer only has to follow it (`ChipRasterizer`).
///
/// Distances are in the design system's pixels at 12 px type; the rasterizer
/// scales them by the caption's own size.
public struct ChipLook: Hashable, Sendable {

    /// A drop shadow under the plate.
    public struct Shadow: Hashable, Sendable {
        public var y: CGFloat
        public var blur: CGFloat
        public var alpha: Double
    }

    /// A light rim drawn just inside the plate's edge, brighter at one end.
    public struct Rim: Hashable, Sendable {
        /// White's alpha where the light hits and where it fades to.
        public var start: Double
        public var end: Double
        /// Diagonal (top left to bottom right, Glass) or top to bottom (Spec).
        public var diagonal: Bool
    }

    /// The style's own detail at the front of the chip.
    public enum Accent: Hashable, Sendable {
        /// A short upright bar (Paper).
        case stripe(RGBA)
        /// A small round dot (Spec, Two-tone).
        case dot(RGBA)
    }

    /// A status icon.
    public struct Marker: Hashable, Sendable {
        public var kind: ChipMarker
        public var disc: RGBA
        public var glyph: RGBA
    }

    public var style: ChipStyle
    /// The plate at its top and bottom: the same colour for a flat plate.
    /// Alpha below one lets the picture through (Glass).
    public var fillTop: RGBA?
    public var fillBottom: RGBA?
    public var edge: RGBA?
    public var edgeWidth: CGFloat
    public var rim: Rim?
    /// White's alpha along the plate's top inner edge, 0 for none.
    public var innerHighlight: Double
    public var shadows: [Shadow]
    /// A hairline ring just outside the plate, in black at this alpha.
    public var ringAlpha: Double
    public var text: RGBA
    /// A soft shadow under the words (Glass): dark under white words, a light
    /// lift under dark ones.
    public var textShadow: Bool
    public var textShadowIsLight = false
    public var monospaced: Bool
    /// Corners drawn as a continuous curve rather than a circle's quarter.
    public var continuousCorners: Bool
    public var accent: Accent?
    /// Two-tone's tab, in the plate colour for the ink.
    public var tab: RGBA?
    /// Highlighter's swipe.
    public var swipe: RGBA?
    public var marker: Marker?
    /// Where the words start, in the design system's pixels from the chip's
    /// left edge, when an accent or marker leads it; nil when nothing does.
    public var textStart: CGFloat?
    /// Whether anything leads the chip at all.
    public var lead: CGFloat { textStart ?? 0 }

    /// The chip for `style` painted from `ink`, with its three part colours as
    /// the style derives them.
    public static func resolve(style: ChipStyle, ink: String, marker: ChipMarker) -> ChipLook {
        resolve(style: style, ink: ink, marker: marker, reading: InkPlate.reading(forInk: ink))
    }

    /// The same, with the ink's plate already worked out, for a caller asking
    /// about many styles of one ink.
    static func resolve(style: ChipStyle, ink: String, marker: ChipMarker,
                        reading: InkPlate.Reading) -> ChipLook {
        let parts = style.parts(forInk: ink, reading: reading)
        return resolve(style: style, ink: ink, fill: parts.fill, edge: parts.edge,
                       text: parts.text, marker: marker, reading: reading)
    }

    /// The chip for `style` with its part colours as they are stored on the
    /// caption, which is where a part set by hand lives.
    public static func resolve(style: ChipStyle, ink: String, fill: String?, edge: String?,
                               text: String, marker: ChipMarker) -> ChipLook {
        resolve(style: style, ink: ink, fill: fill, edge: edge, text: text, marker: marker,
                reading: InkPlate.reading(forInk: ink))
    }

    static func resolve(style: ChipStyle, ink: String, fill: String?, edge: String?,
                        text: String, marker: ChipMarker, reading: InkPlate.Reading) -> ChipLook {
        let inkRGBA = RGBA(hex: ink) ?? RGBA(r: 1, g: 0.23, b: 0.19)
        let base = fill.flatMap { RGBA(hex: $0) }
        let white = RGBA(r: 1, g: 1, b: 1)
        let black = RGBA(r: 0, g: 0, b: 0)
        var look = ChipLook(style: style, fillTop: base, fillBottom: base,
                            edge: edge.flatMap { RGBA(hex: $0) }, edgeWidth: 0, rim: nil,
                            innerHighlight: 0, shadows: [], ringAlpha: 0,
                            text: RGBA(hex: text) ?? white, textShadow: false, monospaced: false,
                            continuousCorners: false, accent: nil, tab: nil, swipe: nil,
                            marker: nil, textStart: nil)
        switch style {
        case .today:
            look.edgeWidth = 2
            look.shadows = [Shadow(y: 2, blur: 4, alpha: 0.35)]
        case .solid:
            look.fillTop = base.map { $0.mixed(with: white, 0.05) }
            look.fillBottom = base.map { $0.mixed(with: black, 0.08) }
            look.innerHighlight = 0.38
            look.shadows = [Shadow(y: 1, blur: 3, alpha: 0.22)]
            look.edgeWidth = 1
        case .squircle:
            look.continuousCorners = true
            look.edgeWidth = 1
        case .hairline:
            look.edgeWidth = 1
        case .glass:
            // One tint, a touch more see-through at the top, as markup.css
            // draws it (80 to 84 percent there).
            look.fillTop = base.map { var c = $0; c.a = InkPlate.glassDrawnOpacity - 0.01; return c }
            look.fillBottom = base.map { var c = $0; c.a = InkPlate.glassDrawnOpacity + 0.01; return c }
            look.textShadowIsLight = look.text.hexString == InkPlate.darkWordsHex
            look.rim = Rim(start: 0.7, end: 0.45, diagonal: true)
            look.innerHighlight = 0.3
            look.shadows = [Shadow(y: 4, blur: 12, alpha: 0.22), Shadow(y: 1, blur: 2, alpha: 0.16)]
            look.textShadow = true
            look.continuousCorners = true
            look.edgeWidth = 1
        case .paper:
            look.shadows = [Shadow(y: 1, blur: 1, alpha: 0.10), Shadow(y: 3, blur: 6, alpha: 0.10),
                            Shadow(y: 8, blur: 16, alpha: 0.14)]
            look.edgeWidth = 1
            if marker == .accent {
                look.accent = .stripe(inkRGBA)
                look.textStart = 13
            }
        case .spec:
            look.fillTop = base.map { $0.mixed(with: white, 0.03) }
            look.fillBottom = base.map { $0.mixed(with: black, 0.08) }
            look.rim = Rim(start: 0.34, end: 0.06, diagonal: false)
            look.ringAlpha = 0.65
            look.shadows = [Shadow(y: 3, blur: 10, alpha: 0.35)]
            look.monospaced = true
            look.edgeWidth = 1
            if marker == .accent {
                // A dark ink would vanish on graphite: its dot is lifted.
                let dot = InkPlate.contrast(inkRGBA, RGBA(hex: "#2F2F32") ?? black) < 2
                    ? inkRGBA.mixed(with: white, 0.55) : inkRGBA
                look.accent = .dot(dot)
                look.textStart = 18
            }
        case .tag:
            look.fillTop = base.map { $0.mixed(with: white, 0.05) }
            look.fillBottom = base.map { $0.mixed(with: black, 0.06) }
            look.innerHighlight = 0.5
            look.shadows = [Shadow(y: 2, blur: 6, alpha: 0.22)]
            look.edgeWidth = 1
        case .twotone:
            look.ringAlpha = 0.14
            look.shadows = [Shadow(y: 2, blur: 8, alpha: 0.16)]
            look.edgeWidth = 1
            if marker != .none {
                look.tab = RGBA(hex: reading.plateHex)
                look.textStart = 28
                if marker == .accent {
                    var dot = RGBA(hex: reading.onPlateHex) ?? white
                    dot.a = 0.9
                    look.accent = .dot(dot)
                }
            }
        case .highlight:
            look.ringAlpha = 0.12
            look.shadows = [Shadow(y: 2, blur: 7, alpha: 0.15)]
            look.swipe = inkRGBA.mixed(with: white, 0.58)
            look.edgeWidth = 1
        }
        if marker.isStatus, let meaning = marker.meaningHex.flatMap({ RGBA(hex: $0) }),
           let onWhite = marker.meaningOnWhiteHex.flatMap({ RGBA(hex: $0) }) {
            look.marker = style.isInkFilled
                ? Marker(kind: marker, disc: white, glyph: onWhite)
                : Marker(kind: marker, disc: meaning,
                         glyph: marker == .warning ? (RGBA(hex: InkPlate.darkWordsHex) ?? black) : white)
            // Two-tone holds its icon in the tab it already makes room for.
            if style != .twotone { look.textStart = iconTextStart }
        }
        return look
    }

    /// Where the words start when a status icon leads the chip, in the design
    /// system's pixels: the icon from 6.6 (1.15 em wide) and a 0.4 em gap.
    static let iconTextStart: CGFloat = 26.4
    static let iconX: CGFloat = 6.6

    /// Where things sit at the front of a chip, given the caption's type size
    /// and padding and the chip's rectangle.
    public struct Layout: Hashable, Sendable {
        public var stripe: CGRect?
        public var dot: CGRect?
        public var tab: CGRect?
        public var icon: CGRect?
        /// Highlighter's swipe: four corners, top left round to bottom left.
        public var swipe: [CGPoint]?
        /// The middle of the room the words are centred in.
        public var wordsCenterX: CGFloat
    }

    /// How many points one of the design system's pixels is at this size.
    public static func unit(fontSize: CGFloat) -> CGFloat { fontSize / 12 }

    /// The extra width at the chip's front, in points: from where the words
    /// would start (the padding) to where the accent lets them start.
    public func leadWidth(padding: CGFloat, fontSize: CGFloat) -> CGFloat {
        guard let textStart else { return 0 }
        return max(0, textStart * Self.unit(fontSize: fontSize) - padding)
    }

    public func layout(in rect: CGRect, fontSize: CGFloat, padding: CGFloat) -> Layout {
        let u = Self.unit(fontSize: fontSize)
        // Accents sit where the design system puts them, in its pixels.
        let k = u
        let leadRoom = leadWidth(padding: padding, fontSize: fontSize)
        var out = Layout(stripe: nil, dot: nil, tab: nil, icon: nil, swipe: nil,
                         wordsCenterX: rect.midX + leadRoom / 2)
        if tab != nil {
            out.tab = CGRect(x: rect.minX, y: rect.minY, width: 22 * k, height: rect.height)
        }
        switch accent {
        case .stripe?:
            let inset = min(4 * u, rect.height / 4)
            out.stripe = CGRect(x: rect.minX + 5 * k, y: rect.minY + inset,
                                width: max(3 * u, 1.5), height: rect.height - 2 * inset)
        case .dot?:
            let d = 6 * u
            let cx = style == .twotone ? rect.minX + 11 * k : rect.minX + 10 * k
            out.dot = CGRect(x: cx - d / 2, y: rect.midY - d / 2, width: d, height: d)
        case nil:
            break
        }
        if marker != nil {
            let size = (style == .twotone ? 14 : 13.8) * u
            let cx = style == .twotone ? rect.minX + 11 * k : rect.minX + Self.iconX * u + size / 2
            out.icon = CGRect(x: cx - size / 2, y: rect.midY - size / 2, width: size, height: size)
        }
        if swipe != nil {
            let left = rect.minX + 3 * k + leadRoom
            let right = rect.maxX - 3 * k
            let tilt = min((right - left) * 0.02, 1.5 * u)
            let top = rect.minY + rect.height * 0.34
            let bottom = rect.minY + rect.height * 0.80
            out.swipe = [CGPoint(x: left, y: top + tilt), CGPoint(x: right, y: top - tilt),
                         CGPoint(x: right, y: bottom - tilt), CGPoint(x: left, y: bottom + tilt)]
        }
        return out
    }

    /// The worst contrast the words have against what is directly behind them,
    /// over a picture of colour `backdrop`. The plate is read at the top and
    /// bottom of the band the letters sit in, and a see-through plate is
    /// composited over the backdrop first.
    public func wordContrast(over backdrop: RGBA) -> Double {
        var behind: [RGBA] = []
        if let top = fillTop, let bottom = fillBottom {
            for share in [0.25, 0.75] {
                let plate = top.mixed(with: bottom, share)
                behind.append(plate.over(backdrop))
                behind.append(plate.overInLinearLight(backdrop))
            }
        } else {
            behind.append(backdrop)
        }
        if let swipe { behind.append(swipe.over(backdrop)) }
        return behind.map { InkPlate.contrast(text, $0) }.min() ?? 1
    }

    /// A short description of what makes this chip itself, for telling styles
    /// apart in a test.
    var signature: String {
        [String(format: "%.2f", Double(style.roundness)), fillTop?.hexString ?? "-", fillBottom?.hexString ?? "-",
         edge?.hexString ?? "-", rim.map { "\($0.diagonal)" } ?? "-", "\(shadows.count)",
         "\(ringAlpha)", text.hexString, "\(monospaced)", "\(continuousCorners)",
         accent.map { "\($0)" } ?? "-", tab?.hexString ?? "-", swipe?.hexString ?? "-"]
            .joined(separator: "|")
    }
}

extension RGBA {
    /// This colour moved `amount` of the way to `other`, in sRGB, the way CSS's
    /// `color-mix(in srgb, ...)` mixes. Alpha follows too.
    func mixed(with other: RGBA, _ amount: Double) -> RGBA {
        RGBA(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount,
             b: b + (other.b - b) * amount, a: a + (other.a - a) * amount)
    }

    /// The same, blended in linear light the way the compositor blends.
    func overInLinearLight(_ backdrop: RGBA) -> RGBA {
        func mix(_ f: Double, _ b: Double) -> Double {
            InkPlate.encode(InkPlate.decode(f) * a + InkPlate.decode(b) * (1 - a))
        }
        return RGBA(r: mix(r, backdrop.r), g: mix(g, backdrop.g), b: mix(b, backdrop.b))
    }

    /// This colour laid over an opaque `backdrop` at its own alpha.
    func over(_ backdrop: RGBA) -> RGBA {
        RGBA(r: r * a + backdrop.r * (1 - a), g: g * a + backdrop.g * (1 - a),
             b: b * a + backdrop.b * (1 - a))
    }
}

extension AnnotationContent {
    /// The chip this caption is drawn on, or nil for the pill from before
    /// there were styles, which draws its three stored colours as it always
    /// has.
    public var chipLook: ChipLook? {
        guard let chipStyle else { return nil }
        return ChipLook.resolve(style: chipStyle, ink: paint.hex, fill: captionFill?.hex,
                                edge: captionBorder?.hex, text: captionTextHex, marker: chipMarker)
    }

    /// The style a tile row shows as on: the pill from before styles is Today.
    public var shownChipStyle: ChipStyle { chipStyle ?? .today }

    /// The extra width a marker or accent takes at the chip's front.
    public var captionLeadWidth: CGFloat {
        chipLook?.leadWidth(padding: captionPadding, fontSize: captionFontSize) ?? 0
    }

    /// The family the words are set in: Spec badge is monospaced.
    public var captionFontName: String {
        chipStyle == .spec ? "SF Mono" : "SF Pro"
    }

    /// How heavy the words are: a styled chip sets them semibold, as the
    /// design system does (600), Spec badge's monospace medium. The pill from
    /// before styles keeps its regular words.
    public var captionFontWeight: TextWeight {
        switch chipStyle {
        case nil: .regular
        case .spec?: .medium
        case _?: .semibold
        }
    }

    /// The words' size: the caption's own, and Spec badge's monospace a little
    /// smaller so it is not the widest chip on the picture.
    public var captionTypeSize: CGFloat {
        chipStyle == .spec ? captionFontSize * 0.88 : captionFontSize
    }

    /// Room kept round the chip for its drop shadow, so the shadow never
    /// clips at the layer's edge: the pill's own 12 points, or more for a
    /// style whose shadow reaches further.
    public var captionShadowSlack: CGFloat {
        guard let look = chipLook else { return Self.captionShadowPadding }
        let u = ChipLook.unit(fontSize: captionFontSize)
        let reach = look.shadows.map { (abs($0.y) + $0.blur) * u + 2 }.max() ?? 0
        return max(Self.captionShadowPadding, reach.rounded(.up))
    }

    /// Puts the caption's chip in `style`: its plate, edge and words painted
    /// from the line's ink, its corners the style's own. Parts set by hand
    /// keep their colour. A pill from before styles counts every part it had
    /// changed from its seeded colour as set by hand, so nothing a person
    /// chose is thrown away.
    public mutating func applyChipStyle(_ style: ChipStyle) {
        if chipStyle == nil, captionTextColorHex != nil {
            func same(_ paint: Paint?, _ hex: String?) -> Bool {
                guard let paint else { return hex == nil }
                guard let hex else { return false }
                return paint.kind == .solid && paint.hex.uppercased() == hex.uppercased()
            }
            var byHand = captionPartsByHand
            if !same(captionFill, captionChipColor.hexString) { byHand.insert(.fill) }
            if !same(captionBorder, paint.hex) { byHand.insert(.edge) }
            if captionTextHex.uppercased() != Self.captionTextDefaultHex.uppercased() { byHand.insert(.text) }
            captionPartsByHand = byHand
        }
        chipStyle = style
        captionRoundness = style.roundness
        rederiveChipParts()
    }

    /// Paints one chip part by hand: it keeps this colour through any style or
    /// colour change until it is reset.
    public mutating func setCaptionPartByHand(_ part: CaptionPart, hex: String?) {
        switch part {
        case .fill: captionFill = hex.map { Paint(hex: $0) }
        case .edge: captionBorder = hex.map { Paint(hex: $0) }
        case .text: if let hex { captionTextColorHex = hex }
        }
        if chipStyle != nil { captionPartsByHand.insert(part) }
    }

    /// Marks a part as set by hand after it was painted some other way (a
    /// colour style, a gradient).
    mutating func noteCaptionPartByHand(_ part: CaptionPart) {
        if chipStyle != nil { captionPartsByHand.insert(part) }
    }

    /// The one Color (markup.md section 2): the line takes `hex` exactly as
    /// picked, the head takes it too unless it was painted apart from the
    /// line, and the chip re-derives its plate, edge and words from it so they
    /// read whatever the colour (section 3). Chip parts painted by hand keep
    /// their colour.
    public mutating func setInk(_ hex: String) {
        let headFollows = headPaint == paint
        colorHex = hex
        if headFollows { headPaint = paint }
    }

    /// The worst contrast the label's words have on their chip as it is
    /// drawn, a see-through plate judged over a white and a black picture
    /// alike. Nil with nothing to judge: no words, or no plate, when the words
    /// sit straight on a picture the model cannot see.
    public var captionWordContrast: Double? {
        guard hasCaption else { return nil }
        if let look = chipLook {
            guard look.fillTop != nil else { return nil }
            return [RGBA(r: 1, g: 1, b: 1), RGBA(r: 0, g: 0, b: 0)]
                .map { look.wordContrast(over: $0) }.min()
        }
        guard let fill = captionFill, let back = RGBA(hex: fill.hex),
              let ink = RGBA(hex: captionTextHex), back.a > 0.5 else { return nil }
        return InkPlate.contrast(ink, back)
    }

    /// Whether one step can hand the chip back to its automatic colours: some
    /// part was painted by hand, or it is a pill from before chip styles.
    public var canRestoreAutomaticChip: Bool {
        guard hasCaption else { return false }
        return chipStyle == nil || !captionPartsByHand.isEmpty
    }

    /// Puts the chip back on the colours its style derives from the line, so
    /// the words read again. A pill from before chip styles takes Today, the
    /// look it already wears, painted the automatic way.
    public mutating func restoreAutomaticChip() {
        guard hasCaption else { return }
        if chipStyle == nil { applyChipStyle(.today) }
        resetCaptionPartsByHand()
    }

    /// Hands every chip part back to the style.
    public mutating func resetCaptionPartsByHand(_ parts: Set<CaptionPart> = Set(CaptionPart.allCases)) {
        captionPartsByHand.subtract(parts)
        rederiveChipParts()
    }

    /// Writes the style's colours for the line's ink onto every part not set
    /// by hand. Nothing for a pill from before styles.
    mutating func rederiveChipParts() {
        guard let chipStyle else { return }
        let parts = chipStyle.parts(forInk: paint.hex)
        let byHand = captionPartsByHand
        if !byHand.contains(.fill) { captionFill = parts.fill.map { Paint(hex: $0) } }
        if !byHand.contains(.edge) { captionBorder = parts.edge.map { Paint(hex: $0) } }
        if !byHand.contains(.text) { captionTextColorHex = parts.text }
    }
}
