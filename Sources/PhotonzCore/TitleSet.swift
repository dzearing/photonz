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
// - since 2026-10-18 the calm set's restraint (`TitleSetCalm.swift`,
//   `TitleMoreStylesCalmTests`): one move per part, travel under 24 points,
//   ins under a second on Ease out expo, outs of 300 to 450 ms on an even
//   sine, nothing that springs, flips or turns in depth;
// - something still moving while it holds, barely: a moving look at a third
//   of its old speed and strength, a cursor blinking;
// - words that read over dark and light footage alike;
// - lower thirds inside title safe, a tenth of the frame from the edges.
//
// Amounts are points of a 1080 line frame, scaled to the frame a title lands on.

extension BuiltInTitle {

    // MARK: How each one moves

    /// The design of one of the set, nil for a retired preset.
    ///
    /// Toned down to calm (task `the-existing-title-pages-are-toned-down-to-calm`):
    /// the user called this set far too busy once the Apple-level pages
    /// landed beside it (2026-10-18). Each keeps its own way in, but takes the
    /// approved mock's restraint (`TitleSetCalm.swift`): one move per part, a
    /// rise of 24 points at most, a blur that clears, a mask, a short track
    /// in, nothing that springs, flips or turns in depth; ins of 600 to 950
    /// ms landing on Ease out expo, outs of 300 to 450 ms on an even sine.
    /// What moves while it holds is the background, barely.
    var designedSet: TitleDesign? {
        typealias B = TitleBuild
        let expo = EasingCurve.easeOutExpo, cubic = EasingCurve.easeOut, quint = EasingCurve.easeOutQuint
        /// A background settling in.
        func ground(_ length: Int = 600) -> B { B(.fade, delayMS: 0, lengthMS: length, curve: quint) }
        /// A way off on the mock's even sine: finished `delay` ms before the
        /// title goes, `length` long.
        func off(_ kind: TitleBuildKind, _ delay: Int, _ length: Int, amount: Double? = nil,
                 direction: TitleDirection = .up) -> B {
            B(kind, delayMS: delay, lengthMS: length, amount: amount, direction: direction, curve: .easeInOutSine)
        }
        switch self {
        case .keynote:
            // Words rise a few points into place one after another, then the
            // credit under them, over dust drifting very slowly.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background, in: ground()),
                TitlePart(path: "Title", role: .headline,
                          in: B(.rise, delayMS: 150, lengthMS: 900, amount: 18, curve: expo, by: .word, staggerMS: 90),
                          out: off(.fade, 80, 420)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 450, lengthMS: 750, amount: 12, curve: expo),
                          out: off(.fade, 140, 360)),
            ])
        case .softGlass:
            // The panel settles, then each word sharpens out of a soft focus
            // inside it.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background, in: ground()),
                TitlePart(path: "Panel", role: .accent,
                          in: B(.scaleFrom, delayMS: 100, lengthMS: 800, amount: 97, curve: expo),
                          out: off(.fade, 60, 400)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.blurIn, delayMS: 300, lengthMS: 900, amount: 12, curve: expo, by: .word, staggerMS: 80),
                          out: off(.blurIn, 80, 420, amount: 8)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.blurIn, delayMS: 650, lengthMS: 750, amount: 8, curve: expo),
                          out: off(.fade, 140, 360)),
            ])
        case .kinetic:
            // Each word slides up out of its own line and lands; it leaves by
            // lifting a few points as it fades.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background, in: ground(500)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.maskReveal, delayMS: 150, lengthMS: 900, curve: expo, by: .word, staggerMS: 90),
                          out: off(.rise, 80, 400, amount: 12)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 500, lengthMS: 750, amount: 10, curve: expo),
                          out: off(.fade, 140, 360)),
            ])
        case .editorial:
            // The kicker first, then the serif rises out of its own baseline,
            // the rule draws itself under it and the line below follows.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background, in: ground()),
                TitlePart(path: "Kicker", role: .kicker,
                          in: B(.fade, delayMS: 100, lengthMS: 600, curve: cubic),
                          out: off(.fade, 160, 320)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.maskReveal, delayMS: 250, lengthMS: 950, curve: expo, by: .line, staggerMS: 110),
                          out: off(.rise, 80, 400, amount: 8)),
                TitlePart(path: "Rule", role: .accent,
                          in: B(.drawOn, delayMS: 700, lengthMS: 700, direction: .right, curve: expo),
                          out: off(.drawOn, 120, 300)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 850, lengthMS: 700, amount: 10, curve: expo),
                          out: off(.fade, 140, 300)),
            ])
        case .terminal:
            // The words are typed a letter at a time with the cursor waiting
            // after them, the progress line running out under it all; the
            // cursor is what moves while it holds.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background, in: ground()),
                TitlePart(path: "Kicker", role: .kicker,
                          in: B(.fade, delayMS: 100, lengthMS: 500, curve: cubic),
                          out: off(.fade, 160, 300)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.typewriter, delayMS: 300, lengthMS: 600, staggerMS: 60),
                          out: off(.fade, 80, 400)),
                TitlePart(path: "Cursor", role: .accent,
                          in: B(.fade, delayMS: 300, lengthMS: 360, curve: cubic),
                          hold: TitleHold(.blink),
                          out: off(.fade, 60, 300)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.typewriter, delayMS: 950, lengthMS: 400, staggerMS: 22),
                          out: off(.fade, 140, 320)),
                TitlePart(path: "Progress", role: .accent,
                          in: B(.drawOn, delayMS: 500, lengthMS: 900, direction: .right, curve: expo),
                          out: off(.drawOn, 80, 300)),
            ])
        case .glass:
            // The recording frosts over as the title arrives (nothing of a
            // title is on its first frame), settles from 102% to 100% the
            // whole time it holds, and racks back into focus as the title
            // leaves, ending exactly on the footage. The words sharpen out of
            // a soft focus a line at a time and are gone just before the
            // glass clears.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.frost, delayMS: 0, lengthMS: 700, curve: quint),
                          hold: TitleHold(.push, amount: -2),
                          out: off(.frost, 0, 450)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.blurIn, delayMS: 250, lengthMS: 900, amount: 12, curve: expo, by: .line, staggerMS: 90),
                          out: off(.blurIn, 80, 420, amount: 8)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 600, lengthMS: 750, amount: 10, curve: expo),
                          out: off(.fade, 140, 340)),
            ])
        case .lightLeak:
            // Warm light leaking slowly across the dark; the capitals close
            // up from slightly open tracking.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background, in: ground(700)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.trackIn, delayMS: 300, lengthMS: 950, amount: 8, curve: expo, by: .letter, staggerMS: 20),
                          out: off(.blurIn, 40, 420, amount: 8)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 750, lengthMS: 700, amount: 10, curve: expo),
                          out: off(.fade, 140, 320)),
            ])
        case .gradientGlow:
            // The coloured headline settles from a touch larger as it fades
            // up, while the colours inside it slide very slowly.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background, in: ground(500)),
                TitlePart(path: "Gradient", role: .accent,
                          hold: TitleHold(.drift, amount: 160, direction: .left)),
                TitlePart(path: "Headline", role: .accent,
                          in: B(.scaleFrom, delayMS: 200, lengthMS: 950, amount: 104, curve: expo),
                          out: off(.fade, 80, 420)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.fade, delayMS: 200, lengthMS: 600, curve: cubic)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 650, lengthMS: 750, amount: 10, curve: expo),
                          out: off(.fade, 140, 340)),
            ])
        case .stacked:
            // Each line rises into place a beat after the one above, then
            // the mark settles in; they leave upwards in reverse order. The
            // streams behind them drift slowly while it holds.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background, in: ground()),
                TitlePart(path: "Title", role: .headline,
                          in: B(.rise, delayMS: 150, lengthMS: 900, amount: 16, curve: expo, by: .line),
                          out: off(.rise, 60, 400, amount: 10)),
                TitlePart(path: "Line 2", role: .kicker,
                          in: B(.rise, delayMS: 300, lengthMS: 900, amount: 16, curve: expo, by: .line),
                          out: off(.rise, 100, 380, amount: 10)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 600, lengthMS: 750, amount: 10, curve: expo),
                          out: off(.fade, 200, 300)),
                TitlePart(path: "Mark", role: .accent,
                          in: B(.scaleFrom, delayMS: 750, lengthMS: 600, amount: 94, curve: expo),
                          out: off(.fade, 160, 300)),
            ])
        case .splitWipe:
            // The bar wipes in and the words are uncovered behind its edge;
            // out, the card fades away whole: a bar wiping back would leave
            // the fading words hanging past its edge over the footage.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.wipe, delayMS: 0, lengthMS: 600, direction: .right, curve: expo),
                          out: off(.fade, 0, 360)),
                TitlePart(path: "Edge", role: .accent,
                          in: B(.wipe, delayMS: 80, lengthMS: 500, direction: .down, curve: expo),
                          out: off(.fade, 0, 300)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.wipe, delayMS: 200, lengthMS: 800, direction: .right, curve: expo),
                          out: off(.fade, 100, 380)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.wipe, delayMS: 500, lengthMS: 700, direction: .right, curve: expo),
                          out: off(.fade, 100, 360)),
            ])
        case .underline:
            // The shade softens in, the name rises a few points, the line
            // draws on under it, then the role.
            return TitleDesign(parts: [
                TitlePart(path: "Shade", role: .background, in: ground(500),
                          out: off(.fade, 0, 300)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.rise, delayMS: 100, lengthMS: 800, amount: 12, curve: expo),
                          out: off(.rise, 80, 420, amount: 8)),
                TitlePart(path: "Rule", role: .accent,
                          in: B(.drawOn, delayMS: 450, lengthMS: 650, direction: .right, curve: expo),
                          out: off(.drawOn, 100, 300)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.rise, delayMS: 600, lengthMS: 700, amount: 8, curve: expo),
                          out: off(.fade, 160, 300)),
            ])
        case .pill:
            // The pill settles in from a touch smaller, the mark after it,
            // then the name fades up word by word.
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.scaleFrom, delayMS: 0, lengthMS: 700, amount: 96, curve: expo),
                          out: off(.fade, 0, 320)),
                TitlePart(path: "Mark", role: .accent,
                          in: B(.scaleFrom, delayMS: 120, lengthMS: 650, amount: 94, curve: expo),
                          out: off(.fade, 60, 300)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.fade, delayMS: 250, lengthMS: 800, curve: cubic, by: .word, staggerMS: 70),
                          out: off(.fade, 80, 420)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.rise, delayMS: 600, lengthMS: 600, amount: 8, curve: expo),
                          out: off(.fade, 120, 300)),
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

    // The five below were redesigned on 2026-11-21 from a board of refined
    // title slides (task `keynote-clean-soft-gradient-glass-kinetic-bold-t`,
    // `queue/audits/2026-11-21-title-reference-board.md`): a neutral ground
    // with a temperature, one accent that takes it, ivory or ink instead of
    // pure white or black, and one named typographic idea each. The rules are
    // in `docs/design/video-titles-polish.md`, "Colour and type rules".

    private static func keynote(_ pen: TitlePen) -> [Layer] {
        // Main Title, a film's: Didot's hairlines at display size in ivory on
        // a warm black, the line under it set as a credit, small capitals in
        // brass tracked wide. Dust drifting very slowly in the dark, as in a
        // projector's beam.
        let background = pen.fullFrame(live(.particles, ground: "#0B0A09",
                                            lights: ["#4A3A26", "#56442C", "#3F3222"], speed: 14, strength: 4))
        let title = pen.centred("Title", "The Long Way Home", font: "Didot", size: 168, weight: .regular,
                                color: "#EFE8DC", top: pen.canvas.height * 0.37, tracking: -0.012, lineHeight: 1.02)
        let subtitle = pen.centred("Subtitle", "A FILM BY JUNE HALE", font: "Avenir Next", size: 24,
                                   weight: .medium, color: "#B8A27C", top: title.frame.maxY + pen.u(30),
                                   tracking: 0.34, lineHeight: 1.2)
        return [background, title, TitleLook.shadedOverALook(subtitle)]
    }

    private static func softGlass(_ pen: TitlePen) -> [Layer] {
        // Frosted Glass: pale sage and stone light flowing slowly under a
        // sheet of frosted glass, Apple's serif in a deep green ink on it, the
        // line under it in small sage capitals tracked open. No grain: grain
        // is drawn afresh every frame, which reads as flicker.
        let background = pen.fullFrame(Paint(hex: "#D3D2C6", kind: .live,
                                             stops: [GradientStop(hex: "#D3D2C6", position: 0),
                                                     GradientStop(hex: "#BFC4B3", position: 0.5),
                                                     GradientStop(hex: "#E4E2D8", position: 1)],
                                             live: LiveBackdrop(look: .liquidGradient, speed: 24, strength: 14,
                                                                scale: 180, shape: 0)))
        // Frosted glass: the light behind it softened, white over it.
        let size = CGSize(width: pen.u(1120), height: pen.u(420))
        var panel = pen.box("Panel", CGRect(x: ((pen.canvas.width - size.width) / 2).rounded(),
                                            y: ((pen.canvas.height - size.height) / 2).rounded(),
                                            width: size.width, height: size.height),
                            fill: Paint(hex: "#FFFFFF"), radius: pen.u(20))
        panel.style.opacity = 0.45
        panel.style.effects = [.blur(BlurEffect(radius: pen.u(24), kind: .background))]
        let title = pen.centred("Title", "Quiet Mornings", font: "New York", size: 124, weight: .medium,
                                color: "#1F2620", top: panel.frame.minY + pen.u(110), tracking: -0.018,
                                lineHeight: 1.04)
        let subtitle = pen.centred("Subtitle", "A SHORT FILM ABOUT SLOWING DOWN", font: "SF Pro", size: 24, weight: .semibold,
                                   color: "#4C5644", top: title.frame.maxY + pen.u(26), tracking: 0.22,
                                   lineHeight: 1.2)
        // The light behind the glass may get darker than the small line
        // reads on, so it wears the light shade a restyle would give it.
        return [background, panel, title, TitleLook.shadedOverALook(subtitle, overLightGround: true)]
    }

    private static func kinetic(_ pen: TitlePen) -> [Layer] {
        // Condensed Poster: condensed capitals stacked tight and flush left,
        // nine times the size of the line under them, ivory on a warm black
        // with ember wind barely in it; the one colour is the vermilion of
        // the small line, which the wind takes too.
        let background = pen.fullFrame(live(.windStreams, ground: "#0F0E0D",
                                            lights: ["#5A2A1E", "#4A241A", "#6A3022"], speed: 22, strength: 2))
        let left = (pen.canvas.width * 0.125).rounded()
        // DIN Condensed carries 72 points of its own leading at this size,
        // which a set line height does not take back: 0.62 of the size plus
        // that leading puts the lines a tenth of a capital apart. The box
        // keeps room for letters past those tight lines, so the small line
        // tucks back into it.
        let title = pen.words("Title", "MAKE\nNOISE", font: "DIN Condensed", size: 360, weight: .bold,
                              color: "#F1ECE2", origin: CGPoint(x: left, y: pen.canvas.height * 0.12),
                              tracking: -0.012, lineHeight: 0.62)
        let subtitle = pen.words("Subtitle", "LIVE IN BERLIN, MAY 14", font: "Avenir Next Condensed", size: 40,
                                 weight: .bold, color: "#EE4B2B",
                                 origin: CGPoint(x: left + pen.u(10), y: title.frame.maxY - pen.u(36)),
                                 tracking: 0.08, lineHeight: 1.2)
        return [background, title, TitleLook.shadedOverALook(subtitle)]
    }

    private static func editorial(_ pen: TitlePen) -> [Layer] {
        // Warm paper a faint architect's sketch draws itself across, slowly,
        // in the kicker's own rust and brown.
        let background = pen.fullFrame(live(.sketch, ground: "#F4F1EA",
                                            lights: ["#9A4A26", "#B07A55", "#7A5A3A"], speed: 30, strength: 25))
        let left = (pen.canvas.width * 0.12).rounded()
        let kicker = pen.words("Kicker", "CHAPTER ONE", font: "SF Pro", size: 28, weight: .semibold,
                               color: "#9A4A26", origin: CGPoint(x: left, y: pen.canvas.height * 0.33),
                               tracking: 0.12, lineHeight: 1)
        let title = pen.words("Title", "Your Title", font: "Georgia", size: 120, weight: .regular,
                              color: "#1A1A1A", origin: CGPoint(x: left, y: kicker.frame.maxY + pen.u(14)),
                              tracking: -0.012, lineHeight: 1.06)
        let rule = pen.line("Rule", from: CGPoint(x: left, y: title.frame.maxY + pen.u(26)),
                            length: pen.u(360), width: pen.u(2), color: "#1A1A1A")
        let subtitle = pen.words("Subtitle", "A short line about it", font: "SF Pro", size: 28,
                                 color: "#55524C", origin: CGPoint(x: left, y: rule.frame.maxY + pen.u(24)),
                                 tracking: 0, lineHeight: 1.3)
        // Paper is a light ground: the shade under the small lines is light.
        return [background, TitleLook.shadedOverALook(kicker, overLightGround: true), title, rule,
                TitleLook.shadedOverALook(subtitle, overLightGround: true)]
    }

    private static func terminal(_ pen: TitlePen) -> [Layer] {
        // Command Line: a monospaced system on a grid, as a developer launch
        // page sets one. Across the top, the amber label over a hairline the
        // width of the type area; low on the left, a big near-white mono
        // headline typed onto near black behind an amber caret, a grey mono
        // line under it. A trace of slate light moves through the dark (the
        // grid look draws a synthwave sun, the clip art this replaced).
        let background = pen.fullFrame(Paint(hex: "#09090A", kind: .live,
                                             stops: [GradientStop(hex: "#09090A", position: 0),
                                                     GradientStop(hex: "#1B3640", position: 1.0 / 3),
                                                     GradientStop(hex: "#203E48", position: 2.0 / 3),
                                                     GradientStop(hex: "#18303A", position: 1)],
                                             live: LiveBackdrop(look: .liquidGradient, speed: 16, strength: 2,
                                                                scale: 180, shape: 0)))
        let left = (pen.canvas.width * 0.125).rounded()
        let amber = "#FFB547"
        let kicker = pen.words("Kicker", "RELEASE NOTES", font: "SF Mono", size: 24, weight: .medium, color: amber,
                               origin: CGPoint(x: left + pen.u(4), y: pen.canvas.height * 0.33), tracking: 0.14,
                               lineHeight: 1.2)
        let progress = pen.line("Progress", from: CGPoint(x: left + pen.u(4), y: kicker.frame.maxY + pen.u(22)),
                                length: pen.canvas.width * 0.54, width: pen.u(2), color: "#2E3A45")
        let title = pen.words("Title", "Ship faster", font: "SF Mono", size: 168, weight: .semibold,
                              color: "#E6ECF1", origin: .zero, tracking: -0.05, lineHeight: 1.1)
        // A slim caret after the words, which the row keeps after them
        // however long they are typed.
        let cursor = pen.box("Cursor", CGRect(x: 0, y: 0, width: pen.u(10), height: (title.frame.height * 0.74).rounded()),
                             fill: Paint(hex: amber))
        let prompt = pen.stack([title, cursor], name: "Prompt", direction: .row, gap: pen.u(10),
                               origin: CGPoint(x: left - pen.u(4), y: progress.frame.maxY + pen.u(40)),
                               placement: LayerPlacement(vertical: .center))
        let subtitle = pen.words("Subtitle", "WHAT'S NEW IN VERSION 2.0", font: "SF Mono", size: 24, weight: .regular,
                                 color: "#7D8A97", origin: CGPoint(x: left + pen.u(4), y: prompt.localBounds.maxY + pen.u(22)),
                                 tracking: 0.1, lineHeight: 1.3)
        return [background, TitleLook.shadedOverALook(kicker), progress, prompt, TitleLook.shadedOverALook(subtitle)]
    }

    private static func glass(_ pen: TitlePen) -> [Layer] {
        // Black at 55% over the recording, the recording itself softened
        // behind it and drawn 2% larger, which the hold eases back to 100%.
        // Dim enough that white words read over a white screenshot.
        var background = pen.fullFrame(Paint(hex: "#000000"))
        background.style.opacity = TitleLook.glassDim
        background.style.effects = [.blur(BlurEffect(radius: pen.u(36), kind: .background, zoom: 102))]
        let title = pen.centred("Title", "Your Title", font: "SF Pro", size: 112, weight: .semibold,
                                color: "#FFFFFF", top: pen.canvas.height * 0.38, tracking: -0.022, lineHeight: 1.04)
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 40,
                                   weight: .medium, color: "#FFFFFF", top: title.frame.maxY + pen.u(20),
                                   tracking: -0.004, lineHeight: 1.2)
        return [background, title, subtitle]
    }

    private static func lightLeak(_ pen: TitlePen) -> [Layer] {
        // Warm light leaking slowly and softly across the dark: deeper
        // lights at a low strength, since the leaks overlap and a brighter
        // light only fills the frame with orange.
        let background = pen.fullFrame(live(.lightLeaks, ground: "#08070B",
                                            lights: ["#C8602A", "#C04A5A", "#C88A48"], speed: 30, strength: 12))
        var title = pen.centred("Title", "YOUR TITLE", font: "Avenir Next", size: 88, weight: .medium,
                                color: "#FFF6EE", top: pen.canvas.height * 0.42, tracking: 0.06, lineHeight: 1)
        title.style.effects = [.glow(GlowEffect(colorHex: "#FFB58A", radius: pen.u(14), size: pen.u(1), opacity: 0.2))]
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "Avenir Next", size: 30,
                                   color: "#D8CEC6", top: title.frame.maxY + pen.u(22), tracking: 0.01,
                                   lineHeight: 1.2)
        return [background, title, TitleLook.shadedOverALook(subtitle)]
    }

    private static func gradientGlow(_ pen: TitlePen) -> [Layer] {
        // A faint aurora rippling slowly low in the black, in the violet of
        // the words, so the page holds one colour.
        let background = pen.fullFrame(live(.aurora, ground: "#000000",
                                            lights: ["#9A5CF0", "#B060E0", "#8A5CFF"], speed: 30, strength: 18))
        let title = pen.centred("Title", "Your Title", font: "SF Pro", size: 150, weight: .semibold,
                                color: "#FFFFFF", top: pen.canvas.height * 0.36, tracking: -0.03, lineHeight: 1.05)
        // The colours, cut to the shape of the words under them and twice
        // their width, so the hold can slide them along.
        var gradient = pen.box("Gradient", CGRect(x: title.frame.minX, y: title.frame.minY - pen.u(10),
                                                  width: title.frame.width * 2,
                                                  height: title.frame.height + pen.u(20)),
                               fill: Paint(hex: "#8A5CFF", kind: .linear,
                                           stops: [GradientStop(hex: "#8A5CFF", position: 0),
                                                   GradientStop(hex: "#C77DFF", position: 0.35),
                                                   GradientStop(hex: "#F07AE6", position: 0.65),
                                                   GradientStop(hex: "#8A5CFF", position: 1)],
                                           angle: 90))
        gradient.style.matte = .shape
        // One picture of the coloured words, so its glow is theirs.
        var headline = TitlePen.grouped([title, gradient], name: "Headline")
        headline.style.effects = [.glow(GlowEffect(colorHex: "#B07CFF", radius: pen.u(20), size: pen.u(2),
                                                   opacity: 0.22))]
        // The aurora behind is lit in the same colours as the words, so the
        // coloured words throw a soft dark shade of their own to stand on.
        headline.style.shadows = [TitleLook.liveScrim(forColorHex: "#FFFFFF", fontSize: title.text?.fontSize ?? pen.u(150))]
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 40, weight: .medium,
                                   color: "#A1A1A6", top: title.frame.maxY + pen.u(24), tracking: -0.004,
                                   lineHeight: 1.2)
        return [background, headline, TitleLook.shadedOverALook(subtitle)]
    }

    private static func stacked(_ pen: TitlePen) -> [Layer] {
        // Roman and Italic: two lines at one size, a bold grotesk over a
        // Bodoni italic, as a fashion page sets a headline; ivory and blush on
        // an oxblood black, with faint streams of ember light drifting in it.
        // A short blush rule above, flush left on the same edge.
        let background = pen.fullFrame(Paint(hex: "#260A0E", kind: .live,
                                             stops: [GradientStop(hex: "#260A0E", position: 0),
                                                     GradientStop(hex: "#3B1812", position: 1.0 / 3),
                                                     GradientStop(hex: "#4D2018", position: 2.0 / 3),
                                                     GradientStop(hex: "#6A2D21", position: 1)],
                                             live: LiveBackdrop(look: .energyStreams, speed: 20, strength: 5)))
        let left = (pen.canvas.width * 0.125).rounded()
        let blush = "#E9B096"
        let mark = pen.box("Mark", CGRect(x: left + pen.u(6), y: (pen.canvas.height * 0.27).rounded(),
                                          width: pen.u(96), height: pen.u(3)),
                           fill: Paint(hex: blush))
        let title = pen.words("Title", "Made by Hand", font: "Helvetica Neue", size: 144, weight: .bold,
                              color: "#F4EEE8", origin: CGPoint(x: left, y: mark.frame.maxY + pen.u(34)),
                              tracking: -0.035, lineHeight: 1.0)
        let second = pen.words("Line 2", "slowly, with care", font: "BodoniSvtyTwoITCTT-BookIta", size: 144,
                               color: blush, origin: CGPoint(x: left + pen.u(4), y: title.frame.maxY - pen.u(16)),
                               tracking: -0.01, lineHeight: 1.0)
        let subtitle = pen.words("Subtitle", "THE AUTUMN COLLECTION", font: "Helvetica Neue", size: 24, weight: .medium,
                                 color: "#C4A79B", origin: CGPoint(x: left + pen.u(6), y: second.frame.maxY + pen.u(30)),
                                 tracking: 0.18, lineHeight: 1.2)
        return [background, mark, title, TitleLook.shadedOverALook(second), TitleLook.shadedOverALook(subtitle)]
    }

    // MARK: Name cards, in title safe

    private static func splitWipe(_ pen: TitlePen) -> Layer {
        let edge = pen.u(6), padX = pen.u(32), padY = pen.u(18)
        // Faint rays of light sweeping slowly across the colour bar.
        var bar = pen.box("Background", pen.surfaceStart,
                          fill: live(.lightRays, ground: "#1A4DFF", lights: ["#4D70FF", "#6E8BFF", "#3D63FF"],
                                     speed: 30, strength: 30))
        bar.placement = .fill
        var lip = pen.box("Edge", CGRect(x: 0, y: 0, width: edge, height: edge), fill: Paint(hex: "#FFFFFF"))
        lip.placement = LayerPlacement(horizontal: .left, vertical: .stretch)
        let name = pen.words("Name", "Your Name", font: "SF Pro", size: 48, weight: .semibold,
                             color: "#FFFFFF", origin: .zero, tracking: -0.012, lineHeight: 1.1)
        let role = pen.words("Role", "Role or title", font: "SF Pro", size: 30, weight: .medium,
                             color: "#E3EAFF", origin: .zero, tracking: -0.004, lineHeight: 1.2)
        return pen.card([bar, lip, name, TitleLook.shadedOverALook(role)], name: TitleKind.nameCard.name, gap: pen.u(2),
                        padding: GroupPadding(top: padY, right: padX, bottom: padY, left: edge + padX - pen.u(4)),
                        corner: pen.safeCorner)
    }

    private static func underline(_ pen: TitlePen) -> Layer {
        let name = pen.words("Name", "Your Name", font: "SF Pro", size: 54, weight: .semibold,
                             color: "#FFFFFF", origin: .zero, legibleOverVideo: true, tracking: -0.014,
                             lineHeight: 1.1)
        let role = pen.words("Role", "Role or title", font: "SF Pro", size: 30, weight: .medium,
                             color: "#F2F2F2", origin: .zero, legibleOverVideo: true, tracking: -0.004,
                             lineHeight: 1.2)
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
        // Faint bubbles of colour blooming slowly inside the dark pill.
        var pill = pen.box("Background", pen.surfaceStart,
                           fill: live(.colorBubbles, ground: "#15171C", lights: ["#6E8BFF", "#8C7BFF", "#3D8BFF"],
                                      speed: 30, strength: 25),
                           radius: pen.u(64))
        pill.placement = .fill
        // Solid, so white words on it read over white footage too.
        pill.style.opacity = 1
        pill.style.shadows = [ShadowStyle(radius: pen.u(20), offset: CGSize(width: 0, height: pen.u(6)),
                                          colorHex: "#000000", opacity: 0.3)]
        let mark = pen.oval("Mark", CGRect(x: 0, y: 0, width: pen.u(64), height: pen.u(64)),
                            fill: Paint(hex: "#6E8BFF", kind: .linear,
                                        stops: [GradientStop(hex: "#6E8BFF", position: 0),
                                                GradientStop(hex: "#8C7BFF", position: 1)],
                                        angle: 135))
        let name = pen.words("Name", "Your Name", font: "SF Pro", size: 42, weight: .semibold,
                             color: "#FFFFFF", origin: .zero, tracking: -0.012, lineHeight: 1.1)
        let role = pen.words("Role", "Role or title", font: "SF Pro", size: 28, color: "#B4BAC6",
                             origin: .zero, tracking: -0.004, lineHeight: 1.2)
        let words = pen.stack([name, TitleLook.shadedOverALook(role)], name: "Words",
                              direction: .column, gap: 0, origin: .zero,
                              placement: LayerPlacement(horizontal: .left))
        return pen.card([pill, mark, words], name: TitleKind.nameCard.name, gap: pen.u(18),
                        padding: GroupPadding(top: pen.u(14), right: pen.u(40), bottom: pen.u(14), left: pen.u(14)),
                        direction: .row, corner: pen.safeCorner)
    }
}
