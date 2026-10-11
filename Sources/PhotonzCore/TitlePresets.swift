import CoreGraphics
import Foundation

// Title pages and name cards (`docs/design/video-titles.md`, task
// `insert-title-pages-and-name-cards-on-the-timelin`).
//
// **A preset is a group of ordinary layers placed in time.** A background box,
// the words and a simple graphic, the same layers a person could have drawn by
// hand, wrapped in one group so the timeline shows one bar for it. It comes on
// and goes off with the keys Animate In and Animate Out already write
// (`ClipKeys.swift`), so what a preset made is draggable, easable and deletable
// like any key, and every piece of it is edited with the controls that already
// edit text and shapes. There is no title object.
//
// Not a linked component, on purpose: a component dropped on a recording
// brings its original along with its own track, which for a full-frame title
// page means a second title page on the timeline. Premiere's templates and
// Final Cut's titles both hand you a copy you own, and so does this.

// MARK: - The type list

/// A kind of thing you insert on the timeline. The menus walk this list, so a
/// new kind (an end card, a callout) is one more case and its presets.
public enum TitleKind: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    /// Words over a background that fills the frame.
    case titlePage
    /// A name and a role that come in at the bottom of the frame.
    case nameCard

    public var id: String { rawValue }

    /// What the menus call it.
    public var name: String {
        switch self {
        case .titlePage: "Title Page"
        case .nameCard: "Name Card"
        }
    }

    /// How long one is on screen when it lands: long enough to read twice.
    public var lengthMS: Int {
        switch self {
        case .titlePage: 4000
        case .nameCard: 5000
        }
    }

    /// The name of the line a person types first.
    var wordsName: String {
        switch self {
        case .titlePage: "Title"
        case .nameCard: "Name"
        }
    }

    /// The kind something placed is, read from how much of the frame it
    /// covers: a thing that fills the frame is a page, anything smaller is a
    /// card. Used when a person saves their own.
    static func reading(_ box: CGRect, in canvas: CGSize) -> TitleKind {
        let area = max(canvas.width * canvas.height, 1)
        let covered = box.intersection(CGRect(origin: .zero, size: canvas))
        guard !covered.isNull else { return .nameCard }
        return covered.width * covered.height >= area * 0.9 ? .titlePage : .nameCard
    }
}

/// What one insert left behind: the group, and the line to start typing in.
public struct InsertedTitle: Hashable, Sendable {
    public let layerID: UUID
    public let wordsID: UUID
}

// MARK: - The built-in presets

/// The presets the app ships with. Each is drawn against the frame it lands
/// on, so a 4K recording and a square one both get a page that fills them.
public enum BuiltInTitle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case midnight, sunrise, paper, spotlight
    /// A drifting mesh with grain, and a rule that draws itself on
    /// (`docs/design/video-titles-polish.md`, step 3).
    case aurora
    /// The recording under the title, blurred, dimmed and slowly settling,
    /// sharpening into the real footage as the title leaves: the Photonz
    /// signature, which ties the intro to the content.
    case glass
    case bar, clean, accent, minimal

    public var id: String { rawValue }

    public var kind: TitleKind {
        switch self {
        case .midnight, .sunrise, .paper, .spotlight, .aurora, .glass: .titlePage
        case .bar, .clean, .accent, .minimal: .nameCard
        }
    }

    public var name: String {
        switch self {
        case .midnight: "Midnight"
        case .sunrise: "Sunrise"
        case .paper: "Paper"
        case .spotlight: "Spotlight"
        case .aurora: "Aurora"
        case .glass: "Behind Glass"
        case .bar: "Bar"
        case .clean: "Clean"
        case .accent: "Accent"
        case .minimal: "Minimal"
        }
    }

    /// How it moves: its parts, each coming in on its own beat, gently moving
    /// while it holds, and leaving quicker than it came, in reverse
    /// (`TitleDesign.swift`, `docs/design/video-titles-polish.md`). Amounts are
    /// points of a 1080 line frame.
    ///
    /// A title page's background has no out of its own: the page leaves with
    /// the bar's own fade, which is also the dissolve into a recording an
    /// opening page pushes along (`pushPictureAfterOpeningTitle`). Its words
    /// are gone just before that dissolve ends.
    public var design: TitleDesign {
        typealias B = TitleBuild
        let backdrop = TitlePart(path: "Background", role: .background,
                                 in: B(.fade, delayMS: 0, lengthMS: 500, curve: .easeOutQuint),
                                 hold: TitleHold(.push, amount: 3))
        switch self {
        case .midnight:
            return TitleDesign(parts: [
                backdrop,
                TitlePart(path: "Title", role: .headline,
                          in: B(.rise, delayMS: 150, lengthMS: 700, amount: 28),
                          out: .off(.rise, delayMS: 130, amount: 12)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 280, lengthMS: 600, amount: 18),
                          out: .off(.rise, delayMS: 190, amount: 8)),
                TitlePart(path: "Accent", role: .accent,
                          in: B(.wipe, delayMS: 400, lengthMS: 500, direction: .right),
                          out: .off(.fade, delayMS: 250)),
            ])
        case .sunrise:
            return TitleDesign(parts: [
                backdrop,
                TitlePart(path: "Sun", role: .accent,
                          in: B(.scaleFrom, delayMS: 100, lengthMS: 900, amount: 70),
                          hold: TitleHold(.drift, amount: 16, direction: .up),
                          out: .off(.fade, delayMS: 130)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.blurIn, delayMS: 250, lengthMS: 700, amount: 14),
                          out: .off(.blurIn, delayMS: 190, amount: 8)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 380, lengthMS: 600, amount: 16),
                          out: .off(.fade, delayMS: 250)),
            ])
        case .paper:
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 400, curve: .easeOutQuint),
                          hold: TitleHold(.push, amount: 2)),
                TitlePart(path: "Accent", role: .accent,
                          in: B(.wipe, delayMS: 150, lengthMS: 500, direction: .down),
                          out: .off(.fade, delayMS: 130)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.rise, delayMS: 250, lengthMS: 700, amount: 32, direction: .right),
                          out: .off(.fade, delayMS: 190)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 380, lengthMS: 600, amount: 20, direction: .right),
                          out: .off(.fade, delayMS: 250)),
            ])
        case .spotlight:
            let dots = (0..<3).map { index in
                TitlePart(path: "Dot \(index + 1)", role: .accent,
                          in: B(.springPop, delayMS: 120 + index * 60, lengthMS: 450, amount: 50),
                          out: .off(.fade, delayMS: 100, lengthMS: 200))
            }
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 600, curve: .easeOutQuint),
                          hold: TitleHold(.push, amount: 4)),
            ] + dots + [
                TitlePart(path: "Title", role: .headline,
                          in: B(.scaleFrom, delayMS: 320, lengthMS: 800, amount: 112),
                          out: .off(.fade, delayMS: 190)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 450, lengthMS: 600, amount: 12),
                          out: .off(.fade, delayMS: 250)),
            ])
        case .aurora:
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.fade, delayMS: 0, lengthMS: 600, curve: .easeOutQuint),
                          hold: TitleHold(.push, amount: 2)),
                TitlePart(path: "Title", role: .headline,
                          in: B(.blurIn, delayMS: 150, lengthMS: 800, amount: 14),
                          out: .off(.blurIn, delayMS: 160, amount: 8)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 280, lengthMS: 650, amount: 14),
                          out: .off(.fade, delayMS: 220)),
                TitlePart(path: "Accent", role: .accent,
                          in: B(.drawOn, delayMS: 450, lengthMS: 600, direction: .right),
                          out: .off(.drawOn, delayMS: 100, lengthMS: 300)),
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
                          in: B(.blurIn, delayMS: 200, lengthMS: 800, amount: 16),
                          out: .off(.fade, delayMS: 200, lengthMS: 280)),
                TitlePart(path: "Subtitle", role: .subtitle,
                          in: B(.rise, delayMS: 330, lengthMS: 650, amount: 14),
                          out: .off(.fade, delayMS: 220, lengthMS: 250)),
            ])
        case .bar:
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.wipe, delayMS: 0, lengthMS: 450, direction: .right),
                          out: .off(.wipe, delayMS: 0, direction: .left)),
                TitlePart(path: "Accent", role: .accent,
                          in: B(.wipe, delayMS: 60, lengthMS: 400, direction: .up),
                          out: .off(.fade, delayMS: 50, lengthMS: 200)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.rise, delayMS: 150, lengthMS: 550, amount: 12),
                          out: .off(.fade, delayMS: 100)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.rise, delayMS: 280, lengthMS: 550, amount: 10),
                          out: .off(.fade, delayMS: 150)),
            ])
        case .clean:
            return TitleDesign(parts: [
                TitlePart(path: "Background", role: .background,
                          in: B(.springPop, delayMS: 0, lengthMS: 500, amount: 92),
                          out: .off(.springPop, delayMS: 0, amount: 96)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.blurIn, delayMS: 150, lengthMS: 550, amount: 8),
                          out: .off(.fade, delayMS: 100)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.blurIn, delayMS: 270, lengthMS: 550, amount: 8),
                          out: .off(.fade, delayMS: 150)),
            ])
        case .accent:
            return TitleDesign(parts: [
                TitlePart(path: "Name Box/Background", role: .background,
                          in: B(.wipe, delayMS: 0, lengthMS: 450, direction: .right),
                          out: .off(.wipe, delayMS: 0, direction: .left)),
                TitlePart(path: "Role Box/Background", role: .accent,
                          in: B(.wipe, delayMS: 120, lengthMS: 450, direction: .right),
                          out: .off(.wipe, delayMS: 100, direction: .left)),
                TitlePart(path: "Name", role: .headline,
                          in: B(.rise, delayMS: 150, lengthMS: 500, amount: 10),
                          out: .off(.fade, delayMS: 100)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.rise, delayMS: 270, lengthMS: 500, amount: 10),
                          out: .off(.fade, delayMS: 150)),
            ])
        case .minimal:
            return TitleDesign(parts: [
                TitlePart(path: "Name", role: .headline,
                          in: B(.rise, delayMS: 0, lengthMS: 600, amount: 10),
                          out: .off(.rise, delayMS: 0, lengthMS: 300, amount: 8)),
                TitlePart(path: "Rule", role: .accent,
                          in: B(.wipe, delayMS: 100, lengthMS: 500, direction: .right),
                          out: .off(.wipe, delayMS: 100, direction: .left)),
                TitlePart(path: "Role", role: .subtitle,
                          in: B(.rise, delayMS: 140, lengthMS: 550, amount: 8),
                          out: .off(.fade, delayMS: 150)),
            ])
        }
    }

    /// One kind's presets. `movingBackdrops` false leaves out the pages whose
    /// background moves, for a release that has not got them.
    public static func presets(of kind: TitleKind, movingBackdrops: Bool = true) -> [BuiltInTitle] {
        allCases.filter { $0.kind == kind && (movingBackdrops || !$0.hasMovingBackdrop) }
    }

    /// Whether this preset's background moves (`docs/design/video-titles-polish.md`, step 3).
    public var hasMovingBackdrop: Bool { self == .aurora || self == .glass }

    /// The group this preset draws on a frame this size.
    public func layer(in canvas: CGSize) -> Layer {
        let pen = TitlePen(canvas: canvas)
        let page: [Layer]
        switch self {
        case .midnight: page = Self.midnight(pen)
        case .sunrise: page = Self.sunrise(pen)
        case .paper: page = Self.paper(pen)
        case .spotlight: page = Self.spotlight(pen)
        case .aurora: page = Self.aurora(pen)
        case .glass: page = Self.glass(pen)
        // A card is laid out by the group itself, the way a starter button
        // is: a longer name makes a wider card rather than words running off
        // the edge of their panel.
        case .bar: return Self.bar(pen)
        case .clean: return Self.clean(pen)
        case .accent: return Self.accent(pen)
        case .minimal: return Self.minimal(pen)
        }
        return TitlePen.grouped(page, name: kind.name)
    }

    // MARK: Title pages

    private static func midnight(_ pen: TitlePen) -> [Layer] {
        let background = pen.fullFrame(Paint(hex: "#0B1426", kind: .linear,
                                             stops: [GradientStop(hex: "#0B1426", position: 0),
                                                     GradientStop(hex: "#1F3B73", position: 1)],
                                             angle: 160))
        let title = pen.centred("Title", "Your Title", font: "SF Pro", size: 112, weight: .bold,
                                color: "#FFFFFF", top: pen.canvas.height * 0.36)
        let bar = pen.box("Accent", CGRect(x: pen.canvas.width / 2 - pen.u(48),
                                           y: title.frame.maxY + pen.u(24),
                                           width: pen.u(96), height: pen.u(8)),
                          fill: Paint(hex: "#4C9BFF"), radius: pen.u(4))
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 40,
                                   color: "#B9C8E4", top: bar.frame.maxY + pen.u(28))
        return [background, bar, title, subtitle]
    }

    private static func sunrise(_ pen: TitlePen) -> [Layer] {
        let background = pen.fullFrame(Paint(hex: "#FF6B5A", kind: .linear,
                                             stops: [GradientStop(hex: "#FF6B5A", position: 0),
                                                     GradientStop(hex: "#FFB547", position: 1)],
                                             angle: 135))
        let size = pen.u(420)
        var sun = pen.oval("Sun", CGRect(x: (pen.canvas.width - size) / 2,
                                         y: (pen.canvas.height - size) / 2,
                                         width: size, height: size),
                           fill: Paint(hex: "#FFFFFF"))
        sun.style.opacity = 0.22
        let title = pen.centred("Title", "Your Title", font: "Georgia", size: 120, weight: .bold,
                                color: "#2A140C", top: pen.canvas.height * 0.37)
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "Avenir Next",
                                   size: 40, weight: .medium, color: "#4A2412",
                                   top: title.frame.maxY + pen.u(20))
        return [background, sun, title, subtitle]
    }

    private static func paper(_ pen: TitlePen) -> [Layer] {
        let background = pen.fullFrame(Paint(hex: "#F4F1EA"))
        let left = (pen.canvas.width * 0.12).rounded()
        let textLeft = left + pen.u(48)
        let title = pen.words("Title", "Your Title", font: "Helvetica Neue", size: 104,
                              weight: .bold, color: "#1A1A1A",
                              origin: CGPoint(x: textLeft, y: pen.canvas.height * 0.38))
        let subtitle = pen.words("Subtitle", "A short line about it", font: "Helvetica Neue",
                                 size: 40, color: "#5C5C5C",
                                 origin: CGPoint(x: textLeft, y: title.frame.maxY + pen.u(12)))
        let rule = pen.box("Accent", CGRect(x: left, y: title.frame.minY + pen.u(14),
                                            width: pen.u(14),
                                            height: subtitle.frame.maxY - title.frame.minY - pen.u(20)),
                           fill: Paint(hex: "#E4572E"))
        return [background, rule, title, subtitle]
    }

    private static func spotlight(_ pen: TitlePen) -> [Layer] {
        let background = pen.fullFrame(Paint(hex: "#2A2160", kind: .radial,
                                             stops: [GradientStop(hex: "#3B2F7A", position: 0),
                                                     GradientStop(hex: "#0C0A1C", position: 1)],
                                             center: CGPoint(x: 0.5, y: 0.45)))
        let title = pen.centred("Title", "Your Title", font: "SF Pro", size: 100, weight: .semibold,
                                color: "#FFFFFF", top: pen.canvas.height * 0.4)
        let dot = pen.u(14), gap = pen.u(16)
        let row = dot * 3 + gap * 2
        let dotsTop = title.frame.minY - pen.u(44)
        let dots = (0..<3).map { index in
            pen.oval("Dot \(index + 1)",
                     CGRect(x: (pen.canvas.width - row) / 2 + CGFloat(index) * (dot + gap),
                            y: dotsTop, width: dot, height: dot),
                     fill: Paint(hex: "#8F7CFF"))
        }
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 36,
                                   color: "#A9A2D6", top: title.frame.maxY + pen.u(18))
        return [background] + dots + [title, subtitle]
    }

    private static func aurora(_ pen: TitlePen) -> [Layer] {
        // Three deep colours, all dark enough that white words read on every
        // part of the blend, drifting one slow loop every twenty seconds.
        var background = pen.fullFrame(Paint(hex: "#0E1030", kind: .mesh,
                                             stops: [GradientStop(hex: "#0E1030", position: 0),
                                                     GradientStop(hex: "#3A1F8F", position: 0.5),
                                                     GradientStop(hex: "#8C2B6B", position: 1)],
                                             angle: 200, drift: Paint.startingDrift))
        background.style.effects = [.grain(GrainEffect())]
        let title = pen.centred("Title", "Your Title", font: "SF Pro", size: 112, weight: .bold,
                                color: "#FFFFFF", top: pen.canvas.height * 0.36)
        let rule = pen.line("Accent", from: CGPoint(x: pen.canvas.width / 2 - pen.u(80),
                                                    y: title.frame.maxY + pen.u(22)),
                            length: pen.u(160), width: pen.u(4), color: "#FFFFFF")
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 40,
                                   color: "#D4CCF2", top: rule.frame.maxY + pen.u(26))
        return [background, title, rule, subtitle]
    }

    private static func glass(_ pen: TitlePen) -> [Layer] {
        // Black at 40% over the recording, the recording itself softened
        // behind it and drawn 5% larger, which the hold eases back to 100%.
        var background = pen.fullFrame(Paint(hex: "#000000"))
        background.style.opacity = 0.4
        background.style.effects = [.blur(BlurEffect(radius: pen.u(36), kind: .background, zoom: 105))]
        let title = pen.centred("Title", "Your Title", font: "SF Pro", size: 112, weight: .bold,
                                color: "#FFFFFF", top: pen.canvas.height * 0.38)
        let subtitle = pen.centred("Subtitle", "A short line about it", font: "SF Pro", size: 40,
                                   weight: .medium, color: "#E8E8ED", top: title.frame.maxY + pen.u(18))
        return [background, title, subtitle]
    }

    /// Whether this page's background is the recording under it, so it lies
    /// OVER that recording rather than pushing it later, and leaves through
    /// its own parts rather than the bar's fade.
    public var usesTheRecording: Bool { self == .glass }

    // MARK: Name cards

    private static func bar(_ pen: TitlePen) -> Layer {
        let strip = pen.u(8), padX = pen.u(28), padY = pen.u(20)
        var panel = pen.box("Background", pen.surfaceStart, fill: Paint(hex: "#111418"), radius: pen.u(10))
        panel.placement = .fill
        panel.style.opacity = 0.88
        var accent = pen.box("Accent", CGRect(x: 0, y: 0, width: strip, height: strip),
                             fill: Paint(hex: "#4C9BFF"))
        accent.placement = LayerPlacement(horizontal: .left, vertical: .stretch)
        let name = pen.words("Name", "Your Name", font: "SF Pro", size: 48, weight: .semibold,
                             color: "#FFFFFF", origin: .zero)
        let role = pen.words("Role", "Role or title", font: "SF Pro", size: 30, color: "#C3CAD4",
                             origin: .zero)
        return pen.card([panel, accent, name, role], name: TitleKind.nameCard.name,
                        gap: pen.u(2),
                        padding: GroupPadding(top: padY, right: padX, bottom: padY, left: strip + padX))
    }

    private static func clean(_ pen: TitlePen) -> Layer {
        var card = pen.box("Background", pen.surfaceStart, fill: Paint(hex: "#FFFFFF"), radius: pen.u(16))
        card.placement = .fill
        card.style.shadows = [ShadowStyle(radius: pen.u(24), offset: CGSize(width: 0, height: pen.u(8)),
                                          colorHex: "#000000", opacity: 0.3)]
        let name = pen.words("Name", "Your Name", font: "SF Pro", size: 46, weight: .bold,
                             color: "#1C1C1E", origin: .zero)
        let role = pen.words("Role", "Role or title", font: "SF Pro", size: 28, color: "#6E6E73",
                             origin: .zero)
        return pen.card([card, name, role], name: TitleKind.nameCard.name, gap: 0,
                        padding: GroupPadding(top: pen.u(22), right: pen.u(32),
                                              bottom: pen.u(22), left: pen.u(32)))
    }

    private static func accent(_ pen: TitlePen) -> Layer {
        let padding = GroupPadding(top: pen.u(12), right: pen.u(24), bottom: pen.u(12), left: pen.u(24))
        func slab(_ name: String, _ words: Layer, fill: String) -> Layer {
            var surface = pen.box("Background", pen.surfaceStart, fill: Paint(hex: fill))
            surface.placement = .fill
            var content = GroupContent(children: [surface, words])
            content.layout = GroupLayout(kind: nil, padding: padding)
            return Layer(name: name, content: .group(content), frame: .zero)
        }
        let name = pen.words("Name", "Your Name", font: "Avenir Next", size: 46, weight: .bold,
                             color: "#FFFFFF", origin: .zero)
        let role = pen.words("Role", "Role or title", font: "Avenir Next", size: 28,
                             weight: .medium, color: "#FFFFFF", origin: .zero)
        return pen.card([slab("Name Box", name, fill: "#E4572E"), slab("Role Box", role, fill: "#1C1C1E")],
                        name: TitleKind.nameCard.name, gap: 0, padding: .none)
    }

    private static func minimal(_ pen: TitlePen) -> Layer {
        let name = pen.words("Name", "Your Name", font: "SF Pro", size: 52, weight: .bold,
                             color: "#FFFFFF", origin: .zero, legibleOverVideo: true)
        let role = pen.words("Role", "Role or title", font: "SF Pro", size: 30, weight: .medium,
                             color: "#F2F2F2", origin: .zero, legibleOverVideo: true)
        var line = pen.box("Rule", CGRect(x: 0, y: 0, width: pen.u(120), height: pen.u(4)),
                           fill: Paint(hex: "#FFFFFF"))
        line.style.shadows = TitleLook.shadows(forColorHex: "#FFFFFF", fontSize: pen.u(30))
        return pen.card([name, line, role], name: TitleKind.nameCard.name, gap: pen.u(10),
                        padding: .none)
    }
}

// MARK: - Drawing them

/// Everything a preset is drawn with: sizes stated against a 1080 line frame
/// and scaled to the one it lands on.
struct TitlePen {
    let canvas: CGSize

    /// One point of a 1920 by 1080 frame, on this one.
    var unit: CGFloat { max(min(canvas.width / 1920, canvas.height / 1080), 0.01) }

    func u(_ points: CGFloat) -> CGFloat { (points * unit).rounded() }

    func fullFrame(_ paint: Paint) -> Layer {
        box("Background", CGRect(origin: .zero, size: canvas), fill: paint)
    }

    func box(_ name: String, _ rect: CGRect, fill: Paint, radius: CGFloat = 0) -> Layer {
        shape(.rectangle, name, rect, fill: fill, radius: radius)
    }

    func oval(_ name: String, _ rect: CGRect, fill: Paint) -> Layer {
        shape(.ellipse, name, rect, fill: fill, radius: 0)
    }

    /// A level line `length` long from `start`, `width` thick: a rule that
    /// can draw itself on. Its frame holds half a width of room all round, as
    /// a line drawn by hand does (`AnnotationBuilder`).
    func line(_ name: String, from start: CGPoint, length: CGFloat, width: CGFloat,
              color: String) -> Layer {
        let half = width / 2
        let content = AnnotationContent(shape: .line, strokeWidth: width, colorHex: color,
                                        start: CGPoint(x: half, y: half),
                                        end: CGPoint(x: half + length, y: half))
        return Layer(name: name, content: .annotation(content),
                     frame: CGRect(x: (start.x - half).rounded(), y: (start.y - half).rounded(),
                                   width: length + width, height: width))
    }

    private func shape(_ shape: AnnotationShape, _ name: String, _ rect: CGRect,
                       fill: Paint, radius: CGFloat) -> Layer {
        var content = AnnotationContent(shape: shape, strokeWidth: 0, colorHex: fill.hex,
                                        start: .zero, end: CGPoint(x: rect.width, y: rect.height))
        content.fill = fill
        content.cornerRadius = radius
        return Layer(name: name, content: .annotation(content), frame: rect)
    }

    /// A line of words with its box hugging them, top-left at `origin`.
    func words(_ name: String, _ string: String, font: String, size: CGFloat,
               weight: TextWeight = .regular, color: String, origin: CGPoint,
               align: TextAlign? = nil, width: CGFloat? = nil,
               legibleOverVideo: Bool = false) -> Layer {
        var content = TextContent(string: string, fontName: font, fontSize: u(size),
                                  colorHex: color, weight: weight)
        content.alignment = align
        let natural = TextMeasurement.size(of: content)
        let frame = CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()),
                           size: CGSize(width: max(width ?? 0, natural.width.rounded(.up)),
                                        height: natural.height.rounded(.up)))
        var layer = Layer(name: name, content: .text(content), frame: frame)
        if legibleOverVideo {
            layer.style.shadows = TitleLook.shadows(forColorHex: color, fontSize: u(size))
        }
        return layer
    }

    /// Words centred across the frame, in a box four fifths of its width so
    /// they stay centred however long a person makes them.
    func centred(_ name: String, _ string: String, font: String, size: CGFloat,
                 weight: TextWeight = .regular, color: String, top: CGFloat) -> Layer {
        let width = (canvas.width * 0.8).rounded()
        return words(name, string, font: font, size: size, weight: weight, color: color,
                     origin: CGPoint(x: (canvas.width - width) / 2, y: top),
                     align: .center, width: width)
    }

    /// The box a card's surface is drawn at before its group stretches it to
    /// the words. Not zero: a shape stretched from nothing stays nothing.
    var surfaceStart: CGRect { CGRect(x: 0, y: 0, width: u(100), height: u(100)) }

    /// Where every card's bottom-left corner sits: the safe area a broadcast
    /// lower third keeps to.
    var cardCorner: CGPoint {
        CGPoint(x: (canvas.width * 0.06).rounded(), y: (canvas.height * 0.9).rounded())
    }

    /// A name card: the pieces in a column the group lays out itself, words
    /// on the left edge, its bottom-left corner on `cardCorner`.
    func card(_ pieces: [Layer], name: String, gap: CGFloat, padding: GroupPadding) -> Layer {
        var content = GroupContent(children: pieces,
                                   contentPlacement: LayerPlacement(horizontal: .left))
        content.layout = GroupLayout(kind: .stack, direction: .column, gap: gap, padding: padding)
        var card = GroupFlow.flowing(Layer(name: name, content: .group(content), frame: .zero))
        let box = card.localBounds
        card.frame.origin = CGPoint(x: cardCorner.x - (box.minX - card.frame.minX),
                                    y: cardCorner.y - (box.maxY - card.frame.minY))
        return card
    }

    /// The pieces, drawn in frame coordinates, as one group whose box is
    /// exactly what they cover.
    static func grouped(_ pieces: [Layer], name: String) -> Layer {
        var union = pieces.first?.localBounds ?? .zero
        for piece in pieces.dropFirst() { union = union.union(piece.localBounds) }
        let children = pieces.map { piece -> Layer in
            var child = piece
            child.frame = piece.frame.offsetBy(dx: -union.minX, dy: -union.minY)
            return child
        }
        return Layer(name: name, content: .group(GroupContent(children: children)),
                     frame: CGRect(origin: union.origin, size: .zero))
    }
}

// MARK: - A person's own

/// A preset somebody saved: the thing exactly as they left it, the frame it
/// was made on, and how long it runs.
public struct SavedTitlePreset: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: TitleKind
    /// The layer as it was, keys and all, with its stretch of time still on it
    /// so the keys can be moved to wherever it lands next.
    public var layer: Layer
    public var lengthMS: Int
    public var canvasSize: CGSize

    public init(id: UUID = UUID(), name: String, kind: TitleKind, layer: Layer,
                lengthMS: Int, canvasSize: CGSize) {
        self.id = id
        self.name = name
        self.kind = kind
        self.layer = layer
        self.lengthMS = lengthMS
        self.canvasSize = canvasSize
    }
}

extension PhotonzDocument {

    /// Put a built-in preset on the timeline at a moment of the document: a
    /// track of its own, the kind's length, animated in and out. Nil on a
    /// document with no time. `landing` puts it where a tile let go over the
    /// timeline said it would go instead (`titleLanding`).
    @discardableResult
    ///
    /// `motionBlur` puts a Motion Blur on the title as a whole, so every part
    /// that comes in fast is smeared by its own move (`MotionSmear.swift`).
    public mutating func insertTitle(_ preset: BuiltInTitle, atTimeMS ms: Int,
                                     landing: ClipLanding? = nil, motionBlur: Bool = false) -> InsertedTitle? {
        guard hasTime else { return nil }
        let layer = preset.layer(in: canvasSize)
        guard let inserted = landTitle(layer, kind: preset.kind, lengthMS: preset.kind.lengthMS,
                                       sourceInMS: 0, atTimeMS: ms, landing: landing) else { return nil }
        // Each part on its own beat, as keys on the pieces themselves.
        applyTitleDesign(preset.design, layerID: inserted.layerID)
        if motionBlur { addEffect(.motionBlur, layerIDs: [inserted.layerID]) }
        // The design and where its knobs stand stay on the title, so a theme,
        // a font pair or an energy restyles it later (`TitleRestyle.swift`).
        rememberTitleDesign(preset.design, layerID: inserted.layerID)
        // A page leaves with the one fade everything on the timeline has
        // (`PictureFade`): shaded on the bar, checked under Fade Out, dragged
        // from the bar's corner, and the dissolve into what follows it. A page
        // made of the recording under it leaves by sharpening into it instead,
        // and must lie over it rather than push it on.
        if preset.kind == .titlePage, !preset.usesTheRecording {
            fadePicture(inserted.layerID, .out, toMS: TitleAnimation.lengthMS)
            pushPictureAfterOpeningTitle(inserted.layerID)
        }
        return inserted
    }

    /// Put somebody's own preset on the timeline. Its keys come with it, and a
    /// frame of another size gets it scaled to fit, centred.
    @discardableResult
    public mutating func insertTitle(_ saved: SavedTitlePreset, atTimeMS ms: Int,
                                     landing: ClipLanding? = nil) -> InsertedTitle? {
        guard hasTime else { return nil }
        // A whole copy, fade and keys included, with fresh ids, on no track
        // yet: the track it was saved from belongs to another document, or to
        // this one's original, which this must not land on top of.
        var layer = saved.layer.duplicated()
        layer.name = saved.layer.name
        layer.trackID = nil
        let from = saved.canvasSize
        if from.width > 0, from.height > 0, from != canvasSize {
            let factor = min(canvasSize.width / from.width, canvasSize.height / from.height)
            let shift = CGPoint(x: ((canvasSize.width - from.width * factor) / 2).rounded(),
                                y: ((canvasSize.height - from.height * factor) / 2).rounded())
            layer = layer.drawnLarger(by: factor, about: .zero)
            layer.frame.origin.x += shift.x
            layer.frame.origin.y += shift.y
            layer.motions = layer.motions?.map { motion in
                guard motion.property == .position else { return motion }
                return motion.rebuilt(from: motion.keyframes.map { stop in
                    var moved = stop
                    if case let .point(point) = stop.value {
                        moved.value = .point(CGPoint(x: point.x * factor + shift.x,
                                                     y: point.y * factor + shift.y))
                    }
                    return moved
                })
            }
            // Laid out again at its new size, as every edit lays a card out
            // (`reflowLayouts`): words a few points wider than a plain
            // magnification of their box push what sits under them down by
            // those points instead of drawing over it, and the Library's tile
            // picture, which no edit ever touches, shows the card the canvas
            // will.
            layer = GroupFlow.flowing(layer)
        }
        guard let inserted = landTitle(layer, kind: saved.kind, lengthMS: saved.lengthMS,
                                       sourceInMS: saved.layer.time?.sourceInMS ?? 0,
                                       atTimeMS: ms, landing: landing) else { return nil }
        if saved.kind == .titlePage { pushPictureAfterOpeningTitle(inserted.layerID) }
        return inserted
    }

    /// A title page put at the very start of a recording plays BEFORE it, not
    /// over its first seconds: everything after moves later by the page's
    /// length less its fade out, so the two overlap only for the dissolve and
    /// no frame of the recording plays hidden. Premiere's title on V1 ahead of
    /// the clip, with a dissolve at the cut.
    ///
    /// Only at 0:00 and only over a picture that starts there: anywhere else a
    /// page is laid over what is under it, as a title over footage is. A clip
    /// on a locked track stays put, because locking a track says exactly that,
    /// and then the page lies over it.
    @discardableResult
    mutating func pushPictureAfterOpeningTitle(_ id: UUID) -> Bool {
        guard let page = layer(id: id), let time = page.time, time.inMS == 0 else { return false }
        let locked = layerIDsOnLockedTracks()
        let pictureAtStart = layers.contains { other in
            other.id != id && (other.movie != nil || other.merged != nil)
                && other.time?.inMS == 0 && !locked.contains(other.id)
        }
        let push = time.lengthMS - min(max(0, page.pictureFadeMS(.out)), time.lengthMS)
        guard pictureAtStart, push > 0 else { return false }
        let inside = Set(page.selfAndDescendants.map(\.id))
        for layer in allLayers {
            guard !inside.contains(layer.id), !locked.contains(layer.id),
                  let theirs = layer.time else { continue }
            updateLayer(id: layer.id) { $0.time = theirs.moved(toInMS: theirs.inMS + push) }
        }
        refreshDuration()
        return true
    }

    /// Where an opening page's dissolve into the recording begins: its end
    /// less its fade out, when it starts at 0:00, is not itself a picture,
    /// and a picture on a track that is not locked starts exactly there. Nil
    /// for a page laid over what is under it, as a title anywhere else is.
    func openingDissolveStartMS(_ id: UUID) -> Int? {
        guard let page = layer(id: id), let time = page.time, time.inMS == 0,
              page.movie == nil, page.merged == nil else { return nil }
        let start = time.outMS - min(max(0, page.pictureFadeMS(.out)), time.lengthMS)
        let locked = layerIDsOnLockedTracks()
        let inside = Set(page.selfAndDescendants.map(\.id))
        let follows = allLayers.contains { other in
            !inside.contains(other.id) && (other.movie != nil || other.merged != nil)
                && other.time?.inMS == start && !locked.contains(other.id)
        }
        return follows ? start : nil
    }

    /// An opening page's fade out changed from `oldStart`: the recording that
    /// started under the old dissolve, and everything from it on, moves to
    /// where the new one begins, so the page never fades over an empty frame
    /// and no frame of the recording plays hidden. Premiere and Final Cut
    /// grow a dissolve at the cut the same way. Nothing moves when it would
    /// land on something that stays, on a track they share.
    mutating func keepOpeningDissolve(_ id: UUID, from oldStart: Int) {
        guard let page = layer(id: id), let time = page.time else { return }
        let newStart = time.outMS - min(max(0, page.pictureFadeMS(.out)), time.lengthMS)
        let shift = newStart - oldStart
        guard shift != 0 else { return }
        let locked = layerIDsOnLockedTracks()
        let inside = Set(page.selfAndDescendants.map(\.id))
        let moving = Set(allLayers.filter { layer in
            !inside.contains(layer.id) && !locked.contains(layer.id)
                && (layer.time?.inMS ?? -1) >= oldStart
        }.map(\.id))
        let lands = layers.contains { mover in
            guard moving.contains(mover.id), let track = mover.trackID,
                  let theirs = mover.time else { return false }
            let from = theirs.inMS + shift, to = theirs.outMS + shift
            return layers.contains { stays in
                guard !moving.contains(stays.id), stays.trackID == track,
                      let still = stays.time else { return false }
                return still.inMS < to && from < still.outMS
            }
        }
        guard !lands else { return }
        for layer in allLayers {
            guard moving.contains(layer.id), let theirs = layer.time else { continue }
            updateLayer(id: layer.id) { $0.time = theirs.moved(toInMS: max(0, theirs.inMS + shift)) }
        }
        refreshDuration()
    }

    private mutating func landTitle(_ built: Layer, kind: TitleKind, lengthMS: Int,
                                    sourceInMS: Int, atTimeMS ms: Int,
                                    landing: ClipLanding?) -> InsertedTitle? {
        var layer = built
        let start = max(0, landing?.startMS ?? ms)
        layer.time = LayerTime(inMS: start, outMS: start + max(lengthMS, LayerTime.shortestMS),
                               sourceInMS: sourceInMS)
        let texts = layer.selfAndDescendants.filter { $0.text != nil }
        guard let words = texts.first(where: { $0.name == kind.wordsName }) ?? texts.first
        else { return nil }
        if let landing {
            // Where the ghost said: a free track, or a new one made for it.
            // Never over anything, so the landing's own edit has nothing to
            // clear (`titleLanding`).
            guard land(layer, at: landing) != nil else { return nil }
        } else {
            addLayer(layer)
        }
        refreshDuration()
        return InsertedTitle(layerID: layer.id, wordsID: words.id)
    }

    /// Whether a layer can be kept as a preset: something placed in time, at
    /// the top of the document, with words in it and no picture or sound that
    /// lives only in this document.
    public func canSaveTitlePreset(layerID: UUID) -> Bool {
        guard let layer = layer(id: layerID), layer.isPlacedInTime, parentID(of: layerID) == nil
        else { return false }
        let pieces = layer.selfAndDescendants
        guard pieces.contains(where: { $0.text != nil }) else { return false }
        return !pieces.contains { piece in
            switch piece.content {
            case .image, .sound: true
            default: piece.movie != nil
            }
        }
    }

    /// The layer as a preset with this name, its kind read from how much of
    /// the frame it covers. Nil when it cannot be kept or the name is blank.
    public func savedTitlePreset(layerID: UUID, name: String) -> SavedTitlePreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canSaveTitlePreset(layerID: layerID),
              let layer = layer(id: layerID), let time = layer.time else { return nil }
        return SavedTitlePreset(name: trimmed,
                                kind: TitleKind.reading(layer.localBounds, in: canvasSize),
                                layer: layer, lengthMS: time.lengthMS, canvasSize: canvasSize)
    }
}
