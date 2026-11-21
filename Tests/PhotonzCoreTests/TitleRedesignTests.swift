import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Five title pages redesigned from a reference board (task
/// `keynote-clean-soft-gradient-glass-kinetic-bold-t`).
///
/// Written before the designs changed. The user, 2026-11-21, of Keynote Clean
/// and Soft Gradient Glass: "looks like clipart ... These purple colors are just
/// not what you would see on high quality refined title slides. You would
/// expect far better color pairings and typographical effects", then "same with
/// kinetic bold, tech terminal, stacked stagger". The rules these hold are the
/// board's (`queue/audits/2026-11-21-title-reference-board.md`, copied into
/// `docs/design/video-titles-polish.md`, "Colour and type rules for title
/// pages"). How they look is judged from the reel, not here; this holds what
/// can be counted.
@Suite("Five title pages redesigned from a reference board")
struct TitleRedesignTests {

    static let canvas = CGSize(width: 1920, height: 1080)
    static let five: [BuiltInTitle] = [.keynote, .softGlass, .kinetic, .terminal, .stacked]

    @Test("The five carry names that say what they are now")
    func names() {
        #expect(Self.five.map(\.name) == ["Main Title", "Frosted Glass", "Condensed Poster", "Command Line",
                                          "Roman and Italic"])
        // Still under More Styles, in the same places.
        #expect(Self.five.allSatisfy { $0.isMoreStyle })
    }

    /// Hue in degrees and saturation (HSV) of `hex`.
    static func hueAndSaturation(_ hex: String) -> (hue: Double, saturation: Double, value: Double)? {
        guard let c = RGBA(hex: String(hex.prefix(7))) else { return nil }
        let high = max(c.r, c.g, c.b), low = min(c.r, c.g, c.b), span = high - low
        guard high > 0, span > 0 else { return (0, 0, high) }
        var degrees: Double
        if high == c.r { degrees = 60 * ((c.g - c.b) / span) } else if high == c.g { degrees = 60 * ((c.b - c.r) / span + 2) }
        else { degrees = 60 * ((c.r - c.g) / span + 4) }
        if degrees < 0 { degrees += 360 }
        return (degrees, span / high, high)
    }

    static func colours(_ layer: Layer) -> [String] {
        layer.selfAndDescendants.flatMap { piece -> [String] in
            var found: [String] = []
            if let text = piece.text { found.append(text.colorHex) }
            if let shape = piece.annotation {
                found.append(shape.colorHex)
                if let fill = shape.fill { found += [fill.hex] + fill.stops.map(\.hex) }
            }
            return found
        }
    }

    @Test("No saturated purple, violet or electric blue anywhere in the five")
    func noStockPurpleOrBlue() {
        for preset in Self.five {
            for hex in Self.colours(preset.layer(in: Self.canvas)) {
                guard let (hue, saturation, value) = Self.hueAndSaturation(hex) else { continue }
                let stock = (215...300).contains(hue) && saturation > 0.35 && value > 0.25
                #expect(!stock, "\(preset.name) uses \(hex) (hue \(Int(hue)), saturation \(String(format: "%.2f", saturation)))")
            }
        }
    }

    /// The headline's words: the part the design calls its headline.
    static func headline(_ preset: BuiltInTitle) throws -> TextContent {
        let layer = preset.layer(in: canvas)
        let part = try #require(preset.design.parts.first { $0.role == .headline }, "\(preset.name)")
        return try #require(TitleDesign.find(part.path, in: layer)?.text, "\(preset.name)")
    }

    @Test("Every headline is set in a face chosen for it, not plain SF Pro")
    func chosenFaces() throws {
        var faces: Set<String> = []
        for preset in Self.five {
            let words = try Self.headline(preset)
            #expect(words.fontName != "SF Pro", "\(preset.name) is still plain SF Pro")
            faces.insert(words.fontName)
        }
        // Five different faces for five different ideas.
        #expect(faces.count == Self.five.count, "\(faces.sorted())")
    }

    @Test("Each carries a typographic idea: a second family in contrast, or small caps tracked open against a tight headline")
    func typographicIdea() throws {
        for preset in Self.five {
            let layer = preset.layer(in: Self.canvas)
            let headline = try Self.headline(preset)
            let others = layer.selfAndDescendants.compactMap(\.text).filter { $0 != headline }
            let secondFamily = others.contains { $0.fontName != headline.fontName }
            let openCaps = others.contains { ($0.tracking ?? 0) >= 0.1 && $0.string == $0.string.uppercased() }
            #expect(secondFamily || openCaps, "\(preset.name) has no idea in its type")
            // Tracking moves against size: the big line is never set open.
            #expect((headline.tracking ?? 0) <= 0, "\(preset.name)'s headline is set open")
            // Two sizes, three to eight times apart.
            let sizes = Set(layer.selfAndDescendants.compactMap { $0.text.map { Double($0.fontSize) } })
            if let high = sizes.max(), let low = sizes.min(), low > 0 {
                #expect((2.6...9).contains(high / low), "\(preset.name) sizes \(sizes.sorted())")
            }
        }
    }

    /// The colour a part stands on: the top opaque-enough fill under its
    /// middle, blended over the full frame ground, or nil.
    static func ground(of words: Layer, in title: Layer) -> RGBA? {
        let pieces = TitleSetTests.flattened(title)
        guard let mine = pieces.first(where: { $0.piece.id == words.id })?.frame else { return nil }
        let middle = CGPoint(x: mine.midX, y: mine.midY)
        var behind: RGBA?
        for (piece, frame) in pieces where piece.id != words.id && piece.text == nil {
            guard let fill = piece.annotation?.fill, frame.contains(middle), frame.height > mine.height else { continue }
            guard let colour = RGBA(hex: String(fill.hex.prefix(7))) else { continue }
            let alpha = Double(piece.style.opacity)
            if let under = behind {
                behind = RGBA(r: colour.r * alpha + under.r * (1 - alpha), g: colour.g * alpha + under.g * (1 - alpha),
                              b: colour.b * alpha + under.b * (1 - alpha))
            } else {
                behind = colour
            }
        }
        return behind
    }

    @Test("Headlines read at 7:1 or better on their ground, small lines at 4.5:1")
    func contrast() throws {
        for preset in Self.five {
            let layer = preset.layer(in: Self.canvas)
            for words in layer.selfAndDescendants where words.text != nil {
                guard let text = words.text, let ink = RGBA(hex: text.colorHex),
                      let ground = Self.ground(of: words, in: layer) else {
                    Issue.record("\(preset.name) \(words.name) stands on nothing")
                    continue
                }
                let ratio = SegmentInk.contrast(ink, ground)
                let needed = text.fontSize >= 60 ? 7.0 : 4.5
                #expect(ratio >= needed, "\(preset.name) \(words.name) reads at \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    @Test("No rounded square or blob stands in for a logo")
    func structuralOrnament() {
        for preset in Self.five {
            for piece in preset.layer(in: Self.canvas).selfAndDescendants where piece.text == nil {
                guard let shape = piece.annotation, piece.name != "Background", piece.name != "Panel" else { continue }
                let square = abs(piece.frame.width - piece.frame.height) < 4 && piece.frame.width > 20
                #expect(!(square && shape.cornerRadius > 0) && shape.shape != .ellipse,
                        "\(preset.name) \(piece.name) is a decorative mark")
            }
        }
    }

    @Test("A line set in a face of its own keeps it when laid out again, and takes a picked font pair's face")
    func ownFaceSurvivesARelayout() throws {
        var (doc, id) = try TitleSetTests.placed(.stacked)
        let relaid = doc.relayOutTitle(layerID: id)
        #expect(relaid)
        let italic = try #require(doc.layer(id: id).flatMap { TitleDesign.find("Line 2", in: $0) }?.text)
        #expect(italic.fontName == "BodoniSvtyTwoITCTT-BookIta")
        let technical = try #require(TitleFontPair.curated.first { $0.id == "technical" })
        let picked = doc.restyleTitle(layerID: id) { $0.fonts = technical }
        #expect(picked)
        let restyled = try #require(doc.layer(id: id).flatMap { TitleDesign.find("Line 2", in: $0) }?.text)
        #expect(restyled.fontName == technical.text)
        let turnedBack = doc.restyleTitle(layerID: id) { $0.fonts = $0.originalFonts }
        #expect(turnedBack)
        let back = try #require(doc.layer(id: id).flatMap { TitleDesign.find("Line 2", in: $0) }?.text)
        #expect(back.fontName == "BodoniSvtyTwoITCTT-BookIta")
    }

    // MARK: - Old documents and shelf entries

    @Test("A shelf entry or drag that names an old one opens the new design under its new name")
    func oldEntriesOpenTheNewDesign() throws {
        for (raw, name) in zip(["keynote", "softGlass", "kinetic", "terminal", "stacked"],
                               ["Main Title", "Frosted Glass", "Condensed Poster", "Command Line", "Roman and Italic"]) {
            let preset = try #require(TitlePreset(entryID: "title.builtIn.\(raw)", saved: []), "\(raw)")
            #expect(preset.name == name)
            #expect(BuiltInTitle(rawValue: raw)?.name == name)
        }
    }

    @Test("A document holding one of the old five opens drawing it exactly as it was")
    func oldDocumentsKeepTheirLook() throws {
        for preset in Self.five {
            var (doc, id) = try TitleSetTests.placed(preset)
            // As a document saved before the redesign has it: the old purple
            // ground and plain SF Pro.
            let title = try #require(doc.layer(id: id))
            let background = try #require(TitleDesign.find("Background", in: title))
            let headline = try #require(TitleDesign.find("Title", in: title))
            doc.updateLayer(id: background.id) { layer in
                guard case .annotation(var content) = layer.content, var fill = content.fill else { return }
                fill.hex = "#16205E"
                if !fill.stops.isEmpty { fill.stops[0].hex = "#16205E" }
                content.fill = fill
                layer.content = .annotation(content)
            }
            doc.updateLayer(id: headline.id) { layer in
                guard case .text(var words) = layer.content else { return }
                words.fontName = "SF Pro"
                layer.content = .text(words)
            }
            let opened = try JSONDecoder().decode(PhotonzDocument.self, from: JSONEncoder().encode(doc))
            let reopened = try #require(opened.layer(id: id))
            #expect(TitleDesign.find("Background", in: reopened)?.annotation?.fill?.hex == "#16205E", "\(preset.name)")
            #expect(TitleDesign.find("Title", in: reopened)?.text?.fontName == "SF Pro", "\(preset.name)")
            #expect(opened.drawn(atTimeMS: 3000).layer(id: id) == doc.drawn(atTimeMS: 3000).layer(id: id))
        }
    }
}
