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

    @Test("Every number typeable keeps the caption it always had, plus the angle's unit")
    func allFourStillPromiseStepping() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        let sel = LayerGeometrySelection([member(rectangle(frame), frame)])
        #expect(sel.caption
                == "\(LayerGeometry.unitSuffix) from the top left, A in degrees clockwise. "
                + "Up or down arrow steps by 1, Shift by 10.")
    }

    @Test("Only some numbers typeable, so the caption names the ones that step")
    func someTypeableNamesThem() {
        let (row, stack, frame) = rowInAStack()
        let sel = LayerGeometrySelection([member(row, frame, in: stack)])
        #expect(!sel.allows(.x) && !sel.allows(.y))
        #expect(sel.allows(.width) && sel.allows(.height))
        #expect(sel.caption.contains("steps W, H and A by 1"))
        #expect(sel.caption.contains("Shift by 10"))
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
        #expect(!sel.caption.contains("arrow steps"))
        #expect(!sel.caption.contains("Shift by 10"))
        #expect(sel.caption.contains("Click one"))
    }

    @Test("A locked selection still says the lock, which is its own answer")
    func aLockedSelectionIsUnchanged() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        var layer = rectangle(frame)
        layer.isLocked = true
        let sel = LayerGeometrySelection([member(layer, frame)])
        #expect(sel.caption == LayerGeometryEditing.lockedReason)
    }

    @Test("Several layers with only some numbers typeable name those numbers too")
    func severalLayersNameWhatSteps() {
        let (row, stack, frame) = rowInAStack()
        let (other, _, otherFrame) = rowInAStack()
        let sel = LayerGeometrySelection([member(row, frame, in: stack),
                                          member(other, otherFrame, in: stack)])
        #expect(sel.caption.hasPrefix("2 layers, all at once."))
        #expect(sel.caption.contains("W, H and A"))
        #expect(!sel.caption.contains("every left edge"))
    }

    @Test("Several layers with all four typeable keep the caption they always had")
    func severalLayersUnchanged() {
        let a = CGRect(x: 0, y: 0, width: 120, height: 32)
        let b = CGRect(x: 0, y: 40, width: 120, height: 32)
        let sel = LayerGeometrySelection([member(rectangle(a), a), member(rectangle(b), b)])
        #expect(sel.caption
                == "2 layers, all at once. X sets every left edge, Y every top edge, "
                + "W and H each layer's own size, A each layer's own angle. "
                + "Arrow steps them all by 1, Shift by 10.")
    }
}
