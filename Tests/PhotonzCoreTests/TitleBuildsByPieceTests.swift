import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A title part's words come in a piece at a time (task
/// `a-set-of-titles-that-look-designed`, `docs/design/video-titles-polish.md`).
///
/// Written before the model. A part's in can say what its words split into
/// (line, word or letter) and how far apart the pieces start, and it can be a
/// mask reveal, a track in or a typewriter. On words all of those compile to
/// the text's own reveal (`TextReveal.swift`), never to keys that would fade
/// the whole line as a block under its words; on a shape they fall back to the
/// nearest thing a shape can do. A cursor can blink while the title holds.
@Suite("A title part's words come in a piece at a time")
struct TitleBuildsByPieceTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    /// A title page (one of the set retired from the shelf, kept for exactly
    /// this: a plain page with a headline, a subtitle and a box accent),
    /// placed at one second for four.
    static func placed() throws -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.durationMS = 10_000
        let placed = doc.insertTitle(.midnight, atTimeMS: 1000)
        let inserted = try #require(placed)
        return (doc, inserted.layerID)
    }

    /// The title's own design swapped for `design`: its keys off, the new
    /// one compiled, as a restyle does.
    @discardableResult
    static func redesign(_ doc: inout PhotonzDocument, _ id: UUID, _ design: TitleDesign) -> Bool {
        doc.restyleTitle(layerID: id) { $0.design = design }
    }

    static func piece(_ doc: PhotonzDocument, _ group: UUID, _ path: String) -> Layer? {
        doc.layer(id: group).flatMap { TitleDesign.find(path, in: $0) }
    }

    static func design(_ title: TitleBuild?, accent: TitleBuild? = nil,
                       titleHold: TitleHold = .still) -> TitleDesign {
        TitleDesign(parts: [
            TitlePart(path: "Title", role: .headline, in: title, hold: titleHold,
                      out: .off(.fade, delayMS: 100)),
            TitlePart(path: "Accent", role: .accent, in: accent),
        ])
    }

    @Test("A rise by word on a headline is the words' own reveal, not keys on the line")
    func riseByWordIsAReveal() throws {
        var (doc, id) = try Self.placed()
        let clock = try #require(doc.layer(id: id)?.time?.sourceInMS)
        let build = TitleBuild(.rise, delayMS: 150, lengthMS: 500, amount: 12, by: .word, staggerMS: 80)
        let applied = Self.redesign(&doc, id, Self.design(build))
        #expect(applied)
        let title = try #require(Self.piece(doc, id, "Title"))
        let text = try #require(title.text)
        let reveal = try #require(text.reveal)
        #expect(reveal.style == .riseAndFade)
        #expect(reveal.unit == .word)
        #expect(reveal.staggerMS == 80)
        #expect(reveal.lengthMS == 500)
        #expect(reveal.startMS == clock + 150)
        #expect(reveal.curve == .easeOutExpo)
        #expect(reveal.direction == .up)
        // Twelve points of a 1080 line frame, said as a share of the type.
        #expect(abs(reveal.amount - 12 / Double(text.fontSize) * 100) < 0.01)
        // Nothing keyed on the line before its out: no block fading under the words.
        let opacity = title.motions?.first { $0.property == .opacity }
        let length = try #require(doc.layer(id: id)?.time?.lengthMS)
        for key in opacity?.keyframes ?? [] {
            #expect(key.atMS - clock >= length / 2, "an opacity key at \(key.atMS - clock) ms is part of the in")
        }
        #expect(title.motions?.contains { $0.property == .position } != true)
    }

    @Test("Mask reveal, track in and typewriter are reveals on words, with the units they suit")
    func newKindsOnWords() throws {
        let cases: [(TitleBuildKind, TextRevealStyle, TextRevealUnit)] = [
            (.maskReveal, .maskReveal, .line),
            (.trackIn, .trackIn, .letter),
            (.typewriter, .typewriter, .letter),
        ]
        for (kind, style, unit) in cases {
            var (doc, id) = try Self.placed()
            let applied = Self.redesign(&doc, id, Self.design(TitleBuild(kind, delayMS: 0, lengthMS: 600)))
            #expect(applied)
            let reveal = try #require(Self.piece(doc, id, "Title")?.text?.reveal, "\(kind)")
            #expect(reveal.style == style, "\(kind)")
            #expect(reveal.unit == unit, "\(kind)")
        }
        // Said by word, a mask reveal goes by word.
        var (doc, id) = try Self.placed()
        Self.redesign(&doc, id, Self.design(TitleBuild(.maskReveal, delayMS: 0, lengthMS: 600, by: .word)))
        #expect(Self.piece(doc, id, "Title")?.text?.reveal?.unit == .word)
        // A track in's amount is already a share of the type.
        (doc, id) = try Self.placed()
        Self.redesign(&doc, id, Self.design(TitleBuild(.trackIn, delayMS: 0, lengthMS: 1500, amount: 25)))
        #expect(Self.piece(doc, id, "Title")?.text?.reveal?.amount == 25)
        #expect(TitleBuildKind.maskReveal.title == "Mask Reveal")
        #expect(TitleBuildKind.trackIn.title == "Track In")
        #expect(TitleBuildKind.typewriter.title == "Typewriter")
    }

    @Test("On a shape a mask reveal is a wipe, and a track in or a typewriter is a fade")
    func newKindsOnShapes() throws {
        var (doc, id) = try Self.placed()
        Self.redesign(&doc, id, Self.design(nil, accent: TitleBuild(.maskReveal, delayMS: 0, lengthMS: 500)))
        let wiped = try #require(Self.piece(doc, id, "Accent"))
        #expect(wiped.motions?.contains { $0.property == .cropTop } == true)
        for kind in [TitleBuildKind.trackIn, .typewriter] {
            (doc, id) = try Self.placed()
            Self.redesign(&doc, id, Self.design(nil, accent: TitleBuild(kind, delayMS: 0, lengthMS: 500)))
            let faded = try #require(Self.piece(doc, id, "Accent"))
            #expect(faded.motions?.map(\.property) == [.opacity], "\(kind)")
        }
    }

    @Test("Energy paces the stagger with everything else, and intensity scales a track in")
    func energyAndIntensity() throws {
        var (doc, id) = try Self.placed()
        let design = TitleDesign(parts: [
            TitlePart(path: "Title", role: .headline,
                      in: TitleBuild(.rise, delayMS: 100, lengthMS: 500, amount: 12, by: .word, staggerMS: 80)),
            TitlePart(path: "Subtitle", role: .subtitle,
                      in: TitleBuild(.trackIn, delayMS: 200, lengthMS: 1000, amount: 30)),
        ])
        let restyled = doc.restyleTitle(layerID: id) {
            $0.design = design
            $0.energy = .punchy
            $0.intensity = 50
        }
        #expect(restyled)
        let title = try #require(Self.piece(doc, id, "Title")?.text?.reveal)
        #expect(title.staggerMS == 56)
        #expect(title.lengthMS == 350)
        let subtitle = try #require(Self.piece(doc, id, "Subtitle")?.text?.reveal)
        #expect(subtitle.amount == 15)
        // Taken off again by the next restyle's clear: no stale reveal left on
        // words whose in stopped being one.
        let again = doc.restyleTitle(layerID: id) {
            $0.design.parts[0].in = TitleBuild(.scaleFrom, delayMS: 0, lengthMS: 400)
        }
        #expect(again)
        #expect(Self.piece(doc, id, "Title")?.text?.reveal == nil)
    }

    @Test("A build written before builds had pieces reads back with none")
    func oldBuildsReadBack() throws {
        let old = #"{"kind":"rise","delayMS":150,"lengthMS":700,"amount":28,"direction":"up","curve":{"easeOutExpo":{}}}"#
        let build = try JSONDecoder().decode(TitleBuild.self, from: Data(old.utf8))
        #expect(build.unit == nil)
        #expect(build.staggerMS == nil)
        #expect(build.kind == .rise)
        let round = try JSONDecoder().decode(TitleBuild.self, from: JSONEncoder().encode(
            TitleBuild(.rise, delayMS: 0, lengthMS: 500, by: .letter, staggerMS: 30)))
        #expect(round.unit == .letter)
        #expect(round.staggerMS == 30)
    }

    @Test("A cursor blinks while the title holds: on and off on a beat, between its in and its out")
    func blinkHold() throws {
        var (doc, id) = try Self.placed()
        let length = try #require(doc.layer(id: id)?.time?.lengthMS)
        let design = Self.design(nil, accent: TitleBuild(.fade, delayMS: 0, lengthMS: 200))
        var parts = design.parts
        parts[1].hold = TitleHold(.blink)
        parts[1].out = .off(.fade, delayMS: 0, lengthMS: 150)
        Self.redesign(&doc, id, TitleDesign(parts: parts))
        let start = try #require(doc.layer(id: id)?.time?.inMS)
        // Sampled at moments of the hold: some on, some off, never between.
        var seen: Set<Double> = []
        for at in stride(from: 250, to: length - 300, by: 37) {
            guard let drawn = doc.drawn(atTimeMS: start + at).layer(id: id),
                  let accent = TitleDesign.find("Accent", in: drawn) else { continue }
            seen.insert((Double(accent.style.opacity) * 1000).rounded() / 1000)
        }
        #expect(seen.contains(0))
        #expect(seen.contains(where: { $0 > 0.5 }))
        #expect(seen.allSatisfy { $0 == 0 || $0 > 0.5 }, "a blink half way: \(seen)")
        #expect(TitleHoldKind.blink.rawValue == "blink")
    }

    @Test("A reveal set by hand on a title's words survives a knob, until that part's In is changed")
    func handRevealSurvivesKnobs() throws {
        var doc = PhotonzDocument(canvasSize: Self.canvas)
        doc.durationMS = 10_000
        let placed = doc.insertTitle(.keynote, atTimeMS: 1000)
        let id = try #require(placed).layerID
        let words = try #require(Self.piece(doc, id, "Title"))
        var hand = try #require(words.text?.reveal)
        hand.style = .maskReveal
        hand.unit = .letter
        hand.order = .centerOut
        let set = doc.setTextReveal(hand, layerID: words.id)
        #expect(set)
        // A theme, an energy: the words keep coming in the way they were told.
        let themed = doc.restyleTitle(layerID: id) { $0.theme = TitleTheme.curated[1] }
        #expect(themed)
        #expect(Self.piece(doc, id, "Title")?.text?.reveal == hand)
        let paced = doc.restyleTitle(layerID: id) { $0.energy = .punchy }
        #expect(paced)
        #expect(Self.piece(doc, id, "Title")?.text?.reveal?.order == .centerOut)
        #expect(Self.piece(doc, id, "Title")?.text?.reveal?.style == .maskReveal)
        // Changing the part's own In says how it comes in now.
        let index = try #require(doc.titleRecipe(layerID: id)?.design.parts.firstIndex { $0.path == "Title" })
        let changed = doc.restyleTitle(layerID: id) {
            $0.design.parts[index].in = TitleBuild(.blurIn, delayMS: 150, lengthMS: 500, by: .line)
        }
        #expect(changed)
        #expect(Self.piece(doc, id, "Title")?.text?.reveal?.style == .blurIn)
    }
}
