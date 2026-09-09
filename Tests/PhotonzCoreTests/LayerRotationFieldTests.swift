import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The A field: the angle a layer was turned to, read back and typed.
///
/// It is the fifth field in Position & Size rather than a control of its own,
/// so everything the other four already settled — Mixed, the read-only look,
/// the click that explains itself, the arrow-key stepping — has to hold for it
/// too. That is most of what is checked here.
@Suite("The angle field in Position & Size")
struct LayerRotationFieldTests {

    private func rectangle(_ frame: CGRect, turnedTo degrees: CGFloat = 0,
                           locked: Bool = false) -> Layer {
        var layer = AnnotationBuilder.layer(content: AnnotationContent(shape: .rectangle),
                                            from: CGPoint(x: frame.minX, y: frame.minY),
                                            to: CGPoint(x: frame.maxX, y: frame.maxY))
        layer.isLocked = locked
        layer.transform.rotation = LayerAngle.radians(fromDegrees: degrees)
        return layer
    }

    private func arrow() -> Layer {
        AnnotationBuilder.layer(content: AnnotationContent(shape: .arrow),
                                from: .zero, to: CGPoint(x: 100, y: 100))
    }

    private func group() -> Layer {
        let child = Layer(name: "Box",
                          content: .image(ImageRef(pixelSize: CGSize(width: 20, height: 10))),
                          frame: CGRect(x: 0, y: 0, width: 20, height: 10))
        return Layer(name: "Group", content: .group(GroupContent(children: [child])),
                     frame: CGRect(x: 5, y: 5, width: 0, height: 0))
    }

    private func member(_ layer: Layer, at degrees: CGFloat = 0) -> LayerGeometrySelection.Member {
        LayerGeometrySelection.Member(id: layer.id, frame: layer.frame,
                                      editing: LayerGeometryEditing(layer: layer),
                                      angle: degrees)
    }

    private func one(_ layer: Layer, at degrees: CGFloat = 0) -> LayerGeometrySelection {
        LayerGeometrySelection([member(layer, at: degrees)])
    }

    // MARK: Which layers turn

    @Test("A plain shape takes a typed angle, because the canvas already lets you turn it")
    func aShapeTurns() {
        let editing = LayerGeometryEditing(layer: rectangle(CGRect(x: 0, y: 0, width: 100, height: 50)))
        #expect(editing.allows(.rotation))
        #expect(editing.shows(.rotation))
        #expect(editing.fixedReason(for: .rotation) == nil)
    }

    @Test("A locked layer's angle is a number to read, and the reason names turning")
    func lockedReadsButDoesNotTurn() {
        let layer = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50), turnedTo: 30, locked: true)
        let editing = LayerGeometryEditing(layer: layer)
        #expect(!editing.allows(.rotation))
        #expect(editing.shows(.rotation))
        #expect(editing.fixedReason(for: .rotation) == LayerGeometryEditing.lockedReason)
        // Still reads the 30 it was turned to, rather than going blank.
        let sel = one(layer, at: 30)
        #expect(sel.reading(.rotation) == .agreed(30))
        #expect(sel.isReadOnly(.rotation))
    }

    @Test("A group has no angle at all: a dash and a sentence, not a live box showing 0")
    func aGroupDoesNotTurn() {
        let editing = LayerGeometryEditing(layer: group())
        #expect(!editing.allows(.rotation))
        #expect(!editing.shows(.rotation))
        #expect(editing.fixedReason(for: .rotation) == LayerGeometryEditing.groupTurnReason)
        let sel = one(group())
        #expect(sel.reading(.rotation) == .empty)
        #expect(sel.reading(.rotation).readoutText(for: .rotation) == LayerGeometrySelection.blankText)
        #expect(sel.explanation(for: .rotation) == LayerGeometryEditing.groupTurnReason)
    }

    @Test("A shape held between two ends is aimed by its ends, so it takes no typed angle")
    func anArrowDoesNotTurn() {
        let editing = LayerGeometryEditing(layer: arrow())
        #expect(!editing.allows(.rotation))
        #expect(!editing.shows(.rotation))
        #expect(editing.fixedReason(for: .rotation) == LayerGeometryEditing.endpointTurnReason)
    }

    // MARK: Reading it back

    @Test("The field reads the angle the knob left behind, in whole degrees")
    func readsTheAngle() {
        let sel = one(rectangle(CGRect(x: 0, y: 0, width: 100, height: 50)), at: 44.6)
        #expect(sel.reading(.rotation) == .agreed(45))
        #expect(sel.reading(.rotation).draftText(for: .rotation) == "45\u{00B0}")
    }

    @Test("A knob swung right round reads as where the layer ended up")
    func readsTheShortWayRound() {
        let sel = one(rectangle(CGRect(x: 0, y: 0, width: 100, height: 50)), at: 370)
        #expect(sel.reading(.rotation) == .agreed(10))
    }

    @Test("Two layers at different angles say Mixed rather than showing one of them")
    func differentAnglesAreMixed() {
        let a = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        let b = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        let sel = LayerGeometrySelection([member(a, at: 15), member(b, at: 30)])
        #expect(sel.reading(.rotation) == .mixed)
        #expect(sel.reading(.rotation).draftText(for: .rotation) == LayerGeometrySelection.mixedText)
        // Mixed is a word, not a measurement, so no degree sign is stuck on it.
        #expect(!sel.reading(.rotation).draftText(for: .rotation).hasSuffix("\u{00B0}"))
    }

    @Test("A degree sign only ever lands on the angle, never on a length")
    func onlyTheAngleCarriesAUnit() {
        let sel = one(rectangle(CGRect(x: 12, y: 0, width: 100, height: 50)), at: 45)
        #expect(sel.reading(.x).draftText(for: .x) == "12")
        #expect(sel.reading(.width).draftText(for: .width) == "100")
    }

    // MARK: Typing one

    @Test("A typed angle turns every layer that can turn, in one go")
    func typingTurnsThemAll() {
        let a = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        let b = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        let sel = LayerGeometrySelection([member(a, at: 15), member(b, at: 30)])
        let turns = sel.turning(to: 45)
        #expect(turns == [a.id: 45, b.id: 45])
    }

    @Test("Typing 0 puts a turned layer back to straight")
    func typingZeroStraightensIt() {
        let layer = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50), turnedTo: 33)
        #expect(one(layer, at: 33).turning(to: 0) == [layer.id: 0])
    }

    @Test("Typing the angle it is already at records nothing, so there is no empty undo step")
    func typingTheSameAngleChangesNothing() {
        let layer = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50), turnedTo: 45)
        #expect(one(layer, at: 45).turning(to: 45).isEmpty)
        // The same turn said the long way round is still the same turn.
        #expect(one(layer, at: 45).turning(to: 405).isEmpty)
    }

    @Test("A number typed past a full turn lands on the same angle said the short way")
    func typingPastAFullTurnWraps() {
        let layer = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(one(layer, at: 0).turning(to: 370) == [layer.id: 10])
    }

    @Test("Layers that cannot turn sit the typed angle out")
    func lockedAndGroupsSitOut() {
        let locked = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50), locked: true)
        let turnable = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        let sel = LayerGeometrySelection([member(locked), member(group()), member(turnable)])
        #expect(sel.turning(to: 45) == [turnable.id: 45])
    }

    @Test("A typed angle moves no box: the two write paths never cross")
    func aTypedAngleMovesNoFrame() {
        let layer = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        let sel = one(layer)
        #expect(sel.applying(45, to: .rotation).isEmpty)
        #expect(sel.stepping(.rotation, direction: 1, coarse: false).isEmpty)
    }

    // MARK: Arrow keys

    @Test("An arrow key steps a degree, Shift ten, each layer from its own angle")
    func arrowStepsFromItsOwnAngle() {
        let a = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        let b = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        let sel = LayerGeometrySelection([member(a, at: 15), member(b, at: 30)])
        #expect(sel.steppingRotation(direction: 1, coarse: false) == [a.id: 16, b.id: 31])
        #expect(sel.steppingRotation(direction: -1, coarse: true) == [a.id: 5, b.id: 20])
    }

    @Test("Stepping past half a turn keeps saying the angle the short way")
    func steppingWrapsRatherThanRunningOn() {
        let layer = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(one(layer, at: 180).steppingRotation(direction: 1, coarse: false) == [layer.id: -179])
    }

    // MARK: The line under the fields

    @Test("The caption says degrees as soon as there is an angle on show")
    func captionNamesTheUnit() {
        let turnable = one(rectangle(CGRect(x: 0, y: 0, width: 100, height: 50)))
        #expect(turnable.caption.contains("A in degrees clockwise"))
        // An arrow has no angle row to explain, so the line says nothing about it.
        #expect(!one(arrow()).caption.contains("degrees"))
    }

    @Test("With several picked the line says the angle lands on each of them")
    func captionForSeveral() {
        let a = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        let b = rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
        let sel = LayerGeometrySelection([member(a), member(b)])
        #expect(sel.caption.contains("A each layer's own angle"))
    }

    // MARK: Pasting a number back in

    @Test("A number typed with its degree sign still reads as that number")
    func parsesADegreeSign() {
        #expect(LayerGeometry.parse("45\u{00B0}") == 45)
        #expect(LayerGeometry.parse("-12 deg") == -12)
        #expect(LayerGeometry.parse("90 degrees") == 90)
    }
}
