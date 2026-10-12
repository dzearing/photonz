import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Title backgrounds that are alive (task
/// `title-backgrounds-that-are-alive-auroras-energy`).
///
/// Written before the looks. A title's background can be one of ten moving
/// looks, each a kind of paint with a few knobs that matter, coloured from the
/// title's theme and kept legible under its words; Mesh is no longer offered,
/// and a document that has one still opens with it.
@Suite("Title backgrounds that are alive")
struct LiveBackdropTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func placed(_ preset: BuiltInTitle) throws -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        let landed = doc.insertTitle(preset, atTimeMS: 2_000)
        let inserted = try #require(landed)
        return (doc, inserted.layerID)
    }

    static func background(_ doc: PhotonzDocument, _ id: UUID) -> Paint? {
        doc.layer(id: id).flatMap { TitleDesign.find("Background", in: $0) }.flatMap(TitleRestyler.paint)
    }

    // MARK: - The looks

    @Test("Ten looks, each clearly named, each with a knob of its own")
    func tenLooks() {
        let looks = LiveLook.allCases
        #expect(looks.count >= 10)
        #expect(Set(looks.map(\.title)).count == looks.count)
        for name in ["Aurora", "Energy Streams", "Color Bubbles", "Light Rays", "Light Leaks",
                     "Wind Streams", "Architectural Sketch", "Particles", "Liquid Gradient", "Grid Horizon"] {
            #expect(looks.contains { $0.title == name }, "missing \(name)")
        }
        for look in looks {
            let knobs = LiveBackdrop(look: look).knobs
            #expect((3...5).contains(knobs.count))
            #expect(knobs.map(\.label).contains("Speed"))
            #expect(knobs.last?.label == look.shapeKnob)
            // No two knobs of a look share a name.
            #expect(Set(knobs.map(\.label)).count == knobs.count)
            // Every knob starts inside its own range.
            for knob in knobs { #expect(knob.range.contains(knob.value)) }
            #expect(look.shapeKnob.count <= 20)
        }
    }

    @Test("A knob turns inside its range and nowhere else")
    func knobsHoldTheirRange() {
        let look = LiveBackdrop(look: .lightRays)
        #expect(look.with(.speed, at: 900).speed == LiveBackdrop.speedRange.upperBound)
        #expect(look.with(.scale, at: 1).scale == LiveBackdrop.scaleRange.lowerBound)
        #expect(look.with(.shape, at: 80).shape == 80)
        #expect(look.with(.strength, at: .nan).strength == LiveBackdrop.strengthRange.lowerBound)
        #expect(look.seconds(atMS: 2000) == 2)
        #expect(look.with(.speed, at: 50).seconds(atMS: 2000) == 1)
    }

    // MARK: - As a paint

    @Test("A live paint moves unless its speed is nought, and is kept in the document")
    func liveIsAPaint() throws {
        var paint = Paint(hex: "#0B1426", kind: .live,
                          stops: [GradientStop(hex: "#0B1426", position: 0),
                                  GradientStop(hex: "#4C9BFF", position: 1)],
                          live: LiveBackdrop(look: .aurora, speed: 140, shape: 20))
        #expect(paint.isGradient)
        #expect(paint.moves)
        let back = try JSONDecoder().decode(Paint.self, from: JSONEncoder().encode(paint))
        #expect(back == paint)
        #expect(back.live?.speed == 140)
        #expect(back.live?.shape == 20)
        // Two looks with the same colours do not draw alike.
        var other = paint
        other.live = LiveBackdrop(look: .particles)
        #expect(!paint.draws(sameAs: other))
        paint.live = paint.live?.with(.speed, at: 0)
        #expect(!paint.moves)
        // A flat paint still writes its bare hex, and an older gradient has
        // no look in it.
        let flat = String(decoding: try JSONEncoder().encode(Paint.solid("#FF3B30")), as: UTF8.self)
        #expect(flat == "\"#FF3B30\"")
        let old = ##"{"kind":"mesh","hex":"#0E1030","stops":[{"hex":"#0E1030","position":0},{"hex":"#3A1F8F","position":1}],"angle":200,"cx":0.5,"cy":0.5,"drift":40}"##
        let mesh = try JSONDecoder().decode(Paint.self, from: Data(old.utf8))
        #expect(mesh.kind == .mesh)
        #expect(mesh.live == nil)
        #expect(mesh.moves)
    }

    @Test("A look saved before a knob existed opens with that knob where a new look starts it")
    func olderLooksOpen() throws {
        let json = #"{"look":"gridHorizon","speed":50}"#
        let look = try JSONDecoder().decode(LiveBackdrop.self, from: Data(json.utf8))
        #expect(look.look == .gridHorizon)
        #expect(look.speed == 50)
        #expect(look.strength == 100)
        #expect(look.shape == LiveLook.gridHorizon.startingShape)
    }

    @Test("Turning a paint live starts it as the liquid gradient")
    func becomingLive() {
        var paint = Paint(hex: "#1F3B73")
        paint.becoming(.live)
        #expect(paint.kind == .live)
        #expect(paint.live?.look == .liquidGradient)
        #expect(paint.stops.count >= 2)
        #expect(paint.moves)
    }

    // MARK: - Colours

    @Test("Over a dark ground the lights are lifted to read as light, keeping the theme's hue")
    func lightsAreLifted() throws {
        let night = try #require(TitleTheme.curated.first { $0.id == "night" })
        let paint = Paint(hex: night.ground, kind: .live,
                          stops: night.liveStops, live: LiveBackdrop(look: .aurora))
        let palette = LivePalette(paint)
        #expect(!palette.lightGround)
        #expect(palette.lights.count == 3)
        for (light, source) in zip(palette.lights, paint.orderedStops.dropFirst().compactMap { RGBA(hex: $0.hex) }) {
            #expect(light.linearLuminance >= source.linearLuminance - 1e-9)
            #expect(light.hsl.lightness >= 0.6 - 1e-9)
            #expect(abs(light.hsl.hue - source.hsl.hue) < 2)
        }
        #expect(palette.limit == LivePalette.darkGroundCeiling)
    }

    @Test("Over a light ground the look tints and never darkens the frame below its floor")
    func lightGround() throws {
        for id in ["paper", "daylight", "sunset"] {
            let theme = try #require(TitleTheme.curated.first { $0.id == id })
            let palette = LivePalette(Paint(hex: theme.ground, kind: .live, stops: theme.liveStops))
            #expect(palette.lightGround, "\(id)")
            let ground = try #require(RGBA(hex: theme.ground)).linearLuminance
            #expect(palette.limit <= ground)
            // Dark words on the darkest the frame may get still read.
            let words = try #require(RGBA(hex: theme.primary)).linearLuminance
            #expect(RGBA.contrast(words, palette.limit) >= 4.5, "\(id)")
        }
    }

    @Test("White headline words read over the brightest a dark ground's look may get")
    func darkGroundCeilingIsLegible() {
        #expect(RGBA.contrast(1, LivePalette.darkGroundCeiling) >= 4.5)
    }

    @Test("Fewer than three lights go round again, turned, so no two are the same")
    func fewStops() {
        let palette = LivePalette(Paint(hex: "#000000", kind: .live,
                                        stops: [GradientStop(hex: "#000000", position: 0),
                                                GradientStop(hex: "#3366FF", position: 1)]))
        #expect(palette.lights.count == 3)
        #expect(Set(palette.lights.map(\.hexString)).count == 3)
    }

    // MARK: - On a title

    @Test("The Background knob offers every look and no longer offers Mesh")
    func offered() {
        let offered = TitleBackgroundKind.offered(glass: false)
        #expect(!offered.contains(.mesh))
        #expect(!offered.contains(.glass))
        #expect(TitleBackgroundKind.offered(glass: true).last == .glass)
        for look in LiveLook.allCases {
            #expect(offered.contains(TitleBackgroundKind(look: look)))
            #expect(TitleBackgroundKind(look: look).look == look)
            #expect(TitleBackgroundKind(look: look).title == look.title)
        }
    }

    @Test("Picking a look paints the background with it in the theme's colours, and a theme keeps the look's knobs")
    func pickingALook() throws {
        var (doc, id) = try Self.placed(.midnight)
        #expect(doc.restyleTitle(layerID: id) { $0.background = .aurora })
        let aurora = try #require(Self.background(doc, id))
        #expect(aurora.kind == .live)
        #expect(aurora.live?.look == .aurora)
        #expect(aurora.moves)
        #expect(doc.titleRecipe(layerID: id)?.background == .aurora)
        #expect(aurora.orderedStops.first?.hex == doc.titleRecipe(layerID: id)?.theme.ground)
        #expect(aurora.orderedStops.count >= 3)

        // A knob turned by hand stays through a new theme, and the colours follow it.
        var layers = doc.layers
        let groupIndex = try #require(layers.firstIndex { $0.id == id })
        func turn(_ layer: inout Layer) {
            guard case .group(var group) = layer.content else { return }
            for index in group.children.indices where group.children[index].name == "Background" {
                if case .annotation(var shape) = group.children[index].content {
                    let turned = shape.fill?.live?.with(.speed, at: 180)
                    shape.fill?.live = turned
                    group.children[index].content = .annotation(shape)
                }
            }
            layer.content = .group(group)
        }
        turn(&layers[groupIndex])
        doc.layers = layers
        let forest = try #require(TitleTheme.curated.first { $0.id == "forest" })
        #expect(doc.restyleTitle(layerID: id) { $0.theme = forest })
        let recoloured = try #require(Self.background(doc, id))
        #expect(recoloured.live?.look == .aurora)
        #expect(recoloured.live?.speed == 180)
        #expect(recoloured.orderedStops.first?.hex == forest.ground)
        #expect(recoloured.orderedStops.map(\.hex).contains(forest.accent))

        // Another look starts at its own knobs; Solid goes flat.
        #expect(doc.restyleTitle(layerID: id) { $0.background = .gridHorizon })
        #expect(Self.background(doc, id)?.live == LiveBackdrop(look: .gridHorizon))
        #expect(doc.restyleTitle(layerID: id) { $0.background = .gradient })
        let gradient = try #require(Self.background(doc, id))
        #expect(gradient.kind == .linear)
        #expect(!gradient.moves)
        #expect(doc.restyleTitle(layerID: id) { $0.background = .solid })
        #expect(Self.background(doc, id)?.isGradient == false)
    }

    @Test("A knob of the look behind a title turns on its own, keeps through a theme, and goes with the look")
    func turningAKnob() throws {
        var (doc, id) = try Self.placed(.midnight)
        #expect(doc.titleLiveBackdrop(layerID: id) == nil)
        let turned1 = doc.setTitleLiveKnob(layerID: id, .speed, to: 50)
        #expect(!turned1)
        #expect(doc.restyleTitle(layerID: id) { $0.background = .lightRays })
        #expect(doc.titleLiveBackdrop(layerID: id) == LiveBackdrop(look: .lightRays))
        func keys(_ doc: PhotonzDocument) -> Int {
            guard let title = doc.layer(id: id) else { return -1 }
            var count = 0
            for child in title.children { count += child.motions?.count ?? 0 }
            return count
        }
        let before = keys(doc)
        let turned2 = doc.setTitleLiveKnob(layerID: id, .shape, to: 85)
        #expect(turned2)
        let turned3 = doc.setTitleLiveKnob(layerID: id, .speed, to: 999)
        #expect(turned3)
        let turned4 = doc.setTitleLiveKnob(layerID: id, .speed, to: 300)
        #expect(!turned4)
        let look = try #require(doc.titleLiveBackdrop(layerID: id))
        #expect(look.shape == 85)
        #expect(look.speed == LiveBackdrop.speedRange.upperBound)
        // Its keys are left exactly as they were.
        #expect(keys(doc) == before)
        let ink = try #require(TitleTheme.curated.first { $0.id == "ink" })
        #expect(doc.restyleTitle(layerID: id) { $0.theme = ink })
        #expect(doc.titleLiveBackdrop(layerID: id)?.shape == 85)
        #expect(doc.restyleTitle(layerID: id) { $0.background = .solid })
        #expect(doc.titleLiveBackdrop(layerID: id) == nil)
    }

    @Test("A moving look keeps the headline its own colour: words are read against what the look can draw, not its lights")
    func wordsKeepTheirInk() throws {
        // Keynote Clean's own theme: black, near-white words, no colour at all.
        var (doc, id) = try Self.placed(.keynote)
        let ink = doc.layer(id: id).flatMap { TitleDesign.find("Title", in: $0) }?.text?.colorHex
        for kind in LiveLook.allCases.map(TitleBackgroundKind.init(look:)) {
            #expect(doc.restyleTitle(layerID: id) { $0.background = kind })
            let now = doc.layer(id: id).flatMap { TitleDesign.find("Title", in: $0) }?.text?.colorHex
            #expect(now == ink, "\(kind.title) changed the headline to \(now ?? "-")")
        }
    }

    @Test("A theme with no colour in it still lights a look in colour")
    func colourlessThemes() throws {
        let grey = Paint(hex: "#000000", kind: .live,
                         stops: [GradientStop(hex: "#000000", position: 0),
                                 GradientStop(hex: "#1C1C1E", position: 0.5),
                                 GradientStop(hex: "#F5F5F7", position: 1)])
        for light in LivePalette(grey).lights { #expect(light.hsl.saturation > 0.4) }
        // Keynote Clean's own: black, black, and its near-white words as accent.
        let keynote = Paint(hex: "#000000", kind: .live,
                            stops: [GradientStop(hex: "#000000", position: 0), GradientStop(hex: "#000000", position: 0.5),
                                    GradientStop(hex: "#F5F5F7", position: 1)])
        for light in LivePalette(keynote).lights { #expect(light.hsl.saturation > 0.4, "\(light.hexString)") }
        // A theme with one colour lends it to its grey stops.
        let ink = try #require(TitleTheme.curated.first { $0.id == "ink" })
        let lights = LivePalette(Paint(hex: ink.ground, kind: .live, stops: ink.liveStops)).lights
        let blue = try #require(RGBA(hex: ink.accent)).hsl.hue
        for light in lights {
            #expect(light.hsl.saturation > 0.4)
            let apart = abs(light.hsl.hue - blue)
            #expect(min(apart, 360 - apart) <= 90)
        }
    }

    @Test("No built-in title is drawn on Mesh any more")
    func presetsLeftMesh() throws {
        for preset in BuiltInTitle.allCases {
            let (doc, id) = try Self.placed(preset)
            guard let paint = Self.background(doc, id) else { continue }
            #expect(paint.kind != .mesh, "\(preset.rawValue) still on Mesh")
        }
        let (doc, id) = try Self.placed(.aurora)
        #expect(Self.background(doc, id)?.live?.look == .aurora)
        #expect(doc.titleRecipe(layerID: id)?.background == .aurora)
    }

    @Test("A title saved on Mesh still opens on Mesh")
    func meshStillOpens() throws {
        var (doc, id) = try Self.placed(.midnight)
        #expect(doc.restyleTitle(layerID: id) { $0.background = .mesh })
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.titleRecipe(layerID: id)?.background == .mesh)
        #expect(Self.background(back, id)?.kind == .mesh)
    }
}
