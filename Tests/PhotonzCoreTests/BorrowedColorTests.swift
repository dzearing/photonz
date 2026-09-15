import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A colour you saved is reachable from every row that could paint it.
///
/// Reported by the user on 2026-09-15:
///
/// > I have a circle and a line. The line is a different color than the
/// > circle's border. I want to quickly match them. It's hard. I save the style
/// > of the circle border, try to use that for the color of the line, no luck.
/// > they mismatch on type. this is weird. Any style which holds a color should
/// > be usable for a color style.
///
/// The first half of that was already true and is nailed down here so it stays
/// true: a colour saved off a border IS offered on a line, because both paint
/// ink. What was not true is the second half — a colour saved inside a BORDER,
/// a shadow, a glow or a way of setting text had no way out of the style it
/// was saved in, and a colour kept for other parts simply vanished from the row
/// rather than saying where it had gone.
struct BorrowedColorTests {

    // MARK: - Fixtures

    private func circle(border: String = "#FF0055") -> Layer {
        var layer = Layer(name: "Circle",
                          content: .annotation(AnnotationContent(shape: .ellipse,
                                                                 start: .zero,
                                                                 end: CGPoint(x: 60, y: 60))),
                          frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        layer.style.effects = [.border(BorderEffect(width: 3, colorHex: border))]
        return layer
    }

    private func line(_ hex: String = "#101010") -> Layer {
        var content = AnnotationContent(shape: .line, start: .zero, end: CGPoint(x: 80, y: 0))
        content.colorHex = hex
        return Layer(name: "Line", content: .annotation(content),
                     frame: CGRect(x: 0, y: 0, width: 80, height: 2))
    }

    private func box(fill: String = "#3366FF") -> Layer {
        var content = AnnotationContent(shape: .rectangle, start: .zero,
                                        end: CGPoint(x: 60, y: 30))
        content.fillColorHex = fill
        return Layer(name: "Box", content: .annotation(content),
                     frame: CGRect(x: 0, y: 0, width: 60, height: 30))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    // MARK: - The half that already worked, kept working

    @Test func aColourSavedOffABorderIsOfferedOnALine() {
        var doc = document([circle(), line()])
        let saved = doc.saveColorStyle(from: [doc.layers[0].id], effectAt: 0, name: "Ring")
        #expect(saved != nil)
        #expect(doc.colorStyles(for: .stroke).map(\.name) == ["Ring"])
    }

    @Test func aColourSavedOffALineIsOfferedOnABorder() {
        var doc = document([circle(), line()])
        let saved = doc.saveColorStyle(from: doc.layers[1].id, slot: .stroke, name: "Hairline")
        #expect(saved != nil)
        #expect(doc.colorStyles(for: .border).map(\.name) == ["Hairline"])
    }

    // MARK: - The colour inside a saved border, shadow or glow

    @Test func theColourInsideASavedBorderCanBePaintedOnALine() {
        var doc = document([circle(border: "#FF0055"), line()])
        _ = doc.saveEffectStyle(from: [doc.layers[0].id], at: 0, name: "Circle edge")
        // It is not a saved COLOUR, so it does not turn up as a name to wear...
        #expect(doc.colorStyles(for: .stroke).isEmpty)
        // ...but the colour in it is reachable, and says where it came from.
        let borrowed = doc.borrowedColors(for: .stroke)
        #expect(borrowed.map(\.name) == ["Circle edge"])
        #expect(borrowed.first?.paint.hex == "#FF0055")
        #expect(borrowed.first?.origin == "border")
        #expect(borrowed.first?.label == "Circle edge (border)")
    }

    @Test func aSavedShadowAndGlowLendTheirColoursToo() {
        var layer = box()
        layer.style.effects = [.shadow(ShadowStyle(colorHex: "#223344")),
                               .glow(GlowEffect(colorHex: "#FFCC00"))]
        var doc = document([layer, line()])
        _ = doc.saveEffectStyle(from: [doc.layers[0].id], at: 0, name: "Card lift")
        _ = doc.saveEffectStyle(from: [doc.layers[0].id], at: 1, name: "Focus ring")
        let borrowed = doc.borrowedColors(for: .stroke)
        #expect(borrowed.map(\.label) == ["Card lift (shadow)", "Focus ring (glow)"])
    }

    @Test func aSavedBlurLendsNothingBecauseItPaintsNoColour() {
        var layer = box()
        layer.style.effects = [.blur(BlurEffect(radius: 6, isOn: true))]
        var doc = document([layer, line()])
        _ = doc.saveEffectStyle(from: [doc.layers[0].id], at: 0, name: "Soften")
        #expect(doc.borrowedColors(for: .stroke).isEmpty)
    }

    // MARK: - The colour inside a saved way of setting text

    @Test func theColourInsideASavedTextStyleCanBePaintedOnALine() {
        let text = Layer(name: "Label",
                         content: .text(TextContent(string: "Hi", colorHex: "#00AA88")),
                         frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        var doc = document([text, line()])
        _ = doc.saveTextStyle(from: [doc.layers[0].id], name: "Heading")
        let borrowed = doc.borrowedColors(for: .stroke)
        #expect(borrowed.map(\.label) == ["Heading (text)"])
        #expect(borrowed.first?.paint.hex == "#00AA88")
    }

    // MARK: - A saved colour kept for other parts says which parts

    @Test func aColourKeptForFillsSaysSoOnAnInkRow() {
        var doc = document([box(), line()])
        _ = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Card")
        #expect(doc.colorStyles(for: .stroke).isEmpty)
        let borrowed = doc.borrowedColors(for: .stroke)
        #expect(borrowed.map(\.label) == ["Card (for fills and backgrounds)"])
        #expect(borrowed.first?.keptFor == "fills and backgrounds")
    }

    @Test func aColourOfferedHereIsNotAlsoOfferedAsSomethingToCopy() {
        var doc = document([circle(), line()])
        _ = doc.saveColorStyle(from: doc.layers[1].id, slot: .stroke, name: "Hairline")
        #expect(doc.colorStyles(for: .stroke).map(\.name) == ["Hairline"])
        #expect(doc.borrowedColors(for: .stroke).isEmpty)
    }

    // MARK: - A ramp on a row that can only hold one flat colour

    @Test func aSavedRampIsOfferedFlatWhereARampCannotGo() {
        var doc = document([box(), line()])
        let ramp = Paint(hex: "#FF8800", kind: .linear,
                         stops: [GradientStop(hex: "#FF8800", position: 0),
                                 GradientStop(hex: "#8800FF", position: 1)])
        doc.addColorStyle(name: "Sunset", paint: ramp, roles: [.ink])
        // Text cannot draw a ramp, so it is not a name the row wears...
        #expect(doc.colorStyles(for: .text).isEmpty)
        // ...but the colour it starts on is still reachable, flattened.
        let borrowed = doc.borrowedColors(for: .text)
        #expect(borrowed.map(\.label) == ["Sunset (gradient)"])
        #expect(borrowed.first?.paint.isGradient == false)
        #expect(borrowed.first?.paint.hex == ramp.hex)
        // ...and on a row that CAN draw one it is a name, not a copy.
        #expect(doc.colorStyles(for: .stroke).map(\.name) == ["Sunset"])
        #expect(doc.borrowedColors(for: .stroke).isEmpty)
    }

    // MARK: - The list stays short

    @Test func theSameColourIsOnlyOfferedOnce() {
        var doc = document([circle(border: "#FF0055"), line()])
        _ = doc.saveEffectStyle(from: [doc.layers[0].id], at: 0, name: "Circle edge")
        _ = doc.saveEffectStyle(from: [doc.layers[0].id], at: 0, name: "Circle edge copy")
        #expect(doc.borrowedColors(for: .stroke).map(\.name) == ["Circle edge"])
    }

    @Test func aColourAlreadyOfferedAsANameIsNotOfferedAgainAsACopy() {
        var doc = document([circle(border: "#FF0055"), line()])
        _ = doc.saveColorStyle(from: [doc.layers[0].id], effectAt: 0, name: "Ring")
        _ = doc.saveEffectStyle(from: [doc.layers[0].id], at: 0, name: "Circle edge")
        #expect(doc.colorStyles(for: .stroke).map(\.name) == ["Ring"])
        #expect(doc.borrowedColors(for: .stroke).isEmpty)
    }

    // MARK: - Whether the row has anywhere to send somebody

    @Test func theRowKnowsWhenChangingWhatAColourIsForWouldHelp() {
        var doc = document([box(), line()])
        _ = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Card")
        #expect(doc.borrowedColors(for: .stroke).first?.isSavedColor == true)
        var other = document([circle(), line()])
        _ = other.saveEffectStyle(from: [other.layers[0].id], at: 0, name: "Circle edge")
        #expect(other.borrowedColors(for: .stroke).first?.isSavedColor == false)
    }
}
