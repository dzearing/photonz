import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Where the background is READ FROM around a piece of any outline. The
/// deciding half (`PatchDecision`) never knew what shape a piece was; this is
/// the half that lets an ellipse or a wand blob hand it a ring at all.
@Suite("Walking the ring around a shape of any outline")
struct PatchRingWalkTests {

    /// A mask over `rect` that is `inside` everywhere `shape` says so.
    private func mask(_ rect: CGRect, _ shape: (Int, Int) -> Bool) -> [Bool] {
        var bits: [Bool] = []
        for y in 0..<Int(rect.height) {
            for x in 0..<Int(rect.width) { bits.append(shape(x, y)) }
        }
        return bits
    }

    private let clip = CGRect(x: 0, y: 0, width: 200, height: 200)

    @Test func aSolidBoxIsRingedOnAllFourSides() {
        let rect = CGRect(x: 50, y: 40, width: 20, height: 10)
        let spots = PatchRingWalk.spots(inside: mask(rect) { _, _ in true },
                                        rect: rect, clip: clip, width: 3)
        // Nothing inside the box is ever a sample: the ring is the background.
        #expect(!spots.contains { (s: PatchRingWalk.Spot) in
            s.x >= 50 && s.x < 70 && s.y >= 40 && s.y < 50
        })
        // Three bands out on every side, corners included.
        #expect(spots.contains { $0.x == 50 && $0.y == 37 })   // above
        #expect(spots.contains { $0.x == 50 && $0.y == 52 })   // below
        #expect(spots.contains { $0.x == 47 && $0.y == 40 })   // left
        #expect(spots.contains { $0.x == 72 && $0.y == 40 })   // right
        #expect(spots.contains { $0.x == 47 && $0.y == 37 })   // the corner
        // Four bands out is not the background right THERE any more.
        #expect(!spots.contains { $0.x == 50 && $0.y == 36 })
        #expect(!spots.contains { $0.x == 74 && $0.y == 45 })
        // Every spot appears once. A ring that counts a pixel twice weights it
        // twice in the median, and the flat case stops being exact.
        #expect(Set(spots.map { "\($0.x),\($0.y)" }).count == spots.count)
    }

    /// `u` and `v` are measured against the piece's own box, exactly the way
    /// `PatchFill.color(u:v:)` reads them back, so a fitted ramp lands where
    /// the fit said it would.
    @Test func theCoordinatesAreMeasuredAgainstThePiecesOwnBox() {
        let rect = CGRect(x: 50, y: 40, width: 20, height: 10)
        let spots = PatchRingWalk.spots(inside: mask(rect) { _, _ in true },
                                        rect: rect, clip: clip, width: 3)
        let leftOfTheMiddle = spots.first { $0.x == 47 && $0.y == 45 }
        #expect(leftOfTheMiddle != nil)
        // One and a half pixels left of a 20 wide box: a little past 0.
        #expect(abs((leftOfTheMiddle?.u ?? 0) - (-3 + 0.5) / 20) < 1e-9)
        #expect(abs((leftOfTheMiddle?.v ?? 0) - (5 + 0.5) / 10) < 1e-9)
        // A sample just past the bottom sits a little past 1, which is where a
        // fit wants it.
        let belowTheMiddle = spots.first { $0.x == 60 && $0.y == 51 }
        #expect((belowTheMiddle?.v ?? 0) > 1)
    }

    /// The whole point of the walk: a ring that follows the outline rather
    /// than the box round it. An ellipse's corner is OUTSIDE the ellipse and
    /// more than three pixels from it, so it must not vote on the fill.
    @Test func anEllipseIsRingedAlongItsOutlineAndNotItsCorners() {
        let rect = CGRect(x: 20, y: 20, width: 40, height: 40)
        let spots = PatchRingWalk.spots(inside: mask(rect) { x, y in
            let dx = (Double(x) + 0.5 - 20) / 20, dy = (Double(y) + 0.5 - 20) / 20
            return dx * dx + dy * dy <= 1
        }, rect: rect, clip: clip, width: 3)
        // Just outside the ellipse at its widest: in.
        #expect(spots.contains { $0.x == 61 && $0.y == 40 })
        // The corner of the box the ellipse is inscribed in: far outside it.
        #expect(!spots.contains { $0.x == 20 && $0.y == 20 })
        #expect(!spots.contains { $0.x == 59 && $0.y == 59 })
        // And the ring reaches INSIDE the box, which a four-sided ring never
        // could: the pixels between the ellipse and the box corner are the
        // background too.
        #expect(spots.contains { (s: PatchRingWalk.Spot) in
            s.x > 20 && s.x < 60 && s.y > 20 && s.y < 60
        })
    }

    /// A blob with a bite out of it, which is what the wand hands over: the
    /// bite's own walls are background and must be read.
    @Test func aShapeWithAHoleInItIsRingedInsideTheHoleToo() {
        let rect = CGRect(x: 10, y: 10, width: 30, height: 30)
        let spots = PatchRingWalk.spots(inside: mask(rect) { x, y in
            !(x >= 12 && x < 18 && y >= 12 && y < 18)
        }, rect: rect, clip: clip, width: 3)
        // The middle of the bite is background, and it is right beside the shape.
        #expect(spots.contains { $0.x == 25 && $0.y == 25 })
    }

    /// The band right against the outline can be skipped, which is what a cut
    /// does: a wand follows the ink exactly, so the pixel touching the outline
    /// is half ink and would poison the reading.
    @Test func theBandRightAgainstTheOutlineCanBeLeftOut() {
        let rect = CGRect(x: 50, y: 40, width: 20, height: 10)
        let spots = PatchRingWalk.spots(inside: mask(rect) { _, _ in true },
                                        rect: rect, clip: clip, width: 3, gap: 1)
        // One out: too close to the outline to be background.
        #expect(!spots.contains { $0.x == 49 && $0.y == 45 })
        #expect(!spots.contains { $0.x == 50 && $0.y == 39 })
        // Two, three and four out: the band that is read.
        #expect(spots.contains { $0.x == 48 && $0.y == 45 })
        #expect(spots.contains { $0.x == 46 && $0.y == 45 })
        // Five out is past it.
        #expect(!spots.contains { $0.x == 45 && $0.y == 45 })
        #expect(Set(spots.map { "\($0.x),\($0.y)" }).count == spots.count)
    }

    @Test func nothingIsSampledFromOffThePicture() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let spots = PatchRingWalk.spots(inside: mask(rect) { _, _ in true },
                                        rect: rect, clip: CGRect(x: 0, y: 0, width: 40, height: 40),
                                        width: 3)
        #expect(!spots.contains { $0.x < 0 || $0.y < 0 })
        #expect(spots.contains { $0.x == 12 && $0.y == 4 })
    }

    /// A marquee flung round the whole picture has no background left to read.
    /// The walk says so by handing back nothing rather than by inventing a
    /// ring, and the caller turns that into an honest empty space.
    @Test func aShapeThatFillsThePictureHasNoRingAtAll() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        let spots = PatchRingWalk.spots(inside: mask(rect) { _, _ in true },
                                        rect: rect, clip: rect, width: 3)
        #expect(spots.isEmpty)
    }

    @Test func aMaskThatDoesNotMatchItsBoxIsRefused() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(PatchRingWalk.spots(inside: [true, false], rect: rect, clip: clip).isEmpty)
        #expect(PatchRingWalk.spots(inside: [], rect: .zero, clip: clip).isEmpty)
    }
}
