import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **A clip nobody can see is not read while it plays** (`MovieFramesSeen.swift`).
@Suite("The frames a playing clock reads are the ones that are seen")
struct MovieFramesSeenTests {

    static let size = CGSize(width: 1600, height: 1000)
    static let movie = MovieRef(pixelSize: size, durationMS: 20_000, hasSound: false)

    static func clip(_ name: String, from: Int = 0, to: Int = 10_000,
                     frame: CGRect = CGRect(origin: .zero, size: size)) -> Layer {
        var layer = Layer(name: name, content: .image(movie.frameRef(atSourceMS: 0)), frame: frame)
        layer.movie = movie
        layer.time = LayerTime(inMS: from, outMS: to, sourceInMS: 0, sourceLengthMS: movie.durationMS)
        return layer
    }

    static func document(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: size, layers: layers)
        doc.durationMS = 10_000
        return doc
    }

    @Test("A clip filling the frame hides every one under it, while it is on")
    func covered() {
        let under = Self.clip("under"), over = Self.clip("over", from: 2000, to: 4000)
        let corner = Self.clip("corner", frame: CGRect(x: 20, y: 20, width: 300, height: 200))
        let doc = Self.document([under, over, corner])
        #expect(doc.movieFramesSeen(atTimeMS: 3000).map(\.layerID) == [over.id, corner.id])
        #expect(doc.movieFramesSeen(atTimeMS: 1000).map(\.layerID) == [under.id, corner.id])
        #expect(doc.movieFrames(atTimeMS: 3000).count == 3)
    }

    @Test("Anything that lets the clip under it show keeps it read")
    func seenThrough() {
        let under = Self.clip("under")
        var changes: [(inout Layer) -> Void] = []
        changes.append { $0.style.opacity = 0.9 }
        changes.append { $0.style.cornerRadius = 12 }
        changes.append { $0.style.blendMode = .multiply }
        changes.append { $0.frame.size.width -= 1 }
        changes.append { $0.crop = CGRect(x: 0, y: 0, width: 800, height: 500) }
        changes.append { $0.transform.rotation = 0.1 }
        changes.append { $0.isVisible = false }
        for (n, change) in changes.enumerated() {
            var over = Self.clip("over")
            change(&over)
            let seen = Self.document([under, over]).movieFramesSeen(atTimeMS: 3000)
            #expect(seen.contains { $0.layerID == under.id }, "change \(n)")
        }
        var faded = Self.document([under, Self.clip("over")])
        _ = faded.fadePicture(faded.layers[1].id, .in, toMS: 400)
        #expect(faded.movieFramesSeen(atTimeMS: 100).count == 2)
    }

    @Test("A clip on a track switched off is not read")
    func offTrack() {
        let under = Self.clip("under")
        var over = Self.clip("over", frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        var doc = Self.document([])
        let track = doc.addTrack(.video), other = doc.addTrack(.video)
        var low = under
        low.trackID = track
        over.trackID = other
        doc.layers = [low, over]
        #expect(doc.movieFramesSeen(atTimeMS: 1000).count == 2)
        if let index = doc.tracks.firstIndex(where: { $0.id == other }) { doc.tracks[index].isHidden = true }
        #expect(doc.movieFramesSeen(atTimeMS: 1000).map(\.layerID) == [low.id])
    }

    @Test("Looking ahead, a clip coming out from under another is a stretch coming on")
    func comesOut() {
        let under = Self.clip("under")
        var over = Self.clip("over", from: 0, to: 2000)
        over.time = LayerTime(inMS: 0, outMS: 2000, sourceInMS: 15_000, sourceLengthMS: Self.movie.durationMS)
        let points = Self.document([under, over]).moviePlayPoints(atTimeMS: 1500)
        #expect(points.now.map(\.layerID) == [over.id])
        #expect(points.coming.map(\.layerID) == [under.id])
    }
}
