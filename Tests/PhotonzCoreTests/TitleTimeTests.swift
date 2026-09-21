import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A title is text that knows when it is on screen
/// (`docs/design/mocks/pages/video-title-wt.html`).
///
/// Written before the model, which is the rule for `PhotonzCore`. The whole
/// specification is one sentence — "a title is a text layer that happens to
/// live in a document with time, so it gets an in and an out, and nothing else
/// about it is special" — and everything here is that sentence taken
/// seriously:
///
///  - a layer PLACED in time is not a clip, so nothing that belongs to media
///    (a trim into the frames behind it, a speed, a held frame) applies to it;
///  - its left end is FREE, because there is nothing behind it to trim into;
///  - it comes on and goes off with an ordinary Opacity motion, not with a
///    fade property that only titles have.
@Suite("A title's in and out")
struct TitleTimeTests {

    // MARK: - Fixtures

    static func words(_ string: String) -> Layer {
        Layer(name: string,
              content: .text(TextContent(string: string)),
              frame: CGRect(x: 10, y: 10, width: 200, height: 40))
    }

    /// An eight second document with one clip-shaped layer filling it. The
    /// stand-in carries a source length, which is what makes it behave like
    /// media: there are frames behind both its ends.
    static func eightSeconds() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle,
                                                                colorHex: "#0C0E14")),
                         frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        clip.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        doc.layers = [clip]
        doc.durationMS = 8000
        return doc
    }

    // MARK: - Text placed in a document with time gets a start and an end

    @Test func textPlacedOnADocumentWithTimeGetsAStretch() {
        let doc = Self.eightSeconds()
        let span = doc.placedSpan(atTimeMS: 4000)
        #expect(span?.inMS == 4000)
        #expect(span?.outMS == 4000 + TitleTime.defaultLengthMS)
    }

    @Test func aDocumentWithNoTimeGivesNothingAStretch() {
        // Every screenshot and every drawing: nothing new, nowhere.
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [Self.words("Hello")]
        #expect(doc.placedSpan(atTimeMS: 0) == nil)
    }

    @Test func aStretchNeverRunsPastTheLastFrame() {
        let doc = Self.eightSeconds()
        let span = doc.placedSpan(atTimeMS: 7000)
        #expect(span?.inMS == 7000)
        #expect(span?.outMS == 8000)
    }

    @Test func aStretchAskedForOnTheLastFrameIsStillSomethingYouCanGrab() {
        let doc = Self.eightSeconds()
        let span = doc.placedSpan(atTimeMS: 7999)
        #expect((span?.lengthMS ?? 0) >= LayerTime.shortestMS)
        #expect((span?.outMS ?? 0) <= 8000)
    }

    @Test func textOnAHeldFrameTakesTheHoldRatherThanThreeSeconds() {
        // The rule `HeldFrame` already set for a mark drawn on a frozen frame
        // holds for words too: what is on screen for the hold is on screen for
        // the hold.
        var doc = Self.eightSeconds()
        var clip = doc.layers[0]
        clip.movie = nil
        var pieces = clip.clipPieces ?? ClipPieces(single: LayerTime(inMS: 0, outMS: 8000))
        _ = pieces.holdFrame(atMS: 4000, forMS: 2000)
        clip.setClipPieces(pieces)
        doc.layers[0] = clip
        doc.durationMS = nil
        guard let held = doc.heldFrame(atTimeMS: 4500) else {
            Issue.record("the stand-in clip is not holding a frame at 4.5s")
            return
        }
        #expect(doc.placedSpan(atTimeMS: 4500) == held.span)
    }

    // MARK: - Placed in time is not the same as playing

    @Test func aLayerPlacedInTimePlaysNothing() {
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 1000, outMS: 4000)
        #expect(title.isPlacedInTime)
        #expect(title.startIsFree)
        #expect(!title.isClip)
    }

    @Test func aClipIsNotPlacedInTime() {
        let clip = Self.eightSeconds().layers[0]
        #expect(!clip.isPlacedInTime)
        #expect(!clip.startIsFree)
    }

    @Test func aLayerWithNoStretchAtAllIsNotPlacedInTime() {
        #expect(!Self.words("Hello").isPlacedInTime)
    }

    @Test func aTitleIsNeverTheClipInHand() {
        // The bug this closes: a mark drawn on a held frame answered
        // `clipToTrim`, so the panel offered it a speed and a held frame, and
        // B would have cut it into pieces. Picking one now leaves nothing in
        // hand, so nothing about media is offered for it; with nothing picked
        // the clip under the playhead answers, and the mark never does.
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 3000, outMS: 6000)
        doc.layers.append(title)
        #expect(doc.clipToTrim(pickedLayerID: title.id, atTimeMS: 4000) == nil)
        #expect(doc.clipToTrim(pickedLayerID: nil, atTimeMS: 4000) == doc.layers[0].id)
    }

    // MARK: - Both ends, on the timeline

    @Test func theStartOfATitleMovesAndTheEndStaysPut() {
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 3000, outMS: 6000)
        let id = title.id
        doc.layers.append(title)
        let did1 = doc.moveLayerStart(id, toMS: 1500)
        #expect(did1)
        #expect(doc.layer(id: id)?.time?.inMS == 1500)
        #expect(doc.layer(id: id)?.time?.outMS == 6000)
    }

    @Test func aTitleCannotStartBeforeTheFirstFrame() {
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 3000, outMS: 6000)
        let id = title.id
        doc.layers.append(title)
        let did2 = doc.moveLayerStart(id, toMS: -2000)
        #expect(did2)
        #expect(doc.layer(id: id)?.time?.inMS == 0)
    }

    @Test func aTitlesStartCannotPassItsEnd() {
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 3000, outMS: 6000)
        let id = title.id
        doc.layers.append(title)
        let did3 = doc.moveLayerStart(id, toMS: 9000)
        #expect(did3)
        #expect(doc.layer(id: id)?.time?.lengthMS == LayerTime.shortestMS)
        #expect(doc.layer(id: id)?.time?.outMS == 6000)
    }

    @Test func aClipsStartIsNotFreeToMove() {
        // There ARE frames behind a clip's in point, so its left end is a trim
        // into them rather than a choice about when it starts.
        var doc = Self.eightSeconds()
        let id = doc.layers[0].id
        let did4 = doc.moveLayerStart(id, toMS: 1000)
        #expect(!did4)
        #expect(doc.layer(id: id)?.time?.inMS == 0)
    }

    @Test func theEndOfATitleMovesAndTheStartStaysPut() {
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 3000, outMS: 6000)
        let id = title.id
        doc.layers.append(title)
        let did5 = doc.moveLayerEnd(id, toMS: 7500)
        #expect(did5)
        #expect(doc.layer(id: id)?.time?.inMS == 3000)
        #expect(doc.layer(id: id)?.time?.outMS == 7500)
    }

    @Test func aTitleDraggedOffTheEndOfTheDocumentMakesTheDocumentLonger() {
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 3000, outMS: 6000)
        let id = title.id
        doc.layers.append(title)
        let did6 = doc.moveLayerEnd(id, toMS: 12_000)
        #expect(did6)
        #expect(doc.documentDurationMS == 12_000)
    }

    // MARK: - A bar with nothing behind it

    @Test func theLeftEndOfAPlacedBarIsUnstoppedGoingOut() {
        // A clip's left end can only go as far out as there is recording
        // behind it. A title has nothing behind it, so what stops it is the
        // start of the document, which the drag itself clamps.
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 3000, outMS: 6000)
        let drag = ClipBarDrag(grab: .clipStart, pieces: title.clipPieces!,
                               clipStartMS: 3000, startIsFree: true)
        let landing = drag.landing(byMS: -1500)
        #expect(landing.clipStartMS == 1500)
        #expect(landing.pieces.totalLengthMS == 4500)
    }

    @Test func theLeftEndOfAClipsBarStillTrimsIntoWhatIsBehindIt() {
        let time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 1000, sourceLengthMS: 8000)
        let drag = ClipBarDrag(grab: .clipStart, pieces: ClipPieces(single: time),
                               clipStartMS: 0)
        let landing = drag.landing(byMS: -500)
        // Where it always was: a trim does not move the clip.
        #expect(landing.clipStartMS == 0)
        #expect(landing.pieces.totalLengthMS == 4500)
    }

    // MARK: - Coming on and going off, with the animation model

    @Test func aFadeIsAnOrdinaryOpacityMotion() {
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 2000, outMS: 5000)
        let id = title.id
        doc.layers.append(title)
        let did7 = doc.setTitleFade(id, toMS: 500)
        #expect(did7)
        let motions = doc.layer(id: id)?.motions ?? []
        #expect(motions.count == 1)
        #expect(motions.first?.property == .opacity)
        #expect(motions.first?.repeats == .once)
        #expect(doc.layer(id: id)?.titleFadeMS == 500)
    }

    @Test func aFadedTitleIsInvisibleAtItsFirstFrameAndFullAfterTheFade() {
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 2000, outMS: 5000)
        let id = title.id
        doc.layers.append(title)
        let did8 = doc.setTitleFade(id, toMS: 500)
        #expect(did8)

        func opacity(atMS ms: Int) -> Double? {
            doc.drawn(atTimeMS: ms).layer(id: id).map { Double($0.style.opacity) }
        }
        #expect((opacity(atMS: 2000) ?? 1) < 0.02)
        #expect((opacity(atMS: 2500) ?? 0) > 0.98)
        #expect((opacity(atMS: 3500) ?? 0) > 0.98)
        #expect((opacity(atMS: 4900) ?? 1) < 0.35)
    }

    @Test func aTitleDraggedLongerKeepsItsFade() {
        // The thing absolute milliseconds get wrong: the last key stays where
        // it was, so the words go out early and never come back. The fade is
        // refitted to the stretch it is on.
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 2000, outMS: 5000)
        let id = title.id
        doc.layers.append(title)
        let did9 = doc.setTitleFade(id, toMS: 500)
        #expect(did9)
        let did10 = doc.moveLayerEnd(id, toMS: 7000)
        #expect(did10)
        #expect(doc.layer(id: id)?.titleFadeMS == 500)
        let middle = doc.drawn(atTimeMS: 5500).layer(id: id)
        #expect(Double(middle?.style.opacity ?? 0) > 0.98)
    }

    @Test func aFadeNobodyAskedForIsNotWritten() {
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 2000, outMS: 5000)
        let id = title.id
        doc.layers.append(title)
        #expect(doc.layer(id: id)?.titleFadeMS == nil)
        let did11 = doc.setTitleFade(id, toMS: 500)
        #expect(did11)
        let did12 = doc.setTitleFade(id, toMS: 0)
        #expect(did12)
        #expect(doc.layer(id: id)?.motions == nil)
        #expect(doc.layer(id: id)?.titleFadeMS == nil)
    }

    @Test func aFadeNeverEatsTheWholeTitle() {
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 2000, outMS: 2600)
        let id = title.id
        doc.layers.append(title)
        let did13 = doc.setTitleFade(id, toMS: 1000)
        #expect(did13)
        // Half in and half out at most, so there is always a moment the words
        // are fully up.
        #expect((doc.layer(id: id)?.titleFadeMS ?? 0) <= 300)
    }

    @Test func aMotionSomebodyEditedByHandIsLeftAlone() {
        // Once the shape stops being the one the Fade row writes, the fade row
        // reads nothing and nothing refits it: their edit wins.
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 2000, outMS: 5000)
        title.motions = [LayerMotion(property: .opacity, from: .number(20), to: .number(90),
                                     timing: MotionTiming(startMS: 0, durationMS: 900),
                                     curve: .easeInOut, repeats: .once)]
        let id = title.id
        doc.layers.append(title)
        #expect(doc.layer(id: id)?.titleFadeMS == nil)
        let did14 = doc.moveLayerEnd(id, toMS: 7000)
        #expect(did14)
        #expect(doc.layer(id: id)?.motions?.first?.timing.durationMS == 900)
        #expect(doc.layer(id: id)?.motions?.first?.from == .number(20))
    }

    // MARK: - The bar says what the words say

    @Test func aTitlesBarIsNamedAfterWhatItSays() {
        var doc = Self.eightSeconds()
        var title = Self.words("Shipping today")
        title.name = "Text"
        title.time = LayerTime(inMS: 2000, outMS: 5000)
        doc.layers.append(title)
        let rows = doc.motionStrip()
        // The title is the last layer in the document, so it draws on top, so
        // it is the FIRST row of the strip (`LayerCompositing.swift`).
        #expect(rows.first?.layerName == "Shipping today")
        #expect(rows.first?.bar == title.time)
    }

    @Test func aTitleSomebodyNamedKeepsTheNameTheyGaveIt() {
        var doc = Self.eightSeconds()
        var title = Self.words("Shipping today")
        title.name = "Opening card"
        title.time = LayerTime(inMS: 2000, outMS: 5000)
        doc.layers.append(title)
        #expect(doc.motionStrip().first?.layerName == "Opening card")
    }

    @Test func aFadesLaneIsDrawnWhereTheFadeActuallyHappens() {
        // A motion is written in its layer's own clock and the timeline is
        // drawn in the document's. A fade on a title that arrives at two
        // seconds happens at two seconds, and a lane drawn at nought would say
        // the words come on before they exist.
        var doc = Self.eightSeconds()
        var title = Self.words("Shipping today")
        title.time = LayerTime(inMS: 2000, outMS: 5000)
        let id = title.id
        doc.layers.append(title)
        let did = doc.setTitleFade(id, toMS: 500)
        #expect(did)
        let lane = doc.motionStrip().first?.lanes.first
        #expect(lane?.timing.startMS == 2000)
        #expect(lane?.timing.endMS == 5000)
        // ...and the motion itself is untouched, in its own clock.
        #expect(doc.layer(id: id)?.motions?.first?.timing.startMS == 0)
    }

    @Test func anIconsLanesAreExactlyWhereTheyAlwaysWere() {
        // Nothing occupies time, so nothing moves along.
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        var bell = Self.words("Bell")
        bell.motions = [LayerMotion(property: .rotation, from: .number(0), to: .number(20),
                                    timing: MotionTiming(startMS: 120, durationMS: 400))]
        doc.layers = [bell]
        #expect(doc.motionStrip().first?.lanes.first?.timing.startMS == 120)
    }

    // MARK: - Nothing else about it is special

    @Test func aSavedTextStyleDressesATitleLikeAnyOtherText() {
        // The half of "nothing else about it is special" that is easiest to
        // get wrong: a title is not a new kind of layer, so everything the
        // library already does to words does to these.
        var doc = Self.eightSeconds()
        let heading = Layer(name: "A heading",
                            content: .text(TextContent(string: "A heading", fontName: "Georgia",
                                                       fontSize: 44, colorHex: "#FFCC00",
                                                       weight: .bold)),
                            frame: CGRect(x: 0, y: 0, width: 300, height: 60))
        var title = Self.words("Shipping today")
        title.time = LayerTime(inMS: 2000, outMS: 5000)
        let id = title.id
        doc.layers.append(contentsOf: [heading, title])
        guard let style = doc.saveTextStyle(from: [heading.id], name: "Display") else {
            Issue.record("the heading did not save as a style")
            return
        }
        let dressed = doc.bindTextStyle(layerIDs: [id], styleID: style)
        #expect(dressed)
        #expect(doc.layer(id: id)?.textStyleID == style)
        #expect(doc.layer(id: id)?.text?.fontSize == 44)
        // ...and it is still on screen for exactly the stretch it was.
        #expect(doc.layer(id: id)?.time == LayerTime(inMS: 2000, outMS: 5000))
    }

    @Test func wordsOverAPictureKeepTheContrastShadowTheyAlwaysHad() {
        // The acceptance item about staying readable over whatever is behind
        // it: it is the shadow every text layer in this app is built with,
        // which is the answer the app already had for text over a picture it
        // did not choose.
        let built = TextBuilder.layer(content: TextContent(string: "Shipping today",
                                                           colorHex: "#111111"),
                                      at: .zero, naturalSize: CGSize(width: 200, height: 40))
        #expect(built.style.shadow != nil)
    }

    // MARK: - What plays is what exports

    @Test func everyExportedFrameShowsWhatPlaybackShowsAtThatMoment() {
        // Frame by frame, over the whole file: the moment the exporter
        // photographs is the moment the player draws, so the words are in the
        // file for exactly the frames they are on screen for.
        var doc = Self.eightSeconds()
        var title = Self.words("Hello")
        title.time = LayerTime(inMS: 2000, outMS: 5000)
        let id = title.id
        doc.layers.append(title)
        let plan = DocumentVideoExport.plan(durationMS: doc.documentDurationMS,
                                            canvasSize: doc.canvasSize,
                                            format: .mp4, quality: .high)
        #expect(plan.frameCount > 200)
        var on = 0
        for index in 0..<plan.frameCount {
            let ms = plan.timeMS(at: index)
            let shown = doc.drawn(atTimeMS: ms).layer(id: id)
            let onScreen = shown?.isVisible == true
            #expect(onScreen == (ms >= 2000 && ms < 5000))
            if onScreen { on += 1 }
        }
        // ...and it really was on screen for about three seconds of them,
        // rather than the comparison passing because it was never on at all.
        #expect(on > 80)
    }
}
