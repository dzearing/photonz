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

    /// What a moment needs, worked out the long way: every layer gone through.
    static func slowly(_ doc: PhotonzDocument, atTimeMS ms: Int) -> (all: [MovieFrameRequest], seen: [MovieFrameRequest]) {
        let moment = min(max(0, ms), doc.lastDrawableTimeMS)
        var all: [MovieFrameRequest] = []
        doc.forEachLayer { all += $0.movieFrameRequests(atTimeMS: moment) }
        for layer in doc.layers where layer.merged != nil {
            all += layer.mergedFrameRequests(atTimeMS: moment, canvasSize: doc.canvasSize, pixelScale: doc.pixelScale)
        }
        if doc.hasEditPointTransitions { all += doc.editPointFrameRequests(atMS: moment) }
        let off = doc.layersOffScreenByTrack()
        var hidden = Set<UUID>()
        func hide(_ layer: Layer) {
            for inside in layer.selfAndDescendants {
                hidden.insert(inside.id)
                hidden.insert(Layer.transitionPartnerID(of: inside.id))
            }
        }
        for layer in doc.layers where off.contains(layer.id) { hide(layer) }
        if doc.camera == nil, let cover = doc.layers.lastIndex(where: {
            !off.contains($0.id) && doc.fillsTheFrame($0, atTimeMS: moment)
        }) {
            let changing = Set(doc.editPointMoments(atMS: moment).flatMap { [$0.onScreen, $0.borrowed] })
            if !changing.contains(doc.layers[cover].id) { for layer in doc.layers[..<cover] { hide(layer) } }
        }
        return (all, all.count > 1 ? all.filter { !hidden.contains($0.layerID) } : all)
    }

    @Test("What a moment needs is what going through every layer says, all along the wide edit")
    func matchesTheLongWay() {
        var doc = ReferenceWideEditTests.fifty
        for step in 0..<2 {
            if step == 1, let track = doc.tracks.lastIndex(where: { $0.kind == .video }) {
                doc.tracks[track].isHidden = true
                doc.layers.append(Self.clip("cover", from: 10_000, to: 40_000,
                                            frame: CGRect(origin: .zero, size: doc.canvasSize)))
            }
            for ms in stride(from: 0, through: ReferenceEdit.wideLengthMS, by: 370) {
                let slow = Self.slowly(doc, atTimeMS: ms)
                #expect(doc.movieFrames(atTimeMS: ms) == slow.all, "\(ms)")
                #expect(doc.movieFramesSeen(atTimeMS: ms) == slow.seen, "\(ms)")
            }
        }
    }

    @Test("A recording inside a group is read whatever the group's own time says")
    func insideAGroup() {
        let inner = Self.clip("inner", from: 0, to: 9000, frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        var group = Layer(name: "group", content: .group(GroupContent(children: [inner])),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        group.time = LayerTime(inMS: 5000, outMS: 8000)
        let doc = Self.document([group])
        for ms in [0, 4000, 6000, 8500, 9500] {
            #expect(doc.movieFrames(atTimeMS: ms) == Self.slowly(doc, atTimeMS: ms).all)
        }
    }

    @Test("A clip moved, and a merge made, are known at once")
    func planFollowsTheLayers() {
        var doc = Self.document([Self.clip("one", from: 0, to: 2000)])
        #expect(doc.movieFrames(atTimeMS: 5000).isEmpty)
        doc.layers[0].time = LayerTime(inMS: 4000, outMS: 6000, sourceInMS: 0, sourceLengthMS: 20_000)
        #expect(doc.movieFrames(atTimeMS: 5000).count == 1)
        #expect(!doc.hasMergedClips)
    }
}
