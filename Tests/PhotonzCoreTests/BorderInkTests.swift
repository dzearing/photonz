import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// "No edge until you ask for one", the answer the user gave on 2026-09-13 to
/// "When you draw a shape, what should its border look like before you have
/// picked a colour for it?" — and the ink a border you DID ask for arrives in.
/// See `BorderInk.swift`.
@Suite("BorderInk")
struct BorderInkTests {

    private func box(fill: Paint?, paint: Paint = Paint(hex: "#FF3B30")) -> Layer {
        // Width 0: a box drawn in the app has no stroke of its own, and a
        // content built in code with one would arrive already ringed
        // (`Layer.moveItsOutlineIntoEffects`).
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0)
        content.paint = paint
        content.fill = fill
        return AnnotationBuilder.layer(content: content,
                                       from: CGPoint(x: 100, y: 100),
                                       to: CGPoint(x: 300, y: 240))
    }

    // MARK: - The ink itself

    @Test func aRingOnALightFillIsGraphite() {
        #expect(BorderInk.standingOutHex(from: Paint(hex: "#FFD60A")) == BorderInk.onLight)
        #expect(BorderInk.standingOutHex(from: Paint(hex: "#FFFFFF")) == BorderInk.onLight)
    }

    @Test func aRingOnADarkFillIsWhite() {
        #expect(BorderInk.standingOutHex(from: Paint(hex: "#000000")) == BorderInk.onDark)
        #expect(BorderInk.standingOutHex(from: Paint(hex: "#1C1C1E")) == BorderInk.onDark)
    }

    // The red every shape arrives in sits just under halfway in lightness, so
    // a rule that only asked "light or dark" would put a white ring on it at
    // 2.4:1. Contrast picks the graphite one, which reads at 7.1:1.
    @Test func theRingOnTheDefaultRedReadsAgainstIt() {
        let ink = BorderInk.standingOutHex(from: Paint(hex: "#FF3B30"))
        #expect(ink == BorderInk.onLight)
        #expect(ink != "#FF3B30")
        let fill = RGBA(hex: "#FF3B30")!.relativeLuminance
        let ring = RGBA(hex: ink)!.relativeLuminance
        #expect(abs(fill - ring) > 0.25)
    }

    // Nothing behind the ring but the canvas, which is light far more often
    // than not.
    @Test func aRingOnNoFillIsGraphite() {
        #expect(BorderInk.standingOutHex(from: nil) == BorderInk.onLight)
    }

    // A gradient answers with its whole ramp rather than the one flat colour
    // it stands for, so a dark ramp labelled with a light hex still gets a
    // light ring.
    @Test func aGradientFillIsJudgedAcrossItsRamp() {
        var ramp = Paint(hex: "#FFFFFF", kind: .linear)
        ramp.stops = [GradientStop(hex: "#000000", position: 0),
                      GradientStop(hex: "#101014", position: 1)]
        #expect(BorderInk.standingOutHex(from: ramp) == BorderInk.onDark)
    }

    // MARK: - No edge until you ask for one

    @Test func aFreshBoxOrOvalArrivesWithNoBorderAtAll() {
        let styles = AnnotationStyles()
        for shape in [AnnotationShape.rectangle, .ellipse] {
            let arriving = styles.arrivingStyle(forShape: shape)
            #expect(arriving.effects.isEmpty)
            #expect(arriving.borderEffects.isEmpty)
            // ...and no stroke of the shape's own standing in for one either.
            #expect(styles.content(for: shape == .rectangle ? .rectangle : .ellipse)?.strokeWidth == 0)
        }
    }

    // A line and an arrow ARE their stroke: taking it away would leave nothing
    // on the canvas, so their width is untouched by any of this.
    @Test func aLineAndAnArrowKeepTheirWidth() {
        let styles = AnnotationStyles()
        for shape in [AnnotationShape.line, .arrow] {
            #expect(styles.strokeWidth(forShape: shape) == AnnotationContent.defaultStrokeWidth)
        }
    }

    // MARK: - The border you DO ask for

    // The plus on the Effects header.
    @Test func aBorderAddedFromThePlusStandsOutFromTheFill() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let red = box(fill: Paint(hex: "#FF3B30"))
        doc.addLayer(red)
        doc.addEffect(.border, layerIDs: [red.id])

        let ring = doc.layer(id: red.id)?.style.borderEffects.first
        #expect(ring != nil)
        #expect(ring?.width == BorderEffect.startingWidth)
        #expect(ring?.colorHex == BorderInk.standingOutHex(from: Paint(hex: "#FF3B30")))
        #expect(ring?.colorHex != "#FF3B30")
    }

    @Test func aBorderAddedToANearBlackBoxComesOutLight() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let dark = box(fill: Paint(hex: "#101014"), paint: Paint(hex: "#101014"))
        doc.addLayer(dark)
        doc.addEffect(.border, layerIDs: [dark.id])

        #expect(doc.layer(id: dark.id)?.style.borderEffects.first?.colorHex == BorderInk.onDark)
    }

    // The other door: the Border checkbox in the toolbar's shape popover,
    // which sets the width and nothing else.
    @Test func aShapeGainingAnEdgeFromTheWidthAloneStandsOutFromItsFill() {
        let red = box(fill: Paint(hex: "#FF3B30"))
        let edged = AnnotationBuilder.restyled(red, strokeWidth: 4)
        let ring = edged.style.borderEffects.first
        #expect(ring?.width == 4)
        #expect(ring?.colorHex != "#FF3B30")
        #expect(ring?.colorHex == BorderInk.standingOutHex(from: Paint(hex: "#FF3B30")))
    }

    // A colour named in the same breath still wins: this rule only fills in a
    // blank, it never overrules a pick.
    @Test func anEdgeAskedForInAColourKeepsThatColour() {
        let red = box(fill: Paint(hex: "#FF3B30"))
        let edged = AnnotationBuilder.restyled(red, paint: Paint(hex: "#34C759"), strokeWidth: 4)
        #expect(edged.style.borderEffects.first?.colorHex == "#34C759")
    }

    // An outline-only shape has nothing behind its ring but the canvas, and
    // the shape's own colour is what it has always been drawn in.
    @Test func anUnfilledShapeGainsAnEdgeInItsOwnColour() {
        let hollow = box(fill: nil, paint: Paint(hex: "#0A84FF"))
        let edged = AnnotationBuilder.restyled(hollow, strokeWidth: 4)
        #expect(edged.style.borderEffects.first?.colorHex == "#0A84FF")
    }

    // The third door: the Border switch on the toolbar's shape popover, which
    // arms the TOOL rather than a shape on the canvas.
    @Test func tickingBorderOnTheToolArmsAnInkThatReads() {
        var styles = AnnotationStyles()
        styles.armEdge(width: AnnotationContent.defaultStrokeWidth, forShape: .rectangle)

        let arriving = styles.arrivingStyle(forShape: .rectangle)
        #expect(arriving.borderEffects.count == 1)
        #expect(arriving.borderEffects.first?.colorHex == BorderInk.onLight)
        #expect(arriving.borderEffects.first?.colorHex != styles.fillColorHex(forShape: .rectangle))
    }

    // ...and it is only ever the FIRST one. A colour somebody chose for an
    // edge is theirs, even when they chose the colour of the fill.
    @Test func anEdgeTheToolAlreadyHoldsKeepsItsColour() {
        var styles = AnnotationStyles()
        var style = LayerStyle()
        style.effects.append(.border(BorderEffect(width: 5, colorHex: "#FF3B30")))
        styles.remember(style, forShape: .rectangle)
        #expect(styles.arrivingStyle(forShape: .rectangle).borderEffects.first?.colorHex == "#FF3B30")

        styles.armEdge(width: 9, forShape: .rectangle)
        #expect(styles.arrivingStyle(forShape: .rectangle).borderEffects.first?.colorHex == "#FF3B30")
        #expect(styles.arrivingStyle(forShape: .rectangle).borderEffects.first?.width == 9)
    }

    // MARK: - A shape never becomes nothing

    // Turning Fill off used to leave an outline box in the shape's colour,
    // because the edge was always there wearing the fill's colour. With no
    // edge to fall back on it would leave an invisible layer, so the outline
    // arrives to carry the shape.
    @Test func takingTheFillOffABorderlessShapeLeavesAnOutline() {
        let red = box(fill: Paint(hex: "#FF3B30"))
        #expect(red.style.borderEffects.isEmpty)
        let hollow = AnnotationBuilder.restyled(red, fill: .some(nil))
        let ring = hollow.style.borderEffects.first
        #expect(ring?.isOn == true)
        #expect(ring?.width == AnnotationContent.defaultStrokeWidth)
        #expect(ring?.colorHex == "#FF3B30")
    }

    // ...and a shape that already has a ring is left exactly as it is: no
    // second one, no width changed under it.
    @Test func takingTheFillOffAShapeThatHasARingChangesNothingElse() {
        var red = box(fill: Paint(hex: "#FF3B30"))
        red.style.effects.append(.border(BorderEffect(width: 9, colorHex: "#0A84FF", position: .inside)))
        let hollow = AnnotationBuilder.restyled(red, fill: .some(nil))
        #expect(hollow.style.borderEffects.count == 1)
        #expect(hollow.style.borderEffects.first?.width == 9)
        #expect(hollow.style.borderEffects.first?.colorHex == "#0A84FF")
    }

    // The door the panel actually uses: the Fill switch in the shape's parts,
    // which empties the slot rather than restyling the shape.
    @Test func switchingTheFillOffLeavesAnOutlineToo() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let red = box(fill: Paint(hex: "#FF3B30"))
        doc.addLayer(red)
        #expect(doc.setColorEnabled(layerIDs: [red.id], slot: .fill, on: false) == 1)

        let after = doc.layer(id: red.id)
        #expect(after?.paint(for: .fill) == nil)
        #expect(after?.style.borderEffects.first?.width == AnnotationContent.defaultStrokeWidth)
        #expect(after?.style.borderEffects.first?.colorHex == "#FF3B30")
        // ...and switching it back on takes nothing away: the ring is the
        // shape's now, and it is one cross from gone.
        #expect(doc.setColorEnabled(layerIDs: [red.id], slot: .fill, on: true) == 1)
        #expect(doc.layer(id: red.id)?.style.borderEffects.count == 1)
    }

    // The same rule on arrival: a tool armed with no fill draws an outline
    // shape rather than an invisible one.
    @Test func aToolArmedWithNoFillDrawsAnOutlineShape() {
        var styles = AnnotationStyles()
        styles.setFillPaint(nil, forShape: .rectangle)
        let arriving = styles.arrivingStyle(forShape: .rectangle)
        #expect(arriving.borderEffects.count == 1)
        #expect(arriving.borderEffects.first?.isOn == true)
        #expect(arriving.borderEffects.first?.width == AnnotationContent.defaultStrokeWidth)
        #expect(arriving.borderEffects.first?.colorHex == styles.colorHex(forShape: .rectangle))
    }

    // MARK: - The memory rule still holds

    // Leave a border on a box and the next box wears it, ink and all: that is
    // what makes this one trip to the plus rather than one per shape.
    @Test func theNextShapeWearsTheBorderYouLeftOnTheLastOne() {
        var styles = AnnotationStyles()
        var style = LayerStyle()
        style.effects.append(.border(BorderEffect(width: 6, colorHex: "#0A84FF", position: .outside)))
        styles.remember(style, forShape: .rectangle)

        let arriving = styles.arrivingStyle(forShape: .rectangle)
        #expect(arriving.borderEffects.count == 1)
        #expect(arriving.borderEffects.first?.width == 6)
        #expect(arriving.borderEffects.first?.colorHex == "#0A84FF")
        #expect(arriving.borderEffects.first?.position == .outside)
    }

    // ...and taking it off again with the cross means the next box is bare
    // once more, rather than the app quietly putting one back.
    @Test func aBorderTakenOffStaysOffOnTheNextShape() {
        var styles = AnnotationStyles()
        var style = LayerStyle()
        style.effects.append(.border(BorderEffect(width: 6, colorHex: "#0A84FF")))
        styles.remember(style, forShape: .rectangle)
        styles.remember(LayerStyle(), forShape: .rectangle)

        #expect(styles.arrivingStyle(forShape: .rectangle).borderEffects.isEmpty)
    }
}
