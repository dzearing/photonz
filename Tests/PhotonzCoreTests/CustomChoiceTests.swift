import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A menu that says Custom lets you pick Custom
/// (task `a-menu-that-says-custom-lets-you-get-back-to-cus`).
///
/// Drag a pivot somewhere of your own, open Around to see what Top centre
/// looks like, pick it, and your own point used to be gone: Custom was a word
/// the menu printed and would not let you choose. The one answer, for every
/// menu with a value of your own in it, is that the menu keeps the last one you
/// made and picking Custom puts it back.
@Suite("A menu that says Custom lets you pick Custom")
struct CustomChoiceTests {

    // MARK: - The one answer

    @Test("Nothing of your own yet means there is no Custom to go back to")
    func nothingKeptOffersNothing() {
        let choice = CustomChoice<Int>()
        #expect(choice.kept == nil)
        #expect(choice.custom(current: 3, currentIsOwn: false) == nil)
    }

    @Test("A value of your own, left for a named one, is what Custom gives back")
    func leavingYourOwnKeepsIt() {
        var choice = CustomChoice<Int>()
        choice.change(from: 142, oldIsOwn: true, to: 0, newIsOwn: false)
        #expect(choice.kept == 142)
        #expect(choice.custom(current: 0, currentIsOwn: false) == 142)
    }

    @Test("While your own value is showing, Custom is that value")
    func ownValueShowingIsCustom() {
        let choice = CustomChoice<Int>(kept: 7)
        #expect(choice.custom(current: 9, currentIsOwn: true) == 9)
    }

    @Test("The newest value of your own wins, and a named one never replaces it")
    func newestOwnWins() {
        var choice = CustomChoice<Int>()
        choice.change(from: 0, oldIsOwn: false, to: 10, newIsOwn: true)
        choice.change(from: 10, oldIsOwn: true, to: 20, newIsOwn: true)
        choice.change(from: 20, oldIsOwn: true, to: 0, newIsOwn: false)
        choice.change(from: 0, oldIsOwn: false, to: 1, newIsOwn: false)
        #expect(choice.kept == 20)
    }

    @Test("A value kept by hand alone is kept only when it is your own")
    func keepIgnoresNamed() {
        var choice = CustomChoice<Int>(kept: 5)
        choice.keep(2, isOwn: false)
        #expect(choice.kept == 5)
        choice.keep(6, isOwn: true)
        #expect(choice.kept == 6)
    }

    // MARK: - The Around menu

    static func bell() -> Layer {
        Layer(name: "Bell",
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
              frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    static func turn() -> LayerMotion {
        LayerMotion.starting(.rotation, on: bell())
    }

    @Test("A turn that has only ever sat on named spots has no Custom to offer")
    func freshTurnHasNoCustom() {
        let motion = Self.turn()
        #expect(motion.customPivot == nil)
    }

    @Test("Drag the pivot, pick Top centre, and Custom gives your point back")
    func pivotRoundTrip() {
        let own = MotionPivot(unit: CGPoint(x: 0.3, y: -0.2))
        let start = Self.turn()

        var dragged = start
        dragged.pivot = own
        dragged = dragged.keepingOwnValues(of: start)
        #expect(dragged.customPivot == own)

        var named = dragged
        named.pivot = .topCentre
        named = named.keepingOwnValues(of: dragged)
        #expect(named.turnsAbout.title == "Top centre")
        #expect(named.customPivot == own)

        var back = named
        back.pivot = named.customPivot
        back = back.keepingOwnValues(of: named)
        #expect(back.turnsAbout == own)
        #expect(back.turnsAbout.title == "Custom")
    }

    @Test("A pivot of your own that came in with the document is kept the moment you leave it")
    func pivotFromAFileIsKept() {
        let own = MotionPivot(unit: CGPoint(x: 0.8, y: 0.1))
        var loaded = Self.turn()
        loaded.pivot = own
        #expect(loaded.ownPivot == nil)

        var named = loaded
        named.pivot = .centre
        named = named.keepingOwnValues(of: loaded)
        #expect(named.customPivot == own)
    }

    @Test("The point of your own survives a save")
    func ownPivotRoundTripsThroughCodable() throws {
        let own = MotionPivot(unit: CGPoint(x: 0.25, y: 0.75))
        var motion = Self.turn()
        motion.pivot = own
        let start = motion
        motion.pivot = .bottomCentre
        motion = motion.keepingOwnValues(of: start)

        let data = try JSONEncoder().encode(motion)
        let read = try JSONDecoder().decode(LayerMotion.self, from: data)
        #expect(read.customPivot == own)
    }

    @Test("A motion written before Custom could be picked reads back untouched")
    func oldMotionStillReads() throws {
        let motion = Self.turn()
        let data = try JSONEncoder().encode(motion)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("ownPivot"))
        #expect(!json.contains("ownCurve"))
        #expect(try JSONDecoder().decode(LayerMotion.self, from: data) == motion)
    }

    // MARK: - The Curve menu

    @Test("Draw a curve, pick Ease in, and the drawn one is still there to pick")
    func drawnCurveRoundTrip() {
        let drawn = EasingCurve.custom(x1: 0.1, y1: 0.9, x2: 0.4, y2: 1.2)
        let start = Self.turn()
        #expect(start.customCurve == nil)

        var mine = start
        mine.curve = drawn
        mine = mine.keepingOwnValues(of: start)

        var named = mine
        named.curve = .easeIn
        named = named.keepingOwnValues(of: mine)
        #expect(named.curve == .easeIn)
        #expect(named.customCurve == drawn)
    }
}
