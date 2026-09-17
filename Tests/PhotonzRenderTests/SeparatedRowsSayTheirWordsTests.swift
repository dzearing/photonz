import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// The whole of it, end to end on a real capture: take a screenshot apart, read
/// the words off the pieces, and ask the layers list what its rows say and the
/// find field what it can reach.
///
/// The app does exactly this in `EditorState+RunWords`, one dozen pieces at a
/// time in the background. What is checked here is everything but the
/// background: that the pieces a real separation makes read back into the words
/// a person can see, that those words become the names in the list, and that
/// the document is untouched by all of it.
@Suite("A separated screenshot hands back a list you can read", .serialized)
struct SeparatedRowsSayTheirWordsTests {

    private static func capture(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }

    /// A document with the capture separated into it, the way the command
    /// builds one, and the words read off every run.
    private struct Taken {
        let document: PhotonzDocument
        let words: [ImageRef: String]
        let runs: Int
        let readMS: Double
    }

    private static func takeApart(_ name: String, scale: CGFloat) -> Taken? {
        guard let image = capture(name) else { return nil }
        let store = ImageStore()
        let gap = Double(AlignmentScan.visibleGap * scale)
        let minElement = Double(max(10, 10 * scale))
        guard let result = LayerSeparator.separate(
            image, luma: EdgeMapAnalyzer.analyzeFully(image).luma,
            gap: gap, minElement: minElement), !result.pieces.isEmpty else { return nil }

        let source = store.register(image)
        var document = PhotonzDocument(
            canvasSize: CGSize(width: image.width, height: image.height),
            layers: [Layer(name: "Background", content: .image(source),
                           frame: CGRect(x: 0, y: 0,
                                         width: CGFloat(image.width),
                                         height: CGFloat(image.height)))])
        let id = document.layers[0].id
        var runs = 0, boxes = 0
        let pieces = result.pieces.map { piece -> PhotonzDocument.SeparatedPiece in
            let isRun = piece.kind == .text
            if isRun { runs += 1 } else { boxes += 1 }
            let name = isRun ? "Text \(runs)" : "Box \(boxes)"
            switch piece.body {
            case .picture(let cut):
                return PhotonzDocument.SeparatedPiece(
                    frame: piece.rect, content: .picture(store.register(cut)),
                    name: name, isRunOfText: isRun)
            case .shape(let shape):
                return PhotonzDocument.SeparatedPiece(
                    frame: piece.rect,
                    content: .shape(fill: shape.fill, radii: shape.radii,
                                    borderWidth: shape.borderWidth,
                                    borderColor: shape.borderColor),
                    name: name, isRunOfText: isRun)
            }
        }
        _ = document.separateIntoLayers(id: id, patched: store.register(result.background),
                                        pieces: pieces)

        // Every run, read for its words — the pass the app runs in the
        // background once the pieces have landed.
        let refs = document.allLayers.filter { $0.isARunOfText == true }.compactMap(\.imageRef)
        let t0 = Date()
        var words: [ImageRef: String] = [:]
        for ref in refs {
            guard let picture = store.image(for: ref) else { continue }
            words[ref] = TextReader.words(in: picture) ?? ""
        }
        return Taken(document: document, words: words, runs: refs.count,
                     readMS: Date().timeIntervalSince(t0) * 1000)
    }

    private static let settings = takeApart("settings-pane-2x", scale: 2)

    // MARK: - The list

    @Test func everyRowSaysTheWordsInItsPicture() throws {
        let taken = try #require(Self.settings)
        let names = taken.document
            .layerRows(expanded: taken.document.openableGroupIDs, selected: [],
                       readWords: taken.words)
            .map(\.name)
        for words in ["General", "Save Changes", "Launch at login", "Copy to clipboard"] {
            #expect(names.contains(words), "no row says \(words); the list says \(names)")
        }
        // And nothing is left saying the number the command gave it, because
        // every run of this pane reads.
        #expect(!names.contains { $0.hasPrefix("Text ") },
                "some rows still say a number: \(names)")
    }

    @Test func typingAWordYouCanSeeReachesThePieceHoldingIt() throws {
        let taken = try #require(Self.settings)
        let hits = taken.document.layerRows(matching: "save ch", selected: [],
                                            readWords: taken.words)
        #expect(hits.map(\.name) == ["Save Changes"])
        // The word on the canvas, in any case, in any order, the same as every
        // other row: this is the find field's own rule, applying to a picture
        // of words for the first time.
        #expect(taken.document.layerRows(matching: "CHANGES save", selected: [],
                                         readWords: taken.words).count == 1)
    }

    @Test func nothingIsWrittenIntoTheDocument() throws {
        let taken = try #require(Self.settings)
        // The bytes of the document with the words read and without them are
        // the same bytes: the names in the list are worked out as it is drawn.
        // This is what keeps it off the undo stack and out of the file.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let written = try encoder.encode(taken.document)
        let names = taken.document.allLayers.filter { $0.isARunOfText == true }.map(\.name)
        #expect(names.allSatisfy { $0.hasPrefix("Text ") })
        #expect(try encoder.encode(taken.document) == written)
        #expect(String(data: written, encoding: .utf8)?.contains("Save Changes") != true)
    }

    // MARK: - What it costs

    /// What it costs, printed rather than asserted, and only when asked for:
    ///
    /// ```
    /// PHOTONZ_STUDY=1 Scripts/test.sh -c release --filter SeparatedRowsSayTheirWords
    /// ```
    ///
    /// A number off the wall clock means nothing inside an ordinary test run.
    /// The suite reads three captures apart and runs several hundred Vision
    /// passes at once across every core, so these same nine runs came back in
    /// 195 seconds there and 294 milliseconds on their own. Timing belongs in a
    /// run that is not fighting itself.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_STUDY"] == "1"))
    func readingAWholePaneIsQuickEnoughToHappenBehindTheCommand() throws {
        let taken = try #require(Self.settings)
        #expect(taken.runs == 9)
        print("read \(taken.runs) runs for their words in \(Int(taken.readMS)) ms")
        #expect(taken.readMS < 5_000)
    }

    // MARK: - The dense page

    /// A hundred and forty two runs is the case the task was filed about, and
    /// reading them all is a hundred and forty two Vision passes, so it is kept
    /// out of an ordinary test run:
    ///
    /// ```
    /// PHOTONZ_STUDY=1 Scripts/test.sh -c release --filter SeparatedRowsSayTheirWords
    /// ```
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_STUDY"] == "1"))
    func aDensePageComesBackReadable() throws {
        let taken = try #require(Self.takeApart("dense-page-1x", scale: 1))
        let names = taken.document
            .layerRows(expanded: taken.document.openableGroupIDs, selected: [],
                       readWords: taken.words)
            .map(\.name)
        let said = names.filter { !$0.hasPrefix("Text ") && !$0.hasPrefix("Box ") }
        print("""
        ==== dense-page-1x
        runs \(taken.runs) · read for words one after another \(Int(taken.readMS)) ms \
        (\(Int(taken.readMS / Double(max(taken.runs, 1)))) ms each)
        rows that say words rather than a number: \(said.count) of \(names.count)
        \(said.prefix(40).joined(separator: " · "))
        """)
        // The word the task was filed about, plainly on the page and findable.
        #expect(taken.document.layerRows(matching: "recommended", selected: [],
                                         readWords: taken.words).count >= 1)
        #expect(said.count >= taken.runs / 2)
    }
}
