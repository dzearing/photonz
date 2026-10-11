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
    var designedSet: TitleDesign? {
        typealias B = TitleBuild
        switch self {
        case .keynote:
            // Words rise into place one after another, Apple's two frame
            // stagger, and everything leaves together. The headline's slow
            // push is what moves while it holds; pushing the full-frame
            // gradient behind it too would redraw it every frame for a
            // change nobody sees.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 400, curve: .easeOutQuint)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.rise, delayMS: 150, lengthMS: 500, amount: 12, by: .word, staggerMS: 80),
                          hold: TitleHold(.push, amount: 1.5),
                          out: .off(.fade, delayMS: 150, lengthMS: 250)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 420, lengthMS: 500, amount: 10, by: .word, staggerMS: 60),
                          out: .off(.fade, delayMS: 150, lengthMS: 250)),
            ])
        case .softGlass:
            // The panel settles first, then each line sharpens inside it.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 600, curve: .easeOutQuint)),
                TitlePart(path: "Panel", role: .accent,
                          in: B(.scaleFrom, delayMS: 100, lengthMS: 600, amount: 96, curve: .easeOutQuint),
                          hold: TitleHold(.push, amount: 1),
                          out: .off(.scaleFrom, delayMS: 60, lengthMS: 300, amount: 97)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.blurIn, delayMS: 250, lengthMS: 700, amount: 12, by: .line),
                          out: .off(.fade, delayMS: 150, lengthMS: 220)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.blurIn, delayMS: 400, lengthMS: 650, amount: 10, by: .line),
                          out: .off(.fade, delayMS: 150, lengthMS: 220)),
            ])
        case .kinetic:
            // Each word slides up out of its own line with a little spring,
            // and the block keeps pushing in while it holds.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 300, curve: .easeOutQuint)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.maskReveal, delayMS: 150, lengthMS: 550, curve: .easeOutBack,
                                by: .word, staggerMS: 60),
                          hold: TitleHold(.push, amount: 2),
                          out: .off(.rise, delayMS: 140, lengthMS: 250, amount: 24)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 520, lengthMS: 450, amount: 14, by: .word, staggerMS: 45),
                          out: .off(.fade, delayMS: 140, lengthMS: 200)),
            ])
        case .editorial:
            // The kicker first, then the serif wiped on, then the rule.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 400, curve: .easeOutQuint),
                          hold: TitleHold(.push, amount: 2)),
                TitlePart(path: "Kicker", role: .kicker,
                          in: B(.fade, delayMS: 120, lengthMS: 500),
                          out: .off(.fade, delayMS: 150, lengthMS: 220)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.wipe, delayMS: 300, lengthMS: 700, direction: .right),
                          out: .off(.fade, delayMS: 180, lengthMS: 250)),
                TitlePart(path: "Rule", role: .accent,
                          in: B(.drawOn, delayMS: 750, lengthMS: 600, direction: .right),
                          out: .off(.drawOn, delayMS: 220, lengthMS: 250)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 950, lengthMS: 500, amount: 8),
                          out: .off(.fade, delayMS: 260, lengthMS: 200)),
            ])
        case .terminal:
            // Typed in a letter at a time, the cursor waiting after it, the
            // progress line running out under it all; the cursor is what
            // moves while it holds.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 400, curve: .easeOutQuint)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.typewriter, delayMS: 200, lengthMS: 400, staggerMS: 45),
                          out: .off(.fade, delayMS: 120, lengthMS: 200)),
                TitlePart(path: "Cursor", role: .accent,
                          in: B(.fade, delayMS: 600, lengthMS: 150),
                          hold: TitleHold(.blink),
                          out: .off(.fade, delayMS: 100, lengthMS: 100)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.typewriter, delayMS: 760, lengthMS: 400, staggerMS: 25),
                          out: .off(.fade, delayMS: 120, lengthMS: 200)),
                TitlePart(path: "Progress", role: .accent,
                          in: B(.drawOn, delayMS: 300, lengthMS: 1400, direction: .right, curve: .easeOutQuint),
                          out: .off(.drawOn, delayMS: 80, lengthMS: 250)),
            ])
        case .glass:
            // The recording frosts over as the title arrives (nothing of a
            // title is on its first frame), settles from 105% to 100% the
            // whole time it holds, and racks back into focus as the title
            // leaves, ending exactly on the footage. The words are gone just
            // before the glass clears.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.frost, delayMS: 0, lengthMS: 700, curve: .easeOutQuint),
                          hold: TitleHold(.push, amount: -5),
                          out: .off(.frost, delayMS: 0, lengthMS: 480)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.blurIn, delayMS: 200, lengthMS: 800, amount: 16, by: .line),
                          out: .off(.fade, delayMS: 200, lengthMS: 280)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 330, lengthMS: 650, amount: 14),
                          out: .off(.fade, delayMS: 220, lengthMS: 250)),
            ])
        case .lightLeak:
            // Two warm lights cross the dark the whole time; the capitals
            // close up from wide tracking.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 500, curve: .easeOutQuint)),
                TitlePart(path: "Leak 1", role: .accent,
                          in: B(.fade, delayMS: 0, lengthMS: 900, curve: .easeOutQuint),
                          hold: TitleHold(.drift, amount: 220, direction: .right)),
                TitlePart(path: "Leak 2", role: .accent,
                          in: B(.fade, delayMS: 200, lengthMS: 900, curve: .easeOutQuint),
                          hold: TitleHold(.drift, amount: 180, direction: .left)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.trackIn, delayMS: 300, lengthMS: 1500, amount: 25, curve: .easeOutQuint,
                                by: .letter, staggerMS: 0),
                          out: .off(.fade, delayMS: 150, lengthMS: 300)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 1100, lengthMS: 600, amount: 8),
                          out: .off(.fade, delayMS: 150, lengthMS: 250)),
            ])
        case .gradientGlow:
            // The headline settles from 115% out of a blur while the colours
            // inside it keep sliding.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 400, curve: .easeOutQuint)),
                TitlePart(path: "Gradient", role: .accent,
                          hold: TitleHold(.drift, amount: 900, direction: .left)),
                TitlePart(path: "Headline", role: .accent,
                          in: B(.scaleFrom, delayMS: 150, lengthMS: 900, amount: 115),
                          out: .off(.fade, delayMS: 150, lengthMS: 300)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.blurIn, delayMS: 150, lengthMS: 900, amount: 20)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 600, lengthMS: 600, amount: 10),
                          out: .off(.fade, delayMS: 150, lengthMS: 250)),
            ])
        case .stacked:
            // Lines revealed from alternating sides a beat apart, then the
            // mark; they leave upwards in reverse order. The mesh drifting
            // behind them is what moves while it holds.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 500, curve: .easeOutQuint)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.maskReveal, delayMS: 150, lengthMS: 600, direction: .up),
                          out: .off(.rise, delayMS: 160, lengthMS: 200, amount: 20)),
                TitlePart(path: "Line 2", role: .kicker,
                          in: B(.maskReveal, delayMS: 250, lengthMS: 600, direction: .down),
                          out: .off(.rise, delayMS: 200, lengthMS: 200, amount: 20)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.maskReveal, delayMS: 350, lengthMS: 550, direction: .up),
                          out: .off(.rise, delayMS: 240, lengthMS: 200, amount: 20)),
                TitlePart(path: "Mark", role: .accent,
                          in: B(.springPop, delayMS: 700, lengthMS: 500, amount: 40),
                          out: .off(.fade, delayMS: 280, lengthMS: 180)),
            ])
        case .splitWipe:
            // The bar wipes in and the words are uncovered behind its edge;
            // out in reverse, quicker.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.wipe, delayMS: 0, lengthMS: 300, direction: .right),
                          out: .off(.wipe, delayMS: 0, lengthMS: 200, direction: .left)),
                TitlePart(path: "Edge", role: .accent,
                          in: B(.wipe, delayMS: 60, lengthMS: 280, direction: .down),
                          out: .off(.fade, delayMS: 0, lengthMS: 150)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.wipe, delayMS: 110, lengthMS: 380, direction: .right),
                          out: .off(.fade, delayMS: 80, lengthMS: 150)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.wipe, delayMS: 230, lengthMS: 380, direction: .right),
                          out: .off(.fade, delayMS: 120, lengthMS: 150)),
            ])
        case .underline:
            // The shade softens in, the name rises, the line draws on under
            // it, then the role.
            return TitleDesign(parts: [
                TitlePart(path: "Shade", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 500, curve: .easeOutQuint),
                          out: .off(.fade, delayMS: 0, lengthMS: 250)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.rise, delayMS: 60, lengthMS: 500, amount: 8),
                          out: .off(.rise, delayMS: 40, lengthMS: 220, amount: 8)),
                TitlePart(path: "Rule", role: .accent,
                          in: B(.drawOn, delayMS: 100, lengthMS: 400, direction: .right),
                          out: .off(.wipe, delayMS: 100, lengthMS: 200, direction: .left)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.rise, delayMS: 480, lengthMS: 450, amount: 6),
                          hold: TitleHold(.drift, amount: 4, direction: .right),
                          out: .off(.fade, delayMS: 160, lengthMS: 180)),
            ])
        case .pill:
            // The pill springs in, the mark after it, then the words sharpen.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.springPop, delayMS: 0, lengthMS: 550, amount: 88),
                          out: .off(.springPop, delayMS: 0, lengthMS: 220, amount: 94)),
                TitlePart(path: "Mark", role: .accent,
                          in: B(.springPop, delayMS: 120, lengthMS: 500, amount: 60),
                          hold: TitleHold(.push, amount: 6),
                          out: .off(.fade, delayMS: 60, lengthMS: 150)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.blurIn, delayMS: 200, lengthMS: 500, amount: 8),
                          out: .off(.fade, delayMS: 90, lengthMS: 150)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.blurIn, delayMS: 320, lengthMS: 500, amount: 8),
                          out: .off(.fade, delayMS: 120, lengthMS: 150)),
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

    private static func keynote(_ pen: TitlePen) -> [Layer] {
        // Black with the faintest lift in the middle, near-white words.
        let background = pen.fullFrame(Paint(hex: "#000000", kind: .radial,
                                             stops: [GradientStop(hex: "#1C1C1F", position: 0),
                                                     GradientStop(hex: "#000000", position: 1)],
                                             center: CGPoint(x: 0.5, y: 0.45)))
        let title = pen.centred("Title", "Your Title", font: "SF Pro", size: 120, weight: .bold,
                                color: "#F5F5F7", top: pen.canvas.height * 0.39)
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 42,
                                   color: "#A1A1A6", top: title.frame.maxY + pen.u(14))
        return [background, title, subtitle]
    }

    private static func softGlass(_ pen: TitlePen) -> [Layer] {
        // Three deep colours drifting one sweep every ten seconds, with grain.
        var background = pen.fullFrame(Paint(hex: "#16205E", kind: .mesh,
                                             stops: [GradientStop(hex: "#16205E", position: 0),
                                                     GradientStop(hex: "#4A2FA8", position: 0.5),
                                                     GradientStop(hex: "#0B4F66", position: 1)],
                                             angle: 200, drift: 80))
        background.style.effects = [.grain(GrainEffect())]
        // Frosted glass: the mesh behind it softened, a breath of white over it.
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
        return [background, panel, title, subtitle]
    }

    private static func kinetic(_ pen: TitlePen) -> [Layer] {
        let background = pen.fullFrame(Paint(hex: "#1D3BFF"))
        let title = pen.centred("Title", "YOUR TITLE", font: "Avenir Next Condensed", size: 210,
                                weight: .bold, color: "#FFFFFF", top: pen.canvas.height * 0.3)
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 40,
                                   weight: .semibold, color: "#DDE3FF", top: title.frame.maxY + pen.u(4))
        return [background, title, subtitle]
    }

    private static func editorial(_ pen: TitlePen) -> [Layer] {
        var background = pen.fullFrame(Paint(hex: "#F4F1EA"))
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
        return [background, kicker, title, rule, subtitle]
    }

    private static func terminal(_ pen: TitlePen) -> [Layer] {
        var background = pen.fullFrame(Paint(hex: "#050A07", kind: .radial,
                                             stops: [GradientStop(hex: "#0E2A1B", position: 0),
                                                     GradientStop(hex: "#050A07", position: 1)],
                                             center: CGPoint(x: 0.3, y: 0.4)))
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
        return [background, prompt, subtitle, progress]
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
        var background = pen.fullFrame(Paint(hex: "#08070B"))
        background.style.effects = [.grain(GrainEffect(amount: 22))]
        // Two big soft warm lights thrown over the dark.
        func leak(_ name: String, _ rect: CGRect, _ hex: String, _ opacity: Double, blur: CGFloat) -> Layer {
            var light = pen.oval(name, rect, fill: Paint(hex: hex))
            light.style.opacity = opacity
            light.style.blendMode = .screen
            light.style.effects = [.blur(BlurEffect(radius: pen.u(blur)))]
            return light
        }
        let first = leak("Leak 1", CGRect(x: -pen.u(240), y: -pen.u(180), width: pen.u(1100), height: pen.u(900)),
                         "#FF7A2F", 0.5, blur: 160)
        let second = leak("Leak 2", CGRect(x: (pen.canvas.width * 0.55).rounded(), y: (pen.canvas.height * 0.42).rounded(),
                                           width: pen.u(900), height: pen.u(760)),
                          "#FF3D7F", 0.42, blur: 150)
        var title = pen.centred("Title", "YOUR TITLE", font: "Avenir Next", size: 88, weight: .medium,
                                color: "#FFF6EE", top: pen.canvas.height * 0.42)
        title.style.effects = [.glow(GlowEffect(colorHex: "#FFB58A", radius: pen.u(18), size: pen.u(2), opacity: 0.55))]
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "Avenir Next", size: 30,
                                   color: "#D8CEC6", top: title.frame.maxY + pen.u(18))
        return [background, first, second, title, subtitle]
    }

    private static func gradientGlow(_ pen: TitlePen) -> [Layer] {
        let background = pen.fullFrame(Paint(hex: "#000000"))
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
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 40,
                                   color: "#A1A1A6", top: title.frame.maxY + pen.u(20))
        return [background, headline, subtitle]
    }

    private static func stacked(_ pen: TitlePen) -> [Layer] {
        var background = pen.fullFrame(Paint(hex: "#0A0C1C", kind: .mesh,
                                             stops: [GradientStop(hex: "#0A0C1C", position: 0),
                                                     GradientStop(hex: "#1B2050", position: 0.5),
                                                     GradientStop(hex: "#2A1240", position: 1)],
                                             angle: 200, drift: Paint.startingDrift))
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
        return [background, mark, title, second, subtitle]
    }

    // MARK: Name cards, in title safe

    private static func splitWipe(_ pen: TitlePen) -> Layer {
        let edge = pen.u(6), padX = pen.u(32), padY = pen.u(18)
        var bar = pen.box("Background", pen.surfaceStart, fill: Paint(hex: "#1A4DFF"))
        bar.placement = .fill
        var lip = pen.box("Edge", CGRect(x: 0, y: 0, width: edge, height: edge), fill: Paint(hex: "#FFFFFF"))
        lip.placement = LayerPlacement(horizontal: .left, vertical: .stretch)
        let name = pen.words("Name", "Your Name", font: "SF Pro", size: 48, weight: .bold,
                             color: "#FFFFFF", origin: .zero)
        let role = pen.words("Role", "Role or title", font: "SF Pro", size: 30, weight: .medium,
                             color: "#E3EAFF", origin: .zero)
        return pen.card([bar, lip, name, role], name: TitleKind.nameCard.name, gap: pen.u(2),
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
        var pill = pen.box("Background", pen.surfaceStart, fill: Paint(hex: "#15171C"), radius: pen.u(64))
        pill.placement = .fill
        pill.style.opacity = 0.94
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
        let words = pen.stack([name, role], name: "Words", direction: .column, gap: 0, origin: .zero,
                              placement: LayerPlacement(horizontal: .left))
        return pen.card([pill, mark, words], name: TitleKind.nameCard.name, gap: pen.u(18),
                        padding: GroupPadding(top: pen.u(14), right: pen.u(40), bottom: pen.u(14), left: pen.u(14)),
                        direction: .row, corner: pen.safeCorner)
    }
}
