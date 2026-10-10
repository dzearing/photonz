import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Titles already placed in a document open looking exactly as they did
/// (task `titles-move-in-parts-not-as-one-block`).
///
/// The fixture is a document holding all eight built-in titles as they were
/// inserted BEFORE titles moved in parts (one block, Animate In and Out keys or
/// the bar's own fade), with a fingerprint of every layer as drawn at moments
/// across each one's in, hold and out. Rebuilding the presets must never touch
/// a title somebody already placed: it is keys on their layers, and those keys
/// have to keep drawing what they drew.
///
/// The fixture was written once, from the code as it stood, with
/// `PHOTONZ_WRITE_TITLE_FIXTURE=1 Scripts/test.sh --filter PlacedTitlesOpenTheSameTests`.
@Suite("Titles already placed open the same")
struct PlacedTitlesOpenTheSameTests {

    struct Fixture: Codable {
        var document: PhotonzDocument
        /// Moment of the document to a fingerprint of everything drawn then.
        var drawn: [String: String]
    }

    static let fixtureName = "placed-titles-before-parts"

    static var writeURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixtureName).json")
    }

    /// Every built-in title, one after the other, each on its own track.
    static func placedTitles() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 720))
        doc.durationMS = 1000
        for (index, preset) in BuiltInTitle.allCases.enumerated() {
            doc.insertTitle(preset, atTimeMS: index * 6000)
        }
        return doc
    }

    static func moments(_ doc: PhotonzDocument) -> [Int] {
        var out: [Int] = []
        for layer in doc.layers {
            guard let time = layer.time else { continue }
            let marks = [0, 100, 200, 250, 300, 400, 500, 750, time.lengthMS / 2,
                         time.lengthMS - 500, time.lengthMS - 300, time.lengthMS - 100, time.lengthMS - 1]
            out += marks.map { time.inMS + $0 }
        }
        return out
    }

    /// FNV-1a over the sorted JSON of everything drawn: a change anywhere,
    /// however small, reads as a different fingerprint.
    static func fingerprint(_ doc: PhotonzDocument, atMS ms: Int) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(doc.drawn(atTimeMS: ms).layers)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    @Test("Every title placed before titles moved in parts draws exactly what it drew")
    func placedTitlesDrawWhatTheyDrew() throws {
        if ProcessInfo.processInfo.environment["PHOTONZ_WRITE_TITLE_FIXTURE"] == "1" {
            // Fingerprinted as it reads back from disk, which is what opening it does.
            let doc = try JSONDecoder().decode(PhotonzDocument.self,
                                               from: JSONEncoder().encode(Self.placedTitles()))
            var drawn: [String: String] = [:]
            for ms in Self.moments(doc) { drawn[String(ms)] = try Self.fingerprint(doc, atMS: ms) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Fixture(document: doc, drawn: drawn)).write(to: Self.writeURL)
            return
        }
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(Self.fixtureName)",
                                                 withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        #expect(fixture.drawn.count >= 8 * 10)
        for (moment, expected) in fixture.drawn {
            let ms = try #require(Int(moment))
            #expect(try Self.fingerprint(fixture.document, atMS: ms) == expected, "at \(ms) ms")
        }
    }
}
