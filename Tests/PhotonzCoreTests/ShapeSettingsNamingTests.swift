import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The words a picked shape's settings are written in: the section is headed
/// after the shape, and every color row says what part of it it paints.
///
/// Reported by the user on 2026-09-03: a picked rectangle showed a section
/// headed "Annotation" over two colors, one labelled with the shape's name and
/// one labelled with nothing, so there was no way to tell the outline from the
/// inside.
struct ShapeSettingsNamingTests {

    // MARK: - The section is named after what is selected

    @Test func everyShapeIsNamedAfterItself() {
        #expect(AnnotationShape.rectangle.title == "Rectangle")
        #expect(AnnotationShape.ellipse.title == "Ellipse")
        #expect(AnnotationShape.arrow.title == "Arrow")
        #expect(AnnotationShape.line.title == "Line")
        #expect(AnnotationShape.highlight.title == "Highlight")
    }

    @Test func noShapeIsNamedAfterTheModel() {
        for shape in AnnotationShape.allCases {
            #expect(shape.title != "Annotation")
            #expect(!shape.title.isEmpty)
        }
    }

    // MARK: - Every color row says what it paints

    @Test func aBoxNamesItsOutlineAndItsInside() {
        for shape in [AnnotationShape.rectangle, .ellipse] {
            #expect(shape.colorTitle(for: .stroke) == "Outline")
            #expect(shape.colorTitle(for: .fill) == "Fill")
        }
    }

    @Test func aShapeThatIsAllOneColorJustCallsItColor() {
        for shape in [AnnotationShape.arrow, .line, .highlight] {
            #expect(shape.colorTitle(for: .stroke) == "Color")
        }
    }

    @Test func aSlotTheShapeDoesNotHaveHasNoLabel() {
        #expect(AnnotationShape.arrow.colorTitle(for: .fill) == nil)
        #expect(AnnotationShape.line.colorTitle(for: .fill) == nil)
        #expect(AnnotationShape.rectangle.colorTitle(for: .text) == nil)
    }

    /// The label and the slots the layer actually offers have to agree, or a
    /// row appears with no name or a name appears with no row.
    @Test func everyShapeLabelsExactlyTheSlotsItHas() {
        for shape in AnnotationShape.allCases {
            let annotation = AnnotationContent(shape: shape, start: .zero,
                                               end: CGPoint(x: 40, y: 20))
            let layer = Layer(name: "S", content: .annotation(annotation),
                              frame: CGRect(x: 0, y: 0, width: 40, height: 20))
            for slot in ColorSlot.allCases {
                #expect((shape.colorTitle(for: slot) != nil)
                        == layer.colorSlots.contains(slot))
            }
        }
    }

    /// With colors living in the Color section, a shape's own section is worth
    /// showing only while it has something else to say.
    @Test func onlyAHighlightHasNothingLeftOnceItsColorHasMovedOut() {
        #expect(AnnotationShape.highlight.hasSettingsBesidesColor == false)
        for shape in AnnotationShape.allCases where shape != .highlight {
            #expect(shape.hasSettingsBesidesColor)
        }
    }

    /// One word per slot, whatever is picked. A label that read Color over a
    /// lone arrow and Outline the moment a box joined it would move the same
    /// way the section used to.
    @Test func aRowIsNamedByItsSlotAndNothingElse() {
        #expect(ColorSlot.stroke.selectionTitle == "Outline")
        #expect(ColorSlot.fill.selectionTitle == "Fill")
        #expect(ColorSlot.text.selectionTitle == "Text")
        #expect(Set(ColorSlot.allCases.map(\.selectionTitle)).count == ColorSlot.allCases.count)
    }
}
