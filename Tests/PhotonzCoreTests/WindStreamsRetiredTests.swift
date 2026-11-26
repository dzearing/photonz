import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Wind Streams is taken out (task
/// `no-title-has-the-wavy-line-background-wind-strea`).
///
/// The user, 2026-11-26, of Condensed Poster's ground of thin wavy ember lines:
/// "this screen, the background is so freaking amateur. we need to just remove
/// this. it's like some kind of bland wood grain". No built-in title draws it,
/// no title can be restyled to it, the Library does not offer it, and a
/// document saved with it opens on the plain ground it moved over.
@Suite("Wind Streams is taken out")
struct WindStreamsRetiredTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    @Test("No list of moving looks offers Wind Streams")
    func notOffered() {
        #expect(!LiveLook.allCases.map(\.title).contains("Wind Streams"))
        #expect(LiveLook(rawValue: "windStreams") == nil)
        #expect(!TitleBackgroundKind.offered(glass: true).map(\.title).contains("Wind Streams"))
        #expect(!TitleBackgroundKind.allCases.map(\.rawValue).contains("windStreams"))
    }

    @Test("No built-in title page or name card moves wavy lines behind its words")
    func noTitleDrawsIt() throws {
        for preset in BuiltInTitle.allCases {
            let layer = preset.layer(in: Self.canvas)
            let data = try JSONEncoder().encode(layer)
            let json = try #require(String(data: data, encoding: .utf8))
            #expect(!json.contains("windStreams"), "\(preset.name) still draws Wind Streams")
        }
    }

    @Test("Condensed Poster sits on a still warm black, at most a barely visible falloff")
    func condensedPosterGround() throws {
        let (doc, id) = try LiveBackdropTests.placed(.kinetic)
        let paint = try #require(LiveBackdropTests.background(doc, id))
        // Still: nothing drawn afresh every frame.
        #expect(paint.kind != .live)
        #expect(paint.kind != .mesh)
        let hexes = [paint.hex] + paint.stops.map(\.hex)
        let colours = hexes.compactMap { RGBA(hex: $0) }
        #expect(colours.count == hexes.count)
        for colour in colours {
            // Warm: red at or above blue. Black: dark enough that ivory reads
            // at better than 15 to 1 on every part of it.
            #expect(colour.r >= colour.b, "\(colour) is not warm")
            #expect(RGBA.contrast(RGBA(hex: "#F1ECE2")?.linearLuminance ?? 1, colour.linearLuminance) > 15)
        }
        // Barely visible: the lightest and darkest part of the ground are
        // within a few levels of each other.
        let lights = colours.map(\.linearLuminance)
        if let high = lights.max(), let low = lights.min() {
            #expect(RGBA.contrast(high, low) < 1.25, "the falloff is more than barely visible")
        }
        // The Background picker reads it as a still background.
        let recipe = try #require(doc.titleRecipe(layerID: id))
        #expect(recipe.background?.look == nil)
        #expect(recipe.originalBackground?.look == nil)
    }

    /// A placed title's document as it would have been written by a build that
    /// still had Wind Streams: the same title on Particles, with the look's
    /// name swapped in the saved file.
    static func savedWithWindStreams() throws -> (Data, UUID, ground: String) {
        var (doc, id) = try LiveBackdropTests.placed(.kinetic)
        #expect(doc.restyleTitle(layerID: id) { $0.background = .particles })
        let live = try #require(LiveBackdropTests.background(doc, id))
        let ground = try #require(live.orderedStops.first?.hex)
        let data = try JSONEncoder().encode(doc)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"particles\""))
        let old = text.replacingOccurrences(of: "\"particles\"", with: "\"windStreams\"")
        return (Data(old.utf8), id, ground)
    }

    @Test("A document saved with Wind Streams opens on the plain ground it moved over")
    func oldDocumentsOpen() throws {
        let (data, id, ground) = try Self.savedWithWindStreams()
        let doc = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        let paint = try #require(LiveBackdropTests.background(doc, id))
        #expect(paint.kind == .solid)
        #expect(paint.live == nil)
        #expect(paint.hex == ground)
        let recipe = try #require(doc.titleRecipe(layerID: id))
        #expect(recipe.background == .solid)
        // It writes back out with no trace of the look, and opens again.
        let again = try JSONEncoder().encode(doc)
        #expect(!(String(data: again, encoding: .utf8) ?? "").contains("windStreams"))
        _ = try JSONDecoder().decode(PhotonzDocument.self, from: again)
    }

    @Test("A title opened from Wind Streams restyles like any other")
    func oldDocumentsRestyle() throws {
        let (data, id, _) = try Self.savedWithWindStreams()
        var doc = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(doc.restyleTitle(layerID: id) { $0.background = .aurora })
        #expect(LiveBackdropTests.background(doc, id)?.live?.look == .aurora)
        #expect(doc.restyleTitle(layerID: id) { $0.background = .solid })
        #expect(LiveBackdropTests.background(doc, id)?.kind == .solid)
    }

    @Test("A paint saved on Wind Streams reads as its ground")
    func oldPaintReadsAsItsGround() throws {
        let json = """
        {"kind":"live","hex":"#0F0E0D","angle":135,"cx":0.5,"cy":0.5,
         "stops":[{"hex":"#0F0E0D","position":0},{"hex":"#5A2A1E","position":0.5},{"hex":"#6A3022","position":1}],
         "live":{"look":"windStreams","speed":22,"strength":2,"scale":100,"shape":35}}
        """
        let paint = try JSONDecoder().decode(Paint.self, from: Data(json.utf8))
        #expect(paint.kind == .solid)
        #expect(paint.hex == "#0F0E0D")
        #expect(paint.live == nil)
        // Even when the ground is only in the stops.
        let groundInStops = json.replacingOccurrences(of: "\"hex\":\"#0F0E0D\",\"angle\"", with: "\"angle\"")
        let other = try JSONDecoder().decode(Paint.self, from: Data(groundInStops.utf8))
        #expect(other.kind == .solid)
        #expect(other.hex == "#0F0E0D")
    }

    @Test("A recipe saved on Wind Streams reads as Solid")
    func oldKindReadsAsSolid() throws {
        let kinds = try JSONDecoder().decode([TitleBackgroundKind].self,
                                             from: Data(#"["windStreams","aurora","solid"]"#.utf8))
        #expect(kinds == [.solid, .aurora, .solid])
        // An unknown name that never existed is still refused.
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([TitleBackgroundKind].self, from: Data(#"["confetti"]"#.utf8))
        }
    }
}
