import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **The next thing you draw keeps the last one's look, fades included.**
///
/// The user, 2026-10-19: "Today i wanted to make a video pause at sections have
/// some arrows fade in and out. It was annoying to make it do that. I had to
/// select each one, add a fade in, then add a fade out", and "at minimum i wish
/// it remembered the transitions from the previous object".
///
/// Written before the model. What it pins down:
///  - each kind of drawn thing remembers the fade last set on one of its kind,
///    and the next one drawn on a video starts with it;
///  - the remembered fade never makes the new thing longer or shorter, so an
///    arrow drawn on a freeze still takes exactly the hold;
///  - several picked things fade at once, and both ends fade in one step at the
///    remembered lengths;
///  - text and Pen paths remember their effects (shadow and the rest) the way
///    shapes always have.
@Suite("Remembered looks")
struct RememberedLooksTests {

    // MARK: - Fixtures

    static func arrow(_ name: String = "Arrow") -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .arrow, colorHex: "#FF3B30")),
              frame: CGRect(x: 100, y: 100, width: 200, height: 40))
    }

    static func rectangle() -> Layer {
        Layer(name: "Rectangle",
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF3B30")),
              frame: CGRect(x: 400, y: 300, width: 200, height: 120))
    }

    static func words() -> Layer {
        Layer(name: "Hello", content: .text(TextContent(string: "Hello")),
              frame: CGRect(x: 10, y: 10, width: 200, height: 40))
    }

    static func placed(_ layer: Layer, from inMS: Int, to outMS: Int) -> Layer {
        var placed = layer
        placed.time = LayerTime(inMS: inMS, outMS: outMS)
        return placed
    }

    /// `layer` faded, the way the app fades one: through the document.
    static func faded(_ layer: Layer, in inMS: Int, out outMS: Int, curve: EasingCurve? = nil) -> Layer {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        doc.layers.append(layer)
        doc.setPictureFades([layer.id], inMS: inMS, outMS: outMS)
        if let curve { doc.setPictureFadeCurve(layer.id, curve) }
        return doc.layer(id: layer.id) ?? layer
    }

    // MARK: - What kind a layer is

    @Test func everyDrawnThingHasAKindAndARecordingHasNone() {
        #expect(DrawnKind(Self.arrow()) == .arrow)
        #expect(DrawnKind(Self.rectangle()) == .rectangle)
        #expect(DrawnKind(Self.words()) == .text)
        let path = Layer(name: "Path", content: .path(PathContent(anchors: [])),
                         frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(DrawnKind(path) == .path)
        let picture = Layer(name: "Picture", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                            frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(DrawnKind(picture) == .picture)
        let recording = PhotonzDocument.recording(HeldFrameTests.movie(), name: "Take 1").layers[0]
        #expect(DrawnKind(recording) == nil)
    }

    // MARK: - The fade is remembered per kind

    @Test func anArrowsFadeIsRememberedForTheNextArrowAndOnlyArrows() {
        var looks = RememberedLooks()
        looks.rememberFade(of: Self.faded(Self.placed(Self.arrow(), from: 0, to: 4000), in: 500, out: 1000))
        #expect(looks.fade(for: .arrow) == PictureFade(inMS: 500, outMS: 1000))
        #expect(looks.fade(for: .rectangle) == nil)
        #expect(looks.fade(for: .text) == nil)
    }

    @Test func takingTheFadeOffIsRememberedToo() {
        var looks = RememberedLooks()
        let arrow = Self.placed(Self.arrow(), from: 0, to: 4000)
        looks.rememberFade(of: Self.faded(arrow, in: 500, out: 500))
        looks.rememberFade(of: arrow)
        #expect(looks.fade(for: .arrow) == nil)
    }

    @Test func aRecordingsFadeIsNotRemembered() {
        var looks = RememberedLooks()
        var doc = PhotonzDocument.recording(HeldFrameTests.movie(), name: "Take 1")
        let id = doc.layers[0].id
        doc.setPictureFades([id], inMS: 1000, outMS: 1000)
        if let recording = doc.layer(id: id) { looks.rememberFade(of: recording) }
        #expect(RememberedLooks() == looks)
    }

    @Test func theCurveIsRememberedWithTheLengths() {
        var looks = RememberedLooks()
        looks.rememberFade(of: Self.faded(Self.placed(Self.arrow(), from: 0, to: 4000),
                                          in: 500, out: 500, curve: .easeInOut))
        #expect(looks.fade(for: .arrow)?.curve == .easeInOut)
    }

    @Test func itSurvivesBeingSavedAndReadBack() throws {
        var looks = RememberedLooks()
        looks.rememberFade(of: Self.faded(Self.placed(Self.arrow(), from: 0, to: 4000), in: 250, out: 2000))
        var style = LayerStyle()
        style.opacity = 0.5
        looks.rememberStyle(style, for: .text)
        let data = try JSONEncoder().encode(looks)
        let back = try JSONDecoder().decode(RememberedLooks.self, from: data)
        #expect(back == looks)
        #expect(try JSONDecoder().decode(RememberedLooks.self, from: Data("{}".utf8)) == RememberedLooks())
    }

    // MARK: - The next one drawn starts with it

    @Test func theNextArrowDrawnOnAVideoStartsWithTheRememberedFade() {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        let fade = PictureFade(inMS: 500, outMS: 1000)
        doc.addLayerDrawn(Self.arrow(), atTimeMS: 1000, placingInTime: true, fade: fade)
        #expect(doc.layers.last?.pictureFade == fade)
        #expect(doc.layers.last?.time == LayerTime(inMS: 1000, outMS: 8000))
    }

    @Test func onAFreezeTheRememberedFadeNeitherLengthensNorShortensIt() {
        var (doc, _) = HeldFrameTests.held()
        guard let held = doc.heldFrame(atTimeMS: 4500) else {
            Issue.record("no held frame at 4.5s")
            return
        }
        // Longer fades than the hold has room for: they share it.
        let fade = PictureFade(inMS: 2000, outMS: 2000)
        doc.addLayerDrawn(Self.arrow(), atTimeMS: 4500, placingInTime: true, fade: fade)
        #expect(doc.layers.last?.time == held.span)
        let shown = doc.layers.last?.shownPictureFade
        #expect((shown?.inMS ?? 0) + (shown?.outMS ?? 0) <= held.span.lengthMS)
    }

    @Test func onAPictureNothingIsPlacedInTimeSoNoFadeArrives() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.addLayerDrawn(Self.arrow(), atTimeMS: 0, placingInTime: true,
                          fade: PictureFade(inMS: 500, outMS: 500))
        #expect(doc.layers.last?.time == nil)
        #expect(doc.layers.last?.pictureFade == nil)
    }

    @Test func somethingThatArrivesWithAFadeOfItsOwnKeepsIt() {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        let pasted = Self.faded(Self.placed(Self.arrow(), from: 1000, to: 8000), in: 2000, out: 0)
        doc.addLayerDrawn(pasted, atTimeMS: 1000, placingInTime: true,
                          fade: PictureFade(inMS: 500, outMS: 500))
        #expect(doc.layers.last?.pictureFade == PictureFade(inMS: 2000, outMS: 0))
    }

    @Test func undoingTheFirstArrowsFadeLeavesTheSecondOnesAlone() {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        doc.addLayerDrawn(Self.arrow("One"), atTimeMS: 1000, placingInTime: true)
        let one = doc.layers.last?.id ?? UUID()
        let before = doc
        doc.setPictureFades([one], inMS: 500, outMS: 500)
        var looks = RememberedLooks()
        if let layer = doc.layer(id: one) { looks.rememberFade(of: layer) }
        doc.addLayerDrawn(Self.arrow("Two"), atTimeMS: 2000, placingInTime: true,
                          fade: looks.fade(for: .arrow))
        let two = doc.layers.last?.id ?? UUID()
        // Undo is the document going back: the second arrow is a new layer the
        // first's fade never touched, and the memory is not part of history.
        var undone = before
        undone.addLayerDrawn(doc.layer(id: two) ?? Self.arrow(), atTimeMS: 2000, placingInTime: true)
        #expect(undone.layer(id: one)?.pictureFade == nil)
        #expect(undone.layer(id: two)?.pictureFade == PictureFade(inMS: 500, outMS: 500))
        #expect(looks.fade(for: .arrow) == PictureFade(inMS: 500, outMS: 500))
    }

    // MARK: - Several at once

    @Test func threePickedArrowsFadeInAtOnce() {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        let ids = (0..<3).map { index -> UUID in
            let layer = Self.placed(Self.arrow("Arrow \(index)"), from: 1000, to: 3000)
            doc.layers.append(layer)
            return layer.id
        }
        let changed = doc.setPictureFades(ids, inMS: 500, outMS: nil)
        #expect(Set(changed) == Set(ids))
        for id in ids {
            #expect(doc.layer(id: id)?.pictureFadeMS(.in) == 500)
            #expect(doc.layer(id: id)?.pictureFadeMS(.out) == 0)
        }
    }

    @Test func fadingOneEndOfSeveralLeavesEachOnesOtherEndAlone() {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        let first = Self.faded(Self.placed(Self.arrow("A"), from: 1000, to: 3000), in: 0, out: 250)
        let second = Self.placed(Self.arrow("B"), from: 1000, to: 3000)
        doc.layers += [first, second]
        doc.setPictureFades([first.id, second.id], inMS: 500, outMS: nil)
        #expect(doc.layer(id: first.id)?.pictureFade == PictureFade(inMS: 500, outMS: 250))
        #expect(doc.layer(id: second.id)?.pictureFade == PictureFade(inMS: 500, outMS: 0))
    }

    @Test func bothEndsInOneStep() {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        let layer = Self.placed(Self.arrow(), from: 1000, to: 3000)
        doc.layers.append(layer)
        doc.setPictureFades([layer.id], inMS: 1000, outMS: 1000)
        #expect(doc.layer(id: layer.id)?.pictureFade == PictureFade(inMS: 1000, outMS: 1000))
    }

    @Test func fadingSeveralSkipsWhatCannotFade() {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        let unplaced = Self.arrow()
        let placed = Self.placed(Self.arrow(), from: 0, to: 2000)
        doc.layers += [unplaced, placed]
        let changed = doc.setPictureFades([unplaced.id, placed.id], inMS: 500, outMS: 500)
        #expect(changed == [placed.id])
        #expect(doc.layer(id: unplaced.id)?.pictureFade == nil)
    }

    @Test func noughtAtBothEndsTakesTheFadeAway() {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        let layer = Self.faded(Self.placed(Self.arrow(), from: 0, to: 2000), in: 500, out: 500)
        doc.layers.append(layer)
        doc.setPictureFades([layer.id], inMS: 0, outMS: 0)
        #expect(doc.layer(id: layer.id)?.pictureFade == nil)
    }

    @Test func aFadeTooLongForTheBarSharesItRatherThanBeingRefused() {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        let layer = Self.placed(Self.arrow(), from: 0, to: 1500)
        doc.layers.append(layer)
        doc.setPictureFades([layer.id], inMS: 1000, outMS: 1000)
        #expect(doc.layer(id: layer.id)?.shownPictureFade == PictureFade(inMS: 750, outMS: 750))
        #expect(doc.layer(id: layer.id)?.time == LayerTime(inMS: 0, outMS: 1500))
    }

    @Test func aFadeKeepsItsCurveWhenSeveralAreFaded() {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        let layer = Self.faded(Self.placed(Self.arrow(), from: 0, to: 4000), in: 500, out: 0, curve: .easeInOut)
        doc.layers.append(layer)
        doc.setPictureFades([layer.id], inMS: nil, outMS: 500)
        #expect(doc.layer(id: layer.id)?.pictureFade?.curve == .easeInOut)
    }

    // MARK: - Fade In and Out: the lengths it uses

    @Test func fadeInAndOutUsesTheRememberedLengthsOrASecond() {
        var looks = RememberedLooks()
        #expect(looks.bothEnds(for: .arrow) == PictureFade(inMS: 1000, outMS: 1000))
        let arrow = Self.placed(Self.arrow(), from: 0, to: 4000)
        looks.rememberFade(of: Self.faded(arrow, in: 500, out: 0))
        // One end remembered: the other end matches it.
        #expect(looks.bothEnds(for: .arrow) == PictureFade(inMS: 500, outMS: 500))
        looks.rememberFade(of: Self.faded(arrow, in: 250, out: 2000))
        #expect(looks.bothEnds(for: .arrow) == PictureFade(inMS: 250, outMS: 2000))
        #expect(looks.bothEnds(for: nil) == PictureFade(inMS: 1000, outMS: 1000))
    }

    @Test func whetherSeveralAlreadyFadeAtBothEnds() {
        let faded = Self.faded(Self.placed(Self.arrow(), from: 0, to: 4000), in: 500, out: 500)
        let half = Self.faded(Self.placed(Self.arrow(), from: 0, to: 4000), in: 500, out: 0)
        #expect(RememberedLooks.fadesAtBothEnds([faded]))
        #expect(!RememberedLooks.fadesAtBothEnds([faded, half]))
        #expect(!RememberedLooks.fadesAtBothEnds([]))
    }

    // MARK: - The rest of the look, for kinds the shape tools never covered

    @Test func textAndPathsRememberTheirEffects() {
        var looks = RememberedLooks()
        #expect(looks.style(for: .text) == nil)
        var style = LayerStyle()
        style.opacity = 0.6
        style.shadows = [ShadowStyle()]
        looks.rememberStyle(style, for: .text)
        #expect(looks.style(for: .text) == style)
        #expect(looks.style(for: .path) == nil)
    }

    @Test func newWordsWearTheRememberedEffectsUnlessTheyBroughtTheirOwn() {
        var looks = RememberedLooks()
        var style = LayerStyle()
        style.opacity = 0.6
        looks.rememberStyle(style, for: .text)
        let typed = TextBuilder.layer(content: TextContent(string: "Hi"), at: .zero,
                                      naturalSize: CGSize(width: 40, height: 20))
        #expect(looks.wearing(typed, startsWith: typed.style).style.opacity == 0.6)
        var styled = typed
        styled.style.opacity = 0.9
        #expect(looks.wearing(styled, startsWith: typed.style).style.opacity == 0.9)
    }

    @Test func newWordsKeepAShadowThatSuitsTheirOwnColour() {
        var looks = RememberedLooks()
        var white = TextContent(string: "Hi")
        white.colorHex = "#FFFFFF"
        var black = white
        black.colorHex = "#000000"
        let started = TextBuilder.layer(content: white, at: .zero, naturalSize: CGSize(width: 40, height: 20))
        var remembered = started
        remembered.style.opacity = 0.8
        looks.rememberStyle(remembered.style, for: .text, startedWith: started.style)
        let typed = TextBuilder.layer(content: black, at: .zero, naturalSize: CGSize(width: 40, height: 20))
        let worn = looks.wearing(typed, startsWith: typed.style)
        #expect(worn.style.opacity == 0.8)
        #expect(worn.style.shadow == TextBuilder.autoContrastShadow(forColorHex: "#000000"))
    }

    @Test func aShadowSomebodyChoseGoesAcrossAsItIs() {
        var looks = RememberedLooks()
        let started = TextBuilder.layer(content: TextContent(string: "Hi"), at: .zero,
                                        naturalSize: CGSize(width: 40, height: 20))
        var remembered = started
        remembered.style.shadows = [ShadowStyle(radius: 20)]
        looks.rememberStyle(remembered.style, for: .title, startedWith: started.style)
        let typed = TextBuilder.layer(content: TextContent(string: "Next"), at: .zero,
                                      naturalSize: CGSize(width: 40, height: 20))
        #expect(looks.wearing(typed, as: .title, startsWith: typed.style).style.shadows == [ShadowStyle(radius: 20)])
        #expect(looks.wearing(typed, as: .text, startsWith: typed.style).style == typed.style)
    }

    @Test func aPathWearsTheRememberedEffects() {
        var looks = RememberedLooks()
        var style = LayerStyle()
        style.shadows = [ShadowStyle()]
        looks.rememberStyle(style, for: .path)
        let path = Layer(name: "Path", content: .path(PathContent(anchors: [])),
                         frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(looks.wearing(path).style == style)
    }

    @Test func somethingGivenABarSomeOtherWayIsFadedToo() {
        var looks = RememberedLooks()
        let measured = Layer(name: "Measure", content: .measure(MeasureContent(start: .zero,
                                                                                 end: CGPoint(x: 10, y: 0))),
                             frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let placed = Self.placed(measured, from: 0, to: 4000)
        looks.rememberFade(of: Self.faded(placed, in: 500, out: 500))
        #expect(looks.fading(placed).pictureFade == PictureFade(inMS: 500, outMS: 500))
        #expect(looks.fading(measured).pictureFade == nil)
    }
}
