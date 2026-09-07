import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Switching a part off is remembered for the next shape you draw.
///
/// Reported by the user on 2026-09-06: take a box's outline off, draw another
/// box, and the outline is back. Everything else the tool remembers — the
/// colour, the thickness, the corner radius, and the inside, which had already
/// been wired up — so a part being switched off has to stick the same way.
///
/// This is the reading that lets the Outline switch arm the tool: which kind of
/// shape the switch reached, and what line each of those kinds is left wearing.
/// A width of zero is a real answer, not a missing one.
@Suite("Outline arming")
struct OutlineArmingTests {

    private func shape(_ kind: AnnotationShape, strokeWidth: CGFloat = 4,
                       style: LayerStyle = LayerStyle(), locked: Bool = false) -> Layer {
        var layer = Layer(name: kind.title,
                          content: .annotation(AnnotationContent(shape: kind,
                                                                 strokeWidth: strokeWidth,
                                                                 colorHex: "#FF0000",
                                                                 start: .zero,
                                                                 end: CGPoint(x: 100, y: 60))),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 60),
                          style: style)
        layer.isLocked = locked
        return layer
    }

    private func picture(style: LayerStyle = LayerStyle()) -> Layer {
        Layer(name: "Shot",
              content: .image(ImageRef(pixelSize: CGSize(width: 40, height: 40))),
              frame: CGRect(x: 0, y: 0, width: 40, height: 40),
              style: style)
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        for layer in layers { doc.addLayer(layer) }
        return doc
    }

    private func border(_ width: CGFloat) -> LayerStyle {
        var style = LayerStyle()
        style.borderWidth = width
        return style
    }

    // MARK: - What the switch leaves the tool holding

    @Test func switchingABoxesOutlineOffLeavesTheBoxToolWithNoLine() {
        let box = shape(.rectangle, strokeWidth: 6)
        var doc = document([box])
        doc.setOutlineEnabled(layerIDs: [box.id], on: false)
        #expect(doc.outlineArming(layerIDs: [box.id]) == [OutlineArming(shape: .rectangle, width: 0)])
    }

    @Test func switchingItBackOnLeavesTheToolTheWidthItCameBackAt() {
        let box = shape(.rectangle, strokeWidth: 6)
        var doc = document([box])
        doc.setOutlineEnabled(layerIDs: [box.id], on: false)
        doc.setOutlineEnabled(layerIDs: [box.id], on: true, restoring: [box.id: 6])
        #expect(doc.outlineArming(layerIDs: [box.id]) == [OutlineArming(shape: .rectangle, width: 6)])
    }

    /// The width the switch actually put back, not the one it took away: a
    /// shape drawn with no line has nothing remembered for it, so switching it
    /// on has to hand the tool the line the person can now see rather than a
    /// zero that would draw nothing.
    @Test func aShapeWithNothingRememberedArmsTheWidthItCameBackAt() {
        let box = shape(.rectangle, strokeWidth: 0)
        var doc = document([box])
        doc.setOutlineEnabled(layerIDs: [box.id], on: true)
        let width = doc.outlineArming(layerIDs: [box.id]).first?.width
        #expect(width == AnnotationContent.defaultStrokeWidth)
        #expect((width ?? 0) > 0)
    }

    // MARK: - One answer per kind of shape

    @Test func eachKindIsAnsweredForOnItsOwn() {
        let box = shape(.rectangle, strokeWidth: 6)
        let round = shape(.ellipse, strokeWidth: 2)
        var doc = document([box, round])
        doc.setOutlineEnabled(layerIDs: [box.id], on: false)
        #expect(doc.outlineArming(layerIDs: [box.id, round.id]) == [
            OutlineArming(shape: .rectangle, width: 0),
            OutlineArming(shape: .ellipse, width: 2),
        ])
    }

    @Test func aKindNotPickedIsLeftAlone() {
        let box = shape(.rectangle, strokeWidth: 6)
        let round = shape(.ellipse, strokeWidth: 2)
        var doc = document([box, round])
        doc.setOutlineEnabled(layerIDs: [box.id], on: false)
        #expect(doc.outlineArming(layerIDs: [box.id]).map(\.shape) == [.rectangle])
    }

    // MARK: - A selection that disagrees teaches nothing

    /// The line being THERE is never in doubt — the switch just set it — so
    /// only the thickness is withheld. Being left saying "no line" right after
    /// somebody put the line back is what this rule exists to prevent.
    @Test func twoBoxesThatComeBackDifferentTeachTheLineButNotItsThickness() {
        let thin = shape(.rectangle, strokeWidth: 2)
        let thick = shape(.rectangle, strokeWidth: 10)
        var doc = document([thin, thick])
        doc.setOutlineEnabled(layerIDs: [thin.id, thick.id], on: false)
        // Off, they agree: no line is no line.
        #expect(doc.outlineArming(layerIDs: [thin.id, thick.id])
            == [OutlineArming(shape: .rectangle, width: 0)])
        // Back on at the widths each of them used to wear, they disagree, and
        // handing the tool one of them would arm it with a number nobody chose.
        doc.setOutlineEnabled(layerIDs: [thin.id, thick.id], on: true,
                              restoring: [thin.id: 2, thick.id: 10])
        #expect(doc.outlineArming(layerIDs: [thin.id, thick.id])
            == [OutlineArming(shape: .rectangle, width: nil)])
    }

    /// Half a kind reached is no answer at all: one box switched off beside one
    /// left alone says nothing about what a box should be.
    @Test func aKindThatCannotAgreeWhetherItHasALineTeachesNothing() {
        let off = shape(.rectangle, strokeWidth: 0)
        let on = shape(.rectangle, strokeWidth: 6)
        let doc = document([off, on])
        #expect(doc.outlineArming(layerIDs: [off.id, on.id]).isEmpty)
    }

    @Test func twoBoxesThatAgreeArmTogether() {
        let one = shape(.rectangle, strokeWidth: 6)
        let two = shape(.rectangle, strokeWidth: 6)
        var doc = document([one, two])
        doc.setOutlineEnabled(layerIDs: [one.id, two.id], on: false)
        #expect(doc.outlineArming(layerIDs: [one.id, two.id])
            == [OutlineArming(shape: .rectangle, width: 0)])
    }

    // MARK: - Who has no say

    @Test func aLockedShapeHasNoSay() {
        let locked = shape(.rectangle, strokeWidth: 10, locked: true)
        let box = shape(.rectangle, strokeWidth: 6)
        var doc = document([locked, box])
        doc.setOutlineEnabled(layerIDs: [locked.id, box.id], on: false)
        // The switch could not reach the locked one, so letting it hold the old
        // width would stop the press arming anything at all.
        #expect(doc.outlineArming(layerIDs: [locked.id, box.id])
            == [OutlineArming(shape: .rectangle, width: 0)])
    }

    /// A ring round a picture, a label or a highlight is styling laid over the
    /// layer rather than part of the shape, so it rides along with the rest of
    /// that layer's remembered look instead of arming a thickness.
    @Test func aRingIsNotAThicknessAnyToolHolds() {
        let wash = shape(.highlight, style: border(3))
        let shot = picture(style: border(3))
        let doc = document([wash, shot])
        #expect(doc.outlineArming(layerIDs: [wash.id, shot.id]).isEmpty)
    }

    @Test func nothingPickedArmsNothing() {
        let doc = document([shape(.rectangle)])
        #expect(doc.outlineArming(layerIDs: []).isEmpty)
    }

    // MARK: - What the next shape comes out as

    @Test func aToolArmedWithNoLineDrawsABoxWithNoLine() {
        var styles = AnnotationStyles()
        styles.setStrokeWidth(0, forShape: .rectangle)
        #expect(styles.content(for: .rectangle)?.strokeWidth == 0)
        // ...and the kinds it never reached are untouched.
        #expect((styles.content(for: .ellipse)?.strokeWidth ?? 0) > 0)
    }

    @Test func aSwitchedOffOutlineSurvivesQuittingTheApp() throws {
        var styles = AnnotationStyles()
        styles.setStrokeWidth(0, forShape: .rectangle)
        let data = try JSONEncoder().encode(styles)
        let back = try JSONDecoder().decode(AnnotationStyles.self, from: data)
        #expect(back.strokeWidth(forShape: .rectangle) == 0)
        #expect(back.content(for: .rectangle)?.strokeWidth == 0)
    }
}
