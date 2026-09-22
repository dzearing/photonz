import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// **A component you built is a thing you can put on a timeline**
/// (`components-on-the-timeline-animated-the-way-ever`).
///
/// This is the chain the product argument rests on: a drawing becomes a
/// component, the component goes on a recording's timeline with an in and an
/// out, and it animates with the machinery every other moving thing uses. Not
/// one line of it is a video feature — a placed component is a layer with a
/// `LayerTime` on it, exactly as a title is (`TitleTime.swift`).
struct ComponentOnTheTimelineTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// A document with an eight second recording in it as one clip, plus a
    /// component of two parts waiting on the shelf to be placed.
    private func recordingWithAComponent() -> (PhotonzDocument, UUID) {
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
        return (doc, componentID)
    }

    /// A move written on a part, in the clock of the thing it is on: it starts
    /// `startMS` after the copy carrying it arrives.
    private func slide(_ layer: Layer, startMS: Int, durationMS: Int, byX: CGFloat) -> LayerMotion {
        let origin = layer.frame.origin
        return LayerMotion(property: .position, from: .point(origin),
                           to: .point(CGPoint(x: origin.x + byX, y: origin.y)),
                           timing: MotionTiming(startMS: startMS, durationMS: durationMS),
                           curve: .linear, repeats: .once)
    }


    /// One copy placed at a moment, unwrapped. A mutating call cannot live
    /// inside `#require`, so it happens here and the answer is checked here.
    private func place(_ doc: inout PhotonzDocument, _ componentID: UUID,
                       at point: CGPoint, atMS ms: Int) throws -> UUID {
        let placed = doc.insertComponentInstance(of: componentID, at: point, atTimeMS: ms)
        return try #require(placed)
    }

    // MARK: - It gets a start and an end

    @Test("A component placed on a document with time arrives at the playhead and runs three seconds")
    func aPlacedComponentGetsASpan() throws {
        var (doc, componentID) = recordingWithAComponent()
        let placed = try place(&doc, componentID, at: CGPoint(x: 400, y: 300), atMS: 4000)
        let copy = try #require(doc.layer(id: placed))
        let time = try #require(copy.time)
        #expect(time.inMS == 4000)
        #expect(time.outMS == 7000)
        // It is PLACED, not played: there are no frames behind either end, so
        // both ends are free and none of the media rows are offered for it.
        #expect(copy.isPlacedInTime)
        #expect(copy.startIsFree)
    }

    @Test("A component placed in a document with no time in it is untouched")
    func aScreenshotIsUnchanged() throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        doc.addLayer(box("Dot", CGRect(x: 10, y: 10, width: 40, height: 40)))
        let grouped = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Badge")
        let group = try #require(grouped)
        let made = doc.makeComponent(id: group.id)
        let componentID = try #require(made)
        let placed = try place(&doc, componentID, at: CGPoint(x: 200, y: 150), atMS: 0)
        #expect(doc.layer(id: placed)?.time == nil)
        #expect(!doc.hasTime)
    }

    @Test("It is off screen before it arrives and after it goes")
    func itIsOnlyThereWhileItIsThere() throws {
        var (doc, componentID) = recordingWithAComponent()
        let placed = try place(&doc, componentID, at: CGPoint(x: 400, y: 300), atMS: 4000)
        #expect(doc.drawn(atTimeMS: 2000).layer(id: placed)?.isVisible == false)
        #expect(doc.drawn(atTimeMS: 5000).layer(id: placed)?.isVisible == true)
        #expect(doc.drawn(atTimeMS: 7500).layer(id: placed)?.isVisible == false)
    }

    @Test("Both ends move on the timeline, the way a title's do")
    func bothEndsMove() throws {
        var (doc, componentID) = recordingWithAComponent()
        let placed = try place(&doc, componentID, at: CGPoint(x: 400, y: 300), atMS: 4000)
        let movedEnd = doc.moveLayerEnd(placed, toMS: 8000)
        let movedStart = doc.moveLayerStart(placed, toMS: 3000)
        #expect(movedEnd)
        #expect(movedStart)
        let time = try #require(doc.layer(id: placed)?.time)
        #expect(time.inMS == 3000 && time.outMS == 8000)
    }

    // MARK: - It keeps its link to the original

    @Test("Editing the original changes what is on the timeline, and leaves its in and out alone")
    func theOriginalStillDrivesIt() throws {
        var (doc, componentID) = recordingWithAComponent()
        let placed = try place(&doc, componentID, at: CGPoint(x: 400, y: 300), atMS: 4000)
        #expect(doc.layer(id: placed)?.instanceOf == componentID)
        let main = try #require(doc.mainComponent(componentID: componentID))
        let part = try #require(main.children.first).id
        doc.updateLayer(id: part) { $0.name = "Spot" }
        doc.syncComponentInstances()
        #expect(doc.layer(id: placed)?.children.first?.name == "Spot")
        // ...and where it sits in time is the copy's own business, untouched.
        #expect(doc.layer(id: placed)?.time?.inMS == 4000)
    }

    // MARK: - It animates with the same machinery

    @Test("Two parts of one placed component move out of phase")
    func twoPartsOutOfPhase() throws {
        var (doc, componentID) = recordingWithAComponent()
        let main = try #require(doc.mainComponent(componentID: componentID))
        let dot = try #require(main.children.first)
        let bar = try #require(main.children.last)
        doc.updateLayer(id: dot.id) { $0.motions = [self.slide(dot, startMS: 0, durationMS: 1000, byX: 100)] }
        doc.updateLayer(id: bar.id) { $0.motions = [self.slide(bar, startMS: 1000, durationMS: 1000, byX: 100)] }
        let placed = try place(&doc, componentID, at: CGPoint(x: 400, y: 300), atMS: 4000)
        func parts(atMS ms: Int) throws -> (dot: CGFloat, bar: CGFloat) {
            let copy = try #require(doc.drawn(atTimeMS: ms).layer(id: placed))
            return (copy.children[0].frame.origin.x, copy.children[1].frame.origin.x)
        }
        let arrives = try parts(atMS: 4000)
        // A whole second after the copy arrives the first part has finished
        // its move and the second has not started: out of phase, which is the
        // test the animation model was chosen against.
        let atOne = try parts(atMS: 4990)
        #expect(atOne.dot > arrives.dot + 50)
        #expect(atOne.bar == arrives.bar)
        // ...and a second later the second part has moved and the first is
        // where it finished.
        let atTwo = try parts(atMS: 5990)
        #expect(atTwo.bar > atOne.bar + 50)
        // ...and the first part is done moving and stays where it finished.
        #expect(atTwo.dot == arrives.dot + 100)
    }

    @Test("A motion on a placed component is measured from the moment it arrives")
    func itsClockStartsWhenItArrives() throws {
        var (doc, componentID) = recordingWithAComponent()
        let placed = try place(&doc, componentID, at: CGPoint(x: 400, y: 300), atMS: 4000)
        let copy = try #require(doc.layer(id: placed))
        doc.updateLayer(id: placed) { $0.motions = [self.slide(copy, startMS: 0, durationMS: 1000, byX: 100)] }
        let start = try #require(doc.drawn(atTimeMS: 4000).layer(id: placed)).frame.origin.x
        let done = try #require(doc.drawn(atTimeMS: 4990).layer(id: placed)).frame.origin.x
        #expect(done - start > 50)
    }

    @Test("A motion written on the original reaches every copy, at each copy's own moment")
    func theSameComponentAnimatesWhereverItIsPlaced() throws {
        var (doc, componentID) = recordingWithAComponent()
        let main = try #require(doc.mainComponent(componentID: componentID))
        let dot = try #require(main.children.first)
        doc.updateLayer(id: dot.id) { $0.motions = [self.slide(dot, startMS: 0, durationMS: 1000, byX: 100)] }
        let first = try place(&doc, componentID, at: CGPoint(x: 200, y: 300), atMS: 1000)
        let second = try place(&doc, componentID, at: CGPoint(x: 600, y: 300), atMS: 5000)
        func dotX(_ id: UUID, atMS ms: Int) throws -> CGFloat {
            try #require(doc.drawn(atTimeMS: ms).layer(id: id)).children[0].frame.origin.x
        }
        #expect(try dotX(first, atMS: 1990) > dotX(first, atMS: 1000) + 50)
        #expect(try dotX(second, atMS: 5990) > dotX(second, atMS: 5000) + 50)
        // The second copy has not started moving at four seconds, when the
        // first finished three seconds ago: each copy's clock starts where
        // the copy does.
        #expect(try dotX(second, atMS: 4000) == dotX(second, atMS: 5000))
        #expect(try dotX(first, atMS: 4000) == dotX(first, atMS: 3000))
    }

    @Test("A motion on a part of the original survives a sync")
    func aMotionOnAPartFollowsTheCopy() throws {
        var (doc, componentID) = recordingWithAComponent()
        let main = try #require(doc.mainComponent(componentID: componentID))
        let dot = try #require(main.children.first)
        doc.updateLayer(id: dot.id) { $0.motions = [self.slide(dot, startMS: 0, durationMS: 1000, byX: 100)] }
        let placed = try place(&doc, componentID, at: CGPoint(x: 400, y: 300), atMS: 4000)
        doc.syncComponentInstances()
        #expect(doc.layer(id: placed)?.children.first?.motions?.isEmpty == false)
    }

    @Test("A motion on the copy itself survives an edit to the original")
    func theCopysOwnMotionIsItsOwn() throws {
        var (doc, componentID) = recordingWithAComponent()
        let placed = try place(&doc, componentID, at: CGPoint(x: 400, y: 300), atMS: 4000)
        let copy = try #require(doc.layer(id: placed))
        doc.updateLayer(id: placed) { $0.motions = [self.slide(copy, startMS: 0, durationMS: 1000, byX: 100)] }
        let main = try #require(doc.mainComponent(componentID: componentID))
        doc.updateLayer(id: try #require(main.children.first).id) { $0.name = "Spot" }
        doc.syncComponentInstances()
        #expect(doc.layer(id: placed)?.motions?.count == 1)
        #expect(doc.layer(id: placed)?.time?.inMS == 4000)
    }

    // MARK: - Its lanes are drawn where they happen

    @Test("A moving part of a placed component gets its lane where it actually happens")
    func aPartsLaneIsDrawnWhereItHappens() throws {
        var (doc, componentID) = recordingWithAComponent()
        let main = try #require(doc.mainComponent(componentID: componentID))
        let dot = try #require(main.children.first)
        doc.updateLayer(id: dot.id) { $0.motions = [self.slide(dot, startMS: 0, durationMS: 1000, byX: 100)] }
        // The original off the canvas, so the only lanes left are the copy's.
        doc.updateLayer(id: main.id) { $0.isVisible = false }
        let placed = try place(&doc, componentID, at: CGPoint(x: 400, y: 300), atMS: 4000)
        let strip = doc.motionStrip()
        let lane = try #require(strip.flatMap(\.lanes).first { lane in
            doc.layer(id: placed)?.children.contains { $0.id == lane.layerID } == true
        })
        // The part moves as the copy arrives, so its lane starts at four
        // seconds. Drawn at nought it would say the badge moves before it is
        // even on screen.
        #expect(lane.timing.startMS == 4000)
    }
}
