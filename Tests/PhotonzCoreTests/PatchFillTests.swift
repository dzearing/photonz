import Foundation
import PhotonzCore
import Testing

/// What goes into the space a piece came out of, and when the app refuses to
/// guess (`docs/design/separate-into-layers.md`).
@Suite("Deciding what fills the space a piece came out of")
struct PatchFillTests {

    /// A ring of samples all round a box, `perSide` of them on each side.
    private func ring(perSide: Int = 12, color: (Double, Double) -> RGBA) -> PatchRing {
        var samples: [PatchRing.Sample] = []
        for i in 0..<perSide {
            let t = (Double(i) + 0.5) / Double(perSide)
            samples.append(.init(u: t, v: -0.05, color: color(t, -0.05)))
            samples.append(.init(u: t, v: 1.05, color: color(t, 1.05)))
            samples.append(.init(u: -0.05, v: t, color: color(-0.05, t)))
            samples.append(.init(u: 1.05, v: t, color: color(1.05, t)))
        }
        return PatchRing(samples: samples)
    }

    private let blue = RGBA(r: 0.04, g: 0.51, b: 0.98)

    @Test func aRingThatAgreesWithItselfFillsFlatAndExactly() {
        let fill = PatchDecision.decide(ring { _, _ in blue })
        #expect(fill == .solid(blue))
        // Exact, everywhere in the box: white words on a solid blue button
        // leave that button one colour, not an average of one.
        #expect(fill?.color(u: 0, v: 0) == blue)
        #expect(fill?.color(u: 1, v: 1) == blue)
        #expect(fill?.color(u: 0.5, v: 0.5) == blue)
    }

    @Test func oneStraySampleDoesNotDragTheFlatColourOff() {
        var samples = ring { _, _ in blue }.samples
        samples[3] = .init(u: samples[3].u, v: samples[3].v, color: RGBA(r: 1, g: 0, b: 0))
        // The middle is a median, so one red pixel in a blue ring is outvoted
        // rather than averaged in. It still costs the flat answer, because the
        // ring no longer agrees with itself — which is the honest outcome.
        let fill = PatchDecision.decide(PatchRing(samples: samples))
        #expect(fill == nil)
    }

    @Test func aRingThatRampsDownFillsWithThatRamp() {
        let fill = PatchDecision.decide(ring { _, v in
            RGBA(r: 0.2 + 0.6 * v, g: 0.2 + 0.6 * v, b: 0.2 + 0.6 * v)
        })
        guard case .gradient(let start, let end, let axis)? = fill else {
            Issue.record("expected a gradient, got \(String(describing: fill))")
            return
        }
        #expect(axis == .down)
        #expect(abs(start.r - 0.2) < 0.01)
        #expect(abs(end.r - 0.8) < 0.01)
        // And it reads back as the ramp in the middle of the box, not at its
        // edges, which is where the pixels it has to fill actually are.
        #expect(abs((fill?.color(u: 0.5, v: 0.5).r ?? 0) - 0.5) < 0.01)
    }

    @Test func aRingThatRampsAcrossPicksTheOtherAxis() {
        let fill = PatchDecision.decide(ring { u, _ in
            RGBA(r: 0.1 + 0.8 * u, g: 0.3, b: 0.3)
        })
        guard case .gradient(_, _, let axis)? = fill else {
            Issue.record("expected a gradient, got \(String(describing: fill))")
            return
        }
        #expect(axis == .across)
    }

    @Test func aRingThatIsNeitherIsRefused() {
        // A photograph: every sample somewhere else. Neither flat nor a ramp,
        // so the piece is left in the picture rather than smeared over.
        var seed = 1
        func noise() -> Double {
            seed = (seed &* 1103515245 &+ 12345) & 0x7FFF_FFFF
            return Double(seed % 1000) / 1000
        }
        #expect(PatchDecision.decide(ring { _, _ in
            RGBA(r: noise(), g: noise(), b: noise())
        }) == nil)
    }

    @Test func tooFewSamplesIsRefused() {
        let thin = PatchRing(samples: (0..<4).map {
            .init(u: Double($0) / 4, v: 0, color: blue)
        })
        #expect(PatchDecision.decide(thin) == nil)
    }

    @Test func anEmptyRingIsRefused() {
        #expect(PatchDecision.decide(PatchRing(samples: [])) == nil)
    }

    @Test func aGradientReadsTheSameAtBothEndsWhicheverWayItRuns() {
        let down = PatchFill.gradient(start: RGBA(r: 0, g: 0, b: 0),
                                      end: RGBA(r: 1, g: 1, b: 1), axis: .down)
        #expect(down.color(u: 0.9, v: 0).r == 0)
        #expect(down.color(u: 0.1, v: 1).r == 1)
        let across = PatchFill.gradient(start: RGBA(r: 0, g: 0, b: 0),
                                        end: RGBA(r: 1, g: 1, b: 1), axis: .across)
        #expect(across.color(u: 0, v: 0.9).r == 0)
        #expect(across.color(u: 1, v: 0.1).r == 1)
    }

    @Test func aFillNeverReadsOutsideItsOwnEnds() {
        // A ring sample sits a little past the box, so the fit is asked for
        // colours at 1.05 and -0.05. They clamp rather than running off the end
        // of the ramp into a colour that was never in the picture.
        let fill = PatchFill.gradient(start: RGBA(r: 0.2, g: 0.2, b: 0.2),
                                      end: RGBA(r: 0.8, g: 0.8, b: 0.8), axis: .down)
        #expect(fill.color(u: 0, v: -2).r == 0.2)
        #expect(fill.color(u: 0, v: 4).r == 0.8)
    }
}

/// What the pill says after Separate into Layers, which is the only thing on
/// screen that says the command did anything: the canvas is identical the
/// instant after (`docs/design/separate-into-layers.md`).
@Suite("What the separate pill says")
struct SeparateNoticeTests {

    private func pill(runs: Int, boxes: Int = 0, skipped: Int,
                      crowded: Int = 0) -> CopyConfirmation {
        CopyConfirmation(subject: .separatedIntoLayers(runs: runs, boxes: boxes,
                                                       skipped: skipped, crowded: crowded),
                         shownAt: Date())
    }

    @Test func itCountsWhatCameOut() {
        #expect(pill(runs: 9, skipped: 0).title == "Separated")
        #expect(pill(runs: 9, skipped: 0).detail == "9 runs of text")
        #expect(pill(runs: 1, skipped: 0).detail == "1 run of text")
    }

    @Test func itCountsTheBoxesBesideTheWords() {
        #expect(pill(runs: 9, boxes: 4, skipped: 0).detail == "9 runs of text and 4 boxes")
        #expect(pill(runs: 1, boxes: 1, skipped: 0).detail == "1 run of text and 1 box")
        // A picture with boxes in it and no text says only what it found.
        #expect(pill(runs: 0, boxes: 2, skipped: 0).detail == "2 boxes")
        #expect(pill(runs: 0, boxes: 2, skipped: 0).title == "Separated")
    }

    @Test func itAlsoSaysWhatWasLeftBehind() {
        #expect(pill(runs: 4, skipped: 2).detail
            == "4 runs of text. 2 left in the picture, too unclear to read")
        #expect(pill(runs: 4, boxes: 1, skipped: 2).detail
            == "4 runs of text and 1 box. 2 left in the picture, too unclear to read")
    }

    @Test func aSecondRunOnTheSamePictureSaysThereIsNothingThere() {
        // The first run took the text, so there is none to find: NOT "could not
        // be read", which would be a different and untrue thing to say.
        #expect(pill(runs: 0, skipped: 0).title == "Nothing to separate")
        #expect(pill(runs: 0, skipped: 0).detail == "Nothing here reads as text or a box")
    }

    @Test func aPictureItCannotReadSaysSoInstead() {
        #expect(pill(runs: 0, skipped: 3).detail
            == "3 pieces left in the picture, too unclear to read")
        #expect(pill(runs: 0, skipped: 1).detail
            == "1 piece left in the picture, too unclear to read")
    }

    @Test func aPictureWithMorePiecesThanOneCommandTakesSaysWhatToDoNext() {
        // The limit case, which is NOT the same sentence as "could not read
        // it": these are pieces the app read perfectly well and chose to leave,
        // and the thing to do about them is run the command again.
        #expect(pill(runs: 100, boxes: 2, skipped: 0, crowded: 290).detail
            == "100 runs of text and 2 boxes. 290 left in the picture, run it again for more")
        // Both reasons in one picture: the count is everything still in it,
        // because that is the number a person can check by looking.
        #expect(pill(runs: 100, skipped: 2, crowded: 290).detail
            == "100 runs of text. 292 left in the picture, run it again for more")
    }

    @Test func itDoesNotOfferAnotherRunWhenNothingCameOutOfThisOne() {
        // Running it again would find the same pieces and fail on them the
        // same way, so the line that says to would be sending somebody round a
        // loop.
        #expect(pill(runs: 0, skipped: 2, crowded: 1).detail
            == "3 pieces left in the picture, too unclear to read")
    }

    @Test func aPhotographIsToldItIsAPhotographRatherThanGivenANumber() {
        // MEASURED on a real photograph of a mountain: the sweep finds 437
        // pieces in the grass and the rock and can read none of them. Saying
        // "437 left in the picture" is true about texture and useless about the
        // photograph, and it reads as the app having failed at something.
        #expect(pill(runs: 0, skipped: 150, crowded: 287).detail
            == "Nothing here reads as text or a box")
        #expect(pill(runs: 0, skipped: 437).title == "Nothing to separate")
        // A caption burnt into a photograph is the case the count is FOR, and
        // it still says it: you are looking straight at the words wondering why
        // they are still there.
        #expect(pill(runs: 0, skipped: 1).detail
            == "1 piece left in the picture, too unclear to read")
    }

    @Test func itStaysUpLongEnoughToRead() {
        // Two sentences with numbers in them, so it takes the longer clock the
        // notices you might act on take.
        #expect(pill(runs: 9, skipped: 2).lifetime == CopyConfirmation.breakLifetime)
    }
}
