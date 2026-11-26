import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The moments of a video at which its titles' words are drawn for the first
/// time, so the editor can draw them ahead of a hand that has not got there
/// yet (`scrubbing-a-long-edit-never-trails-the-pointer-b`, pass 5).
///
/// Written before the code. The first time a drag over the 6 minute reference
/// edit crossed the title at 2:44, the words of its letter-by-letter reveal
/// were set out and drawn inside that refresh's picture: 9 ms of a 7.6 ms
/// window, and the picture was three refreshes behind the hand. Every later
/// crossing found them drawn.
@Suite("Words drawn ahead of the hand")
struct WordsDrawnAheadTests {

    private func text(_ string: String, reveal: TextReveal? = nil) -> Layer {
        var content = TextContent(string: string)
        content.reveal = reveal
        return Layer(name: string, content: .text(content), frame: CGRect(x: 0, y: 0, width: 400, height: 80))
    }

    private func title(_ children: [Layer], inMS: Int, outMS: Int) -> Layer {
        var group = Layer(name: "Title", content: .group(GroupContent(children: children)),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        group.time = LayerTime(inMS: inMS, outMS: outMS)
        return group
    }

    private func video(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        doc.durationMS = 60_000
        doc.layers = layers
        return doc
    }

    /// How far into its reveal `id` is at `ms`, read the way the canvas
    /// reads it.
    private func elapsed(_ doc: PhotonzDocument, _ id: UUID, at ms: Int) -> Int? {
        guard case .text(let shown) = doc.drawn(atTimeMS: ms).layer(id: id)?.content else { return nil }
        return shown.revealElapsedMS
    }

    @Test("A title's letters are asked for while they are coming in, and its words once they are home")
    func midRevealAndAtRest() throws {
        let reveal = TextReveal(style: .trackIn, unit: .letter, staggerMS: 0, lengthMS: 900, startMS: 100)
        let words = text("Capture", reveal: reveal)
        let doc = video([title([text("Chapter 2"), words], inMS: 20_000, outMS: 24_000)])
        let moments = doc.momentsToDrawWordsAhead()
        // The kicker, which has no reveal, in the middle of the title.
        #expect(moments.count == 3)
        #expect(moments.contains(22_000))
        let count = try #require(TextReveal.spans(in: "Capture", unit: .letter)).count
        let length = reveal.lengthMS(count: count)
        // One moment with the letters part way in, on the title's own clock...
        #expect(moments.contains { ms in
            guard let at = elapsed(doc, words.id, at: ms) else { return false }
            return at > 0 && at < length
        })
        // ...and one with every letter home, inside the title.
        #expect(moments.contains { ms in
            guard let at = elapsed(doc, words.id, at: ms) else { return false }
            return at >= length && ms < 24_000
        })
        #expect(moments.allSatisfy { $0 >= 20_000 && $0 < 24_000 })
    }

    @Test("Words with no reveal are asked for once, in the middle of their stretch")
    func plainWords() {
        let doc = video([title([text("Name"), text("Role")], inMS: 10_000, outMS: 14_000)])
        #expect(doc.momentsToDrawWordsAhead() == [12_000])
    }

    @Test("A text with a stretch of its own is asked for on its own clock")
    func timedText() throws {
        var words = text("Hello", reveal: TextReveal(style: .riseAndFade, unit: .word, lengthMS: 600, startMS: 0))
        words.time = LayerTime(inMS: 5_000, outMS: 8_000)
        let doc = video([words])
        let moments = doc.momentsToDrawWordsAhead()
        #expect(moments.count == 2)
        let at = try #require(elapsed(doc, words.id, at: moments.min() ?? 0))
        #expect(at > 0 && at < 600)
    }

    @Test("Hidden titles, and a document with no time, ask for nothing; every title is asked for in order")
    func nothingToDraw() {
        var hidden = title([text("Gone")], inMS: 0, outMS: 4_000)
        hidden.isVisible = false
        #expect(video([hidden]).momentsToDrawWordsAhead().isEmpty)
        var still = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        still.layers = [text("A picture's words")]
        #expect(still.momentsToDrawWordsAhead().isEmpty)
        let two = video([title([text("Late")], inMS: 30_000, outMS: 32_000),
                         title([text("Early")], inMS: 2_000, outMS: 4_000)])
        #expect(two.momentsToDrawWordsAhead() == [3_000, 31_000])
    }
}
