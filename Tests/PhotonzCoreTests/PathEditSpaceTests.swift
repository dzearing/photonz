import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Reshaping a path that has been TURNED: the space a press is read in, the
/// space the points are drawn in, and the box a reshaped turned path takes so
/// the parts of it nobody touched do not move.
@Suite("A turned path's own coordinates")
struct PathEditSpaceTests {

    /// A square with one side bowed out, the same shape the straight reshape
    /// tests use, so the two read side by side.
    static func bowedSquare() -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0), handleOut: CGPoint(x: 40, y: 30)),
            PathAnchor(point: CGPoint(x: 100, y: 100), handleIn: CGPoint(x: 40, y: -30)),
            PathAnchor(point: CGPoint(x: 0, y: 100))
        ], isClosed: true)
    }

    static func turnedLayer(_ radians: CGFloat) -> Layer {
        var layer = PathBuilder.layer(bowedSquare(), at: CGPoint(x: 200, y: 120))
        layer.transform = LayerTransform(rotation: radians)
        return layer
    }

    static func near(_ a: CGPoint, _ b: CGPoint, _ slack: CGFloat = 1e-6) -> Bool {
        abs(a.x - b.x) <= slack && abs(a.y - b.y) <= slack
    }

    // MARK: - The two maps

    @Test func aStraightShapeIsStillJustItsCorner() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: CGPoint(x: 200, y: 120))
        let space = PathEditSpace(layer: layer)
        #expect(Self.near(space.document(CGPoint(x: 10, y: 20)), CGPoint(x: 210, y: 140)))
        #expect(Self.near(space.local(CGPoint(x: 210, y: 140)), CGPoint(x: 10, y: 20)))
    }

    @Test func aTurnedShapeReadsAPressInItsOwnCoordinates() {
        let layer = Self.turnedLayer(.pi / 6)
        let space = PathEditSpace(layer: layer)
        // A press right on a corner of the drawing, taken from where that
        // corner ACTUALLY is on the canvas, comes back as that corner.
        for anchor in layer.path?.anchors ?? [] {
            let onCanvas = space.document(anchor.point)
            #expect(Self.near(space.local(onCanvas), anchor.point))
        }
    }

    @Test func aPointOfATurnedShapeIsWhereTheTurnPutsIt() {
        // A plain square, so the numbers can be read off by hand: the bowed
        // one's curve pushes its box out to 130 wide.
        let square = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)), PathAnchor(point: CGPoint(x: 100, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 100)), PathAnchor(point: CGPoint(x: 0, y: 100))
        ], isClosed: true)
        var layer = PathBuilder.layer(square, at: CGPoint(x: 200, y: 120))
        layer.transform = LayerTransform(rotation: .pi / 2)
        let space = PathEditSpace(layer: layer)
        // A quarter turn about the middle of a 100 x 100 box at (200, 120):
        // the top-left corner swings to where the top-right corner was, and
        // the bottom-left swings to where the top-left was.
        #expect(Self.near(space.document(CGPoint(x: 0, y: 0)), CGPoint(x: 300, y: 120)))
        #expect(Self.near(space.document(CGPoint(x: 0, y: 100)), CGPoint(x: 200, y: 120)))
    }

    @Test func anArrowKeyPushesThePointTheWayTheKeyPoints() {
        let layer = Self.turnedLayer(.pi / 6)
        let space = PathEditSpace(layer: layer)
        let onScreen = CGPoint(x: 0, y: -1)
        let inShape = space.localVector(onScreen)
        // Said in the shape's own coordinates and mapped back out, the push is
        // the one the key asked for: straight up the canvas, one point.
        let from = space.document(CGPoint(x: 50, y: 50))
        let to = space.document(CGPoint(x: 50 + inShape.x, y: 50 + inShape.y))
        #expect(Self.near(CGPoint(x: to.x - from.x, y: to.y - from.y), onScreen))
    }

    @Test func aStraightShapeTakesTheKeyAsItComes() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: CGPoint(x: 200, y: 120))
        #expect(PathEditSpace(layer: layer).localVector(CGPoint(x: 0, y: -1))
            == CGPoint(x: 0, y: -1))
    }

    // MARK: - A piece inside a turned card

    /// A path's own numbers are stated in the upright space inside its card,
    /// so a piece of a card on a slant needs the card's swing taken off the
    /// press and put back on the drawing. Composed the same way and in the
    /// same order `PhotonzDocument.turnedOverlay` composes it: the layer's own
    /// knob first, about its own middle, then the cards above it.
    @Test func aPieceOfATurnedCardIsReadThroughBothTurns() {
        let card = CGAffineTransform(rotationAngle: .pi / 4)
            .concatenating(CGAffineTransform(translationX: 40, y: -15))
        let layer = Self.turnedLayer(.pi / 6)
        let own = PathEditSpace(layer: layer)
        let inside = PathEditSpace(layer: layer, inheritedTurn: card)
        guard let content = layer.path else { Issue.record("a path"); return }
        for anchor in content.anchors {
            // Where it lands is its own turn first, then the card's.
            #expect(Self.near(inside.document(anchor.point),
                              own.document(anchor.point).applying(card)))
            // And a press there comes back as that point.
            #expect(Self.near(inside.local(inside.document(anchor.point)), anchor.point, 1e-5))
        }
    }

    // MARK: - The box that does not slide

    @Test func aStraightShapeKeepsTheBoxItAlwaysHad() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: CGPoint(x: 200, y: 120))
        var pulled = Self.bowedSquare()
        pulled.moveAnchors([0], by: CGPoint(x: -30, y: -40))
        let box = PathEditSpace(layer: layer).steadyFrame(contentBounds: pulled.bounds)
        // The bow puts the box's right edge at 130, so pulling the top-left
        // corner 30 further left makes it 160 across.
        #expect(box == CGRect(x: 170, y: 80, width: 160, height: 140))
    }

    /// The whole point of the task: pull one point of a turned shape out past
    /// the old edge and every OTHER point stays exactly where it was.
    @Test func anUntouchedPointDoesNotMoveWhenTheBoxGrows() {
        let layer = Self.turnedLayer(.pi / 6)
        let space = PathEditSpace(layer: layer)
        guard let original = layer.path else { Issue.record("a path"); return }
        var pulled = original
        pulled.moveAnchors([0], by: CGPoint(x: -30, y: -40))
        let grown = PathEditSpace(frame: space.steadyFrame(contentBounds: pulled.bounds),
                                  transform: layer.transform, pivot: nil)
        let refit = pulled.offsetBy(dx: -pulled.bounds.minX, dy: -pulled.bounds.minY)
        for index in original.anchors.indices {
            let was = space.document(original.anchors[index].point)
            let now = grown.document(refit.anchors[index].point)
            if index == 0 {
                // The one that moved went exactly where the hand took it, and
                // nowhere else.
                let asked = space.document(pulled.anchors[0].point)
                #expect(Self.near(now, asked, 1e-5))
            } else {
                #expect(Self.near(now, was, 1e-5),
                        "point \(index) slid from \(was) to \(now)")
            }
        }
    }

    @Test func theBoxDoesNotSlideWhenTheShapeTurnsAboutSomewhereElse() {
        var layer = Self.turnedLayer(.pi / 3)
        layer.motions = [LayerMotion(property: .rotation,
                                     from: .number(0), to: .number(90),
                                     timing: MotionTiming(startMS: 0, durationMS: 500),
                                     pivot: MotionPivot(unit: CGPoint(x: 0, y: 0)))]
        let space = PathEditSpace(layer: layer)
        #expect(space.pivot != nil, "the pivot on the turn is the one that counts")
        guard let original = layer.path else { Issue.record("a path"); return }
        var pulled = original
        pulled.moveAnchors([2], by: CGPoint(x: 40, y: 25))
        let grown = PathEditSpace(frame: space.steadyFrame(contentBounds: pulled.bounds),
                                  transform: layer.transform, pivot: space.pivot)
        let refit = pulled.offsetBy(dx: -pulled.bounds.minX, dy: -pulled.bounds.minY)
        for index in original.anchors.indices where index != 2 {
            #expect(Self.near(grown.document(refit.anchors[index].point),
                              space.document(original.anchors[index].point), 1e-5))
        }
    }

    // MARK: - Sweeping a box over a turned shape's points

    /// The band is the upright box the hand dragged, and it takes the points
    /// it visibly goes round. On a turned shape that is a different set from
    /// the one the old code took, which tested a canvas box against the
    /// shape's own untravelled coordinates and so gathered points nowhere near
    /// it.
    @Test func aBandTakesThePointsItGoesRoundOnScreen() {
        let layer = Self.turnedLayer(.pi / 2)
        let space = PathEditSpace(layer: layer)
        guard let content = layer.path else { Issue.record("a path"); return }
        // A box drawn tightly round where anchor 3 actually sits.
        let onCanvas = space.document(content.anchors[3].point)
        let band = CGRect(x: onCanvas.x - 5, y: onCanvas.y - 5, width: 10, height: 10)
        #expect(content.anchorIndices(in: band, of: space) == [3])
        // And a band round the whole drawing takes all of it.
        var whole = CGRect(x: onCanvas.x, y: onCanvas.y, width: 0, height: 0)
        for anchor in content.anchors {
            let p = space.document(anchor.point)
            whole = whole.union(CGRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        #expect(content.anchorIndices(in: whole.insetBy(dx: -2, dy: -2), of: space)
            == Set(content.anchors.indices))
    }

    @Test func aBandOnAStraightShapeAnswersWhatItAlwaysDid() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: CGPoint(x: 200, y: 120))
        let space = PathEditSpace(layer: layer)
        guard let content = layer.path else { Issue.record("a path"); return }
        let band = CGRect(x: 195, y: 115, width: 20, height: 20)
        #expect(content.anchorIndices(in: band, of: space)
            == content.anchorIndices(in: band.offsetBy(dx: -200, dy: -120)))
    }

    // MARK: - Through the refit every reshape goes through

    @Test func refittingATurnedPathLeavesEveryPointItDidNotMoveWhereItWas() {
        let layer = Self.turnedLayer(.pi / 6)
        guard let original = layer.path else { Issue.record("a path"); return }
        var pulled = original
        pulled.moveAnchors([0], by: CGPoint(x: -30, y: -40))
        let fitted = PathBuilder.refit(layer, content: pulled)
        guard let after = fitted.path else { Issue.record("a path"); return }
        let before = PathEditSpace(layer: layer)
        let now = PathEditSpace(layer: fitted)
        for index in original.anchors.indices where index != 0 {
            #expect(Self.near(now.document(after.anchors[index].point),
                              before.document(original.anchors[index].point), 1e-5))
        }
        // The turn itself is untouched: the A field reads the same afterwards.
        #expect(fitted.transform == layer.transform)
        // And the box really did grow to take the point that moved out.
        #expect(abs(fitted.frame.width - 160) < 1e-6)
        #expect(abs(fitted.frame.height - 140) < 1e-6)
    }
}
