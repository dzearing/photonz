import CoreGraphics
import Foundation

// A set of titles that look designed (task `a-set-of-titles-that-look-designed`,
// `docs/design/video-titles-polish.md`, "Twelve style directions").
//
// The user called the old built-ins "powerpoint titles". These are the brief's
// twelve directions, each drawn from the same ordinary layers as before and
// moved by a design (`TitleDesign.swift`), so everything a preset makes is
// still layers you own. What makes them read as designed is the brief's short
// list, kept in every one and held by `TitleSetTests`:
//
// - each part arrives on its own beat, and words come in by line, word or
//   letter rather than as a slab;
// - two type sizes at most, a big headline over a small line;
// - ins on Ease out expo or quint (or a spring), outs shorter and eased in;
// - something still moving while it holds: a drifting mesh, a slow push, a
//   light crossing, a cursor blinking;
// - words that read over dark and light footage alike;
// - lower thirds inside title safe, a tenth of the frame from the edges.
//
// Amounts are points of a 1080 line frame, scaled to the frame a title lands on.

extension BuiltInTitle {

    // MARK: How each one moves

    /// The design of one of the set, nil for a retired preset.
    ///
    /// Every headline comes in its own way (task
    /// `title-text-visibly-comes-in-and-every-built-in-t`): the user saw the
    /// first set's words already standing at their in, because each arrived
    /// in a third of a second on Ease out expo and travelled twelve points.
    /// Now a headline takes most of a second, its pieces a good beat apart on
    /// a plain Ease out, travelling half its type or more, so half way through
    /// its in about half of it is there (`TitleEntranceInkTests` measures it).
    /// Outs are keys and shorter, on an ease in, and start leaving at least
    /// 400 ms before the end so the leaving is seen too.
    var designedSet: TitleDesign? {
        typealias B = TitleBuild
        switch self {
        case .keynote:
            // Words rise into place one after another out of their own
            // motion blur, then the line under them; the headline's slow push
            // is what moves while it holds, over drifting specks of light.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 500, curve: .easeOutQuint)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.rise, delayMS: 200, lengthMS: 800, amount: 70, curve: .easeOut,
                                by: .word, staggerMS: 280),
                          hold: TitleHold(.push, amount: 1.5),
                          out: .off(.rise, delayMS: 80, lengthMS: 400, amount: 36)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 1000, lengthMS: 600, amount: 24, curve: .easeOut,
                                by: .word, staggerMS: 70),
                          out: .off(.fade, delayMS: 200, lengthMS: 280)),
            ])
        case .softGlass:
            // The panel settles first, then each word sharpens out of a deep
            // blur inside it.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 600, curve: .easeOutQuint)),
                TitlePart(path: "Panel", role: .accent,
                          in: B(.scaleFrom, delayMS: 100, lengthMS: 600, amount: 92, curve: .easeOutQuint),
                          hold: TitleHold(.push, amount: 1),
                          out: .off(.scaleFrom, delayMS: 60, lengthMS: 360, amount: 96)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.blurIn, delayMS: 300, lengthMS: 900, amount: 40, curve: .easeOut,
                                by: .word, staggerMS: 300),
                          out: .off(.blurIn, delayMS: 80, lengthMS: 400, amount: 24)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.blurIn, delayMS: 1000, lengthMS: 600, amount: 16, curve: .easeOut,
                                by: .word, staggerMS: 60),
                          out: .off(.fade, delayMS: 200, lengthMS: 280)),
            ])
        case .kinetic:
            // Each word slides up out of its own line with a little spring,
            // and the block keeps pushing in while it holds; it leaves by
            // flying on up.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 300, curve: .easeOutQuint)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.maskReveal, delayMS: 150, lengthMS: 700, curve: .easeOutBack,
                                by: .word, staggerMS: 420),
                          hold: TitleHold(.push, amount: 2),
                          out: .off(.rise, delayMS: 80, lengthMS: 400, amount: 90)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 1100, lengthMS: 500, amount: 20, curve: .easeOut,
                                by: .word, staggerMS: 50),
                          out: .off(.fade, delayMS: 200, lengthMS: 280)),
            ])
        case .editorial:
            // The kicker first, then each line of the serif swings up on a
            // hinge at its foot like a page turning flat, then the rule
            // draws itself under it and the line below follows.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 400, curve: .easeOutQuint),
                          hold: TitleHold(.push, amount: 2)),
                TitlePart(path: "Kicker", role: .kicker,
                          in: B(.fade, delayMS: 120, lengthMS: 500),
                          out: .off(.fade, delayMS: 240, lengthMS: 240)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.swingIn, delayMS: 300, lengthMS: 1000, amount: 90, curve: .easeOut,
                                by: .word, staggerMS: 260),
                          out: .off(.rise, delayMS: 80, lengthMS: 400, amount: 10)),
                TitlePart(path: "Rule", role: .accent,
                          in: B(.drawOn, delayMS: 1000, lengthMS: 600, direction: .right),
                          out: .off(.drawOn, delayMS: 200, lengthMS: 300)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 1200, lengthMS: 500, amount: 12, curve: .easeOut),
                          out: .off(.fade, delayMS: 240, lengthMS: 260)),
            ])
        case .terminal:
            // The words are typed a letter at a time with the cursor waiting
            // after them, the progress line running out under it all; the
            // cursor is what moves while it holds.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 400, curve: .easeOutQuint)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.typewriter, delayMS: 300, lengthMS: 800, staggerMS: 85),
                          out: .off(.fade, delayMS: 80, lengthMS: 400)),
                TitlePart(path: "Cursor", role: .accent,
                          in: B(.fade, delayMS: 600, lengthMS: 150),
                          hold: TitleHold(.blink),
                          out: .off(.fade, delayMS: 100, lengthMS: 100)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.typewriter, delayMS: 1250, lengthMS: 600, staggerMS: 28),
                          out: .off(.fade, delayMS: 200, lengthMS: 280)),
                TitlePart(path: "Progress", role: .accent,
                          in: B(.drawOn, delayMS: 400, lengthMS: 1500, direction: .right, curve: .easeOutQuint),
                          out: .off(.drawOn, delayMS: 80, lengthMS: 300)),
            ])
        case .glass:
            // The recording frosts over as the title arrives (nothing of a
            // title is on its first frame), settles from 105% to 100% the
            // whole time it holds, and racks back into focus as the title
            // leaves, ending exactly on the footage. Each word flies forward
            // out of the depth of the glass, turning to face you; the words
            // are gone just before the glass clears.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.frost, delayMS: 0, lengthMS: 700, curve: .easeOutQuint),
                          hold: TitleHold(.push, amount: -5),
                          out: .off(.frost, delayMS: 0, lengthMS: 480)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.flyInFromDepth, delayMS: 250, lengthMS: 1000, amount: 900,
                                by: .word, staggerMS: 260),
                          out: .off(.blurIn, delayMS: 80, lengthMS: 400, amount: 20)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 1150, lengthMS: 650, amount: 16, curve: .easeOut),
                          out: .off(.fade, delayMS: 220, lengthMS: 260)),
            ])
        case .lightLeak:
            // Warm light leaks drift across the dark the whole time; the
            // capitals close up from wide tracking a letter after another.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 700, curve: .easeOutQuint)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.trackIn, delayMS: 300, lengthMS: 1100, amount: 70, curve: .easeOut,
                                by: .letter, staggerMS: 40),
                          out: .off(.blurIn, delayMS: 40, lengthMS: 460, amount: 40)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 1300, lengthMS: 600, amount: 10, curve: .easeOut),
                          out: .off(.fade, delayMS: 220, lengthMS: 280)),
            ])
        case .gradientGlow:
            // The headline falls into place from far larger out of a deep
            // blur, while the colours inside it keep sliding.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 400, curve: .easeOutQuint)),
                TitlePart(path: "Gradient", role: .accent,
                          hold: TitleHold(.drift, amount: 900, direction: .left)),
                TitlePart(path: "Headline", role: .accent,
                          in: B(.scaleFrom, delayMS: 200, lengthMS: 1000, amount: 170, curve: .easeOut),
                          out: .off(.scaleFrom, delayMS: 80, lengthMS: 400, amount: 85)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.blurIn, delayMS: 200, lengthMS: 1000, amount: 36, curve: .easeOut)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 1050, lengthMS: 600, amount: 12, curve: .easeOut),
                          out: .off(.fade, delayMS: 220, lengthMS: 280)),
            ])
        case .stacked:
            // Each line flips up word by word from facing away, a beat after
            // the one above, then the mark pops; they leave upwards in
            // reverse order. The streams behind them are what moves while it
            // holds.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 500, curve: .easeOutQuint)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.flipUp, delayMS: 150, lengthMS: 800, amount: 90, by: .word, staggerMS: 240),
                          out: .off(.rise, delayMS: 60, lengthMS: 400, amount: 40)),
                TitlePart(path: "Line 2", role: .kicker,
                          in: B(.flipUp, delayMS: 500, lengthMS: 800, amount: 90, by: .word, staggerMS: 240),
                          out: .off(.rise, delayMS: 100, lengthMS: 380, amount: 40)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 1100, lengthMS: 550, amount: 16, curve: .easeOut,
                                by: .word, staggerMS: 50),
                          out: .off(.rise, delayMS: 200, lengthMS: 280, amount: 20)),
                TitlePart(path: "Mark", role: .accent,
                          in: B(.springPop, delayMS: 1300, lengthMS: 500, amount: 40),
                          out: .off(.fade, delayMS: 280, lengthMS: 200)),
            ])
        case .splitWipe:
            // The bar wipes in and the words are uncovered behind its edge;
            // out in reverse, quicker.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.wipe, delayMS: 0, lengthMS: 400, direction: .right, curve: .easeOutQuint),
                          out: .off(.wipe, delayMS: 0, lengthMS: 260, direction: .left)),
                TitlePart(path: "Edge", role: .accent,
                          in: B(.wipe, delayMS: 80, lengthMS: 300, direction: .down, curve: .easeOutQuint),
                          out: .off(.fade, delayMS: 0, lengthMS: 200)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.wipe, delayMS: 200, lengthMS: 700, direction: .right, curve: .easeInOut),
                          out: .off(.maskReveal, delayMS: 60, lengthMS: 420)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.wipe, delayMS: 550, lengthMS: 600, direction: .right, curve: .easeInOut),
                          out: .off(.fade, delayMS: 120, lengthMS: 260)),
            ])
        case .underline:
            // The shade softens in, the name's letters rise one after another,
            // the line draws on under it, then the role.
            return TitleDesign(parts: [
                TitlePart(path: "Shade", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 500, curve: .easeOutQuint),
                          out: .off(.fade, delayMS: 0, lengthMS: 300)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.rise, delayMS: 100, lengthMS: 650, amount: 36, curve: .easeOut,
                                by: .letter, staggerMS: 50),
                          out: .off(.rise, delayMS: 30, lengthMS: 450, amount: 16)),
                TitlePart(path: "Rule", role: .accent,
                          in: B(.drawOn, delayMS: 500, lengthMS: 500, direction: .right),
                          out: .off(.wipe, delayMS: 100, lengthMS: 260, direction: .left)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.rise, delayMS: 750, lengthMS: 450, amount: 8, curve: .easeOut),
                          hold: TitleHold(.drift, amount: 4, direction: .right),
                          out: .off(.fade, delayMS: 160, lengthMS: 200)),
            ])
        case .pill:
            // The pill springs in, the mark after it, then each word settles
            // flat from tipped back.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.springPop, delayMS: 0, lengthMS: 550, amount: 88),
                          out: .off(.springPop, delayMS: 0, lengthMS: 300, amount: 94)),
                TitlePart(path: "Mark", role: .accent,
                          in: B(.springPop, delayMS: 120, lengthMS: 500, amount: 60),
                          hold: TitleHold(.push, amount: 6),
                          out: .off(.fade, delayMS: 60, lengthMS: 200)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.tiltSettle, delayMS: 250, lengthMS: 800, amount: 70, curve: .easeOut,
                                by: .word, staggerMS: 260),
                          out: .off(.rise, delayMS: 60, lengthMS: 440, amount: 20)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.rise, delayMS: 820, lengthMS: 500, amount: 10, curve: .easeOut),
                          out: .off(.fade, delayMS: 120, lengthMS: 200)),
            ])
        default:
            return nil
        }
    }

    // MARK: How each one is drawn

    /// The group one of the set draws on a frame, nil for a retired preset.
    func designedLayer(_ pen: TitlePen) -> Layer? {
        let page: [Layer]
        switch self {
        case .keynote: page = Self.keynote(pen)
        case .softGlass: page = Self.softGlass(pen)
        case .kinetic: page = Self.kinetic(pen)
        case .editorial: page = Self.editorial(pen)
        case .terminal: page = Self.terminal(pen)
        case .glass: page = Self.glass(pen)
        case .lightLeak: page = Self.lightLeak(pen)
        case .gradientGlow: page = Self.gradientGlow(pen)
        case .stacked: page = Self.stacked(pen)
        case .splitWipe: return Self.splitWipe(pen)
        case .underline: return Self.underline(pen)
        case .pill: return Self.pill(pen)
        default: return nil
        }
        return TitlePen.grouped(page, name: kind.name)
    }

    /// A moving look over `ground`, lit in `lights` (`LivePalette` reads the
    /// stops: the first is the ground, the rest the lights).
    static func live(_ look: LiveLook, ground: String, lights: [String], speed: Double = 100,
                     strength: Double = 100, scale: Double = 100) -> Paint {
        let colours = [ground] + lights
        let stops = colours.enumerated().map { index, hex in
            GradientStop(hex: hex, position: Double(index) / Double(max(1, colours.count - 1)))
        }
        return Paint(hex: ground, kind: .live, stops: stops,
                     live: LiveBackdrop(look: look, speed: speed, strength: strength, scale: scale))
    }

    private static func keynote(_ pen: TitlePen) -> [Layer] {
        // Near black with specks of cool light drifting through it in depth,
        // near-white words.
        let background = pen.fullFrame(live(.particles, ground: "#050507",
                                            lights: ["#5E6B8C", "#8C7BB8", "#4A6FA5"], speed: 70, strength: 80))
        let title = pen.centred("Title", "Your Title", font: "SF Pro", size: 120, weight: .bold,
                                color: "#F5F5F7", top: pen.canvas.height * 0.39)
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 42,
                                   color: "#A1A1A6", top: title.frame.maxY + pen.u(14))
        return [background, title, TitleLook.shadedOverALook(subtitle)]
    }

    private static func softGlass(_ pen: TitlePen) -> [Layer] {
        // A deep liquid gradient flowing under the glass, with grain.
        var background = pen.fullFrame(Paint(hex: "#16205E", kind: .live,
                                             stops: [GradientStop(hex: "#16205E", position: 0),
                                                     GradientStop(hex: "#4A2FA8", position: 0.5),
                                                     GradientStop(hex: "#0B4F66", position: 1)],
                                             live: LiveBackdrop(look: .liquidGradient)))
        background.style.effects = [.grain(GrainEffect())]
        // Frosted glass: the look behind it softened, a breath of white over it.
        let size = CGSize(width: pen.u(1180), height: pen.u(400))
        var panel = pen.box("Panel", CGRect(x: ((pen.canvas.width - size.width) / 2).rounded(),
                                            y: ((pen.canvas.height - size.height) / 2).rounded(),
                                            width: size.width, height: size.height),
                            fill: Paint(hex: "#FFFFFF"), radius: pen.u(40))
        panel.style.opacity = 0.14
        panel.style.effects = [.blur(BlurEffect(radius: pen.u(20), kind: .background))]
        let title = pen.centred("Title", "Your Title", font: "SF Pro", size: 104, weight: .bold,
                                color: "#FFFFFF", top: panel.frame.minY + pen.u(112))
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 38,
                                   color: "#ECEAF8", top: title.frame.maxY + pen.u(14))
        return [background, panel, title, TitleLook.shadedOverALook(subtitle)]
    }

    private static func kinetic(_ pen: TitlePen) -> [Layer] {
        // Saturated blue with streaks of wind running through it.
        let background = pen.fullFrame(live(.windStreams, ground: "#1D3BFF",
                                            lights: ["#6C8CFF", "#59D9FF", "#A98BFF"]))
        let title = pen.centred("Title", "YOUR TITLE", font: "Avenir Next Condensed", size: 210,
                                weight: .bold, color: "#FFFFFF", top: pen.canvas.height * 0.3)
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 40,
                                   weight: .semibold, color: "#DDE3FF", top: title.frame.maxY + pen.u(4))
        return [background, title, TitleLook.shadedOverALook(subtitle)]
    }

    private static func editorial(_ pen: TitlePen) -> [Layer] {
        // Warm paper an architect's sketch draws itself across, with grain.
        var background = pen.fullFrame(live(.sketch, ground: "#F4F1EA",
                                            lights: ["#9A4A26", "#3E5C76", "#7A5A3A"], strength: 80))
        background.style.effects = [.grain(GrainEffect(amount: 30))]
        let left = (pen.canvas.width * 0.12).rounded()
        let kicker = pen.words("Kicker", "CHAPTER ONE", font: "SF Pro", size: 28, weight: .semibold,
                               color: "#9A4A26", origin: CGPoint(x: left, y: pen.canvas.height * 0.33))
        let title = pen.words("Title", "Your Title", font: "Georgia", size: 120, weight: .bold,
                              color: "#1A1A1A", origin: CGPoint(x: left, y: kicker.frame.maxY + pen.u(8)))
        let rule = pen.line("Rule", from: CGPoint(x: left, y: title.frame.maxY + pen.u(26)),
                            length: pen.u(360), width: pen.u(2), color: "#1A1A1A")
        let subtitle = pen.words("Subtitle", "A short line about it", font: "SF Pro", size: 28,
                                 color: "#55524C", origin: CGPoint(x: left, y: rule.frame.maxY + pen.u(24)))
        return [background, TitleLook.shadedOverALook(kicker), title, rule, TitleLook.shadedOverALook(subtitle)]
    }

    private static func terminal(_ pen: TitlePen) -> [Layer] {
        // A green grid running away to a horizon in the dark.
        var background = pen.fullFrame(live(.gridHorizon, ground: "#050A07",
                                            lights: ["#3DFF8F", "#1FA35B", "#7CFFB8"], speed: 80))
        background.style.effects = [.grain(GrainEffect(amount: 20))]
        let left = (pen.canvas.width * 0.12).rounded()
        let green = "#3DFF8F"
        let title = pen.words("Title", "Your Title", font: "SF Mono", size: 72, weight: .semibold,
                              color: green, origin: .zero)
        // A block cursor after the words, which the row keeps after them
        // however long they are typed.
        let cursor = pen.box("Cursor", CGRect(x: 0, y: 0, width: pen.u(38), height: (title.frame.height * 0.78).rounded()),
                             fill: Paint(hex: green))
        let prompt = pen.stack([title, cursor], name: "Prompt", direction: .row, gap: pen.u(10),
                               origin: CGPoint(x: left, y: pen.canvas.height * 0.4),
                               placement: LayerPlacement(vertical: .center))
        let subtitle = pen.words("Subtitle", "a short line about it", font: "SF Mono", size: 30,
                                 color: "#8FD6AE", origin: CGPoint(x: left, y: prompt.localBounds.maxY + pen.u(22)))
        let progress = pen.line("Progress", from: CGPoint(x: left, y: subtitle.frame.maxY + pen.u(36)),
                                length: pen.u(520), width: pen.u(4), color: green)
        return [background, prompt, TitleLook.shadedOverALook(subtitle), progress]
    }

    private static func glass(_ pen: TitlePen) -> [Layer] {
        // Black at 55% over the recording, the recording itself softened
        // behind it and drawn 5% larger, which the hold eases back to 100%.
        // Dim enough that white words read over a white screenshot.
        var background = pen.fullFrame(Paint(hex: "#000000"))
        background.style.opacity = TitleLook.glassDim
        background.style.effects = [.blur(BlurEffect(radius: pen.u(36), kind: .background, zoom: 105))]
        let title = pen.centred("Title", "Your Title", font: "SF Pro", size: 112, weight: .bold,
                                color: "#FFFFFF", top: pen.canvas.height * 0.38)
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 40,
                                   weight: .medium, color: "#FFFFFF", top: title.frame.maxY + pen.u(18))
        return [background, title, subtitle]
    }

    private static func lightLeak(_ pen: TitlePen) -> [Layer] {
        // Warm light leaking across the dark, with grain.
        var background = pen.fullFrame(live(.lightLeaks, ground: "#08070B",
                                            lights: ["#FF7A2F", "#FF3D7F", "#FFB35C"], strength: 65))
        background.style.effects = [.grain(GrainEffect(amount: 22))]
        var title = pen.centred("Title", "YOUR TITLE", font: "Avenir Next", size: 88, weight: .medium,
                                color: "#FFF6EE", top: pen.canvas.height * 0.42)
        title.style.effects = [.glow(GlowEffect(colorHex: "#FFB58A", radius: pen.u(18), size: pen.u(2), opacity: 0.55))]
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "Avenir Next", size: 30,
                                   color: "#D8CEC6", top: title.frame.maxY + pen.u(18))
        return [background, title, TitleLook.shadedOverALook(subtitle)]
    }

    private static func gradientGlow(_ pen: TitlePen) -> [Layer] {
        // An aurora rippling low in the black, cool teal and blue so the warm
        // colours of the words stand out from it rather than into it.
        let background = pen.fullFrame(live(.aurora, ground: "#000000",
                                            lights: ["#14B8A6", "#1F6FFF", "#2EC4B6"], strength: 55))
        let title = pen.centred("Title", "Your Title", font: "SF Pro", size: 150, weight: .bold,
                                color: "#FFFFFF", top: pen.canvas.height * 0.36)
        // The colours, cut to the shape of the words under them and twice
        // their width, so the hold can slide them along.
        var gradient = pen.box("Gradient", CGRect(x: title.frame.minX, y: title.frame.minY - pen.u(10),
                                                  width: title.frame.width * 2,
                                                  height: title.frame.height + pen.u(20)),
                               fill: Paint(hex: "#8A5CFF", kind: .linear,
                                           stops: [GradientStop(hex: "#8A5CFF", position: 0),
                                                   GradientStop(hex: "#FF5FD2", position: 0.35),
                                                   GradientStop(hex: "#FFB36B", position: 0.65),
                                                   GradientStop(hex: "#8A5CFF", position: 1)],
                                           angle: 90))
        gradient.style.matte = .shape
        // One picture of the coloured words, so its glow is theirs.
        var headline = TitlePen.grouped([title, gradient], name: "Headline")
        headline.style.effects = [.glow(GlowEffect(colorHex: "#B07CFF", radius: pen.u(28), size: pen.u(4),
                                                   opacity: 0.6))]
        // The aurora behind is lit in the same colours as the words, so the
        // coloured words throw a soft dark shade of their own to stand on.
        headline.style.shadows = [TitleLook.liveScrim(forColorHex: "#FFFFFF", fontSize: title.text?.fontSize ?? pen.u(150))]
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 40,
                                   color: "#A1A1A6", top: title.frame.maxY + pen.u(20))
        return [background, headline, TitleLook.shadedOverALook(subtitle)]
    }

    private static func stacked(_ pen: TitlePen) -> [Layer] {
        // Streams of light running behind the stacked lines.
        var background = pen.fullFrame(Paint(hex: "#0A0C1C", kind: .live,
                                             stops: [GradientStop(hex: "#0A0C1C", position: 0),
                                                     GradientStop(hex: "#1B2050", position: 1.0 / 3),
                                                     GradientStop(hex: "#2A1240", position: 2.0 / 3),
                                                     GradientStop(hex: "#7C8CFF", position: 1)],
                                             live: LiveBackdrop(look: .energyStreams)))
        background.style.effects = [.grain(GrainEffect(amount: 20))]
        let left = (pen.canvas.width * 0.12).rounded()
        let mark = pen.box("Mark", CGRect(x: left, y: (pen.canvas.height * 0.22).rounded(),
                                          width: pen.u(56), height: pen.u(56)),
                           fill: Paint(hex: "#7C8CFF"), radius: pen.u(14))
        let title = pen.words("Title", "Your Title", font: "SF Pro", size: 120, weight: .bold,
                              color: "#FFFFFF", origin: CGPoint(x: left, y: mark.frame.maxY + pen.u(28)))
        let second = pen.words("Line 2", "Second line", font: "SF Pro", size: 120,
                               color: "#9FA8FF", origin: CGPoint(x: left, y: title.frame.maxY - pen.u(8)))
        let subtitle = pen.words("Subtitle", "A short line about it", font: "SF Pro", size: 36,
                                 color: "#B8BCD6", origin: CGPoint(x: left, y: second.frame.maxY + pen.u(26)))
        // The lighter lines wear a soft shade where the streams run brightest.
        return [background, mark, title, TitleLook.shadedOverALook(second), TitleLook.shadedOverALook(subtitle)]
    }

    // MARK: Name cards, in title safe

    private static func splitWipe(_ pen: TitlePen) -> Layer {
        let edge = pen.u(6), padX = pen.u(32), padY = pen.u(18)
        // Rays of light sweeping slowly across the colour bar.
        var bar = pen.box("Background", pen.surfaceStart,
                          fill: live(.lightRays, ground: "#1A4DFF", lights: ["#6E8BFF", "#59D9FF", "#9C7BFF"]))
        bar.placement = .fill
        var lip = pen.box("Edge", CGRect(x: 0, y: 0, width: edge, height: edge), fill: Paint(hex: "#FFFFFF"))
        lip.placement = LayerPlacement(horizontal: .left, vertical: .stretch)
        let name = pen.words("Name", "Your Name", font: "SF Pro", size: 48, weight: .bold,
                             color: "#FFFFFF", origin: .zero)
        let role = pen.words("Role", "Role or title", font: "SF Pro", size: 30, weight: .medium,
                             color: "#E3EAFF", origin: .zero)
        return pen.card([bar, lip, name, TitleLook.shadedOverALook(role)], name: TitleKind.nameCard.name, gap: pen.u(2),
                        padding: GroupPadding(top: padY, right: padX, bottom: padY, left: edge + padX - pen.u(4)),
                        corner: pen.safeCorner)
    }

    private static func underline(_ pen: TitlePen) -> Layer {
        let name = pen.words("Name", "Your Name", font: "SF Pro", size: 54, weight: .bold,
                             color: "#FFFFFF", origin: .zero, legibleOverVideo: true)
        let role = pen.words("Role", "Role or title", font: "SF Pro", size: 30, weight: .medium,
                             color: "#F2F2F2", origin: .zero, legibleOverVideo: true)
        // As long as the words: the column stretches it to its own width.
        var line = pen.box("Rule", CGRect(x: 0, y: 0, width: pen.u(120), height: pen.u(4)),
                           fill: Paint(hex: "#FFD60A"))
        line.placement = LayerPlacement(horizontal: .stretch)
        line.style.shadows = TitleLook.shadows(forColorHex: "#FFD60A", fontSize: pen.u(30))
        // No backing, only a soft dark shade behind the words, so white words
        // still read over a white screenshot.
        var shade = pen.box("Shade", pen.surfaceStart, fill: Paint(hex: "#000000"))
        shade.placement = .fill
        shade.style.opacity = 0.7
        shade.style.effects = [.blur(BlurEffect(radius: pen.u(24)))]
        return pen.card([shade, name, line, role], name: TitleKind.nameCard.name, gap: pen.u(10),
                        padding: GroupPadding(top: pen.u(14), right: pen.u(24), bottom: pen.u(14), left: pen.u(24)),
                        corner: pen.safeCorner)
    }

    private static func pill(_ pen: TitlePen) -> Layer {
        // Soft bubbles of colour blooming inside the dark pill.
        var pill = pen.box("Background", pen.surfaceStart,
                           fill: live(.colorBubbles, ground: "#15171C", lights: ["#6E8BFF", "#C46BFF", "#3D8BFF"],
                                      strength: 80),
                           radius: pen.u(64))
        pill.placement = .fill
        // Solid, so white words on it read over white footage too.
        pill.style.opacity = 1
        pill.style.shadows = [ShadowStyle(radius: pen.u(20), offset: CGSize(width: 0, height: pen.u(6)),
                                          colorHex: "#000000", opacity: 0.3)]
        let mark = pen.oval("Mark", CGRect(x: 0, y: 0, width: pen.u(64), height: pen.u(64)),
                            fill: Paint(hex: "#6E8BFF", kind: .linear,
                                        stops: [GradientStop(hex: "#6E8BFF", position: 0),
                                                GradientStop(hex: "#C46BFF", position: 1)],
                                        angle: 135))
        let name = pen.words("Name", "Your Name", font: "SF Pro", size: 42, weight: .semibold,
                             color: "#FFFFFF", origin: .zero)
        let role = pen.words("Role", "Role or title", font: "SF Pro", size: 28, color: "#B4BAC6",
                             origin: .zero)
        let words = pen.stack([name, TitleLook.shadedOverALook(role)], name: "Words",
                              direction: .column, gap: 0, origin: .zero,
                              placement: LayerPlacement(horizontal: .left))
        return pen.card([pill, mark, words], name: TitleKind.nameCard.name, gap: pen.u(18),
                        padding: GroupPadding(top: pen.u(14), right: pen.u(40), bottom: pen.u(14), left: pen.u(14)),
                        direction: .row, corner: pen.safeCorner)
    }
}
