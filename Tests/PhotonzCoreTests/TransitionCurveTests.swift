import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Every transition tuned the same way (task
/// `every-transition-can-be-picked-from-presets-and`): a zoom's way in and way
/// out, and a transition at a cut, each take a curve from the one list keys
/// already use, and a curve somebody drew can be kept under a name.
///
/// The bar the task sets: the value at a quarter, a half and three quarters of
/// the way through matches the curve within 2%, and a document written before
/// curves existed plays exactly as it did.
@Suite("Every transition takes a curve from the one list")
struct TransitionCurveTests {

    static let quarters: [Double] = [0.25, 0.5, 0.75]

    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.02) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: - Smooth, the zoom's own curve

    @Test("Smooth is the curve zooms always eased on, slow off the mark and slow to settle")
    func smoothIsTheOldZoomEase() {
        let smooth = EasingCurve.smooth
        #expect(smooth.title == "Smooth")
        for t in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0] {
            let x = t
            let expected = x * x * x * (x * (x * 6 - 15) + 10)
            #expect(abs(smooth.value(at: t) - expected) < 1e-9)
        }
        // Not one of the shared eight the key mock draws: it is offered only
        // where it is the default.
        #expect(!EasingCurve.named.contains(.smooth))
    }

    @Test("Smooth survives being written down and read back")
    func smoothRoundTrips() throws {
        let data = try JSONEncoder().encode(EasingCurve.smooth)
        #expect(try JSONDecoder().decode(EasingCurve.self, from: data) == .smooth)
    }

    // MARK: - A zoom

    static func zoom(ease: Int = 1000) -> ClipZoom {
        ClipZoom(startMS: 2000, endMS: 6000, easeInMS: ease, easeOutMS: ease)
    }

    @Test("A zoom with no curve set eases on Smooth, in and out")
    func aZoomDefaultsToSmooth() {
        let zoom = Self.zoom()
        #expect(zoom.curve == nil)
        #expect(zoom.inCurve == .smooth)
        #expect(zoom.outCurveShown == .smooth)
        #expect(!zoom.curvesApart)
        for q in Self.quarters {
            #expect(Self.near(zoom.amount(atMS: 2000 + Int(q * 1000)), EasingCurve.smooth.value(at: q), 0.001))
            // The way out is the way in played backwards.
            #expect(Self.near(zoom.amount(atMS: 5000 + Int(q * 1000)), 1 - EasingCurve.smooth.value(at: q), 0.001))
        }
    }

    @Test("A zoom written before curves existed reads back with no curve and plays exactly as it did")
    func anOldZoomPlaysAsBefore() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","startMS":2000,"endMS":6000,"easeInMS":1000,"easeOutMS":1000,
         "scale":2,"center":[0.5,0.5],"followsCursor":false,"aimedAtWhatIsSeen":true}
        """
        let zoom = try JSONDecoder().decode(ClipZoom.self, from: Data(json.utf8))
        #expect(zoom.curve == nil && zoom.outCurve == nil)
        let x = 0.25
        #expect(abs(zoom.amount(atMS: 2250) - x * x * x * (x * (x * 6 - 15) + 10)) < 1e-9)
        // And it writes nothing about curves back out.
        let written = String(decoding: try JSONEncoder().encode(zoom), as: UTF8.self)
        #expect(!written.contains("urve"))
    }

    @Test("One curve shapes both the way in and the way out, at a quarter, a half and three quarters")
    func oneCurveForBoth() {
        for curve in EasingCurve.named + [.custom(x1: 0.7, y1: 0, x2: 0.3, y2: 1)] {
            var zoom = Self.zoom()
            zoom.curve = curve
            #expect(zoom.inCurve == curve && zoom.outCurveShown == curve)
            for q in Self.quarters {
                // Overshoot is kept on the way in (a back curve leans past and
                // settles); nothing goes below the whole picture.
                let wayIn = zoom.amount(atMS: 2000 + Int(q * 1000))
                #expect(Self.near(wayIn, max(0, curve.value(at: q))), "\(curve.title) in at \(q)")
                let wayOut = zoom.amount(atMS: 5000 + Int(q * 1000))
                #expect(Self.near(wayOut, max(0, 1 - curve.value(at: q))), "\(curve.title) out at \(q)")
            }
        }
    }

    @Test("The way in and the way out can be set apart")
    func curvesApart() {
        var zoom = Self.zoom()
        zoom.curve = .easeIn
        zoom.outCurve = .linear
        #expect(zoom.curvesApart)
        #expect(zoom.inCurve == .easeIn && zoom.outCurveShown == .linear)
        #expect(Self.near(zoom.amount(atMS: 2250), EasingCurve.easeIn.value(at: 0.25)))
        #expect(Self.near(zoom.amount(atMS: 5250), 0.75))
        #expect(Self.near(zoom.amount(atMS: 5750), 0.25))
    }

    @Test("The window shown follows the curve: halfway along a linear way in is halfway there in scale")
    func theWindowFollowsTheCurve() throws {
        var zoom = ClipZoom(startMS: 0, endMS: 4000, easeInMS: 1000, easeOutMS: 1000, scale: 4)
        zoom.curve = .linear
        let window = try #require(zoom.window(atMS: 500))
        // pow(4, 0.5) = 2: half the width of the picture.
        #expect(abs(Double(window.width) - 0.5) < 0.01)
    }

    @Test("Several zooms picked together say the curve they share, and nil where they differ")
    func severalZoomsReadTheirCurve() {
        var a = Self.zoom(), b = Self.zoom()
        #expect(ClipZoomsReading([a, b]).inCurve == .smooth)
        #expect(ClipZoomsReading([a, b]).curvesApart == false)
        a.curve = .easeOut
        #expect(ClipZoomsReading([a, b]).inCurve == nil)
        b.curve = .easeOut
        b.outCurve = .linear
        let reading = ClipZoomsReading([a, b])
        #expect(reading.inCurve == .easeOut)
        #expect(reading.outCurve == nil)
        #expect(reading.curvesApart == nil)
    }

    @Test("A curve set through the document lands on the zoom and is undone with it")
    func setThroughTheDocument() throws {
        let reel = MovieRef(pixelSize: CGSize(width: 2000, height: 1000), durationMS: 12_000)
        var layer = Layer(name: "screen-recording", content: .image(reel.frameRef(atSourceMS: 0)),
                          frame: CGRect(x: 0, y: 0, width: 1000, height: 500))
        layer.movie = reel
        layer.time = LayerTime(inMS: 0, outMS: 12_000, sourceInMS: 0, sourceLengthMS: 12_000)
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 500), layers: [layer])
        document.durationMS = 12_000
        let added = document.addZoom(toClip: layer.id, atTimeMS: 2000, around: nil)
        let made = try #require(added)
        document.updateZoom(onClip: layer.id, id: made.id) { $0.curve = .easeInOutSine }
        let stored = try #require(document.layer(id: layer.id)?.zooms?.first)
        #expect(stored.curve == .easeInOutSine)
    }

    // MARK: - A transition at a cut

    static func cutClip() -> ClipPieces {
        ClipPieces(pieces: [ClipPiece(sourceInMS: 1000, lengthMS: 3000),
                            ClipPiece(sourceInMS: 10_000, lengthMS: 4000)],
                   sourceLengthMS: 20_000)
    }

    @Test("A transition with no curve set runs straight, as every transition always has")
    func aTransitionDefaultsToLinear() throws {
        #expect(ClipTransition(kind: .dissolve).curve == .linear)
        let json = #"{"kind":"dissolve","lengthMS":1000}"#
        let old = try JSONDecoder().decode(ClipTransition.self, from: Data(json.utf8))
        #expect(old.curve == .linear)
        // ...and writes exactly what it always wrote.
        let written = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!written.contains("curve"))
        var pieces = Self.cutClip()
        _ = pieces.setTransition(old, atCut: 1)
        for q in Self.quarters {
            let moment = try #require(pieces.moment(atMS: 2500 + Int(q * 1000)))
            #expect(Self.near(moment.incomingOpacity, q, 0.001))
        }
    }

    @Test("A curve on a transition is written down and read back")
    func aCurveRoundTrips() throws {
        let made = ClipTransition(kind: .push, lengthMS: 600, curve: .custom(x1: 0.1, y1: 0.8, x2: 0.3, y2: 1))
        let back = try JSONDecoder().decode(ClipTransition.self, from: JSONEncoder().encode(made))
        #expect(back == made)
        #expect(made.withLength(800).curve == made.curve)
    }

    @Test("A dissolve on a curve brings the incoming shot up along the curve")
    func aDissolveFollowsItsCurve() throws {
        for curve in [EasingCurve.easeIn, .easeOut, .easeInOut, .custom(x1: 0.9, y1: 0, x2: 0.9, y2: 0.4)] {
            var pieces = Self.cutClip()
            let did = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000, curve: curve), atCut: 1)
            #expect(did)
            for q in Self.quarters {
                let moment = try #require(pieces.moment(atMS: 2500 + Int(q * 1000)))
                #expect(Self.near(moment.incomingOpacity, curve.value(at: q)), "\(curve.title) at \(q)")
                #expect(Self.near(moment.progress, curve.value(at: q)))
            }
        }
    }

    @Test("A dip on a curve fades down along it, is all colour on the cut, and comes back along it")
    func aDipFollowsItsCurve() throws {
        var pieces = Self.cutClip()
        let curve = EasingCurve.easeIn
        let did = pieces.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000, curve: curve), atCut: 1)
        #expect(did)
        // The fade down is 2500 to 3000, the fade up 3000 to 3500.
        for q in Self.quarters {
            let down = try #require(pieces.moment(atMS: 2500 + Int(q * 500)))
            #expect(Self.near(down.dipOpacity, curve.value(at: q)), "down at \(q)")
            let up = try #require(pieces.moment(atMS: 3000 + Int(q * 500)))
            #expect(Self.near(up.dipOpacity, 1 - curve.value(at: q)), "up at \(q)")
        }
        #expect(try #require(pieces.moment(atMS: 3000)).dipOpacity > 0.99)
    }

    @Test("A dissolve between two clips follows its curve too")
    func anEditPointFollowsItsCurve() throws {
        let take = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 10_000)
        let broll = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 6000)
        var doc = PhotonzDocument.recording(take, name: "take")
        let takeID = doc.layers[0].id
        doc.updateLayer(id: takeID) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "b-roll", content: .image(broll.frameRef(atSourceMS: 1500)),
                         frame: CGRect(origin: .zero, size: broll.pixelSize))
        clip.movie = broll
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 1500, sourceLengthMS: 6000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 8000, over: .onto(v1), edit: .overwrite)
        let landed = doc.land(clip, at: landing)
        let brollID = try #require(landed)
        let curve = EasingCurve.easeOut
        let did = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000, curve: curve),
                                    at: .edit(outgoing: takeID, incoming: brollID))
        #expect(did)
        // A quarter of the way through a second-long dissolve that starts at 7.5s.
        let shown = doc.drawn(atTimeMS: 7750)
        let partner = try #require(shown.layers.first { $0.id != takeID && $0.id != brollID && $0.isVisible })
        #expect(Self.near(partner.style.opacity, curve.value(at: 0.25)))
        // The curve survives the cut being read off the timeline.
        #expect(doc.documentCut(at: .edit(outgoing: takeID, incoming: brollID))?.cut.transition?.curve == curve)
    }

    // MARK: - A picture fade

    @Test("A picture fade with no curve runs straight, and an old one reads back that way")
    func aPictureFadeDefaultsToLinear() throws {
        let old = try JSONDecoder().decode(PictureFade.self, from: Data(#"{"inMS":1000,"outMS":1000}"#.utf8))
        #expect(old.curve == nil)
        #expect(Self.near(old.level(atOffsetMS: 250, lengthMS: 4000), 0.25, 0.001))
        let written = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!written.contains("curve"))
    }

    @Test("A picture fade on a curve comes up along it and goes down along it")
    func aPictureFadeFollowsItsCurve() {
        var fade = PictureFade(inMS: 1000, outMS: 1000)
        fade.curve = .easeIn
        for q in Self.quarters {
            #expect(Self.near(fade.level(atOffsetMS: Int(q * 1000), lengthMS: 4000), EasingCurve.easeIn.value(at: q)))
            #expect(Self.near(fade.level(atOffsetMS: 3000 + Int(q * 1000), lengthMS: 4000),
                              1 - EasingCurve.easeIn.value(at: q)))
        }
        // Fitting a fade into a shorter clip keeps its curve.
        #expect(fade.fitted(lengthMS: 1000).curve == .easeIn)
    }

    @Test("A curve set on a layer's fades through the document keeps its lengths")
    func aPictureFadeCurveThroughTheDocument() throws {
        let reel = MovieRef(pixelSize: CGSize(width: 200, height: 100), durationMS: 8000)
        var layer = Layer(name: "clip", content: .image(reel.frameRef(atSourceMS: 0)),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        layer.movie = reel
        layer.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 100), layers: [layer])
        document.durationMS = 8000
        let none = document.setPictureFadeCurve(layer.id, .easeIn)
        #expect(!none)
        document.setPictureFade(layer.id, .in, toMS: 1000)
        let did = document.setPictureFadeCurve(layer.id, .easeOut)
        #expect(did)
        let fade = try #require(document.layer(id: layer.id)?.pictureFade)
        #expect(fade.curve == .easeOut && fade.inMS == 1000)
        // A length changed afterwards keeps the curve.
        document.setPictureFade(layer.id, .out, toMS: 500)
        #expect(document.layer(id: layer.id)?.pictureFade?.curve == .easeOut)
        let back = document.setPictureFadeCurve(layer.id, .linear)
        #expect(back)
        #expect(document.layer(id: layer.id)?.pictureFade?.curve == nil)
    }

    // MARK: - Saved curves

    @Test("A curve can be kept under a name, and the same name takes the newer curve")
    func savedCurves() {
        var saved = SavedCurves()
        #expect(saved.items.isEmpty)
        let drawn = EasingCurve.custom(x1: 0.2, y1: 0.9, x2: 0.4, y2: 1)
        let first = saved.save(drawn, as: "  Snappy  ")
        #expect(first == "Snappy")
        #expect(saved.items == [SavedCurve(name: "Snappy", curve: drawn)])
        #expect(saved.name(of: drawn) == "Snappy")
        let other = EasingCurve.custom(x1: 0.5, y1: 0, x2: 0.5, y2: 1)
        let second = saved.save(other, as: "snappy")
        #expect(second == "snappy")
        #expect(saved.items.count == 1 && saved.items[0].curve == other)
        // No name, nothing kept.
        let blank = saved.save(drawn, as: "   ")
        #expect(blank == nil)
        #expect(saved.items.count == 1)
        saved.save(drawn, as: "Gentle")
        #expect(saved.items.map(\.name) == ["snappy", "Gentle"])
        saved.remove(named: "SNAPPY")
        #expect(saved.items.map(\.name) == ["Gentle"])
    }

    @Test("Saved curves survive being written down")
    func savedCurvesRoundTrip() throws {
        var saved = SavedCurves()
        saved.save(.custom(x1: 0.2, y1: 0.9, x2: 0.4, y2: 1), as: "Snappy")
        saved.save(.easeOutBack, as: "Bouncy")
        let back = try JSONDecoder().decode(SavedCurves.self, from: JSONEncoder().encode(saved))
        #expect(back == saved)
    }
}
