import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// **A component let go over the timeline lands where it was let go**
/// (`a-library-component-dropped-on-the-timeline-land`,
/// `video-title-wt.html` step 10: the lower third dragged onto the Title track).
///
/// The landing is the one a title tile takes (`titleLanding`): the track under
/// the pointer when it is free, otherwise a new track of its own, so a drop
/// never covers or cuts the recording.
struct ComponentTimelineDropTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// An eight second recording on V1, an empty V2 above it, and a component
    /// waiting on the shelf.
    private func recordingWithAComponent() -> (doc: PhotonzDocument, component: UUID, v1: UUID, v2: UUID) {
        let canvas = CGSize(width: 800, height: 600)
        let movie = MovieRef(pixelSize: canvas, durationMS: 8000)
        var clip = Layer(name: "Recording", content: .image(movie.frameRef(atSourceMS: 0)),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.movie = movie
        clip.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        var doc = PhotonzDocument(canvasSize: canvas, layers: [clip])
        doc.durationMS = 8000
        doc.addLayer(box("Dot", CGRect(x: 10, y: 10, width: 40, height: 40)))
        doc.addLayer(box("Bar", CGRect(x: 60, y: 10, width: 80, height: 40)))
        let parts = Set(doc.layers.suffix(2).map(\.id))
        let group = doc.groupLayers(ids: parts, name: "Badge")!
        let componentID = doc.makeComponent(id: group.id)!
        let v1 = doc.addTrack(.video, at: 0)
        doc.updateLayer(id: clip.id) { $0.trackID = v1 }
        let v2 = doc.addTrack(.video, at: 0)
        return (doc, componentID, v1, v2)
    }

    /// Places a copy the way the timeline does: in the picture with no time of
    /// its own, then landed, in one edit.
    private func drop(_ doc: inout PhotonzDocument, _ componentID: UUID,
                      _ landing: ClipLanding) throws -> UUID {
        let placed = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300),
                                                 atTimeMS: nil)
        let id = try #require(placed)
        let landed = doc.landPlacedLayer(id, at: landing)
        #expect(landed)
        return id
    }

    @Test func aCopyLetGoOverAFreeTrackLandsOnItAtThatMoment() throws {
        var (doc, componentID, v1, v2) = recordingWithAComponent()
        let landing = doc.titleLanding(lengthMS: TitleTime.defaultLengthMS, atMS: 5000, over: .onto(v2))
        let id = try drop(&doc, componentID, landing)
        #expect(doc.trackID(ofClip: id) == v2)
        let time = try #require(doc.layer(id: id)?.time)
        #expect(time.inMS == 5000)
        #expect(time.outMS == 5000 + TitleTime.defaultLengthMS)
        // It is still a copy of the component, following it.
        #expect(doc.layer(id: id)?.instanceOf == componentID)
        // The recording is untouched.
        #expect(doc.clipIDs(onTrack: v1).count == 1)
        #expect(doc.layers.first { $0.name == "Recording" }?.time?.outMS == 8000)
    }

    @Test func aCopyLetGoOverTheRecordingGetsATrackOfItsOwn() throws {
        var (doc, componentID, v1, _) = recordingWithAComponent()
        let before = doc.timelineTracks.count
        let landing = doc.titleLanding(lengthMS: TitleTime.defaultLengthMS, atMS: 2000, over: .onto(v1))
        let id = try drop(&doc, componentID, landing)
        #expect(doc.timelineTracks.count == before + 1)
        let track = try #require(doc.trackID(ofClip: id))
        #expect(track != v1)
        #expect(doc.timelineTracks.first { $0.id == track }?.name == landing.trackName)
        #expect(doc.layer(id: id)?.time?.inMS == 2000)
        #expect(doc.clipIDs(onTrack: v1).count == 1)
        #expect(doc.layers.first { $0.name == "Recording" }?.time?.inMS == 0)
    }

    @Test func aStarterLandsTheSameWay() throws {
        var (doc, _, _, v2) = recordingWithAComponent()
        let landing = doc.titleLanding(lengthMS: TitleTime.defaultLengthMS, atMS: 1000, over: .onto(v2))
        let placed = doc.insertStarterComponent(.badge, at: CGPoint(x: 400, y: 300), atTimeMS: nil)
        let id = try #require(placed)
        let landed = doc.landPlacedLayer(id, at: landing)
        #expect(landed)
        #expect(doc.trackID(ofClip: id) == v2)
        #expect(doc.layer(id: id)?.time?.inMS == 1000)
        // The original it follows came in too, off the canvas.
        #expect(doc.mainComponent(componentID: StarterComponent.badge.componentID) != nil)
    }

    @Test func aRefusedLandingLeavesTheLayerAsItWas() throws {
        var (doc, componentID, _, v2) = recordingWithAComponent()
        var landing = doc.titleLanding(lengthMS: TitleTime.defaultLengthMS, atMS: 1000, over: .onto(v2))
        landing.allowed = false
        let placed = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300),
                                                 atTimeMS: nil)
        let id = try #require(placed)
        let before = doc
        let landed = doc.landPlacedLayer(id, at: landing)
        #expect(!landed)
        #expect(doc == before)
    }

    @Test func aLayerInsideAGroupIsNeverLanded() throws {
        var (doc, componentID, _, v2) = recordingWithAComponent()
        let landing = doc.titleLanding(lengthMS: TitleTime.defaultLengthMS, atMS: 1000, over: .onto(v2))
        let main = try #require(doc.mainComponent(componentID: componentID))
        let part = try #require(main.children.first?.id)
        let before = doc
        let landed = doc.landPlacedLayer(part, at: landing)
        #expect(!landed)
        #expect(doc == before)
    }

    @Test func theRecordingItselfIsNeverMovedByIt() throws {
        var (doc, _, v1, v2) = recordingWithAComponent()
        let clip = try #require(doc.clipIDs(onTrack: v1).first)
        let landing = doc.titleLanding(lengthMS: TitleTime.defaultLengthMS, atMS: 1000, over: .onto(v2))
        let before = doc
        let landed = doc.landPlacedLayer(clip, at: landing)
        #expect(!landed)
        #expect(doc == before)
    }
}
