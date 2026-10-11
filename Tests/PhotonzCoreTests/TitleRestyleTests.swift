import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A few knobs restyle a title (task `title-tiles-play-and-a-few-knobs-restyle-a-title`,
/// `docs/design/video-titles-polish.md`, step 5).
///
/// Written before the knobs. A placed title keeps the design it was built from
/// and where its knobs stand, so a theme, a font pair, an energy, an intensity
/// and its background restyle the whole title at once, by role, and every one
/// of them can be turned back.
@Suite("A few knobs restyle a title")
struct TitleRestyleTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func tenSeconds() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        return doc
    }

    static func placed(_ preset: BuiltInTitle, motionBlur: Bool = false) throws -> (PhotonzDocument, UUID) {
        var doc = tenSeconds()
        let landed = doc.insertTitle(preset, atTimeMS: 2_000, motionBlur: motionBlur)
        let inserted = try #require(landed)
        return (doc, inserted.layerID)
    }

    static func piece(_ doc: PhotonzDocument, _ id: UUID, _ path: String) -> Layer? {
        doc.layer(id: id).flatMap { TitleDesign.find(path, in: $0) }
    }

    @discardableResult
    static func restyle(_ doc: inout PhotonzDocument, _ id: UUID,
                        _ change: (inout TitleRecipe) -> Void) -> Bool {
        doc.restyleTitle(layerID: id, change)
    }

    static func relayOut(_ doc: inout PhotonzDocument, _ id: UUID) -> Bool {
        doc.relayOutTitle(layerID: id)
    }

    /// Whether two titles are the same, but for the ids of their keys, which
    /// are new each time a design is compiled.
    static func same(_ a: Layer?, _ b: Layer?) throws -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func lines(_ layer: Layer) throws -> [Substring] {
            String(decoding: try encoder.encode(layer), as: UTF8.self).split(separator: "\n")
                .filter { !$0.contains("\"id\"") }
        }
        return try lines(a) == lines(b)
            && a.selfAndDescendants.map(\.id) == b.selfAndDescendants.map(\.id)
    }

    static func night() throws -> TitleTheme {
        try #require(TitleTheme.curated.first { $0.id == "night" })
    }

    // MARK: - The recipe a title keeps

    @Test("A title lands keeping its design, with every knob where the preset drew it")
    func aTitleKeepsItsRecipe() throws {
        let (doc, id) = try Self.placed(.midnight)
        let recipe = try #require(doc.titleRecipe(layerID: id))
        #expect(recipe.design == BuiltInTitle.midnight.design)
        #expect(recipe.theme.id == TitleTheme.originalID)
        #expect(recipe.theme.backgrounds == ["#0B1426", "#1F3B73"])
        #expect(recipe.theme.primary == "#FFFFFF")
        #expect(recipe.theme.secondary == "#B9C8E4")
        #expect(recipe.theme.accent == "#4C9BFF")
        #expect(recipe.fonts.display == "SF Pro")
        #expect(recipe.fonts.displayWeight == .bold)
        #expect(recipe.energy == .normal)
        #expect(recipe.intensity == 100)
        #expect(recipe.background == .gradient)
        #expect(recipe.showsBackground)
        // A part picked inside it reaches the title.
        let words = try #require(Self.piece(doc, id, "Title"))
        #expect(doc.titleLayerID(containing: words.id) == id)
        // A bare name card has no background of its own.
        let (minimal, card) = try Self.placed(.minimal)
        #expect(minimal.titleRecipe(layerID: card)?.background == nil)
        #expect(Self.tenSeconds().titleRecipe(layerID: UUID()) == nil)
    }

    @Test("Laying out a title again, or turning a knob back, leaves exactly the title that landed",
          arguments: BuiltInTitle.allCases)
    func knobsTurnBack(_ preset: BuiltInTitle) throws {
        let (landed, id) = try Self.placed(preset, motionBlur: true)
        var doc = landed
        #expect(Self.relayOut(&doc, id))
        #expect(try Self.same(doc.layer(id: id), landed.layer(id: id)))
        let night = try Self.night()
        let technical = try #require(TitleFontPair.curated.first { $0.id == "technical" })
        #expect(Self.restyle(&doc, id) {
            $0.theme = night
            $0.fonts = technical
            $0.energy = .punchy
            $0.intensity = 160
        })
        #expect(try !Self.same(doc.layer(id: id), landed.layer(id: id)))
        #expect(Self.restyle(&doc, id) {
            $0.theme = $0.originalTheme
            $0.fonts = $0.originalFonts
            $0.energy = .normal
            $0.intensity = 100
        })
        #expect(try Self.same(doc.layer(id: id), landed.layer(id: id)))
        // Nothing changed is nothing done.
        #expect(!Self.restyle(&doc, id) { _ in })
    }

    // MARK: - Theme

    @Test("A theme paints the background, the words and the accent by role")
    func themePaintsByRole() throws {
        var (doc, id) = try Self.placed(.paper)
        let night = try Self.night()
        #expect(Self.restyle(&doc, id) { $0.theme = night })
        let background = try #require(Self.piece(doc, id, "Background"))
        #expect(TitleRestyler.paint(of: background)?.hex == "#0B1426")
        #expect(Self.piece(doc, id, "Title")?.text?.colorHex == "#FFFFFF")
        #expect(Self.piece(doc, id, "Subtitle")?.text?.colorHex == "#B9C8E4")
        #expect(Self.piece(doc, id, "Accent").map(TitleRestyler.ink) == "#4C9BFF")
        // A gradient keeps its shape and takes the theme's colours, first to last.
        var (midnight, page) = try Self.placed(.midnight)
        let ink = try #require(TitleTheme.curated.first { $0.id == "ink" })
        #expect(Self.restyle(&midnight, page) { $0.theme = ink })
        let ramp = try #require(Self.piece(midnight, page, "Background").flatMap(TitleRestyler.paint))
        #expect(ramp.kind == .linear)
        #expect(ramp.angle == 160)
        #expect(ramp.orderedStops.map(\.hex) == ["#000000", "#2C2C2E"])
    }

    @Test("Every theme leaves every line of words legible on the box behind it",
          arguments: BuiltInTitle.allCases)
    func everyThemeIsLegible(_ preset: BuiltInTitle) throws {
        for theme in TitleTheme.curated {
            var (doc, id) = try Self.placed(preset)
            Self.restyle(&doc, id) { $0.theme = theme }
            let group = try #require(doc.layer(id: id))
            func check(_ pieces: [Layer]) {
                for piece in pieces {
                    if piece.isGroup { check(piece.children) }
                    guard let text = piece.text, let ink = RGBA(hex: text.colorHex) else { continue }
                    let middle = CGPoint(x: piece.frame.midX, y: piece.frame.midY)
                    // A box cut to the words' shape fills them; it is not behind them.
                    guard let backing = pieces.last(where: {
                        $0.id != piece.id && $0.isVisible && $0.style.opacity >= 0.5 && $0.style.matte == nil
                            && TitleRestyler.paint(of: $0) != nil && $0.frame.contains(middle)
                    }), let paint = TitleRestyler.paint(of: backing) else { continue }
                    let behind = paint.isGradient ? paint.orderedStops.map(\.hex) : [paint.hex]
                    for hex in behind {
                        let contrast = SegmentInk.contrast(ink, RGBA(hex: hex) ?? ink)
                        #expect(contrast >= 3, "\(preset.name) in \(theme.name): \(piece.name) \(text.colorHex) on \(hex)")
                    }
                }
            }
            check(group.children)
        }
    }

    @Test("From Recording samples a dark ground and the clip's own colour, with white words")
    func fromRecording() throws {
        let red = Array(repeating: RGBA(r: 0.85, g: 0.15, b: 0.1), count: 40)
        let dark = Array(repeating: RGBA(r: 0.12, g: 0.1, b: 0.1), count: 200)
        let theme = TitleTheme.sampled(from: red + dark)
        #expect(theme.id == TitleTheme.recordingID)
        #expect(theme.primary == "#FFFFFF")
        #expect(theme.backgrounds.count == 3)
        let ground = try #require(RGBA(hex: theme.backgrounds[0]))
        #expect(ground.relativeLuminance <= 0.03)
        let accent = try #require(RGBA(hex: theme.accent))
        #expect(accent.r > accent.g && accent.r > accent.b)
        for hex in theme.backgrounds {
            #expect(SegmentInk.contrast(RGBA(r: 1, g: 1, b: 1), try #require(RGBA(hex: hex))) >= 4.5)
        }
        // A grey recording has no colour of its own to give.
        let grey = TitleTheme.sampled(from: Array(repeating: RGBA(r: 0.5, g: 0.5, b: 0.5), count: 50))
        #expect(grey.accent == "#4C9BFF")
        #expect(TitleTheme.sampled(from: []).backgrounds.count == 3)
    }

    // MARK: - Font pair

    @Test("A font pair sets the headline in its display face and the rest in its text face, laid out again")
    func fontPair() throws {
        var (doc, id) = try Self.placed(.midnight)
        let editorial = try #require(TitleFontPair.curated.first { $0.id == "editorial" })
        #expect(Self.restyle(&doc, id) { $0.fonts = editorial })
        let title = try #require(Self.piece(doc, id, "Title"))
        let subtitle = try #require(Self.piece(doc, id, "Subtitle"))
        #expect(title.text?.fontName == "Georgia")
        #expect(title.text?.weight == .bold)
        #expect(subtitle.text?.fontName == "Avenir Next")
        #expect(subtitle.text?.weight == .medium)
        let natural = TextMeasurement.size(of: try #require(title.text))
        #expect(title.frame.height == natural.height.rounded(.up))
        #expect(subtitle.frame.minY > title.frame.maxY)
        #expect(TitleFontPair.curated.count == 5)
    }

    @Test("A name card arranges itself round a new face and keeps its bottom left corner")
    func cardKeepsItsCorner() throws {
        var (doc, id) = try Self.placed(.bar)
        let before = try #require(doc.layer(id: id)?.localBounds)
        let technical = try #require(TitleFontPair.curated.first { $0.id == "technical" })
        #expect(Self.restyle(&doc, id) { $0.fonts = technical })
        let after = try #require(doc.layer(id: id)?.localBounds)
        #expect(abs(after.minX - before.minX) < 1)
        #expect(abs(after.maxY - before.maxY) < 1)
        // (The core measures words by estimate, so the new face's own width is
        // the app's to check; the corner is the layout's.)
        let name = try #require(Self.piece(doc, id, "Name"))
        #expect(name.text?.fontName == "SF Mono")
        let panel = try #require(Self.piece(doc, id, "Background"))
        #expect(panel.frame.width > name.frame.width)
    }

    // MARK: - Energy

    @Test("Energy scales every in and out: Calm takes longer, Punchy less")
    func energyScalesTiming() throws {
        let (landed, id) = try Self.placed(.midnight, motionBlur: true)
        let normal = landed.titleArrivalMS(layerID: id)
        var calm = landed, punchy = landed
        Self.restyle(&calm, id) { $0.energy = .calm }
        Self.restyle(&punchy, id) { $0.energy = .punchy }
        let slow = calm.titleArrivalMS(layerID: id), fast = punchy.titleArrivalMS(layerID: id)
        #expect(abs(Double(slow) - Double(normal) * 1.3) <= 2)
        #expect(abs(Double(fast) - Double(normal) * 0.7) <= 2)
        // The title's motion blur smears harder as it rises.
        func shutter(_ doc: PhotonzDocument) -> Double? {
            doc.layer(id: id)?.style.effects.compactMap { effect -> Double? in
                if case .motionBlur(let blur) = effect { return blur.shutterAngle }
                return nil
            }.first
        }
        #expect(shutter(landed) == 180)
        #expect(shutter(calm) == 120)
        #expect(shutter(punchy) == 270)
        // A spring overshoots more when punchy.
        let compiled = try #require(punchy.titleRecipe(layerID: id)).compiled
        let spot = BuiltInTitle.spotlight.design.parts.first { $0.path == "Title" }?.in?.amount ?? 0
        var spotlight = TitleRecipe.reading(BuiltInTitle.spotlight.layer(in: Self.canvas),
                                            design: BuiltInTitle.spotlight.design)
        spotlight.energy = .punchy
        let punchier = spotlight.compiled.parts.first { $0.path == "Title" }?.in?.amount ?? 0
        #expect(abs((punchier - 100) - (spot - 100) * 1.3) < 1e-9)
        #expect(compiled.parts.first { $0.path == "Title" }?.in?.lengthMS == 490)
    }

    // MARK: - Intensity

    @Test("Intensity scales distances, blurs and grain together")
    func intensity() throws {
        var (doc, id) = try Self.placed(.aurora)
        let landedGrain = Self.piece(doc, id, "Background")?.style.effects.compactMap(\.grain).first?.amount
        #expect(landedGrain == GrainEffect.startingAmount)
        #expect(Self.restyle(&doc, id) { $0.intensity = 200 })
        #expect(Self.piece(doc, id, "Background")?.style.effects.compactMap(\.grain).first?.amount == 50)
        let blurIn = try #require(doc.titleRecipe(layerID: id)?.compiled.parts.first { $0.path == "Title" }?.in)
        #expect(blurIn.amount == 28)
        #expect(Self.restyle(&doc, id) { $0.intensity = 0 })
        #expect(Self.piece(doc, id, "Background")?.style.effects.compactMap(\.grain).first?.amount == 0)
        #expect(Self.restyle(&doc, id) { $0.intensity = 900 })
        #expect(doc.titleRecipe(layerID: id)?.intensity == 200)
    }

    // MARK: - Background

    @Test("The background turns off and on, and changes what it is made of")
    func background() throws {
        var (doc, id) = try Self.placed(.midnight)
        #expect(Self.restyle(&doc, id) { $0.showsBackground = false })
        #expect(Self.piece(doc, id, "Background")?.isVisible == false)
        #expect(Self.restyle(&doc, id) { $0.showsBackground = true })
        #expect(Self.piece(doc, id, "Background")?.isVisible == true)
        #expect(Self.restyle(&doc, id) { $0.background = .mesh })
        let mesh = try #require(Self.piece(doc, id, "Background").flatMap(TitleRestyler.paint))
        #expect(mesh.kind == .mesh)
        #expect(mesh.drift == Paint.startingDrift)
        #expect(mesh.orderedStops.count == 3)
        #expect(Self.restyle(&doc, id) { $0.background = .solid })
        let solid = try #require(Self.piece(doc, id, "Background").flatMap(TitleRestyler.paint))
        #expect(!solid.isGradient)
        #expect(solid.hex == "#0B1426")
        // Glass needs a picture under the title: over nothing it stays put.
        #expect(!doc.titleHasPictureUnder(id))
        Self.restyle(&doc, id) { $0.background = .glass }
        #expect(doc.titleRecipe(layerID: id)?.background == .solid)
    }

    @Test("Behind Glass turned solid stops blurring the recording, and back again frosts it")
    func glassTurnsSolid() throws {
        var (doc, id) = try Self.placed(.glass)
        doc.layers[0].content = .image(ImageRef(pixelSize: Self.canvas))
        #expect(doc.titleHasPictureUnder(id))
        #expect(doc.titleRecipe(layerID: id)?.background == .glass)
        #expect(Self.restyle(&doc, id) { $0.background = .solid })
        let solid = try #require(Self.piece(doc, id, "Background"))
        #expect(!solid.style.effects.contains { $0.blur?.kind == .background })
        #expect(solid.style.opacity == 1)
        #expect(solid.keyedMotion(.backgroundBlur) == nil)
        #expect(solid.keyedMotion(.backgroundZoom) == nil)
        #expect(Self.restyle(&doc, id) { $0.background = .glass })
        let glass = try #require(Self.piece(doc, id, "Background"))
        #expect(glass.style.effects.contains { $0.blur?.kind == .background })
        #expect(glass.keyedMotion(.backgroundBlur) != nil)
    }

    // MARK: - Parts

    @Test("Changing a part's in compiles it again and takes off what the old one moved")
    func partBehaviour() throws {
        var (doc, id) = try Self.placed(.midnight)
        #expect(Self.piece(doc, id, "Title")?.keyedMotion(.position) != nil)
        #expect(Self.restyle(&doc, id) { recipe in
            guard let index = recipe.design.parts.firstIndex(where: { $0.path == "Title" }) else { return }
            recipe.design.parts[index].in = TitleBuild(.blurIn, delayMS: 150, lengthMS: 700)
            recipe.design.parts[index].out = nil
        })
        let title = try #require(Self.piece(doc, id, "Title"))
        #expect(title.keyedMotion(.position) == nil)
        #expect(title.keyedMotion(.blur) != nil)
        #expect(title.keyedMotion(.opacity) != nil)
    }

    // MARK: - Typing

    @Test("Words typed longer lay the title out again: a page's lines move down, a card's box grows")
    func typingLaysOut() throws {
        var (doc, id) = try Self.placed(.midnight)
        let title = try #require(Self.piece(doc, id, "Title"))
        let subtitleTop = try #require(Self.piece(doc, id, "Subtitle")).frame.minY
        doc.updateLayer(id: title.id) { layer in
            guard case .text(var text) = layer.content else { return }
            text.string = "Launch\nDay"
            layer.content = .text(text)
        }
        #expect(Self.relayOut(&doc, id))
        let grown = try #require(Self.piece(doc, id, "Title"))
        #expect(grown.frame.height > title.frame.height)
        let moved = try #require(Self.piece(doc, id, "Subtitle")).frame.minY
        #expect(abs((moved - subtitleTop) - (grown.frame.height - title.frame.height)) < 1)
        // The subtitle rises into its NEW place.
        let keys = try #require(Self.piece(doc, id, "Subtitle")?.keyedMotion(.position)?.keyframes)
        let key = keys[1]
        if case let .point(point) = key.value { #expect(abs(point.y - moved) < 1) }

        var (cards, card) = try Self.placed(.clean)
        let width = try #require(Self.piece(cards, card, "Background")).frame.width
        let name = try #require(Self.piece(cards, card, "Name"))
        cards.updateLayer(id: name.id) { layer in
            guard case .text(var text) = layer.content else { return }
            text.string = "Somebody With A Long Name"
            layer.content = .text(text)
        }
        #expect(Self.relayOut(&cards, card))
        #expect(try #require(Self.piece(cards, card, "Background")).frame.width > width)
    }

    // MARK: - Saving your own

    @Test("A title saved as your own keeps its recipe, so its knobs still turn once it lands again")
    func savedKeepsTheRecipe() throws {
        var (doc, id) = try Self.placed(.sunrise)
        Self.restyle(&doc, id) { $0.energy = .calm }
        let saved = try #require(doc.savedTitlePreset(layerID: id, name: "Mine"))
        let data = try JSONEncoder().encode(saved)
        let read = try JSONDecoder().decode(SavedTitlePreset.self, from: data)
        var other = Self.tenSeconds()
        let landing = other.insertTitle(read, atTimeMS: 0)
        let landed = try #require(landing)
        let recipe = try #require(other.titleRecipe(layerID: landed.layerID))
        #expect(recipe.energy == .calm)
        #expect(recipe.design == BuiltInTitle.sunrise.design)
        let night = try Self.night()
        #expect(other.restyleTitle(layerID: landed.layerID) { $0.theme = night; $0.energy = .punchy })
        #expect(TitleDesign.find("Title", in: try #require(other.layer(id: landed.layerID)))?.text?.colorHex
            == "#FFFFFF")
    }

    @Test("Only a title writes a recipe: any other group saves byte for byte as before")
    func onlyATitleWritesARecipe() throws {
        let plain = GroupContent(children: [])
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!json.contains("\"title\""))
        let (doc, id) = try Self.placed(.accent)
        let data = try JSONEncoder().encode(doc)
        let read = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(read.titleRecipe(layerID: id) == doc.titleRecipe(layerID: id))
    }

    // MARK: - Tiles that play

    @Test("A tile's reel runs from the first frame through the arrival, the way off and a beat of nothing",
          arguments: BuiltInTitle.allCases)
    func tileReel(_ preset: BuiltInTitle) throws {
        let reel = try #require(TitlePreset.builtIn(preset).reel(frame: Self.canvas, width: 320))
        #expect(reel.pictures.count > 20)
        #expect(reel.keyTimes.count == reel.pictures.count + 1)
        #expect(reel.keyTimes.first == 0)
        #expect(reel.keyTimes.last == 1)
        #expect(zip(reel.keyTimes, reel.keyTimes.dropFirst()).allSatisfy { $0 < $1 })
        #expect(reel.lapMS > 1_000 && reel.lapMS < 4_000)
        // Every picture is the same size and has no time left in it.
        let size = try #require(reel.pictures.first?.canvasSize)
        for picture in reel.pictures {
            #expect(picture.canvasSize == size)
            #expect(picture.durationMS == nil)
            #expect(picture.layers.allSatisfy { $0.time == nil && $0.motions == nil })
        }
        // It moves: the first picture is not the picture at rest.
        let rest = try #require(TitlePreset.builtIn(preset).preview(frame: Self.canvas, width: 320))
        #expect(reel.pictures.first != rest)
    }

    @Test("Where the style uses the recording, the tile is pictured over the person's own frame")
    func tileOverTheRecording() throws {
        let frame = ImageRef(pixelSize: CGSize(width: 320, height: 180))
        let glass = try #require(TitlePreset.builtIn(.glass).preview(frame: Self.canvas, width: 320, recording: frame))
        #expect(glass.layers.first?.content == .image(frame))
        #expect(glass.layers.first?.frame == CGRect(origin: .zero, size: glass.canvasSize))
        let card = try #require(TitlePreset.builtIn(.bar).preview(frame: Self.canvas, width: 320, recording: frame))
        #expect(card.layers.first?.content == .image(frame))
        // A page that covers the frame has nothing of the recording to show.
        let page = try #require(TitlePreset.builtIn(.midnight).preview(frame: Self.canvas, width: 320, recording: frame))
        #expect(!page.layers.contains { $0.content == .image(frame) })
        #expect(TitlePreset.builtIn(.glass).usesTheRecording)
        #expect(!TitlePreset.builtIn(.midnight).usesTheRecording)
    }
}
