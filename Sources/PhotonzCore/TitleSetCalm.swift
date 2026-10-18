import CoreGraphics
import Foundation

// Title pages that look like Apple designed them (task
// `title-pages-that-look-like-apple-designed-them`, mock
// `docs/design/mocks/pages/video-titles-apple.html`).
//
// The user called the set before this busy, "interesting for a high school
// student presentation", and picked all ten of the mock's studies on
// 2026-10-18. Each is a transcription of one mock page: its words, faces,
// sizes, tracking, leading and colours, its parts at the mock's positions on
// a 1920 by 1080 frame, and its motion at the mock's delays and lengths. What
// makes them calm is what they leave out: the background holds still, a part
// fades, rises a few points or sharpens out of a soft focus, and lands on an
// ease out in under a second; nothing springs, flips, glows or turns in depth.
//
// The mock places each block of words by its CSS top and sets its lines with
// CSS line-height, which CoreText matches (`TextRasterizer.paragraphStyle`);
// the box only carries extra room above lines set tighter than their face
// (`TextRasterizer.lineOverhang`), and `TitlePen.set` takes that back off.

extension BuiltInTitle {

    /// The ten, in the mock's order: the first title pages on the shelf and
    /// in the Insert menus.
    public static let calmSet: [BuiltInTitle] = [
        .keynoteSection, .filmSuper, .sessionTitle, .chapterCard, .editorialNY,
        .sessionsStage, .launch, .gradientWord, .bigNumber, .endCard,
    ]

    /// One of the ten.
    public var isCalm: Bool { Self.calmSet.contains(self) }

    /// A title page of the set the ten replaced: offered under More Styles,
    /// below them (the user's answer, 2026-10-18).
    public var isMoreStyle: Bool { kind == .titlePage && !isCalm && !isRetired }

    // MARK: How each one moves

    var calmDesign: TitleDesign? {
        typealias B = TitleBuild
        // The mock's curves: a soft exponential landing, a cubic one for a
        // plain fade, and an even sine for leaving.
        let expo = EasingCurve.easeOutExpo, cubic = EasingCurve.easeOut, sine = EasingCurve.easeInOutSine
        let background = TitlePart(path: "Background", role: .background)
        /// A plain fade in: full at three fifths of the mock's length, the
        /// moment its opacity lands.
        func fade(_ delay: Int, _ length: Int) -> B {
            B(.fade, delayMS: delay, lengthMS: max(360, Int((Double(length) * 0.6).rounded())), curve: cubic)
        }
        /// An out, said as the mock says it: starting `after` ms into the
        /// title's way off and lasting `length`, of a way off `total` long.
        func off(_ length: Int, of total: Int, kind: TitleBuildKind = .fade, after: Int = 0,
                 amount: Double? = nil) -> B {
            B(kind, delayMS: total - after - length, lengthMS: length, amount: amount, curve: sine)
        }
        switch self {
        case .keynoteSection:
            return TitleDesign(parts: [
                background,
                TitlePart(path: "Title", role: .headline,
                          in: B(.blurIn, delayMS: 0, lengthMS: 900, amount: 18, curve: expo, scale: 103.5),
                          out: off(420, of: 420, kind: .blurIn, amount: 10)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 280, lengthMS: 750, amount: 14, curve: expo),
                          out: off(360, of: 420)),
            ])
        case .filmSuper:
            return TitleDesign(parts: [
                background,
                TitlePart(path: "Title", role: .headline,
                          in: B(.rise, delayMS: 120, lengthMS: 800, amount: 18, curve: expo, blur: 4),
                          out: off(380, of: 380)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 280, lengthMS: 750, amount: 12, curve: expo),
                          out: off(340, of: 380)),
            ])
        case .sessionTitle:
            return TitleDesign(parts: [
                background,
                TitlePart(path: "Kicker", role: .kicker, in: fade(0, 600), out: off(320, of: 440, after: 120)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.maskReveal, delayMS: 120, lengthMS: 900, curve: expo, by: .line, staggerMS: 90),
                          out: off(380, of: 440, kind: .rise, amount: 10)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 520, lengthMS: 750, amount: 10, curve: expo),
                          out: off(320, of: 440)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.rise, delayMS: 520, lengthMS: 750, amount: 10, curve: expo),
                          out: off(320, of: 440), name: "Role"),
            ])
        case .chapterCard:
            return TitleDesign(parts: [
                background,
                TitlePart(path: "Kicker", role: .kicker, in: fade(0, 600), out: off(320, of: 420, after: 100)),
                // The word closes up from slightly open tracking, a letter
                // spreading about the middle as CSS letter-spacing does.
                TitlePart(path: "Title", role: .headline,
                          in: B(.trackIn, delayMS: 100, lengthMS: 900, amount: 6.6, curve: expo,
                                by: .letter, staggerMS: 0, blur: 6),
                          out: off(380, of: 420)),
            ])
        case .editorialNY:
            return TitleDesign(parts: [
                background,
                TitlePart(path: "Kicker", role: .kicker, in: fade(0, 600), out: off(320, of: 460, after: 140)),
                TitlePart(path: "Rule", role: .accent,
                          in: B(.drawOn, delayMS: 120, lengthMS: 700, direction: .right, curve: expo),
                          out: off(300, of: 460, after: 120)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.maskReveal, delayMS: 200, lengthMS: 950, curve: expo, by: .line, staggerMS: 110),
                          out: off(400, of: 460, kind: .rise, amount: 8)),
                TitlePart(path: "Subtitle", role: .subtitle, in: fade(650, 700), out: off(300, of: 460)),
            ])
        case .sessionsStage:
            return TitleDesign(parts: [
                background,
                // One violet glow drifting so slowly you only see it if you look.
                TitlePart(path: "Glow", role: .accent, hold: TitleHold(.drift, amount: 50, direction: .right)),
                TitlePart(path: "Kicker", role: .kicker, in: fade(0, 600), out: off(320, of: 440, after: 120)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.rise, delayMS: 100, lengthMS: 850, amount: 22, curve: expo,
                                by: .line, staggerMS: 90, blur: 4),
                          out: off(380, of: 440)),
                TitlePart(path: "Subtitle", role: .subtitle, in: fade(520, 700), out: off(300, of: 440)),
            ])
        case .launch:
            return TitleDesign(parts: [
                background,
                TitlePart(path: "Title", role: .headline,
                          in: B(.rise, delayMS: 0, lengthMS: 900, amount: 14, curve: expo, blur: 20),
                          out: off(420, of: 420, kind: .blurIn, amount: 10)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 300, lengthMS: 750, amount: 10, curve: expo),
                          out: off(340, of: 420)),
            ])
        case .gradientWord:
            return TitleDesign(parts: [
                background,
                TitlePart(path: "Title", role: .headline,
                          in: B(.blurIn, delayMS: 0, lengthMS: 900, amount: 16, curve: expo, scale: 102),
                          out: off(420, of: 420, kind: .blurIn, amount: 10)),
            ])
        case .bigNumber:
            return TitleDesign(parts: [
                background,
                TitlePart(path: "Kicker", role: .kicker, in: fade(0, 600), out: off(320, of: 420, after: 100)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.scaleFrom, delayMS: 80, lengthMS: 950, amount: 94, curve: expo, blur: 14),
                          out: off(420, of: 420, kind: .blurIn, amount: 10)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 360, lengthMS: 750, amount: 12, curve: expo),
                          out: off(340, of: 420)),
            ])
        case .endCard:
            return TitleDesign(parts: [
                background,
                TitlePart(path: "Title", role: .headline,
                          in: B(.fade, delayMS: 0, lengthMS: 900, curve: sine), out: off(450, of: 450)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.fade, delayMS: 400, lengthMS: 800, curve: sine), out: off(400, of: 450)),
            ])
        default:
            return nil
        }
    }

    // MARK: How each one is drawn

    func calmLayer(_ pen: TitlePen) -> Layer? {
        let page: [Layer]
        let white = "#F5F5F7"
        switch self {
        case .keynoteSection:
            page = [pen.fullFrame(Paint(hex: "#000000")),
                    pen.set("Title", "Timeline", size: 184, weight: .semibold, tracking: -0.028, lineHeight: 1,
                            color: white, top: 432),
                    pen.set("Subtitle", "What is new in Photonz 3", size: 40, weight: .medium, tracking: -0.004,
                            lineHeight: 1.2, color: "#86868B", top: 664)]
        case .filmSuper:
            // A warm pool of light to the right, falling off to near black.
            let light = Paint(hex: "#070707", kind: .radial,
                              stops: [GradientStop(hex: "#2B2722", position: 0),
                                      GradientStop(hex: "#14120F", position: 0.31),
                                      GradientStop(hex: "#070707", position: 0.64)],
                              center: CGPoint(x: 0.78, y: 0.38))
            var caption = pen.set("Subtitle", "Photonz for Mac", size: 32, weight: .regular, tracking: 0,
                                  lineHeight: 1.25, color: white, left: 160, top: 896)
            caption.style.opacity = 0.62
            page = [pen.fullFrame(light),
                    pen.set("Title", "Record. Redline. Ship.", size: 68, weight: .semibold, tracking: -0.016,
                            lineHeight: 1.06, color: white, left: 160, top: 808),
                    caption]
        case .sessionTitle:
            page = [pen.fullFrame(Paint(hex: "#000000")),
                    pen.set("Kicker", "Session 3", size: 34, weight: .semibold, tracking: -0.004, lineHeight: 1,
                            color: "#BF5AF2", left: 160, top: 330),
                    pen.set("Title", "Measure and redline\nany screenshot", size: 112, weight: .bold,
                            tracking: -0.022, lineHeight: 1.04, color: white, left: 160, top: 392),
                    pen.set("Subtitle", "Dana Zhou", size: 34, weight: .medium, tracking: -0.004, lineHeight: 1.3,
                            color: white, left: 160, top: 716),
                    pen.set("Role", "Design Engineer", size: 34, weight: .medium, tracking: -0.004, lineHeight: 1.3,
                            color: "#8E8E93", left: 160, top: 716 + 34 * 1.3)]
        case .chapterCard:
            page = [pen.fullFrame(Paint(hex: "#FBFBFD")),
                    pen.set("Kicker", "Chapter 2", size: 34, weight: .semibold, tracking: -0.002, lineHeight: 1,
                            color: "#6E6E73", top: 404),
                    pen.set("Title", "Capture", size: 168, weight: .semibold, tracking: -0.026, lineHeight: 1,
                            color: "#1D1D1F", top: 460)]
        case .editorialNY:
            let ink = "#1C1A17"
            page = [pen.fullFrame(Paint(hex: "#F4F0E8")),
                    pen.set("Kicker", "THE MAKING OF", size: 22, weight: .semibold, tracking: 0.16, lineHeight: 1,
                            color: "#A4472A", top: 312),
                    pen.line("Rule", from: CGPoint(x: pen.u(928), y: pen.u(369)), length: pen.u(64),
                             width: pen.u(2), color: ink),
                    pen.set("Title", "A better way\nto explain things", font: "New York", size: 128, weight: .medium,
                            tracking: -0.012, lineHeight: 1.06, color: ink, top: 412),
                    pen.set("Subtitle", "By Sam Rivera", size: 30, weight: .regular, tracking: 0, lineHeight: 1,
                            color: "#6B665E", top: 752)]
        case .sessionsStage:
            // Stripe's navy, and one violet glow high on the right.
            // Drawn at a fifth, so it tints the navy and is never read as
            // what the words stand on.
            var glow = pen.fullFrame(Paint(hex: "#635BFF", kind: .radial,
                                           stops: [GradientStop(hex: "#635BFF", position: 0),
                                                   GradientStop(hex: "#635BFF73", position: 0.17),
                                                   GradientStop(hex: "#635BFF1F", position: 0.3),
                                                   GradientStop(hex: "#635BFF00", position: 0.45)],
                                           center: CGPoint(x: 2000.0 / 1920, y: -60.0 / 1080)))
            glow.name = "Glow"
            glow.style.opacity = 0.2
            let named = glow
            page = [pen.fullFrame(Paint(hex: "#0A2540")), named,
                    pen.set("Kicker", "Sessions 2026", size: 32, weight: .semibold, tracking: -0.004, lineHeight: 1,
                            color: "#A39DFF", left: 160, top: 356),
                    pen.set("Title", "The fastest way\nto make a demo", size: 120, weight: .semibold,
                            tracking: -0.026, lineHeight: 1.02, color: "#FFFFFF", left: 160, top: 414),
                    pen.set("Subtitle", "Keynote · 9:00 AM", size: 30, weight: .medium, tracking: 0,
                            lineHeight: 1, color: "#ADBDCC", left: 160, top: 712)]
        case .launch:
            // Near black under a top light so faint it reads as depth.
            let light = Paint(hex: "#08090A", kind: .radial,
                              stops: [GradientStop(hex: "#1A1B1C", position: 0),
                                      GradientStop(hex: "#08090A", position: 0.34)],
                              center: CGPoint(x: 0.5, y: -60.0 / 1080))
            var title = pen.set("Title", "Built for speed", size: 150, weight: .medium, tracking: -0.034,
                                lineHeight: 1.08, color: "#F7F8F8", top: 418)
            title.fillWords(Paint(hex: "#F7F8F8", kind: .linear,
                                  stops: [GradientStop(hex: "#F7F8F8", position: 0.3),
                                          GradientStop(hex: "#F7F8F885", position: 1)],
                                  angle: 180))
            page = [pen.fullFrame(light), title,
                    pen.set("Subtitle", "Every command is one key away", size: 38, weight: .regular,
                            tracking: -0.006, lineHeight: 1.2, color: "#8A8F98", top: 614)]
        case .gradientWord:
            var title = pen.set("Title", "Smart Redline", size: 172, weight: .semibold, tracking: -0.03,
                                lineHeight: 1.05, color: "#C959DD", top: 450)
            title.fillWords(Paint(hex: "#C959DD", kind: .linear,
                                  stops: [GradientStop(hex: "#0894FF", position: 0),
                                          GradientStop(hex: "#C959DD", position: 0.14),
                                          GradientStop(hex: "#FF2E54", position: 0.29),
                                          GradientStop(hex: "#FF9004", position: 0.44),
                                          GradientStop(hex: "#F5F5F7", position: 0.58),
                                          GradientStop(hex: "#F5F5F7", position: 1)],
                                  angle: 90),
                            length: 2.2, shift: 1)
            // The spectrum washes through the words once as they land, then
            // holds still on white: CSS background-position 100% to 0%.
            title.motions = [LayerMotion.keyed(.gradientShift, atMS: 0, value: .number(100))
                .rebuilt(from: [MotionStop(atMS: 0, value: .number(100), curve: .easeOut),
                                MotionStop(atMS: 1600, value: .number(0))])]
            page = [pen.fullFrame(Paint(hex: "#000000")), title]
        case .bigNumber:
            page = [pen.fullFrame(Paint(hex: "#000000")),
                    pen.set("Kicker", "Up to", size: 48, weight: .semibold, tracking: -0.008, lineHeight: 1,
                            color: white, top: 268),
                    pen.set("Title", "3×", size: 360, weight: .bold, tracking: -0.04, lineHeight: 1,
                            color: white, top: 330),
                    pen.set("Subtitle", "faster to explain a bug", size: 48, weight: .semibold, tracking: -0.008,
                            lineHeight: 1.1, color: "#86868B", top: 722)]
        case .endCard:
            page = [pen.fullFrame(Paint(hex: "#FFFFFF")),
                    pen.set("Title", "Photonz", size: 112, weight: .semibold, tracking: -0.022, lineHeight: 1,
                            color: "#1D1D1F", top: 452),
                    pen.set("Subtitle", "Free on the Mac", size: 36, weight: .regular, tracking: -0.004,
                            lineHeight: 1.2, color: "#6E6E73", top: 594)]
        default:
            return nil
        }
        return TitlePen.grouped(page, name: kind.name)
    }
}

extension TitlePen {

    /// Words set as the mock's CSS sets them: the face, size, weight, tracking
    /// (em) and leading (a multiple of the size), the block's top at `top`,
    /// and its left edge at `left`, or centred across the frame when nil.
    /// Sizes and places are points of a 1920 by 1080 frame.
    func set(_ name: String, _ string: String, font: String = "SF Pro", size: CGFloat, weight: TextWeight,
             tracking: CGFloat, lineHeight: CGFloat, color: String, left: CGFloat? = nil, top: CGFloat) -> Layer {
        var content = TextContent(string: string, fontName: font, fontSize: u(size), colorHex: color, weight: weight)
        content.tracking = tracking == 0 ? nil : tracking
        content.lineHeight = lineHeight
        content.alignment = left == nil ? .center : nil
        let natural = TextMeasurement.size(of: content)
        // The room CoreText keeps above lines set tighter than their face.
        let lines = CGFloat(max(1, string.split(separator: "\n", omittingEmptySubsequences: false).count))
        let overhang = max(0, (natural.height - TextMeasurement.slack - lines * lineHeight * u(size)) / 2)
        let y = (u(top) - overhang).rounded()
        let height = natural.height.rounded(.up)
        let frame: CGRect
        if let left {
            // The renderer starts a line a point in from its box; the browser
            // the mock was drawn in starts it two in from its left.
            frame = CGRect(x: u(left) + 1, y: y,
                           width: natural.width.rounded(.up), height: height)
        } else {
            let width = (canvas.width * 0.8).rounded()
            // A point right of the middle, where the browser centres a line
            // whose tracking it also adds after the last letter.
            frame = CGRect(x: ((canvas.width - width) / 2).rounded() + 1, y: y,
                           width: max(width, natural.width.rounded(.up)), height: height)
        }
        return Layer(name: name, content: .text(content), frame: frame)
    }
}

extension Layer {

    /// Fills these words with `paint` instead of their one colour, the ramp
    /// `length` times each line's width and slid `shift` of the way along it.
    mutating func fillWords(_ paint: Paint, length: Double? = nil, shift: Double? = nil) {
        guard case .text(var text) = content else { return }
        text.fill = paint
        text.fillLength = length
        text.fillShift = shift
        content = .text(text)
    }
}
