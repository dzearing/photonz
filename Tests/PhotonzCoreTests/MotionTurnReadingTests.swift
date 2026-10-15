import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// What the timing strip says about a Forever spinner: how long one turn takes,
/// and whether the turn ends where it starts.
///
/// The mock (`icon-loop-wt.html`): with Forever on it, Over "becomes how long
/// one turn takes, which is why the dock calls it a turn and not a length", and
/// "beside the turn length the dock says ends where it starts, which is the
/// only thing a repeating animation must get right and the one thing the eye
/// will not catch."
@Suite("The strip reads a Forever turn")
struct MotionTurnReadingTests {

    static func spinner(from: Double = 0, to: Double = 360, over: Int = 800,
                        repeats: MotionRepeat = .forever, on: Bool = true) -> LayerMotion {
        LayerMotion(property: .rotation, from: .number(from), to: .number(to),
                    timing: MotionTiming(startMS: 0, durationMS: over),
                    curve: .linear, repeats: repeats, isOn: on)
    }

    @Test("A Forever spinner reads its turn length the way the mock prints it")
    func turnLength() throws {
        let reading = try #require(MotionTurnReading.reading(of: [Self.spinner()]))
        #expect(reading.turnMS == 800)
        #expect(reading.lengthText == "800 ms per turn")
    }

    @Test("A turn of a second or more reads in seconds, as the mock's 1.2 s does")
    func secondsAboveASecond() throws {
        #expect(try #require(MotionTurnReading.reading(of: [Self.spinner(over: 1200)]))
            .lengthText == "1.2 s per turn")
        #expect(try #require(MotionTurnReading.reading(of: [Self.spinner(over: 1000)]))
            .lengthText == "1 s per turn")
        #expect(try #require(MotionTurnReading.reading(of: [Self.spinner(over: 1250)]))
            .lengthText == "1.25 s per turn")
    }

    @Test("0 to 360 is the same picture at both ends, so it joins")
    func fullTurnJoins() throws {
        let reading = try #require(MotionTurnReading.reading(of: [Self.spinner()]))
        #expect(reading.joins)
        #expect(reading.joinText == "ends where it starts")
    }

    @Test("Two whole turns, and a turn the other way, join too")
    func wholeTurnsJoin() throws {
        #expect(try #require(MotionTurnReading.reading(of: [Self.spinner(to: 720)])).joins)
        #expect(try #require(MotionTurnReading.reading(of: [Self.spinner(from: 90, to: -270)])).joins)
    }

    @Test("A turn that stops short jumps at the join, and the strip says so")
    func shortTurnDoesNotJoin() throws {
        let reading = try #require(MotionTurnReading.reading(of: [Self.spinner(to: 300)]))
        #expect(!reading.joins)
        #expect(reading.joinText == "does not end where it starts")
    }

    @Test("A fade that comes back to where it began joins; one that does not, jumps")
    func otherPropertiesJoinOnlyWhenTheEndsAgree() throws {
        func fade(to: Double) -> LayerMotion {
            LayerMotion(property: .opacity, from: .number(100), to: .number(to),
                        timing: MotionTiming(startMS: 0, durationMS: 600), repeats: .forever)
        }
        #expect(try #require(MotionTurnReading.reading(of: [fade(to: 100)])).joins)
        #expect(try #require(MotionTurnReading.reading(of: [fade(to: 0)])).joins == false)
        // An opacity of 0 and 360 is not a whole turn: only angles wrap.
        let wrapped = LayerMotion(property: .opacity, from: .number(0), to: .number(360),
                                  timing: MotionTiming(startMS: 0, durationMS: 600),
                                  repeats: .forever)
        #expect(try #require(MotionTurnReading.reading(of: [wrapped])).joins == false)
    }

    @Test("Colours join when they are the same colour however they are written")
    func coloursJoinByValue() throws {
        let colour = LayerMotion(property: .color, from: .color("#ff0000"), to: .color("#FF0000"),
                                 timing: MotionTiming(startMS: 0, durationMS: 600),
                                 repeats: .forever)
        #expect(try #require(MotionTurnReading.reading(of: [colour])).joins)
    }

    @Test("Only a one way Forever has a turn: there and back, Once and a count have none")
    func onlyOneWayForever() {
        #expect(MotionTurnReading.reading(of: [Self.spinner(repeats: .foreverThereAndBack)]) == nil)
        #expect(MotionTurnReading.reading(of: [Self.spinner(repeats: .once)]) == nil)
        #expect(MotionTurnReading.reading(of: [Self.spinner(repeats: .times(3))]) == nil)
        #expect(MotionTurnReading.reading(of: []) == nil)
    }

    @Test("A spinner switched off has no turn to read")
    func switchedOffHasNoTurn() {
        #expect(MotionTurnReading.reading(of: [Self.spinner(on: false)]) == nil)
    }

    @Test("Beside a swing on the same layer, the Forever one is the one read")
    func readsTheForeverOneAmongOthers() throws {
        let swing = Self.spinner(from: -12, to: 12, over: 900, repeats: .foreverThereAndBack)
        let reading = try #require(MotionTurnReading.reading(of: [swing, Self.spinner(over: 700)]))
        #expect(reading.lengthText == "700 ms per turn")
    }

    @Test("A lone spinner's turn IS the lap, so the strip calls itself One turn and drops the lap")
    func aLoneSpinnerReplacesTheLap() {
        #expect(MotionTurnReading.replacesTheLap(motions: [Self.spinner()], lapIsAutomatic: true))
        #expect(MotionStripCopy.turnTitle == "One turn")
    }

    @Test("Beside a swing that shares the lap, the lap stays, and so does a lap somebody typed")
    func theLapStaysWhenSomethingSharesIt() {
        let swing = Self.spinner(from: -12, to: 12, over: 900, repeats: .foreverThereAndBack)
        #expect(!MotionTurnReading.replacesTheLap(motions: [swing, Self.spinner()],
                                                  lapIsAutomatic: true))
        #expect(!MotionTurnReading.replacesTheLap(motions: [Self.spinner()], lapIsAutomatic: false))
        #expect(!MotionTurnReading.replacesTheLap(motions: [], lapIsAutomatic: true))
        // A swing switched off shares nothing.
        let off = Self.spinner(from: -12, to: 12, over: 900, repeats: .once, on: false)
        #expect(MotionTurnReading.replacesTheLap(motions: [off, Self.spinner()], lapIsAutomatic: true))
    }

    @Test("Both lines fit the chrome's budget")
    func withinTheChromeBudget() throws {
        let long = try #require(MotionTurnReading.reading(of: [Self.spinner(to: 300, over: 98_765)]))
        #expect(long.lengthText.count <= 30)
        #expect(long.joinText.count <= 30)
    }
}
