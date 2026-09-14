import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// How much the line under Position & Size is allowed to say.
///
/// The rule is `docs/design/mocks/shared/UX-PATTERNS.md` §4, "How much a
/// section may say", settled 2026-09-14 by the decision "How much should the
/// right hand panel explain itself in words?", answered "One short line, and
/// only when it earns it".
///
/// This suite pins the half of the rule that lives in the model. The caption
/// used to open with the unit and the origin and close with the arrow keys,
/// three or four lines of panel, every one of which is ALREADY on a hover tip:
/// `LayerGeometryField.title` has said "Distance from the left edge of the
/// canvas" and "Angle, in degrees, turning clockwise" the whole time. So the
/// line now says nothing at all in the ordinary case, and says one short
/// sentence only where something is missing or where several layers behave in
/// a way you cannot see.
@Suite("How much the line under Position & Size says")
struct PanelSaysLessTests {

    private func rectangle(_ frame: CGRect) -> Layer {
        AnnotationBuilder.layer(content: AnnotationContent(shape: .rectangle),
                                from: CGPoint(x: frame.minX, y: frame.minY),
                                to: CGPoint(x: frame.maxX, y: frame.maxY))
    }

    private func arrow(_ frame: CGRect) -> Layer {
        AnnotationBuilder.layer(content: AnnotationContent(shape: .arrow),
                                from: CGPoint(x: frame.minX, y: frame.minY),
                                to: CGPoint(x: frame.maxX, y: frame.maxY))
    }

    private func member(_ layer: Layer, _ frame: CGRect,
                        in container: Layer? = nil) -> LayerGeometrySelection.Member {
        LayerGeometrySelection.Member(id: layer.id, frame: frame,
                                      editing: LayerGeometryEditing(layer: layer, in: container))
    }

    private func rowInAStack() -> (Layer, Layer, CGRect) {
        let frame = CGRect(x: 0, y: 0, width: 120, height: 32)
        let row = rectangle(frame)
        var content = GroupContent(children: [row])
        content.layout = GroupLayout(kind: .stack, gap: 8)
        return (row, Layer(name: "Stack", content: .group(content), frame: .zero), frame)
    }

    /// The ordinary case, and the whole point of the change: one layer, four
    /// numbers you can type, nothing surprising. The section says NOTHING.
    @Test("One layer with ordinary numbers spends no line at all")
    func oneOrdinaryLayerSaysNothing() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        #expect(LayerGeometrySelection([member(rectangle(frame), frame)]).caption == nil)
    }

    /// What the dropped sentence used to carry is still reachable, on the two
    /// fields it was ever about. Nothing was deleted without a home.
    @Test("The origin and the degrees are still said, on the fields' own tips")
    func theTipsStillCarryWhatTheLineDropped() {
        #expect(LayerGeometryField.x.title.contains("left edge"))
        #expect(LayerGeometryField.y.title.contains("top edge"))
        #expect(LayerGeometryField.rotation.title.contains("degrees"))
        #expect(LayerGeometryField.rotation.title.contains("clockwise"))
        // The unit was ONLY ever in the caption, so it moved rather than went.
        #expect(LayerGeometryField.width.unitNote?.contains(LayerGeometry.unitSuffix) == true)
        #expect(LayerGeometryField.rotation.unitNote == nil)
        // ...and so was the keyboard.
        #expect(LayerGeometryField.steppingNote.contains("Shift by 10"))
    }

    /// Several layers ARE surprising: W and H over three boxes give each of
    /// them that width, they do not resize the three as one block. That cannot
    /// be seen, so it earns the line, and it is the only thing on it.
    @Test("Several layers say the one thing you cannot see, and nothing else")
    func severalLayersSayOnlyWhatIsHidden() {
        let a = CGRect(x: 0, y: 0, width: 120, height: 32)
        let b = CGRect(x: 0, y: 40, width: 120, height: 32)
        let sel = LayerGeometrySelection([member(rectangle(a), a), member(rectangle(b), b)])
        #expect(sel.caption == "Each layer keeps its own size and angle.")
    }

    /// The count is already on screen: the Layers section prints "2 layers
    /// selected" whenever more than one is picked, so no section repeats it.
    @Test("No section repeats the selection count")
    func theCountIsNotRepeated() {
        let a = CGRect(x: 0, y: 0, width: 120, height: 32)
        let b = CGRect(x: 0, y: 40, width: 120, height: 32)
        let sel = LayerGeometrySelection([member(rectangle(a), a), member(rectangle(b), b)])
        #expect(sel.caption?.contains("2 layers") == false)
        #expect(sel.caption?.contains("all at once") == false)
    }

    /// Inside a stack the size is still each layer's own but the position is
    /// not typeable at all, so the sentence names only the half that is there.
    @Test("The sentence names only the numbers that are actually there")
    func onlyTheNumbersThatAreThere() {
        let (row, stack, frame) = rowInAStack()
        let (other, _, otherFrame) = rowInAStack()
        let sel = LayerGeometrySelection([member(row, frame, in: stack),
                                          member(other, otherFrame, in: stack)])
        #expect(!sel.allows(.x) && !sel.allows(.y))
        #expect(sel.caption == "Each layer keeps its own size and angle.")
    }

    /// Nothing takes a number, so the line stops being a caption and becomes
    /// the way out. That is a control that is missing, which earns its line.
    @Test("Where nothing types, the line is the way out and stays one sentence")
    func nothingTypeablePointsAtTheAnswer() {
        let frame = CGRect(x: 0, y: 0, width: 120, height: 40)
        let shape = arrow(frame)
        var content = GroupContent(children: [shape])
        content.layout = GroupLayout(kind: .stack, gap: 8)
        let stack = Layer(name: "Stack", content: .group(content), frame: .zero)
        let sel = LayerGeometrySelection([member(shape, frame, in: stack)])
        #expect(LayerGeometryField.allCases.allSatisfy { !sel.allows($0) })
        #expect(sel.caption == "Worked out for you. Click one to see why.")
    }

    /// A lock is a missing control too, so it keeps a line. It gets the SHORT
    /// wording; the long one is still what the field's own tip says, so the
    /// full reason is one hover away rather than three lines of panel.
    @Test("A locked layer says it short, and the long reason stays on the tip")
    func aLockSaysItShort() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        var layer = rectangle(frame)
        layer.isLocked = true
        let sel = LayerGeometrySelection([member(layer, frame)])
        #expect(sel.caption == LayerGeometryEditing.lockedCaption)
        #expect(LayerGeometryEditing.lockedCaption.count
                < LayerGeometryEditing.lockedReason.count)
        #expect(sel.fixedReason(for: .x) == LayerGeometryEditing.lockedReason)
    }

    /// Every line this section can print, held to the budget: one sentence
    /// short enough to sit on one line at the panel's default width.
    @Test("Every line this section can print fits one line")
    func everyLineFitsOneLine() {
        let lines = [
            LayerGeometrySelection.workedOutForYou,
            LayerGeometrySelection.workedOutForThem,
            LayerGeometrySelection.eachOwnSizeAndAngle,
            LayerGeometrySelection.eachOwnSize,
            LayerGeometrySelection.eachOwnAngle,
            LayerGeometrySelection.nothingOnThemYet,
            LayerGeometrySelection.lockedSeveralCaption,
            LayerGeometrySelection.lockedInsideCaption,
            LayerGeometryEditing.lockedCaption,
            LayerGeometryEditing.nothingOnItCaption,
        ]
        for line in lines {
            #expect(line.count <= LayerGeometrySelection.oneLineBudget,
                    "\"\(line)\" is \(line.count) characters, over the one line budget")
        }
    }
}
