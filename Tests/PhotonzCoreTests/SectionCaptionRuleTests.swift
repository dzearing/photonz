import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The line under Position & Size, and the one rule it follows.
///
/// It has one voice and two registers: at rest it is the section's CAPTION, and
/// when you do something the section has to explain it carries an ANSWER for a
/// few seconds. The rule is written down in
/// `docs/design/mocks/shared/UX-PATTERNS.md` §4, "The line under a section".
///
/// This suite pins the half of it that lives in the model: the caption never
/// describes a control that is not there. It used to promise "Up or down arrow
/// steps by 1, Shift by 10" while three of the four numbers were plain text and
/// only one of them stepped.
///
/// How MUCH it may say is the newer half of the same rule, §4 "How much a
/// section may say" (2026-09-14), pinned by `PanelSaysLessTests`. That is why
/// the expected strings here got so much shorter: the keyboard sentence this
/// suite was written about is now on the fields' own hover tips, so the only
/// way the caption can describe a control that is not there is by naming a
/// number nothing takes.
@Suite("The line under Position & Size")
struct SectionCaptionRuleTests {

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

    /// A rectangle sitting in a stack: the stack owns where it sits, so X and Y
    /// are plain text while W and H still take a number.
    private func rowInAStack() -> (Layer, Layer, CGRect) {
        let frame = CGRect(x: 0, y: 0, width: 120, height: 32)
        let row = rectangle(frame)
        var content = GroupContent(children: [row])
        content.layout = GroupLayout(kind: .stack, gap: 8)
        return (row, Layer(name: "Stack", content: .group(content), frame: .zero), frame)
    }

    @Test("Every number typeable, so there is nothing the section has to explain")
    func allFourStillPromiseStepping() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        let sel = LayerGeometrySelection([member(rectangle(frame), frame)])
        #expect(LayerGeometryField.allCases.allSatisfy { sel.allows($0) })
        #expect(sel.caption == nil)
    }

    @Test("Only some numbers typeable, and the section still says nothing about the rest")
    func someTypeableNamesThem() {
        let (row, stack, frame) = rowInAStack()
        let sel = LayerGeometrySelection([member(row, frame, in: stack)])
        #expect(!sel.allows(.x) && !sel.allows(.y))
        #expect(sel.allows(.width) && sel.allows(.height))
        // Which numbers step is shown by which fields are plain text, and each
        // fixed one says its own reason on hover. Nothing for a line to add.
        #expect(sel.caption == nil)
        #expect(sel.fixedReason(for: .x) != nil)
    }

    @Test("No number typeable, so the caption stops promising a keyboard altogether")
    func noneTypeableStopsPromising() {
        // An arrow is drawn end to end inside a stack: the stack owns where it
        // sits and its box is padding around a stroke, so nothing here types.
        let frame = CGRect(x: 0, y: 0, width: 120, height: 40)
        let shape = arrow(frame)
        var content = GroupContent(children: [shape])
        content.layout = GroupLayout(kind: .stack, gap: 8)
        let stack = Layer(name: "Stack", content: .group(content), frame: .zero)
        let sel = LayerGeometrySelection([member(shape, frame, in: stack)])
        #expect(LayerGeometryField.allCases.allSatisfy { !sel.allows($0) })
        #expect(sel.caption?.contains("arrow steps") == false)
        #expect(sel.caption?.contains("Shift by 10") == false)
        #expect(sel.caption?.contains("Click one") == true)
    }

    @Test("A locked selection still says the lock, which is its own answer")
    func aLockedSelectionIsUnchanged() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        var layer = rectangle(frame)
        layer.isLocked = true
        let sel = LayerGeometrySelection([member(layer, frame)])
        #expect(sel.caption == LayerGeometryEditing.lockedCaption)
        // The long reason did not go anywhere: it is the field's own tip.
        #expect(sel.fixedReason(for: .x) == LayerGeometryEditing.lockedReason)
    }

    @Test("Several layers with only some numbers typeable never name the rest")
    func severalLayersNameWhatSteps() {
        let (row, stack, frame) = rowInAStack()
        let (other, _, otherFrame) = rowInAStack()
        let sel = LayerGeometrySelection([member(row, frame, in: stack),
                                          member(other, otherFrame, in: stack)])
        // X and Y are the stack's, so the line may not mention an edge: that is
        // the rule this suite exists for, in the one line the budget leaves.
        #expect(sel.caption == LayerGeometrySelection.eachOwnSizeAndAngle)
        #expect(sel.caption?.contains("edge") == false)
    }

    @Test("Several layers with all four typeable say the one thing you cannot see")
    func severalLayersUnchanged() {
        let a = CGRect(x: 0, y: 0, width: 120, height: 32)
        let b = CGRect(x: 0, y: 40, width: 120, height: 32)
        let sel = LayerGeometrySelection([member(rectangle(a), a), member(rectangle(b), b)])
        #expect(sel.caption == "Each layer keeps its own size and angle.")
    }
}
