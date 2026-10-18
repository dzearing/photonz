import CoreGraphics
import Foundation

// A few knobs restyle a title (task `title-tiles-play-and-a-few-knobs-restyle-a-title`,
// `docs/design/video-titles-polish.md`, "What the person sees", step 4).
//
// A title lands as a design (`TitleDesign.swift`) compiled into ordinary keys.
// Before anybody touches its parts one by one, five knobs restyle the whole
// thing at once: a colour theme, a font pair, an energy, an intensity and its
// background. They work by role, so the same knobs restyle any preset.
//
// **The title keeps its recipe.** The group carries the design it was built
// from and where each knob stands (`GroupContent.titleRecipe`), so turning a
// knob never bakes anything: the old design's keys come off, the pieces are
// restyled, and the design is compiled again at the new energy and intensity.
// A title saved as the person's own keeps the recipe too, so its theme and
// energy stay changeable after it lands again.

// MARK: - Theme

/// Three to five colour roles a title is painted from.
public struct TitleTheme: Hashable, Codable, Sendable, Identifiable {
    /// `original` is the preset's own colours, `recording` the ones sampled
    /// from the clip, and anything else one of `TitleTheme.curated`.
    public var id: String
    public var name: String
    /// One to three colours: what a solid background is painted, and the
    /// stops of a gradient or a mesh in order.
    public var backgrounds: [String]
    /// The headline.
    public var primary: String
    /// The subtitle and the kicker.
    public var secondary: String
    /// Rules, bars, dots and the second box of a card.
    public var accent: String
    /// The one colour a background stands in with where only one can be
    /// drawn, when it is not the first of `backgrounds`: a preset's own
    /// gradient can say a different one.
    public var flat: String?

    public init(id: String, name: String, backgrounds: [String], primary: String,
                secondary: String, accent: String, flat: String? = nil) {
        self.id = id
        self.name = name
        self.backgrounds = backgrounds.isEmpty ? ["#000000"] : backgrounds
        self.primary = primary
        self.secondary = secondary
        self.accent = accent
        self.flat = flat
    }

    /// What a solid background is painted.
    public var ground: String { flat ?? backgrounds[0] }

    /// A moving look's colours out of this theme: its ground first, then the
    /// lights, which are its other background colours and its accent
    /// (`LivePalette` lifts them so they read as light).
    public var liveStops: [GradientStop] { liveStops(lendingAccent: true) }

    /// The same, saying whether the accent is lent as a light. A preset whose
    /// own background is a moving look keeps exactly its own colours under
    /// its own theme; everything else lends its accent where it has room.
    public func liveStops(lendingAccent: Bool) -> [GradientStop] {
        var colours = [ground] + backgrounds.dropFirst()
        if colours.count < 4, lendingAccent { colours.append(accent) }
        return colours.enumerated().map { index, hex in
            GradientStop(hex: hex, position: Double(index) / Double(max(colours.count - 1, 1)))
        }
    }

    public static let originalID = "original"
    public static let recordingID = "recording"

    /// The swatches offered beside the preset's own, each one legible as a
    /// set: light words on the dark ones, dark words on the light ones.
    public static let curated: [TitleTheme] = [
        TitleTheme(id: "night", name: "Night", backgrounds: ["#0B1426", "#1F3B73", "#3A2F7A"],
                   primary: "#FFFFFF", secondary: "#B9C8E4", accent: "#4C9BFF"),
        TitleTheme(id: "ink", name: "Ink", backgrounds: ["#000000", "#1C1C1E", "#2C2C2E"],
                   primary: "#F5F5F7", secondary: "#A1A1A6", accent: "#2997FF"),
        TitleTheme(id: "aurora", name: "Aurora", backgrounds: ["#0E1030", "#3A1F8F", "#8C2B6B"],
                   primary: "#FFFFFF", secondary: "#D4CCF2", accent: "#E58CFF"),
        TitleTheme(id: "forest", name: "Forest", backgrounds: ["#0F2A1F", "#1E4D3A", "#2F6B4F"],
                   primary: "#F2F7F2", secondary: "#B7D3C2", accent: "#7EE0A6"),
        TitleTheme(id: "sunset", name: "Sunset", backgrounds: ["#FF6B5A", "#FF8E4F", "#FFB547"],
                   primary: "#2A140C", secondary: "#4A2412", accent: "#FFFFFF"),
        TitleTheme(id: "paper", name: "Paper", backgrounds: ["#F4F1EA", "#E9E3D6", "#DDD3C0"],
                   primary: "#1A1A1A", secondary: "#5C5C5C", accent: "#E4572E"),
        TitleTheme(id: "daylight", name: "Daylight", backgrounds: ["#F5F5F7", "#E8E8ED", "#D2D2D7"],
                   primary: "#1D1D1F", secondary: "#6E6E73", accent: "#0071E3"),
    ]

    /// Two or three colours out of a recording: a dark backdrop from what it
    /// is mostly made of, a deeper second stop from its most colourful part,
    /// and that colour lifted for the accent. Words are white on it, so the
    /// theme is legible whatever the recording looked like. `pixels` is any
    /// sample of the frame; a grey frame gets a blue accent.
    public static func sampled(from pixels: [RGBA]) -> TitleTheme {
        // The frame's colours, roughly: eight levels a channel.
        var buckets: [Int: (sum: RGBA, count: Int)] = [:]
        for pixel in pixels {
            let key = Int(pixel.r * 7.99) * 64 + Int(pixel.g * 7.99) * 8 + Int(pixel.b * 7.99)
            var bucket = buckets[key] ?? (RGBA(r: 0, g: 0, b: 0), 0)
            bucket.sum = RGBA(r: bucket.sum.r + pixel.r, g: bucket.sum.g + pixel.g, b: bucket.sum.b + pixel.b)
            bucket.count += 1
            buckets[key] = bucket
        }
        let common = buckets.values.sorted { $0.count > $1.count }.prefix(12).map { bucket in
            RGBA(r: bucket.sum.r / Double(bucket.count), g: bucket.sum.g / Double(bucket.count),
                 b: bucket.sum.b / Double(bucket.count))
        }
        let base = common.first ?? RGBA(r: 0.1, g: 0.12, b: 0.2)
        let vivid = common.max { saturation($0) < saturation($1) } ?? base
        let hasColour = saturation(vivid) > 0.18
        let accent = hasColour ? lifted(vivid) : RGBA(hex: "#4C9BFF") ?? vivid
        let deep = darkened(hasColour ? vivid : base, to: 0.07)
        let ground = darkened(base, to: 0.025)
        let between = darkened(mix(ground, accent, 0.4), to: 0.045)
        let secondary = mix(accent, RGBA(r: 1, g: 1, b: 1), 0.72)
        return TitleTheme(id: recordingID, name: "From Recording",
                          backgrounds: [ground.hexString, between.hexString, deep.hexString],
                          primary: "#FFFFFF", secondary: secondary.hexString, accent: accent.hexString)
    }

    private static func saturation(_ color: RGBA) -> Double {
        max(color.r, color.g, color.b) - min(color.r, color.g, color.b)
    }

    private static func mix(_ a: RGBA, _ b: RGBA, _ amount: Double) -> RGBA {
        RGBA(r: a.r + (b.r - a.r) * amount, g: a.g + (b.g - a.g) * amount, b: a.b + (b.b - a.b) * amount)
    }

    /// The colour scaled toward black until it is no brighter than `luminance`.
    private static func darkened(_ color: RGBA, to luminance: Double) -> RGBA {
        var scaled = color
        var factor = 1.0
        while scaled.relativeLuminance > luminance, factor > 0.02 {
            factor *= 0.9
            scaled = RGBA(r: color.r * factor, g: color.g * factor, b: color.b * factor)
        }
        return scaled
    }

    /// The colour at full strength, bright enough to read on the dark ground.
    private static func lifted(_ color: RGBA) -> RGBA {
        let top = max(color.r, color.g, color.b, 0.001)
        var bright = RGBA(r: color.r / top, g: color.g / top, b: color.b / top)
        if bright.relativeLuminance < 0.25 { bright = mix(bright, RGBA(r: 1, g: 1, b: 1), 0.35) }
        return bright
    }
}

// MARK: - Font pair

/// A display face for the headline and a text face for everything under it.
public struct TitleFontPair: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var display: String
    public var displayWeight: TextWeight
    public var text: String
    public var textWeight: TextWeight

    public init(id: String, name: String, display: String, displayWeight: TextWeight,
                text: String, textWeight: TextWeight) {
        self.id = id
        self.name = name
        self.display = display
        self.displayWeight = displayWeight
        self.text = text
        self.textWeight = textWeight
    }

    public static let originalID = "original"

    /// Five pairs that suit moving type: no script or decorative faces.
    public static let curated: [TitleFontPair] = [
        TitleFontPair(id: "clean", name: "Clean", display: "SF Pro", displayWeight: .bold,
                      text: "SF Pro", textWeight: .regular),
        TitleFontPair(id: "editorial", name: "Editorial", display: "Georgia", displayWeight: .bold,
                      text: "Avenir Next", textWeight: .medium),
        TitleFontPair(id: "geometric", name: "Geometric", display: "Avenir Next", displayWeight: .bold,
                      text: "Avenir Next", textWeight: .regular),
        TitleFontPair(id: "swiss", name: "Swiss", display: "Helvetica Neue", displayWeight: .bold,
                      text: "Helvetica Neue", textWeight: .regular),
        TitleFontPair(id: "technical", name: "Technical", display: "SF Mono", displayWeight: .semibold,
                      text: "SF Mono", textWeight: .regular),
    ]
}

// MARK: - Energy

/// How fast and how hard the whole title moves.
public enum TitleEnergy: String, CaseIterable, Hashable, Codable, Sendable {
    case calm, normal, punchy

    public var title: String {
        switch self {
        case .calm: "Calm"
        case .normal: "Normal"
        case .punchy: "Punchy"
        }
    }

    /// What every in and out's length and start, and so every stagger, is
    /// multiplied by.
    public var pace: Double {
        switch self {
        case .calm: 1.3
        case .normal: 1
        case .punchy: 0.7
        }
    }

    /// What a scale's or a spring's overshoot is multiplied by.
    public var overshoot: Double {
        switch self {
        case .calm: 0.7
        case .normal: 1
        case .punchy: 1.3
        }
    }

    /// The motion blur's shutter: softer when calm, a heavy smear when punchy.
    public var shutterAngle: Double {
        switch self {
        case .calm: 120
        case .normal: MotionBlurEffect.startingAngle
        case .punchy: 270
        }
    }
}

// MARK: - Background

/// What a title's background is made of.
public enum TitleBackgroundKind: String, CaseIterable, Hashable, Codable, Sendable {
    case solid, gradient
    /// The faint drifting blend titles had before the moving looks. No longer
    /// offered; a title saved with it still opens and draws it.
    case mesh
    /// The recording under the title, blurred and dimmed.
    case glass
    // The moving looks (`LiveBackdrop.swift`), one each.
    case aurora, energyStreams, colorBubbles, lightRays, lightLeaks
    case windStreams, sketch, particles, liquidGradient, gridHorizon

    public init(look: LiveLook) {
        switch look {
        case .aurora: self = .aurora
        case .energyStreams: self = .energyStreams
        case .colorBubbles: self = .colorBubbles
        case .lightRays: self = .lightRays
        case .lightLeaks: self = .lightLeaks
        case .windStreams: self = .windStreams
        case .sketch: self = .sketch
        case .particles: self = .particles
        case .liquidGradient: self = .liquidGradient
        case .gridHorizon: self = .gridHorizon
        }
    }

    /// The moving look this background is, nil for a still one.
    public var look: LiveLook? {
        switch self {
        case .solid, .gradient, .mesh, .glass: nil
        case .aurora: .aurora
        case .energyStreams: .energyStreams
        case .colorBubbles: .colorBubbles
        case .lightRays: .lightRays
        case .lightLeaks: .lightLeaks
        case .windStreams: .windStreams
        case .sketch: .sketch
        case .particles: .particles
        case .liquidGradient: .liquidGradient
        case .gridHorizon: .gridHorizon
        }
    }

    public var title: String {
        switch self {
        case .solid: "Solid"
        case .gradient: "Gradient"
        case .mesh: "Mesh"
        case .glass: "Glass"
        default: look?.title ?? rawValue
        }
    }

    /// What the Background picker offers, in its order: the still ones, then
    /// every moving look, then Glass where the title has a picture under it.
    /// Mesh is not among them.
    public static func offered(glass: Bool) -> [TitleBackgroundKind] {
        [.solid, .gradient] + LiveLook.allCases.map(TitleBackgroundKind.init(look:)) + (glass ? [.glass] : [])
    }
}

// MARK: - The recipe a title keeps

/// What a piece was drawn with before any knob turned, for the knobs that
/// scale it: grain, a background blur and a glow. And where a preset gave a
/// piece a look of its own that its role would not (a second light in another
/// colour, a second line in a lighter weight, a gradient), that look, which
/// the Original theme and font pair put back.
public struct TitleLookBase: Hashable, Codable, Sendable {
    public var path: String
    public var grain: Double?
    public var blur: Double?
    public var glow: Double?
    /// A shape's own fill, where it is not the theme's colour for its role.
    public var paint: Paint?
    /// Words' own colour, where it is not the theme's colour for their role.
    public var ink: String?
    /// Words' own weight, where it is not the font pair's for their role.
    public var weight: TextWeight?

    public init(path: String, grain: Double? = nil, blur: Double? = nil, glow: Double? = nil,
                paint: Paint? = nil, ink: String? = nil, weight: TextWeight? = nil) {
        self.path = path
        self.grain = grain
        self.blur = blur
        self.glow = glow
        self.paint = paint
        self.ink = ink
        self.weight = weight
    }
}

/// A title's design and where its knobs stand, kept on its group.
public struct TitleRecipe: Hashable, Codable, Sendable {
    /// The design at Normal energy and full intensity.
    public var design: TitleDesign
    public var theme: TitleTheme
    public var fonts: TitleFontPair
    public var energy: TitleEnergy
    /// Blur, distance, grain and glow together, as a percent: 100 is the
    /// preset as drawn.
    public var intensity: Double
    /// Nil for a title with no background of its own (a bare name card).
    public var background: TitleBackgroundKind?
    public var showsBackground: Bool
    /// The preset's own theme, font pair and background, which Original puts
    /// back.
    public var originalTheme: TitleTheme
    public var originalFonts: TitleFontPair
    public var originalBackground: TitleBackgroundKind?
    /// How opaque the background was drawn when it was not glass.
    public var backgroundOpacity: Double
    public var looks: [TitleLookBase]
    /// True when the title plays its whoosh and ticks (`TitleSounds.swift`);
    /// nil, and so off, for every title until somebody turns them on.
    public var sounds: Bool? = nil
    /// The data a chart is drawn from (`AnimatedChart.swift`), nil for every
    /// other title. Every restyle lays a chart's pieces out again from it.
    public var chart: ChartSpec? = nil

    public static let intensityRange: ClosedRange<Double> = 0...200

    /// The design as it is compiled: in and out lengths and starts at this
    /// energy's pace, distances, blurs and overshoots at this intensity.
    public var compiled: TitleDesign {
        let share = intensity / 100
        func scaled(_ build: TitleBuild?) -> TitleBuild? {
            guard var build else { return nil }
            build.delayMS = Int((Double(build.delayMS) * energy.pace).rounded())
            build.lengthMS = max(1, Int((Double(build.lengthMS) * energy.pace).rounded()))
            if let unit = build.unit ?? (build.kind.defaultUnit == .whole ? nil : build.kind.defaultUnit) {
                let stagger = build.staggerMS ?? (build.kind == .typewriter ? 50 : unit.defaultStaggerMS)
                build.staggerMS = Int((Double(stagger) * energy.pace).rounded())
            }
            switch build.kind {
            case .rise, .blurIn, .trackIn, .swingIn, .flipUp, .flyInFromDepth, .tiltSettle:
                build.amount *= share
            case .scaleFrom, .springPop:
                build.amount = 100 + (build.amount - 100) * share * energy.overshoot
            case .fade, .wipe, .drawOn, .frost, .maskReveal, .typewriter, .countUp:
                break
            }
            build.blur = build.blur.map { $0 * share }
            build.scale = build.scale.map { 100 + ($0 - 100) * share }
            return build
        }
        return TitleDesign(parts: design.parts.map { part in
            var part = part
            part.in = scaled(part.in)
            part.out = scaled(part.out)
            part.hold.amount *= share
            return part
        })
    }
}

// MARK: - Reading and restyling a placed title

extension PhotonzDocument {

    /// The recipe a placed title keeps, nil for anything that is not one.
    public func titleRecipe(layerID: UUID) -> TitleRecipe? {
        layer(id: layerID)?.group?.titleRecipe
    }

    /// The topmost title a layer is or sits in, so a part picked inside one
    /// reaches the title's knobs.
    public func titleLayerID(containing id: UUID) -> UUID? {
        var here: UUID? = id
        var found: UUID?
        while let current = here {
            if layer(id: current)?.group?.titleRecipe != nil { found = current }
            here = parentID(of: current)
        }
        return found
    }

    /// Keep `design` on a title just built from it, with every knob where the
    /// preset was drawn.
    @discardableResult
    mutating func rememberTitleDesign(_ design: TitleDesign, layerID: UUID) -> Bool {
        guard let group = layer(id: layerID), group.group != nil else { return false }
        let recipe = TitleRecipe.reading(group, design: design)
        updateLayer(id: layerID) { edited in
            guard case .group(var content) = edited.content else { return }
            content.titleRecipe = recipe
            edited.content = .group(content)
        }
        return true
    }

    /// Turn one or more knobs: `change` edits the recipe, the old design's
    /// keys come off, the pieces take the new theme, font pair and background,
    /// lay themselves out again, and the design is compiled once more at the
    /// new energy and intensity. False when nothing changed.
    @discardableResult
    public mutating func restyleTitle(layerID: UUID, _ change: (inout TitleRecipe) -> Void) -> Bool {
        guard let old = titleRecipe(layerID: layerID) else { return false }
        var recipe = old
        change(&recipe)
        recipe.intensity = min(max(recipe.intensity, TitleRecipe.intensityRange.lowerBound),
                               TitleRecipe.intensityRange.upperBound)
        guard recipe != old else { return false }
        if recipe.background == .glass, old.background != .glass, !titleHasPictureUnder(layerID) {
            recipe.background = old.background
        }
        refitTitle(layerID: layerID, from: old, to: recipe)
        return true
    }

    /// The moving look a title's background wears and where its knobs stand,
    /// nil for a title whose background is still.
    public func titleLiveBackdrop(layerID: UUID) -> LiveBackdrop? {
        guard let recipe = titleRecipe(layerID: layerID), let group = layer(id: layerID),
              let part = recipe.design.parts.first(where: { $0.role == .background }),
              let piece = TitleDesign.find(part.path, in: group),
              let paint = TitleRestyler.paint(of: piece), paint.kind == .live else { return nil }
        return paint.live
    }

    /// Turn one knob of the moving look behind a title. Its keys and layout
    /// are untouched: the look is drawn fresh every frame from its knobs.
    /// False when the title has no moving look or the knob is already there.
    @discardableResult
    public mutating func setTitleLiveKnob(layerID: UUID, _ knob: LiveKnob.ID, to value: Double) -> Bool {
        guard let current = titleLiveBackdrop(layerID: layerID),
              let recipe = titleRecipe(layerID: layerID),
              let part = recipe.design.parts.first(where: { $0.role == .background }),
              let group = layer(id: layerID),
              let path = TitleRestyler.locate(part.path, in: group) else { return false }
        let turned = current.with(knob, at: value)
        guard turned != current else { return false }
        updateLayer(id: layerID) { title in
            TitleRestyler.edit(&title, at: path) { piece in
                guard case .annotation(var shape) = piece.content else { return }
                shape.fill?.live = turned
                piece.content = .annotation(shape)
            }
        }
        return true
    }

    /// Lay a title out again and compile its design once more, as it stands:
    /// after its words were typed, so the backing follows them and every part
    /// moves into its new place.
    @discardableResult
    public mutating func relayOutTitle(layerID: UUID) -> Bool {
        guard let recipe = titleRecipe(layerID: layerID) else { return false }
        var laid = recipe
        // A chart reads back the words typed on it first, so a label renamed
        // or a number retyped in place is its data from now on.
        if var chart = recipe.chart, let group = layer(id: layerID) {
            chart.read(from: group)
            laid.chart = chart.tidied
        }
        refitTitle(layerID: layerID, from: recipe, to: laid)
        return true
    }

    private mutating func refitTitle(layerID: UUID, from old: TitleRecipe, to recipe: TitleRecipe) {
        let kept = handReveals(layerID: layerID, from: old, to: recipe)
        clearTitleDesign(old.compiled, layerID: layerID)
        guard var group = layer(id: layerID) else { return }
        group = TitleRestyler(recipe: recipe, unit: titleUnit).restyled(group)
        group = chartRedrawn(group, recipe: recipe)
        if case .group(var content) = group.content {
            content.titleRecipe = recipe
            group.content = .group(content)
        }
        let edited = group
        updateLayer(id: layerID) { $0 = edited }
        applyTitleDesign(recipe.compiled, layerID: layerID)
        for (pieceID, reveal) in kept {
            updateLayer(id: pieceID) { piece in
                guard case .text(var text) = piece.content else { return }
                text.reveal = reveal
                piece.content = .text(text)
            }
        }
    }

    /// Reveals somebody set by hand on a title's words (the Reveal section):
    /// any that is not what the old design wrote, on a part whose In the
    /// change leaves alone. A theme or an energy never undoes them; changing
    /// that part's In says how it comes in now.
    private func handReveals(layerID: UUID, from old: TitleRecipe, to recipe: TitleRecipe) -> [(UUID, TextReveal)] {
        guard let group = layer(id: layerID), let time = group.time else { return [] }
        let compiled = old.compiled.parts
        var kept: [(UUID, TextReveal)] = []
        for (index, part) in old.design.parts.enumerated() where compiled.indices.contains(index) {
            guard let now = recipe.design.parts.first(where: { $0.path == part.path }), now.in == part.in,
                  let piece = TitleDesign.find(part.path, in: group), let reveal = piece.text?.reveal else { continue }
            let written = TitleCompiler(piece: piece, lengthMS: time.lengthMS, clock: time.sourceInMS,
                                        unit: titleUnit).wordReveal(for: compiled[index])
            if reveal != written { kept.append((piece.id, reveal)) }
        }
        return kept
    }

    /// One point of a 1080 line frame, on this document's.
    var titleUnit: CGFloat { max(min(canvasSize.width / 1920, canvasSize.height / 1080), 0.01) }

    /// Whether any picture is on screen under a title while it is: what glass
    /// needs, since glass with nothing under it is a dim nothing.
    public func titleHasPictureUnder(_ layerID: UUID) -> Bool {
        guard let title = layer(id: layerID), let time = title.time,
              let index = layers.firstIndex(where: { $0.id == layerID }) else { return false }
        return layers[..<index].contains { other in
            var isPicture = other.movie != nil || other.merged != nil
            if case .image = other.content { isPicture = true }
            guard isPicture, let theirs = other.time else { return false }
            return theirs.inMS < time.outMS && theirs.outMS > time.inMS
        }
    }
}

extension TitleRecipe {

    /// The recipe of a title just built from `design`, reading the preset's
    /// own colours, faces and background off its pieces.
    static func reading(_ group: Layer, design: TitleDesign) -> TitleRecipe {
        func piece(_ role: TitlePartRole) -> Layer? {
            design.parts.first { $0.role == role }.flatMap { TitleDesign.find($0.path, in: group) }
        }
        let backdrop = piece(.background)
        let headline = piece(.headline)?.text
        let subtitle = (piece(.subtitle) ?? piece(.kicker))?.text
        let paint = backdrop.flatMap(TitleRestyler.paint)
        let backgrounds = paint.map { $0.isGradient ? $0.orderedStops.map(\.hex) : [$0.hex] } ?? ["#000000"]
        let primary = headline?.colorHex ?? "#FFFFFF"
        let accent = piece(.accent).map(TitleRestyler.ink) ?? primary
        let theme = TitleTheme(id: TitleTheme.originalID, name: "Original", backgrounds: backgrounds,
                               primary: primary, secondary: subtitle?.colorHex ?? primary, accent: accent,
                               flat: paint.map(\.hex).flatMap { $0 == backgrounds.first ? nil : $0 })
        let fonts = TitleFontPair(id: TitleFontPair.originalID, name: "Original",
                                  display: headline?.fontName ?? "SF Pro",
                                  displayWeight: headline?.weight ?? .bold,
                                  text: subtitle?.fontName ?? headline?.fontName ?? "SF Pro",
                                  textWeight: subtitle?.weight ?? .regular)
        let kind = backdrop.map(TitleRestyler.backgroundKind)
        let looks = design.parts.compactMap { part -> TitleLookBase? in
            guard let piece = TitleDesign.find(part.path, in: group) else { return nil }
            let effects = piece.style.effects
            var base = TitleLookBase(path: part.path)
            base.grain = effects.compactMap(\.grain).first.map(\.amount)
            base.blur = effects.compactMap(\.blur).first { $0.kind == .background }.map { Double($0.radius) }
            base.glow = effects.compactMap(\.glow).first.map { Double($0.radius) }
            // A look of its own, which its role under the preset's own theme
            // and faces would not give it back.
            switch part.role {
            case .accent:
                if let paint = TitleRestyler.paint(of: piece), paint.isGradient || paint.hex != theme.accent {
                    base.paint = paint
                }
            case .headline, .subtitle, .kicker:
                if let text = piece.text {
                    let ink = part.role == .headline ? theme.primary : theme.secondary
                    let weight = part.role == .headline ? fonts.displayWeight : fonts.textWeight
                    if text.colorHex != ink { base.ink = text.colorHex }
                    if text.weight != weight { base.weight = text.weight }
                }
            case .background:
                break
            }
            guard base != TitleLookBase(path: part.path) else { return nil }
            return base
        }
        return TitleRecipe(design: design, theme: theme, fonts: fonts, energy: .normal, intensity: 100,
                           background: kind, showsBackground: backdrop?.isVisible ?? true,
                           originalTheme: theme, originalFonts: fonts, originalBackground: kind,
                           backgroundOpacity: kind == .glass ? 1 : (backdrop?.style.opacity ?? 1),
                           looks: looks)
    }
}

// MARK: - Restyling the pieces

/// Paints, sets and lays out a title's pieces from a recipe.
struct TitleRestyler {
    let recipe: TitleRecipe
    /// One point of a 1080 line frame, on this document's.
    let unit: CGFloat

    /// The fill a backdrop or a box is painted with.
    static func paint(of layer: Layer) -> Paint? {
        if case .annotation(let shape) = layer.content { return shape.fill ?? Paint(hex: shape.colorHex) }
        return nil
    }

    /// The one colour a piece is drawn in: a shape's fill or line, or words.
    static func ink(of layer: Layer) -> String {
        switch layer.content {
        case .annotation(let shape): shape.fill?.hex ?? shape.colorHex
        case .text(let text): text.colorHex
        default: "#FFFFFF"
        }
    }

    static func backgroundKind(of layer: Layer) -> TitleBackgroundKind {
        if layer.style.effects.contains(where: { $0.blur?.kind == .background }) { return .glass }
        guard let paint = paint(of: layer), paint.isGradient else { return .solid }
        if paint.kind == .live, let look = paint.live?.look { return TitleBackgroundKind(look: look) }
        return paint.kind == .mesh ? .mesh : .gradient
    }

    func restyled(_ group: Layer) -> Layer {
        var group = group
        let theme = recipe.theme
        for part in recipe.design.parts {
            guard let path = Self.locate(part.path, in: group) else { continue }
            Self.edit(&group, at: path) { piece in
                switch part.role {
                case .background:
                    paintBackground(&piece)
                    piece.isVisible = recipe.showsBackground
                case .accent:
                    paintAccent(&piece, theme.accent, own: own(part.path)?.paint)
                case .headline:
                    setWords(&piece, color: own(part.path)?.ink ?? theme.primary, font: recipe.fonts.display,
                             weight: ownWeight(part.path) ?? recipe.fonts.displayWeight)
                case .subtitle, .kicker:
                    setWords(&piece, color: own(part.path)?.ink ?? theme.secondary, font: recipe.fonts.text,
                             weight: ownWeight(part.path) ?? recipe.fonts.textWeight)
                }
                scaleLooks(&piece, path: part.path)
                if let blur = piece.style.effects.firstIndex(where: { $0.kind == .motionBlur }),
                   case .motionBlur(var effect) = piece.style.effects[blur] {
                    effect.shutterAngle = recipe.energy.shutterAngle
                    piece.style.effects[blur] = .motionBlur(effect)
                }
            }
        }
        // The title's own motion blur, which covers every part.
        if let blur = group.style.effects.firstIndex(where: { $0.kind == .motionBlur }),
           case .motionBlur(var effect) = group.style.effects[blur] {
            effect.shutterAngle = recipe.energy.shutterAngle
            group.style.effects[blur] = .motionBlur(effect)
        }
        group = laidOut(group)
        return legible(group)
    }

    /// The look a preset gave a piece of its own, while its theme is still
    /// the preset's own.
    private func own(_ path: String) -> TitleLookBase? {
        guard recipe.theme.id == TitleTheme.originalID else { return nil }
        return recipe.looks.first { $0.path == path }
    }

    /// The weight a preset gave a line of its own, while its faces are still
    /// the preset's own.
    private func ownWeight(_ path: String) -> TextWeight? {
        guard recipe.fonts.id == TitleFontPair.originalID else { return nil }
        return recipe.looks.first { $0.path == path }?.weight
    }

    // MARK: Paint

    private func paintBackground(_ piece: inout Layer) {
        guard case .annotation(var shape) = piece.content, let kind = recipe.background else { return }
        let colours = recipe.theme.backgrounds
        var paint = shape.fill ?? Paint(hex: shape.colorHex)
        paint.hex = recipe.theme.ground
        switch kind {
        case .solid, .glass:
            paint.kind = .solid
            paint.stops = []
        case .gradient:
            if paint.kind == .solid || paint.kind == .mesh || paint.kind == .live || paint.stops.count < 2 {
                paint.kind = .linear
                paint.angle = 160
                paint.stops = [GradientStop(hex: colours[0], position: 0), GradientStop(hex: colours[0], position: 1)]
            }
            paint.stops = Self.recoloured(paint.orderedStops, colours)
        case .mesh:
            if paint.kind != .mesh {
                paint.kind = .mesh
                paint.angle = 200
                paint.drift = Paint.startingDrift
                let count = max(3, colours.count)
                paint.stops = (0..<count).map {
                    GradientStop(hex: colours[0], position: Double($0) / Double(count - 1))
                }
            }
            paint.stops = Self.recoloured(paint.orderedStops, colours)
        case .aurora, .energyStreams, .colorBubbles, .lightRays, .lightLeaks,
             .windStreams, .sketch, .particles, .liquidGradient, .gridHorizon:
            guard let look = kind.look else { break }
            // The same look keeps where its knobs stand through a new theme;
            // another look starts at its own.
            if paint.kind != .live || paint.live?.look != look {
                paint.live = LiveBackdrop(look: look)
            }
            paint.kind = .live
            paint.stops = recipe.theme.liveStops(
                lendingAccent: recipe.theme.id != TitleTheme.originalID || recipe.originalBackground?.look == nil)
        }
        shape.fill = paint
        shape.colorHex = paint.hex
        piece.content = .annotation(shape)
        let glassAt = piece.style.effects.firstIndex { $0.blur?.kind == .background }
        if kind == .glass {
            // Dark glass or light, the same strength: enough that its words
            // read over whatever the recording shows.
            piece.style.opacity = TitleLook.glassDim
            if glassAt == nil {
                let radius = recipe.looks.first { $0.blur != nil }?.blur ?? Double(36 * unit)
                piece.style.effects.append(.blur(BlurEffect(radius: CGFloat(radius), kind: .background,
                                                            zoom: 105)))
            }
        } else {
            if let glassAt { piece.style.effects.remove(at: glassAt) }
            piece.style.opacity = recipe.backgroundOpacity
        }
    }

    /// The stops in order, each given the theme colour at its place in the
    /// list: the first stop the first colour, the last the last.
    private static func recoloured(_ stops: [GradientStop], _ colours: [String]) -> [GradientStop] {
        guard stops.count > 1 else { return stops.map { var s = $0; s.hex = colours[0]; return s } }
        return stops.enumerated().map { index, stop in
            var stop = stop
            let at = Double(index) * Double(colours.count - 1) / Double(stops.count - 1)
            stop.hex = colours[min(colours.count - 1, Int(at.rounded()))]
            return stop
        }
    }

    /// An accent in the theme's accent colour, or in the look the preset gave
    /// it while the theme is its own. A gradient stays a gradient, running
    /// from the accent to the headline's colour and back.
    private func paintAccent(_ piece: inout Layer, _ hex: String, own: Paint?) {
        switch piece.content {
        case .annotation(var shape):
            if let own {
                shape.fill = own
                shape.colorHex = own.hex
            } else if var paint = shape.fill, paint.isGradient, paint.stops.contains(where: { $0.hex.count == 9 }) {
                // A glow fading to nothing takes the accent and keeps how see
                // through each of its stops is.
                paint.hex = hex
                paint.stops = paint.stops.map { GradientStop(hex: String(hex.prefix(7)) + ($0.hex.count == 9
                                                                                     ? String($0.hex.suffix(2)) : ""),
                                                             position: $0.position) }
                shape.fill = paint
                shape.colorHex = hex
            } else if var paint = shape.fill, paint.isGradient {
                let ends = paint.stops.count > 2 ? [hex, recipe.theme.primary, hex] : [hex, recipe.theme.primary]
                paint.hex = hex
                paint.stops = Self.recoloured(paint.orderedStops, ends)
                shape.fill = paint
                shape.colorHex = hex
            } else {
                if shape.fill != nil { shape.fill = Paint(hex: hex) }
                shape.colorHex = hex
            }
            piece.content = .annotation(shape)
            if !piece.style.shadows.isEmpty {
                piece.style.shadows = TitleLook.shadows(forColorHex: hex,
                                                        fontSize: max(piece.frame.height * 7.5, 24 * unit))
            }
        case .text(var text):
            text.colorHex = hex
            piece.content = .text(text)
        default:
            break
        }
    }

    private func setWords(_ piece: inout Layer, color: String, font: String, weight: TextWeight) {
        guard case .text(var text) = piece.content else { return }
        text.colorHex = color
        text.fontName = font
        text.weight = weight
        piece.content = .text(text)
        // Words that throw their own shadow to stand over the footage throw
        // one that opposes their new colour. A shade a moving look gave them
        // is the legibility pass's to decide (`legibleChildren`).
        if !piece.style.shadows.isEmpty, !piece.style.shadows.allSatisfy(TitleLook.isLiveScrim) {
            piece.style.shadows = TitleLook.shadows(forColorHex: color, fontSize: text.fontSize)
        }
    }

    private func scaleLooks(_ piece: inout Layer, path: String) {
        guard let base = recipe.looks.first(where: { $0.path == path }) else { return }
        let share = recipe.intensity / 100
        piece.style.effects = piece.style.effects.map { effect in
            switch effect {
            case .grain(var grain) where base.grain != nil:
                grain.amount = min(max((base.grain ?? 0) * share, GrainEffect.amountRange.lowerBound),
                                   GrainEffect.amountRange.upperBound)
                return .grain(grain)
            case .blur(var blur) where blur.kind == .background && base.blur != nil:
                blur.radius = CGFloat((base.blur ?? 0) * share)
                return .blur(blur)
            case .glow(var glow) where base.glow != nil:
                glow.radius = CGFloat((base.glow ?? 0) * share)
                return .glow(glow)
            default:
                return effect
            }
        }
    }

    // MARK: Layout

    /// Every line of words measured again in its new face, the pieces under a
    /// line that grew moved down by as much, and a card that arranges itself
    /// arranged again, keeping its bottom left corner where it was.
    private func laidOut(_ group: Layer) -> Layer {
        var group = group
        let before = group.localBounds
        group.children = Self.measured(group.children)
        // A page arranges nothing itself, but a row inside it may (a cursor
        // kept after its words), and it follows the words it holds.
        guard group.group?.layout != nil else { return GroupFlow.flowing(group) }
        group = GroupFlow.flowing(group)
        let after = group.localBounds
        group.frame.origin.x += before.minX - after.minX
        group.frame.origin.y += before.maxY - after.maxY
        return group
    }

    private static func measured(_ pieces: [Layer]) -> [Layer] {
        var pieces = pieces.map { piece -> Layer in
            guard piece.isGroup else { return piece }
            var group = piece
            group.children = measured(piece.children)
            return group
        }
        let order = pieces.indices.filter { pieces[$0].text != nil }.sorted {
            pieces[$0].frame.minY < pieces[$1].frame.minY
        }
        for index in order {
            guard let text = pieces[index].text else { continue }
            let natural = TextMeasurement.size(of: text)
            let old = pieces[index].frame
            var frame = old
            frame.size.height = natural.height.rounded(.up)
            if text.alignment != .center { frame.size.width = natural.width.rounded(.up) }
            pieces[index].frame = frame
            let grew = frame.height - old.height
            guard grew != 0 else { continue }
            for other in pieces.indices where other != index && pieces[other].frame.minY >= old.maxY - 0.5 {
                pieces[other].frame.origin.y += grew
            }
        }
        return pieces
    }

    // MARK: Legibility

    /// Words never land on a backing they cannot be read on: where a line
    /// sits on a box the theme painted and its colour does not stand out from
    /// it, it takes whichever of the theme's words, white or near black does.
    private func legible(_ group: Layer) -> Layer {
        var group = group
        group.children = legibleChildren(group.children, under: [])
        return group
    }

    /// `under` is what the group holding `pieces` is drawn over, framed in
    /// that group's own space: words in a column inside a card sit on the
    /// card's backing as surely as words beside it do.
    private func legibleChildren(_ pieces: [Layer], under: [(layer: Layer, frame: CGRect)]) -> [Layer] {
        let here = under + pieces.map { ($0, $0.frame) }
        return pieces.map { piece in
            if piece.isGroup {
                var group = piece
                let shift = piece.frame.origin
                group.children = legibleChildren(piece.children, under: here.filter { $0.layer.id != piece.id }.map {
                    ($0.layer, $0.frame.offsetBy(dx: -shift.x, dy: -shift.y))
                })
                return group
            }
            guard case .text(var text) = piece.content, let ink = RGBA(hex: text.colorHex) else { return piece }
            // A shade a moving look gave these words comes off first, and
            // goes back on below only if they still need it.
            var piece = piece
            piece.style.shadows.removeAll(where: TitleLook.isLiveScrim)
            let middle = CGPoint(x: piece.frame.midX, y: piece.frame.midY)
            // A box cut to the words' shape is their fill, not their backing.
            guard let backing = here.last(where: { other in
                other.layer.id != piece.id && other.layer.isVisible && other.layer.style.opacity >= 0.5
                    && other.layer.style.matte == nil
                    && !other.layer.style.effects.contains { $0.blur?.kind == .background }
                    && Self.paint(of: other.layer) != nil && other.frame.contains(middle)
            })?.layer, let paint = Self.paint(of: backing) else { return piece }
            // A moving look is read against what it can actually draw: its
            // ground and the brightest (or darkest) it is held to, never its
            // lights, which never reach the frame at full strength.
            let behind: [RGBA]
            if paint.kind == .live, paint.isGradient {
                let palette = LivePalette(paint)
                behind = [palette.ground, palette.extreme]
            } else {
                behind = (paint.isGradient ? paint.orderedStops.map(\.hex) : [paint.hex]).compactMap(RGBA.init(hex:))
            }
            func worst(_ color: RGBA) -> Double {
                behind.map { SegmentInk.contrast(color, $0) }.min() ?? 21
            }
            // Over a moving look, words that read on its ground keep their
            // colour and wear a soft shade wherever the look may get too
            // bright (or too dark) for them.
            if paint.kind == .live, paint.isGradient, let ground = behind.first,
               SegmentInk.contrast(ink, ground) >= 4.5 {
                let needed = text.fontSize >= 60 * unit ? 3.0 : 4.5
                if worst(ink) < needed, piece.style.shadows.isEmpty {
                    piece.style.shadows = [TitleLook.liveScrim(forColorHex: text.colorHex, fontSize: text.fontSize)]
                }
                return piece
            }
            guard worst(ink) < 3 else { return piece }
            let choices = [recipe.theme.primary, recipe.theme.secondary, "#FFFFFF", "#111111"]
            let best = choices.compactMap { hex in RGBA(hex: hex).map { (hex, worst($0)) } }
                .first { $0.1 >= 4.5 }?.0
                ?? choices.max { (RGBA(hex: $0).map(worst) ?? 0) < (RGBA(hex: $1).map(worst) ?? 0) }
                ?? text.colorHex
            text.colorHex = best
            var legible = piece
            legible.content = .text(text)
            return legible
        }
    }

    // MARK: Finding a piece by its path

    /// The index path to the piece `path` names, found the way
    /// `TitleDesign.find` finds it.
    static func locate(_ path: String, in layer: Layer) -> [Int]? {
        var here = layer
        var indices: [Int] = []
        for name in path.split(separator: "/").map(String.init) {
            guard let found = first(named: name, below: here) else { return nil }
            indices += found
            for index in found { here = here.children[index] }
        }
        return indices.isEmpty ? nil : indices
    }

    private static func first(named name: String, below layer: Layer) -> [Int]? {
        for (index, child) in layer.children.enumerated() where child.name == name { return [index] }
        for (index, child) in layer.children.enumerated() {
            if let found = first(named: name, below: child) { return [index] + found }
        }
        return nil
    }

    static func edit(_ layer: inout Layer, at path: [Int], _ change: (inout Layer) -> Void) {
        guard let first = path.first else {
            change(&layer)
            return
        }
        var children = layer.children
        guard children.indices.contains(first) else { return }
        edit(&children[first], at: Array(path.dropFirst()), change)
        layer.children = children
    }
}
