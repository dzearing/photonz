import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A picture fade**: a clip, a title, a shape or a picture on the timeline
/// rising out of black at its start and sinking back into it at its end, the
/// way Final Cut's fade handles and Premiere's dip at a clip's head do it.
///
/// Written before the model. What it pins down:
///  - the fade is measured from the bar's own ends on the DOCUMENT's clock, so
///    a trim, a move or a cut never leaves it stranded in the middle;
///  - it multiplies whatever opacity the layer already has at that moment,
///    keys and all, rather than replacing it;
///  - fades too long for the bar share it rather than overlapping;
///  - it is one fade for everything, so a title's old Fade (an Opacity motion)
///    is read as one and turned into one the first time it is touched.
@Suite("Picture fades")
struct PictureFadeTests {

    // MARK: - Fixtures

    /// An eight second document with one clip filling it. The stand-in carries
    /// a source length, which is what makes it behave like media.
    static func eightSeconds(clipFrom inMS: Int = 0, to outMS: Int = 8000) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle,
                                                                colorHex: "#0C0E14")),
                         frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        clip.time = LayerTime(inMS: inMS, outMS: outMS, sourceInMS: 0, sourceLengthMS: 8000)
        doc.layers = [clip]
        doc.durationMS = 8000
        return doc
    }

    static func title(in doc: inout PhotonzDocument, from inMS: Int, to outMS: Int) -> UUID {
        var words = Layer(name: "Hello", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 10, y: 10, width: 200, height: 40))
        words.time = LayerTime(inMS: inMS, outMS: outMS)
        doc.layers.append(words)
        return words.id
    }

    static func opacity(_ doc: PhotonzDocument, _ id: UUID, at ms: Int) -> Double {
        doc.drawn(atTimeMS: ms).layer(id: id)?.style.opacity ?? -1
    }

    static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.002 }

    // MARK: - What it draws

    @Test("A clip nobody faded draws at its own opacity the whole way")
    func noFadeNoChange() {
        let doc = Self.eightSeconds()
        let id = doc.layers[0].id
        #expect(Self.opacity(doc, id, at: 0) == 1)
        #expect(Self.opacity(doc, id, at: 7999) == 1)
    }

    @Test("A fade in rises out of nothing over its length, in a straight line")
    func fadeInRises() {
        var doc = Self.eightSeconds()
        let id = doc.layers[0].id
        let wrote = doc.setPictureFade(id, .in, toMS: 1000)
        #expect(wrote)
        #expect(Self.near(Self.opacity(doc, id, at: 0), 0))
        #expect(Self.near(Self.opacity(doc, id, at: 250), 0.25))
        #expect(Self.near(Self.opacity(doc, id, at: 500), 0.5))
        #expect(Self.near(Self.opacity(doc, id, at: 750), 0.75))
        #expect(Self.opacity(doc, id, at: 1000) == 1)
        #expect(Self.opacity(doc, id, at: 7999) == 1)
    }

    @Test("A fade out sinks into nothing by the clip's last frame")
    func fadeOutSinks() {
        var doc = Self.eightSeconds()
        let id = doc.layers[0].id
        let wrote = doc.setPictureFade(id, .out, toMS: 1000)
        #expect(wrote)
        #expect(Self.opacity(doc, id, at: 7000) == 1)
        #expect(Self.near(Self.opacity(doc, id, at: 7250), 0.75))
        #expect(Self.near(Self.opacity(doc, id, at: 7500), 0.5))
        #expect(Self.near(Self.opacity(doc, id, at: 7750), 0.25))
        #expect(Self.opacity(doc, id, at: 7999) < 0.01)
        #expect(Self.opacity(doc, id, at: 0) == 1)
    }

    @Test("It multiplies the opacity the layer already has, rather than replacing it")
    func multipliesOpacity() {
        var doc = Self.eightSeconds()
        let id = doc.layers[0].id
        doc.updateLayer(id: id) { $0.style.opacity = 0.8 }
        doc.setPictureFade(id, .in, toMS: 1000)
        #expect(Self.near(Self.opacity(doc, id, at: 500), 0.4))
        #expect(Self.near(Self.opacity(doc, id, at: 2000), 0.8))
    }

    @Test("It is measured from where the bar starts on the timeline, not from nought")
    func measuredFromTheBar() {
        var doc = Self.eightSeconds(clipFrom: 2000, to: 6000)
        let id = doc.layers[0].id
        doc.setPictureFade(id, .in, toMS: 1000)
        doc.setPictureFade(id, .out, toMS: 1000)
        #expect(Self.near(Self.opacity(doc, id, at: 2500), 0.5))
        #expect(Self.opacity(doc, id, at: 4000) == 1)
        #expect(Self.near(Self.opacity(doc, id, at: 5500), 0.5))
    }

    @Test("A trim takes the fade with the end it is on")
    func trimKeepsTheFadeAtTheEnd() {
        var doc = Self.eightSeconds()
        let id = doc.layers[0].id
        doc.setPictureFade(id, .in, toMS: 1000)
        doc.setPictureFade(id, .out, toMS: 1000)
        doc.updateLayer(id: id) { $0.time = $0.time?.withIn(1000).withOut(5000) }
        #expect(Self.near(Self.opacity(doc, id, at: 1500), 0.5))
        #expect(Self.near(Self.opacity(doc, id, at: 4500), 0.5))
    }

    @Test("Fades longer than the bar share it rather than overlapping")
    func fadesShareAShortBar() {
        var doc = Self.eightSeconds(clipFrom: 0, to: 4000)
        let id = doc.layers[0].id
        doc.setPictureFade(id, .in, toMS: 2000)
        doc.setPictureFade(id, .out, toMS: 2000)
        // Shortened from four seconds to two: each fade gets its half.
        doc.updateLayer(id: id) { $0.time = $0.time?.withOut(2000) }
        let layer = doc.layer(id: id)
        #expect(layer?.pictureFadeMS(.in) == 1000)
        #expect(layer?.pictureFadeMS(.out) == 1000)
        #expect(Self.near(Self.opacity(doc, id, at: 500), 0.5))
        #expect(Self.near(Self.opacity(doc, id, at: 1500), 0.5))
    }

    @Test("The fades are also drawn on a layer inside a group, on its own stretch")
    func insideAGroup() throws {
        var doc = Self.eightSeconds()
        let id = Self.title(in: &doc, from: 2000, to: 5000)
        doc.setPictureFade(id, .in, toMS: 1000)
        let words = try #require(doc.layer(id: id))
        doc.layers.removeAll { $0.id == id }
        let group = Layer(name: "Group", content: .group(GroupContent(children: [words])),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 100))
        doc.layers.append(group)
        #expect(Self.near(Self.opacity(doc, id, at: 2500), 0.5))
    }

    // MARK: - Writing it

    @Test("Nought takes a fade away, and with neither end faded nothing is written")
    func noughtRemoves() {
        var doc = Self.eightSeconds()
        let id = doc.layers[0].id
        doc.setPictureFade(id, .in, toMS: 500)
        #expect(doc.layer(id: id)?.pictureFade != nil)
        let wrote = doc.setPictureFade(id, .in, toMS: 0)
        #expect(wrote)
        #expect(doc.layer(id: id)?.pictureFade == nil)
    }

    @Test("A fade that is already that length, or leaves no room for the other end, is not offered")
    func whatIsOffered() {
        var doc = Self.eightSeconds(clipFrom: 0, to: 2000)
        let id = doc.layers[0].id
        doc.setPictureFade(id, .out, toMS: 1000)
        let layer = doc.layer(id: id)
        #expect(layer?.canSetPictureFade(.out, toMS: 1000) == false)
        #expect(layer?.canSetPictureFade(.out, toMS: 0) == true)
        #expect(layer?.canSetPictureFade(.in, toMS: 1000) == true)
        #expect(layer?.canSetPictureFade(.in, toMS: 2000) == false)
        let refused = doc.setPictureFade(id, .in, toMS: 2000)
        #expect(refused == false)
    }

    @Test("Something with no stretch in time, or with no picture, takes no picture fade")
    func onlyPicturesInTime() {
        var still = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        let shape = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle)),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        still.layers = [shape]
        #expect(shape.canFadePicture == false)
        let refused = still.setPictureFade(shape.id, .in, toMS: 500)
        #expect(refused == false)

        var sound = Layer(name: "Music", content: .sound(SoundRef(durationMS: 4000)),
                          frame: .zero)
        sound.time = LayerTime(inMS: 0, outMS: 4000, sourceLengthMS: 4000)
        #expect(sound.canFadePicture == false)
    }

    @Test("A title takes the same fade, one end at a time")
    func titlesFadeTheSameWay() {
        var doc = Self.eightSeconds()
        let id = Self.title(in: &doc, from: 2000, to: 5000)
        #expect(doc.layer(id: id)?.canFadePicture == true)
        doc.setPictureFade(id, .out, toMS: 500)
        #expect(Self.opacity(doc, id, at: 2000) == 1)
        #expect(Self.near(Self.opacity(doc, id, at: 4750), 0.5))
    }

    @Test("A title's old Fade reads as both ends, and the first edit turns it into a picture fade")
    func oldTitleFadeIsOneFade() {
        var doc = Self.eightSeconds()
        let id = Self.title(in: &doc, from: 2000, to: 5000)
        doc.setTitleFade(id, toMS: 500)
        #expect(doc.layer(id: id)?.pictureFadeMS(.in) == 500)
        #expect(doc.layer(id: id)?.pictureFadeMS(.out) == 500)
        let wrote = doc.setPictureFade(id, .out, toMS: 1000)
        #expect(wrote)
        let layer = doc.layer(id: id)
        #expect(layer?.titleFadeMS == nil)
        #expect((layer?.motions ?? []).contains { $0.property == .opacity } == false)
        #expect(layer?.pictureFadeMS(.in) == 500)
        #expect(layer?.pictureFadeMS(.out) == 1000)
        #expect(Self.near(Self.opacity(doc, id, at: 2250), 0.5))
    }

    // MARK: - Keeping it

    @Test("A fade is written down and read back, and a layer without one writes nothing")
    func roundTrips() throws {
        var doc = Self.eightSeconds()
        let id = doc.layers[0].id
        let plain = try JSONEncoder().encode(doc.layers[0])
        #expect(String(decoding: plain, as: UTF8.self).contains("pictureFade") == false)
        doc.setPictureFade(id, .in, toMS: 250)
        doc.setPictureFade(id, .out, toMS: 1000)
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layer(id: id)?.pictureFade == PictureFade(inMS: 250, outMS: 1000))
    }

    @Test("A duplicate fades the way its original does")
    func duplicateKeepsIt() {
        var doc = Self.eightSeconds()
        let id = doc.layers[0].id
        doc.setPictureFade(id, .in, toMS: 500)
        let copy = doc.layer(id: id)?.duplicated()
        #expect(copy?.pictureFade == PictureFade(inMS: 500, outMS: 0))
    }

    @Test("Each length is offered by name, nought as None")
    func lengthTitles() {
        #expect(PictureFade.stopsMS.first == 0)
        #expect(PictureFade.title(0) == "None")
        #expect(PictureFade.title(500) == "0.5s")
        #expect(PictureFade.title(1000) == "1s")
        #expect(PictureFade.title(250) == "0.25s")
    }
}
