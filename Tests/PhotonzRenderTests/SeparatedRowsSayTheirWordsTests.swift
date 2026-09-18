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
        /// The bitmaps the document points at, so the package can be written
        /// the way the app writes one.
        let store: ImageStore
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
                     readMS: Date().timeIntervalSince(t0) * 1000, store: store)
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

    @Test func nothingIsWrittenOntoTheCanvas() throws {
        let taken = try #require(Self.settings)
        // No layer is renamed and no layer becomes text. The names in the list
        // are worked out as it is drawn, from what was read, which is what
        // keeps the reading off the undo stack.
        let runs = taken.document.allLayers.filter { $0.isARunOfText == true }
        #expect(runs.allSatisfy { $0.name.hasPrefix("Text ") })
        #expect(runs.allSatisfy { $0.text == nil })
    }

    /// What the reading found IS written into the document, and comes back
    /// with it: that is the whole of `ReadWords`.
    @Test func whatTheReadingFoundIsSavedWithTheFileAndOpensWithIt() throws {
        let taken = try #require(Self.settings)
        var document = taken.document
        document.readWords.remember(taken.words.map { ($0.key, $0.value) })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let written = try encoder.encode(document)
        let opened = try JSONDecoder().decode(PhotonzDocument.self, from: written)
        #expect(opened == document)

        // The words a person can see on the pane are in the file, against the
        // bitmaps they were read off, and the list built from the OPENED
        // document says them with no reading having happened.
        let names = opened
            .layerRows(expanded: opened.openableGroupIDs, selected: [],
                       readWords: opened.readWords.byPicture)
            .map(\.name)
        #expect(names.contains("Save Changes"))
        #expect(!names.contains { $0.hasPrefix("Text ") })
    }

    /// The point of saving it: opening the file leaves nothing to read.
    @Test func openingASavedReadingLeavesNothingPending() throws {
        let taken = try #require(Self.settings)
        var document = taken.document
        document.readWords.remember(taken.words.map { ($0.key, $0.value) })
        let opened = try JSONDecoder().decode(
            PhotonzDocument.self, from: JSONEncoder().encode(document))

        // Exactly the question `EditorState.readWordsOffRuns` asks before it
        // starts a pass: which runs has nothing been read off yet.
        func pending(_ doc: PhotonzDocument) -> [ImageRef] {
            doc.allLayers
                .filter { $0.isARunOfText == true }
                .compactMap(\.imageRef)
                .filter { !doc.readWords.hasBeenRead($0) }
        }
        #expect(pending(taken.document).count == taken.runs)
        #expect(pending(opened).isEmpty)

        // ...and a run that arrives afterwards is read like any other: nothing
        // about the saved reading covers a picture it has never seen.
        var withANewRun = opened
        let fresh = ImageRef(pixelSize: CGSize(width: 40, height: 12))
        var layer = Layer(name: "Text 99", content: .image(fresh),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 12))
        layer.isARunOfText = true
        withANewRun.layers.append(layer)
        #expect(pending(withANewRun) == [fresh])
    }

    // MARK: - The real save path

    /// Written and opened the way the app writes and opens a file: a .photonz
    /// package, with the bitmaps encoded as HEIC beside the model.
    @Test func aSavedPackageOpensWithItsRowsAlreadySayingTheirWords() throws {
        let taken = try #require(Self.settings)
        var document = taken.document
        document.readWords.remember(taken.words.map { ($0.key, $0.value) })

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("read-words-\(UUID().uuidString).photonz")
        defer { try? FileManager.default.removeItem(at: url) }
        try PackageIO.write(document, store: taken.store, to: url)

        // A new store, the way a new window opens a file: nothing in memory
        // knows anything about these pictures.
        let opened = try PackageIO.read(from: url, into: ImageStore())
        #expect(opened.readWords.count == taken.words.count)
        let names = opened
            .layerRows(expanded: opened.openableGroupIDs, selected: [],
                       readWords: opened.readWords.byPicture)
            .map(\.name)
        #expect(names.contains("Save Changes"))
        #expect(!names.contains { $0.hasPrefix("Text ") })
    }

    /// Whether a second reading would have said the same thing.
    ///
    /// This is the half of the case for saving the reading that could only be
    /// answered by trying it: the bitmaps in a package are HEIC, so the pixels
    /// a reopened file hands the reader are NOT the pixels the first reading
    /// saw. Printed rather than asserted, because it is a fact about Vision on
    /// this machine rather than a rule the app enforces:
    ///
    /// ```
    /// PHOTONZ_STUDY=1 Scripts/test.sh -c release --filter SeparatedRowsSayTheirWords
    /// ```
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_STUDY"] == "1"))
    func aSecondReadingOfTheSavedPicturesNeedNotAgreeWithTheFirst() throws {
        for (name, scale) in [("settings-pane-2x", CGFloat(2)), ("dense-page-1x", CGFloat(1))] {
            guard let taken = Self.takeApart(name, scale: scale) else { continue }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("read-words-\(UUID().uuidString).photonz")
            defer { try? FileManager.default.removeItem(at: url) }
            var document = taken.document
            document.readWords.remember(taken.words.map { ($0.key, $0.value) })
            try PackageIO.write(document, store: taken.store, to: url)
            let store = ImageStore()
            let opened = try PackageIO.read(from: url, into: store)

            // What carrying the reading costs on disk, against what the file
            // weighs anyway.
            func bytes(_ at: URL) -> Int {
                (try? FileManager.default.attributesOfItem(atPath: at.path)[.size] as? Int) as? Int ?? 0
            }
            let modelWith = bytes(url.appendingPathComponent("document.json"))
            let bare = FileManager.default.temporaryDirectory
                .appendingPathComponent("read-words-bare-\(UUID().uuidString).photonz")
            defer { try? FileManager.default.removeItem(at: bare) }
            try PackageIO.write(taken.document, store: taken.store, to: bare)
            let modelWithout = bytes(bare.appendingPathComponent("document.json"))
            let pictures = (try? FileManager.default
                .contentsOfDirectory(at: url.appendingPathComponent("images"),
                                     includingPropertiesForKeys: nil))?
                .reduce(0) { $0 + bytes($1) } ?? 0

            let t0 = Date()
            var differed: [(String, String)] = []
            for (ref, first) in taken.words {
                guard let picture = store.image(for: ref) else { continue }
                let again = TextReader.words(in: picture) ?? ""
                if again != first { differed.append((first, again)) }
            }
            let ms = Date().timeIntervalSince(t0) * 1000
            print("""
            ==== \(name): reading it again after a save
            \(taken.words.count) runs, read again in \(Int(ms)) ms — which is what \
            opening this file used to cost, every time
            \(differed.count) of them came back saying something different
            \(differed.prefix(8).map { "\"\($0.0)\" -> \"\($0.1)\"" }.joined(separator: " · "))
            the file: model \(modelWithout / 1024) KB without the reading, \
            \(modelWith / 1024) KB with it, beside \(pictures / 1024) KB of pictures
            """)
        }
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
