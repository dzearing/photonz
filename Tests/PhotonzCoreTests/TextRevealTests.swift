import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Title text comes in by line, word or letter (task
/// `title-text-comes-in-by-line-word-or-letter`,
/// `docs/design/video-titles-polish.md`).
///
/// Written before the model. A text layer carries ONE reveal: what it splits
/// its words into, how far apart each piece starts, in what order, and how
/// each piece arrives. It is stored once on the layer and read per piece at
/// the moment drawn, never split into a layer per word.
@Suite("Text comes in by line, word or letter")
struct TextRevealTests {

    // MARK: Pieces

    @Test("Letters are what a reader counts as one: an emoji with its skin tone is one letter, spaces are none")
    func lettersAreGraphemes() throws {
        let spans = try #require(TextReveal.spans(in: "Hi 👋🏽 yo", unit: .letter))
        #expect(spans.count == 5)
        // The wave and its tone are four UTF-16 units drawn as one picture.
        #expect(spans[2] == TextRevealSpan(location: 3, length: 4))
        #expect(spans[3] == TextRevealSpan(location: 8, length: 1))
    }

    @Test("Words are runs of non-space characters, in the order they are written")
    func wordsAreRuns() throws {
        let spans = try #require(TextReveal.spans(in: "Ship it  today", unit: .word))
        #expect(spans == [TextRevealSpan(location: 0, length: 4), TextRevealSpan(location: 5, length: 2),
                          TextRevealSpan(location: 9, length: 5)])
    }

    @Test("Right-to-left words split the same way, in reading order")
    func rightToLeft() throws {
        let words = try #require(TextReveal.spans(in: "שלום עולם", unit: .word))
        #expect(words.count == 2)
        #expect(words[0].location == 0)
        let letters = try #require(TextReveal.spans(in: "שלום עולם", unit: .letter))
        #expect(letters.count == 8)
    }

    @Test("Whole is one piece; lines are left to the layout, which alone knows where they break")
    func wholeAndLines() {
        #expect(TextReveal.spans(in: "Two words", unit: .whole) == [TextRevealSpan(location: 0, length: 9)])
        #expect(TextReveal.spans(in: "Two words", unit: .line) == nil)
        #expect(TextReveal.spans(in: "   ", unit: .word) == [])
    }

    // MARK: Order

    @Test("Forward, reverse and center out set which piece goes when")
    func orders() {
        func ranks(_ order: TextRevealOrder, _ count: Int) -> [Int] {
            var reveal = TextReveal(style: .riseAndFade, unit: .word)
            reveal.order = order
            return reveal.ranks(count: count)
        }
        #expect(ranks(.forward, 5) == [0, 1, 2, 3, 4])
        #expect(ranks(.reverse, 5) == [4, 3, 2, 1, 0])
        #expect(ranks(.centerOut, 5) == [2, 1, 0, 1, 2])
        #expect(ranks(.centerOut, 4) == [1, 0, 0, 1])
    }

    @Test("Random is the same shuffle every time for the same seed, so playback and export agree")
    func randomIsSeeded() {
        var reveal = TextReveal(style: .riseAndFade, unit: .letter)
        reveal.order = .random
        reveal.seed = 7
        let first = reveal.ranks(count: 12)
        #expect(first == reveal.ranks(count: 12))
        #expect(first.sorted() == Array(0..<12))
        #expect(first != Array(0..<12))
        reveal.seed = 8
        #expect(reveal.ranks(count: 12) != first)
    }

    // MARK: Timing

    @Test("Each piece starts a stagger after the one before it and runs its own length")
    func timing() {
        var reveal = TextReveal(style: .riseAndFade, unit: .word)
        reveal.staggerMS = 80
        reveal.lengthMS = 500
        #expect(reveal.lengthMS(count: 4) == 3 * 80 + 500)
        #expect(!reveal.hasSettled(atElapsedMS: 739, count: 4))
        #expect(reveal.hasSettled(atElapsedMS: 740, count: 4))
        // A piece not started yet is still off; one finished is home.
        let early = reveal.pose(rank: 2, atElapsedMS: 100)
        #expect(early.opacity == 0)
        let home = reveal.pose(rank: 0, atElapsedMS: 500)
        #expect(home.isAtRest)
    }

    // MARK: Behaviours

    @Test("Rise and fade: comes up from below its place as it fades in")
    func riseAndFade() {
        let reveal = TextReveal(style: .riseAndFade, unit: .word)
        let start = reveal.pose(rank: 0, atElapsedMS: 0)
        #expect(start.opacity == 0)
        #expect(start.offsetEm.y > 0)
        let mid = reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS / 4)
        #expect(mid.opacity > 0 && mid.opacity < 1)
        #expect(mid.offsetEm.y > 0 && mid.offsetEm.y < start.offsetEm.y)
        #expect(reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS).isAtRest)
    }

    @Test("Mask reveal: fully drawn, sliding up from behind its own baseline")
    func maskReveal() {
        let reveal = TextReveal(style: .maskReveal, unit: .word)
        let start = reveal.pose(rank: 0, atElapsedMS: 0)
        #expect(start.slide == 1)
        #expect(start.direction == .up)
        let mid = reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS / 4)
        #expect(mid.opacity == 1)
        #expect(mid.slide > 0 && mid.slide < 1)
        #expect(reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS).slide == 0)
    }

    @Test("Blur in: sharpens from a blur as it fades in")
    func blurIn() {
        let reveal = TextReveal(style: .blurIn, unit: .line)
        let start = reveal.pose(rank: 0, atElapsedMS: 0)
        #expect(start.blurEm > 0.05)
        #expect(start.opacity == 0)
        #expect(reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS).blurEm == 0)
    }

    @Test("Track in: letters start spread apart about their line's middle and close up")
    func trackIn() {
        let reveal = TextReveal(style: .trackIn, unit: .letter)
        let first = reveal.pose(rank: 0, atElapsedMS: 0, place: TextRevealPlace(index: 0, count: 5))
        let middle = reveal.pose(rank: 0, atElapsedMS: 0, place: TextRevealPlace(index: 2, count: 5))
        let last = reveal.pose(rank: 0, atElapsedMS: 0, place: TextRevealPlace(index: 4, count: 5))
        #expect(first.offsetEm.x < 0)
        #expect(middle.offsetEm.x == 0)
        #expect(last.offsetEm.x == -first.offsetEm.x)
        let home = reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS, place: TextRevealPlace(index: 0, count: 5))
        #expect(home.offsetEm.x == 0)
    }

    @Test("Typewriter: each letter appears whole at its moment, nothing in between")
    func typewriter() {
        var reveal = TextReveal(style: .typewriter, unit: .letter)
        reveal.staggerMS = 50
        #expect(reveal.pose(rank: 3, atElapsedMS: 149).opacity == 0)
        #expect(reveal.pose(rank: 3, atElapsedMS: 150).isAtRest)
        #expect(reveal.lengthMS(count: 10) == 9 * 50 + 1)
    }

    @Test("Wipe: the glyphs stay still while an edge uncovers them")
    func wipe() {
        let reveal = TextReveal(style: .wipe, unit: .whole)
        #expect(reveal.pose(rank: 0, atElapsedMS: 0).shown == 0)
        let mid = reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS / 2)
        #expect(mid.shown > 0 && mid.shown < 1)
        #expect(mid.offsetEm == .zero)
        #expect(reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS).isAtRest)
    }

    @Test("A fresh reveal takes the stagger polished intros use for its unit")
    func defaults() {
        #expect(TextReveal(style: .riseAndFade, unit: .letter).staggerMS == 30)
        #expect(TextReveal(style: .riseAndFade, unit: .word).staggerMS == 70)
        #expect(TextReveal(style: .riseAndFade, unit: .line).staggerMS == 100)
        #expect(TextReveal(style: .riseAndFade, unit: .whole).staggerMS == 0)
        #expect(TextReveal(style: .riseAndFade, unit: .word).curve == .easeOutExpo)
    }

    // MARK: Stored once on the layer

    @Test("It is saved on the text and old text opens without one")
    func codable() throws {
        var text = TextContent(string: "Hello there")
        text.reveal = TextReveal(style: .maskReveal, unit: .word)
        let data = try JSONEncoder().encode(text)
        let back = try JSONDecoder().decode(TextContent.self, from: data)
        #expect(back.reveal == text.reveal)
        let old = ##"{"string":"Hi","fontName":"SF Pro","fontSize":24,"colorHex":"#FFFFFF"}"##
        let opened = try JSONDecoder().decode(TextContent.self, from: Data(old.utf8))
        #expect(opened.reveal == nil)
        #expect(opened.revealElapsedMS == nil)
    }

    static func timeline(reveal: TextReveal?, inMS: Int = 1_000) -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var text = TextContent(string: "Ship it today", fontSize: 96)
        text.reveal = reveal
        var layer = Layer(name: "Headline", content: .text(text),
                          frame: CGRect(x: 200, y: 400, width: 1200, height: 140))
        layer.time = LayerTime(inMS: inMS, outMS: inMS + 4_000)
        doc.layers = [layer]
        doc.durationMS = 6_000
        return (doc, layer.id)
    }

    @Test("Drawn at a moment, the text says how far into its reveal it is, and stays one layer")
    func drawnAtAMoment() throws {
        var (doc, id) = Self.timeline(reveal: nil)
        let changed = doc.setTextReveal(TextReveal(style: .maskReveal, unit: .word), layerID: id)
        #expect(changed)
        let drawn = doc.drawn(atTimeMS: 1_250)
        #expect(drawn.allLayers.count == 1)
        guard case .text(let text) = try #require(drawn.layer(id: id)).content else {
            Issue.record("not text"); return
        }
        #expect(text.revealElapsedMS == 250)
        // The document itself never carries a moment.
        guard case .text(let stored) = try #require(doc.layer(id: id)).content else { return }
        #expect(stored.revealElapsedMS == nil)
        #expect(stored.reveal?.style == .maskReveal)
    }

    @Test("Moving the bar along the timeline takes the reveal with it")
    func followsTheBar() throws {
        var (doc, id) = Self.timeline(reveal: nil, inMS: 1_000)
        _ = doc.setTextReveal(TextReveal(style: .riseAndFade, unit: .word), layerID: id)
        doc.updateLayer(id: id) { $0.time = LayerTime(inMS: 3_000, outMS: 7_000) }
        guard case .text(let text) = try #require(doc.drawn(atTimeMS: 3_100).layer(id: id)).content else {
            Issue.record("not text"); return
        }
        #expect(text.revealElapsedMS == 100)
    }

    @Test("Taking the reveal off leaves plain text")
    func removing() throws {
        var (doc, id) = Self.timeline(reveal: TextReveal(style: .blurIn, unit: .line))
        let changed = doc.setTextReveal(nil, layerID: id)
        #expect(changed)
        guard case .text(let text) = try #require(doc.layer(id: id)).content else { return }
        #expect(text.reveal == nil)
    }

    @Test("Only text takes a reveal")
    func onlyText() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        let box = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")),
                        frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        doc.layers = [box]
        let changed = doc.setTextReveal(TextReveal(style: .wipe, unit: .whole), layerID: box.id)
        #expect(!changed)
    }

    // MARK: Inside a title

    @Test("Text inside a title reads its reveal on the title's own clock")
    func insideATitle() throws {
        var doc = TitleDesignTests.tenSeconds()
        let made = doc.insertTitle(.midnight, atTimeMS: 2_000)
        let inserted = try #require(made)
        let group = try #require(doc.layer(id: inserted.layerID))
        let headline = try #require(TitleDesign.find("Title", in: group))
        let changed = doc.setTextReveal(TextReveal(style: .maskReveal, unit: .word), layerID: headline.id)
        #expect(changed)
        guard case .text(let text) = try #require(doc.drawn(atTimeMS: 2_300).layer(id: headline.id)).content else {
            Issue.record("not text"); return
        }
        #expect(text.revealElapsedMS == 300)
        // ...and the title waits for the last word before the playhead lands.
        let words = try #require(TextReveal.spans(in: headline.text?.string ?? "", unit: .word)).count
        let reveal = try #require(text.reveal)
        #expect(doc.titleArrivalMS(layerID: inserted.layerID) >= reveal.lengthMS(count: words))
    }

    @Test("A wipe on a title's words is a real wipe now, not a fade")
    func titleWipeOnWords() throws {
        var doc = TitleDesignTests.tenSeconds()
        let made = doc.insertTitle(.midnight, atTimeMS: 0)
        let inserted = try #require(made)
        let design = TitleDesign(parts: [
            TitlePart(path: "Title", role: .headline,
                      in: TitleBuild(.wipe, delayMS: 100, lengthMS: 600, direction: .right)),
        ])
        let changed = doc.applyTitleDesign(design, layerID: inserted.layerID)
        #expect(changed)
        let group = try #require(doc.layer(id: inserted.layerID))
        let headline = try #require(TitleDesign.find("Title", in: group))
        let reveal = try #require(headline.text?.reveal)
        #expect(reveal.style == .wipe)
        #expect(reveal.unit == .whole)
        #expect(reveal.direction == .right)
        #expect(reveal.lengthMS == 600)
        // Its in is the reveal: no opacity key fading it as well.
        #expect(!(headline.motions ?? []).contains { $0.property == .opacity })
        guard case .text(let text) = try #require(doc.drawn(atTimeMS: 400).layer(id: headline.id)).content else {
            Issue.record("not text"); return
        }
        #expect(text.revealElapsedMS == 300)
    }
}
