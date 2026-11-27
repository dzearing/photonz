import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Words drawn ahead of a hand dragging the playhead: the renderer sets out
/// and keeps a moment's words without drawing its picture, so the first
/// picture that shows them finds them kept
/// (`scrubbing-a-long-edit-never-trails-the-pointer-b`, pass 5;
/// `PhotonzDocument.momentsToDrawWordsAhead`).
@Suite("Words drawn ahead")
struct WordsDrawnAheadRenderTests {

    private func titleMidReveal() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 640, height: 360))
        doc.durationMS = 10_000
        var words = TextContent(string: "Capture", fontSize: 72, colorHex: "#1D1D1F")
        words.reveal = TextReveal(style: .trackIn, unit: .letter, staggerMS: 40, lengthMS: 900, startMS: 100)
        var title = Layer(name: "Title", content: .group(GroupContent(children: [
            Layer(name: "Kicker", content: .text(TextContent(string: "Chapter 2", fontSize: 30)),
                  frame: CGRect(x: 40, y: 60, width: 560, height: 40)),
            Layer(name: "Words", content: .text(words), frame: CGRect(x: 40, y: 120, width: 560, height: 200)),
        ])), frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        title.time = LayerTime(inMS: 2_000, outMS: 6_000)
        doc.layers = [title]
        return doc
    }

    @Test("Every moment's words drawn ahead are found kept by the picture that shows them")
    func drawnAheadAreKept() throws {
        let doc = titleMidReveal()
        let moments = doc.momentsToDrawWordsAhead()
        #expect(moments.count == 3)
        let store = ImageStore()
        let renderer = DocumentRenderer()
        for ms in moments { renderer.drawWordsAhead(doc.drawn(atTimeMS: ms), store: store, contentScale: 2) }
        let missedAhead = renderer.contentCacheMisses
        #expect(missedAhead > 0)
        for ms in moments {
            _ = renderer.renderInteractiveFrame(doc.drawn(atTimeMS: ms), store: store, contentScale: 2)
        }
        #expect(renderer.contentCacheMisses == missedAhead)
    }

    /// A title over a recording none of whose frames has been read yet:
    /// what the editor poses ahead once a video is open.
    private func titleOverARecording() -> PhotonzDocument {
        let movie = MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 10_000)
        var doc = PhotonzDocument.recording(movie, name: "Take 1")
        doc.canvasSize = CGSize(width: 640, height: 360)
        let id = doc.layers[0].id
        doc.updateLayer(id: id) { $0.frame = CGRect(x: 0, y: 0, width: 640, height: 360) }
        doc.layers.append(contentsOf: titleMidReveal().layers)
        return doc
    }

    @Test("A moment drawn ahead is drawn once, so its programs are ready before the hand gets there")
    func drawnAheadIsDrawn() throws {
        // Setting the words out was only half of it: the first picture of
        // the 2:44 title still spent 4.6 ms, and once 57 ms, while Core Image
        // planned a recipe it had never seen (pass 6).
        let doc = titleOverARecording()
        let ms = try #require(doc.momentsToDrawWordsAhead().first)
        let store = ImageStore()
        let renderer = DocumentRenderer()
        renderer.drawWordsAhead(doc.drawn(atTimeMS: ms), store: store, contentScale: 1, colorSpace: nil)
        #expect(renderer.momentsDrawnAhead == 1)
        // The frames it stood in for are not left behind as if they had been
        // read: the store is as it was.
        #expect(store.count == 0)
    }

    @Test("Drawing ahead stands in for a recording's frames at the size they are read at in passing")
    func standInsAreReadInPassingSize() throws {
        let doc = titleOverARecording()
        let ms = try #require(doc.momentsToDrawWordsAhead().first)
        let posed = doc.drawn(atTimeMS: ms)
        let live = ImageStore()
        let (standing, stoodIn) = DocumentRenderer.standInsForFramesNotRead(in: posed, store: live)
        #expect(stoodIn.count == 1)
        #expect(live.count == 0)
        let picture = try #require(stoodIn.first.flatMap { standing.image(for: $0) })
        #expect(picture.width == Int(MovieSweep.roughWidth))
        #expect(MovieSweep.isReadInPassing(frameWidth: picture.width,
                                           of: MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 1)))
    }

    @Test("Drawing words ahead leaves the picture as it would have been")
    func samePicture() throws {
        let doc = titleMidReveal()
        let ms = try #require(doc.momentsToDrawWordsAhead().first)
        let drawn = doc.drawn(atTimeMS: ms)
        let store = ImageStore()
        let plain = try #require(DocumentRenderer().render(drawn, store: store))
        let warmed = DocumentRenderer()
        warmed.drawWordsAhead(drawn, store: store, contentScale: 1)
        let after = try #require(warmed.render(drawn, store: store))
        let a = try #require(plain.dataProvider?.data as Data?)
        let b = try #require(after.dataProvider?.data as Data?)
        #expect(a == b)
    }
}
