import Foundation
import PhotonzCore
import Testing

/// **The timeline never jumps when the recording changes length**
/// (`TimelineZoomGlide.swift`; user 2026-10-28: "we go from one zoom level to
/// another not gracefully; there's no transition but it just immediately
/// snaps").
///
/// The zoom is kept as a share of the length, so a clip let go past the end,
/// the room made for one in the air, or an undo of either moved every second
/// on the strip in one frame. Now the seconds on screen stay put through the
/// change, and a timeline opened right out glides to twice the new length.
///
/// Written before the change, which is the rule for `PhotonzCore`.
@Suite("The timeline glides when the recording changes length")
struct TimelineZoomGlideTests {

    static let eight: Double = 8000
    static let twenty: Double = 20000

    // MARK: - The seconds on screen stay put

    @Test func aLongerRecordingKeepsTheSecondsOnScreen() {
        // Sixteen seconds across (eight, opened right out), and the recording
        // grows to sixteen: still sixteen across, now at Fit.
        let zoom = TimelineZoom(scale: 0.5, startMS: 0)
        let held = zoom.holdingSpan(fromDocumentMS: Self.eight, toDocumentMS: 16000)
        #expect(abs(held.visibleMS(documentMS: 16000) - 16000) < 0.001)
        #expect(held.startMS == 0)
    }

    @Test func aZoomedInWindowStaysOnTheSameFrames() {
        // Half a second across at 3s into an eight second recording; a clip
        // lands past the end and the recording runs twenty. The frames being
        // cut between do not move.
        let zoom = TimelineZoom(scale: 16, startMS: 3000)
        let held = zoom.holdingSpan(fromDocumentMS: Self.eight, toDocumentMS: Self.twenty)
        #expect(abs(held.visibleMS(documentMS: Self.twenty) - 500) < 0.001)
        #expect(held.startMS == 3000)
    }

    @Test func aShorterRecordingKeepsWhatItCanAndNoMore() {
        // Forty seconds across a twenty second recording cut back to eight:
        // twice eight is as far out as eight goes.
        let zoom = TimelineZoom(scale: 0.5, startMS: 0)
        let held = zoom.holdingSpan(fromDocumentMS: Self.twenty, toDocumentMS: Self.eight)
        #expect(abs(held.visibleMS(documentMS: Self.eight) - 16000) < 0.001)
    }

    // MARK: - Opened right out, it glides to twice the new length

    @Test func opensRightOutGlidesOutToTwiceTheNewLength() throws {
        let zoom = TimelineZoom(scale: 0.5, startMS: 0)
        let glide = try #require(TimelineZoomGlide(from: zoom, documentMS: Self.eight,
                                                   to: Self.twenty))
        // It starts on exactly what was on screen...
        #expect(abs(glide.zoom(at: 0).visibleMS(documentMS: glide.heldMS) - 16000) < 0.001)
        // ...ends on twice the new length...
        #expect(abs(glide.zoom(at: 1).visibleMS(documentMS: glide.heldMS) - 40000) < 0.001)
        #expect(glide.landing.scale == TimelineZoom.farthestOutScale)
        #expect(abs(glide.landing.visibleMS(documentMS: Self.twenty) - 40000) < 0.001)
        // ...and goes one way only between.
        var last = 0.0
        for step in 0...10 {
            let span = glide.zoom(at: Double(step) / 10).visibleMS(documentMS: glide.heldMS)
            #expect(span >= last)
            last = span
        }
    }

    @Test func opensRightOutGlidesInWhenTheRecordingShrinks() throws {
        // An undo of that clip: forty across, back to sixteen, and never the
        // forty clamped to sixteen in one frame first.
        let zoom = TimelineZoom(scale: 0.5, startMS: 0)
        let glide = try #require(TimelineZoomGlide(from: zoom, documentMS: Self.twenty,
                                                   to: Self.eight))
        #expect(glide.heldMS == Self.twenty)
        #expect(abs(glide.zoom(at: 0).visibleMS(documentMS: glide.heldMS) - 40000) < 0.001)
        #expect(abs(glide.zoom(at: 1).visibleMS(documentMS: glide.heldMS) - 16000) < 0.001)
        // Where it lands, measured against the new length, is where the glide
        // ended, so letting go of the held length moves nothing.
        #expect(abs(glide.landing.visibleMS(documentMS: Self.eight) - 16000) < 0.001)
    }

    @Test func eachMomentOfAGlideIsAWindowTheHeldLengthAllows() throws {
        let zoom = TimelineZoom(scale: 0.5, startMS: 0)
        for (from, to) in [(Self.eight, Self.twenty), (Self.twenty, Self.eight)] {
            let glide = try #require(TimelineZoomGlide(from: zoom, documentMS: from, to: to))
            for step in 0...10 {
                let moment = glide.zoom(at: Double(step) / 10)
                #expect(moment == moment.clamped(documentMS: glide.heldMS))
            }
        }
    }

    @Test func fitStaysFitAndGlidesThere() throws {
        // The whole recording across the width, and it grows from eight
        // seconds to five minutes: still the whole of it, at Fit, glided to.
        let glide = try #require(TimelineZoomGlide(from: .fit, documentMS: Self.eight, to: 300_000))
        #expect(abs(glide.zoom(at: 0).visibleMS(documentMS: glide.heldMS) - Self.eight) < 0.001)
        #expect(glide.landing.isFit)
        #expect(abs(glide.landing.visibleMS(documentMS: 300_000) - 300_000) < 0.001)
    }

    @Test func showingTheWholeRecordingIsWhatGlides() {
        // Fit or further out shows the whole recording, and goes on showing
        // it; zoomed in to a stretch, the seconds on screen stay instead.
        #expect(TimelineZoom.fit.showsWholeDocument)
        #expect(TimelineZoom.opening.showsWholeDocument)
        #expect(!TimelineZoom(scale: 2).showsWholeDocument)
    }

    @Test func aGlideLandsOnTheShareThatWasChosen() throws {
        // At Fit on eight seconds, a file in the air made it sixteen and the
        // eight seconds on screen were held (2x of sixteen). Carried off
        // again, it is Fit that comes back, not 2x of eight.
        let held = TimelineZoom(scale: 2, startMS: 0)
        let glide = try #require(TimelineZoomGlide(from: held, documentMS: 16000, to: Self.eight,
                                                   landingScale: 1))
        #expect(glide.landing.isFit)
        #expect(abs(glide.zoom(at: 0).visibleMS(documentMS: glide.heldMS) - Self.eight) < 0.001)
    }

    @Test func nothingToGlideWhenTheLengthIsTheSame() {
        #expect(TimelineZoomGlide(from: .opening, documentMS: Self.eight, to: Self.eight) == nil)
    }

    @Test func aGlideStartsFromWhereTheWindowWasScrolled() throws {
        // Scrolled along to 4s, opened right out: the glide begins there and
        // the landing is wherever the new length lets it stand.
        let zoom = TimelineZoom(scale: 0.5, startMS: 4000)
        let glide = try #require(TimelineZoomGlide(from: zoom, documentMS: Self.eight,
                                                   to: Self.twenty))
        #expect(glide.zoom(at: 0).startMS == 4000)
        #expect(glide.landing == glide.landing.clamped(documentMS: Self.twenty))
        #expect(glide.zoom(at: 1).startMS == glide.landing.startMS)
    }
}
