import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The Effects and Shadow rows speaking for a whole selection: pick four
/// buttons, drag Corner Radius once, and all four round
/// (`docs/design/ui-building.md`, step D8, the same shape as the Color rows).
///
/// The rows have to be honest about what they are looking at. Four boxes that
/// are all 8pt round say 8; four that differ say Mixed, because printing one of
/// their numbers is a row claiming a value three of the layers under it are not
/// wearing.
struct LayerStyleSelectionTests {

    // MARK: - Fixtures

    private func box(_ name: String = "Box", style: LayerStyle = LayerStyle(),
                     size: CGSize = CGSize(width: 60, height: 30),
                     locked: Bool = false) -> Layer {
        let annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: size.width, y: size.height))
        var layer = Layer(name: name, content: .annotation(annotation),
                          frame: CGRect(origin: .zero, size: size))
        layer.style = style
        layer.isLocked = locked
        return layer
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    private func selection(_ styles: [LayerStyle]) -> LayerStyleSelection {
        LayerStyleSelection(members: styles.map {
            LayerStyleSelection.Member(id: UUID(), style: $0, cornerRadiusLimit: 15)
        }, selectionCount: styles.count)
    }

    // MARK: - What a row reads

    @Test func nothingPickedReadsEmpty() {
        let reading = selection([]).reading { $0.opacity }
        #expect(reading.isEmpty)
        #expect(!reading.isMixed)
        #expect(reading.value == nil)
    }

    @Test func layersSharingAValueReadThatValue() {
        var style = LayerStyle()
        style.cornerRadius = 8
        let reading = selection([style, style, style]).number { $0.cornerRadius }
        #expect(reading.value == 8)
        #expect(!reading.isMixed)
    }

    @Test func layersThatDifferReadMixed() {
        var a = LayerStyle(); a.cornerRadius = 0
        var b = LayerStyle(); b.cornerRadius = 12
        let reading = selection([a, b]).number { $0.cornerRadius }
        #expect(reading.isMixed)
        // The knob still has to sit somewhere: the topmost layer's value, so
        // the row reads the same way twice running. The READOUT says Mixed.
        #expect(reading.value == 0)
    }

    @Test func oneLayerIsNeverMixed() {
        var style = LayerStyle(); style.blurRadius = 4
        let reading = selection([style]).number { $0.blurRadius }
        #expect(reading.value == 4)
        #expect(!reading.isMixed)
    }

    @Test func borderColorsThatDifferReadMixed() {
        var a = LayerStyle(); a.borderColorHex = "#FF0000"
        var b = LayerStyle(); b.borderColorHex = "#00FF00"
        #expect(selection([a, b]).reading { $0.borderColorHex }.isMixed)
        #expect(selection([a, a]).reading { $0.borderColorHex }.value == "#FF0000")
    }

    // MARK: - The shadow switch

    @Test func shadowIsOnOnlyWhenEveryPickedLayerHasOne() {
        var on = LayerStyle(); on.shadow = ShadowStyle()
        let off = LayerStyle()
        #expect(selection([on, on]).hasShadowEverywhere)
        // Two boxes where one is shadowed read off, so one click shadows the
        // other rather than un-shadowing the first — the way the Fill checkbox
        // over a half-filled selection works.
        #expect(!selection([on, off]).hasShadowEverywhere)
        #expect(!selection([off, off]).hasShadowEverywhere)
    }

    @Test func shadowRowsSpeakForTheLayersThatHaveOne() {
        var on = LayerStyle(); on.shadow = ShadowStyle(radius: 6)
        let off = LayerStyle()
        let shadows = selection([on, off, on]).shadows
        #expect(shadows.count == 2)
        #expect(shadows.selectionCount == 3)
        #expect(shadows.note == "Applies to 2 of the 3 selected layers.")
        #expect(shadows.number { $0.shadow?.radius ?? 0 }.value == 6)
    }

    @Test func shadowRowsSayNothingWhenTheyReachEverything() {
        var on = LayerStyle(); on.shadow = ShadowStyle()
        #expect(selection([on, on]).shadows.note == nil)
        #expect(selection([on]).shadows.note == nil)
    }

    // MARK: - Corner rounding over a selection

    @Test func cornerRadiusReachesFullRoundOnTheBiggestPickedLayer() {
        // Rounding past half a layer's short edge does nothing to it, so the
        // slider stops at the largest picked layer's half-edge: a small box in
        // the selection must not stop a big one going fully round.
        let selection = LayerStyleSelection(members: [
            LayerStyleSelection.Member(id: UUID(), style: LayerStyle(), cornerRadiusLimit: 15),
            LayerStyleSelection.Member(id: UUID(), style: LayerStyle(), cornerRadiusLimit: 60),
        ], selectionCount: 2)
        #expect(selection.cornerRadiusLimit == 60)
    }

    @Test func cornerRadiusLimitIsNeverZero() {
        #expect(selection([]).cornerRadiusLimit == 1)
    }

    // MARK: - Shadow distance and direction

    @Test func distanceAndDirectionDescribeTheOffset() {
        var shadow = ShadowStyle()
        shadow.offset = CGSize(width: 0, height: 10)
        #expect(shadow.distance == 10)
        #expect(shadow.directionDegrees == 90)
    }

    @Test func noOffsetPointsStraightDown() {
        var shadow = ShadowStyle()
        shadow.offset = .zero
        #expect(shadow.distance == 0)
        // So the Direction control still reads sensibly on a shadow that has
        // not been thrown anywhere yet.
        #expect(shadow.directionDegrees == 90)
    }

    @Test func directionIsAlwaysAWholeTurnsWorth() {
        var shadow = ShadowStyle()
        shadow.offset = CGSize(width: 0, height: -10) // straight up
        #expect(shadow.directionDegrees == 270)
    }

    @Test func settingDistanceKeepsTheDirection() {
        var shadow = ShadowStyle()
        shadow.offset = CGSize(width: 3, height: 4) // 5 away
        shadow.setDistance(10)
        #expect(abs(shadow.offset.width - 6) < 0.0001)
        #expect(abs(shadow.offset.height - 8) < 0.0001)
    }

    @Test func settingDirectionOnAShadowWithNoOffsetStillMovesIt() {
        var shadow = ShadowStyle()
        shadow.offset = .zero
        shadow.setDirectionDegrees(0)
        // A direction you cannot see is a control that does nothing, so the
        // shadow steps one point out rather than staying put.
        #expect(shadow.distance == 1)
        #expect(abs(shadow.offset.width - 1) < 0.0001)
    }

    // MARK: - Reading a real selection out of a document

    @Test func lockedLayersAreLeftOutOfTheReading() {
        var round = LayerStyle(); round.cornerRadius = 12
        let a = box("A", style: round)
        let locked = box("Locked", style: LayerStyle(), locked: true)
        let doc = document([a, locked])
        let selection = doc.layerStyleSelection(layerIDs: [a.id, locked.id])
        #expect(selection.layerIDs == [a.id])
        #expect(selection.selectionCount == 2)
        // ...and the row says so, rather than looking as though it did nothing.
        #expect(selection.note == "Applies to 1 of the 2 selected layers.")
        #expect(!selection.number { $0.cornerRadius }.isMixed)
    }

    @Test func theSelectionKeepsTheOrderItWasGiven() {
        let a = box("A"), b = box("B"), c = box("C")
        let doc = document([a, b, c])
        #expect(doc.layerStyleSelection(layerIDs: [c.id, a.id]).layerIDs == [c.id, a.id])
    }

    @Test func cornerRadiusLimitComesFromTheRealLayers() {
        let small = box("Small", size: CGSize(width: 20, height: 20))
        let big = box("Big", size: CGSize(width: 200, height: 100))
        let doc = document([small, big])
        #expect(doc.layerStyleSelection(layerIDs: [small.id, big.id]).cornerRadiusLimit == 50)
    }

    // MARK: - One drag paints them all

    @Test func oneEditReachesEveryPickedLayer() {
        let a = box("A"), b = box("B")
        var doc = document([a, b])
        let changed = doc.updateLayerStyles(layerIDs: [a.id, b.id]) { $0.cornerRadius = 9 }
        #expect(changed == 2)
        #expect(doc.layer(id: a.id)?.style.cornerRadius == 9)
        #expect(doc.layer(id: b.id)?.style.cornerRadius == 9)
    }

    @Test func aLockedLayerIsLeftAlone() {
        let a = box("A")
        let locked = box("Locked", locked: true)
        var doc = document([a, locked])
        let changed = doc.updateLayerStyles(layerIDs: [a.id, locked.id]) { $0.opacity = 0.5 }
        #expect(changed == 1)
        #expect(doc.layer(id: locked.id)?.style.opacity == 1)
    }

    @Test func switchingShadowOnReachesEveryPickedLayer() {
        var shadowed = LayerStyle(); shadowed.shadow = ShadowStyle(radius: 20)
        let a = box("A", style: shadowed)
        let b = box("B")
        var doc = document([a.self, b])
        doc.updateLayerStyles(layerIDs: [a.id, b.id]) { style in
            if style.shadow == nil { style.shadow = ShadowStyle() }
        }
        #expect(doc.layer(id: b.id)?.style.shadow != nil)
        // The one that already had a shadow keeps the shadow it had.
        #expect(doc.layer(id: a.id)?.style.shadow?.radius == 20)
    }
}
