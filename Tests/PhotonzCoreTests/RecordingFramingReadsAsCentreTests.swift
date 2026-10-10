import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A recording's framing reads as Scale then Centre (task
/// `a-recording-s-framing-reads-as-scale-then-centre`).
///
/// The zoom walkthrough (`video-zoom-wt.html`, step 6) names a clip's framing
/// Centre, lists it under Scale, and prints the point of the recording that
/// sits in the middle of the frame. The value underneath is still the clip's
/// Position: only what the row and the lane call it, where they sit, and the
/// numbers they show change. Titles, shapes and pictures keep Position.
@Suite("A recording's framing reads as Scale then Centre")
struct RecordingFramingReadsAsCentreTests {

    /// The walkthrough's punch-in: Scale 100% at 0:03 and 220% at 0:05, then
    /// the picture dragged at 0:05 by `by`, which keys Position at both.
    static func framed(by: CGPoint = CGPoint(x: -300, y: -200)) -> (PhotonzDocument, UUID) {
        var (document, id) = ZoomedClipDragKeysCentreTests.zoomed()
        ZoomedClipDragKeysCentreTests.drag(&document, id, atMS: 5000, by: by)
        return (document, id)
    }

    static func title() -> Layer {
        var layer = Layer(name: "Lift off",
                          content: .text(TextContent(string: "Lift off")),
                          frame: CGRect(x: 100, y: 100, width: 300, height: 80))
        layer.time = LayerTime(inMS: 0, outMS: 6000)
        return layer
    }

    @Test("A recording's Position row is called Centre; a title's stays Position")
    func theRowIsCalledCentre() throws {
        let (document, id) = Self.framed()
        let clip = try #require(document.layer(id: id))
        #expect(KeyedProperty.motion(.position).title(on: clip) == "Centre")
        #expect(KeyedProperty.motion(.position).title(on: Self.title()) == "Position")
        #expect(KeyedProperty.motion(.scale).title(on: clip) == "Scale")
    }

    @Test("A recording lists Scale before Centre; a title keeps Position first")
    func scaleComesFirst() throws {
        let (document, id) = Self.framed()
        let clip = try #require(document.layer(id: id))
        let order = clip.keyableProperties.prefix(2)
        #expect(Array(order) == [.motion(.scale), .motion(.position)])
        let titleOrder = Self.title().keyableProperties.prefix(2)
        #expect(Array(titleOrder) == [.motion(.position), .motion(.scale)])
    }

    @Test("The lanes run Scale, then a lane called Centre under it")
    func lanesRunScaleThenCentre() {
        let (document, id) = Self.framed()
        let lanes = document.keyLanes(layerID: id)
        #expect(lanes.map(\.property) == [.scale, .position])
        #expect(lanes.map(\.title) == ["Scale", "Centre"])
        #expect(lanes.map(\.keys.count) == [2, 2])
    }

    @Test("A title's lanes keep Position above Scale")
    func titleLanesKeepPositionFirst() throws {
        var document = ClipReframeTests.document(Self.title())
        let id = try #require(document.layers.first?.id)
        document.setKeyedValue(.number(100), layerID: id, .motion(.scale), atDocumentTimeMS: 1000)
        document.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 1000)
        #expect(document.keyLanes(layerID: id).map(\.title) == ["Position", "Scale"])
    }

    @Test("The row shows the point of the recording in the middle of the frame")
    func theRowShowsTheCentre() throws {
        let (document, id) = Self.framed()
        let frame = try #require(document.layer(id: id)?.frame)
        // Wide at 0:03: the middle of the recording is in the middle.
        #expect(document.panelValue(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
                == .point(CGPoint(x: frame.midX, y: frame.midY)))
        // At 0:05, 220% and dragged up and left by (300, 200): the middle of
        // the frame shows a point (300, 200)/2.2 right of and below the middle.
        guard case let .point(centre)? = document.panelValue(layerID: id, .motion(.position),
                                                              atDocumentTimeMS: 5000) else {
            Issue.record("no centre at 0:05")
            return
        }
        #expect(abs(centre.x - (frame.midX + 300 / 2.2)) < 0.001)
        #expect(abs(centre.y - (frame.midY + 200 / 2.2)) < 0.001)
        // That point is where the canvas really shows it.
        let shown = try #require(ClipReframeTests.onScreen(centre, of: id, in: document, atMS: 5000))
        #expect(abs(shown.x - frame.midX) < 0.01)
        #expect(abs(shown.y - frame.midY) < 0.01)
    }

    @Test("Typing a centre moves the framing so that point is in the middle")
    func typingACentreMovesTheFraming() throws {
        var (document, id) = Self.framed()
        let frame = try #require(document.layer(id: id)?.frame)
        let wanted = CGPoint(x: 900, y: 500)
        let typed = document.setPanelValue(.point(wanted), layerID: id, .motion(.position),
                                           atDocumentTimeMS: 5000)
        #expect(typed)
        #expect(document.panelValue(layerID: id, .motion(.position), atDocumentTimeMS: 5000)
                == .point(wanted))
        let shown = try #require(ClipReframeTests.onScreen(wanted, of: id, in: document, atMS: 5000))
        #expect(abs(shown.x - frame.midX) < 0.01)
        #expect(abs(shown.y - frame.midY) < 0.01)
        // Still a key at 0:05, not a new one; the wide shot at 0:03 untouched.
        #expect(document.keyCount(layerID: id, .motion(.position)) == 2)
        #expect(document.panelValue(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
                == .point(CGPoint(x: frame.midX, y: frame.midY)))
    }

    @Test("A Centre key on the lane reads the centre, not the corner")
    func laneKeysReadTheCentre() throws {
        let (document, id) = Self.framed()
        let frame = try #require(document.layer(id: id)?.frame)
        let centre = try #require(document.keyLanes(layerID: id).first { $0.property == .position })
        #expect(centre.keys.first?.reading
                == MotionProperty.position.format(.point(CGPoint(x: frame.midX, y: frame.midY))))
        guard case let .point(tight)? = document.panelValue(layerID: id, .motion(.position),
                                                             atDocumentTimeMS: 5000) else {
            Issue.record("no centre at 0:05")
            return
        }
        #expect(centre.keys.last?.reading == MotionProperty.position.format(.point(tight)))
    }

    @Test("A title's row and value are its Position, untouched")
    func aTitleKeepsItsPosition() throws {
        var document = ClipReframeTests.document(Self.title())
        let id = try #require(document.layers.first?.id)
        document.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 1000)
        let corner = document.keyedValue(layerID: id, .motion(.position), atDocumentTimeMS: 1000)
        #expect(document.panelValue(layerID: id, .motion(.position), atDocumentTimeMS: 1000) == corner)
        let typed = document.setPanelValue(.point(CGPoint(x: 40, y: 50)), layerID: id,
                                           .motion(.position), atDocumentTimeMS: 1000)
        #expect(typed)
        #expect(document.keyedValue(layerID: id, .motion(.position), atDocumentTimeMS: 1000)
                == .point(CGPoint(x: 40, y: 50)))
    }
}
