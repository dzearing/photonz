import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Reading a card's shadow off the picture, so a separated card brings it with
/// it as a REAL shadow rather than as a grey halo baked into the page.
///
/// The bar the user set for this one: "in the worst case we ignore parts that
/// we can't interpret". A wrong shadow makes a separated card look broken in a
/// way a missing shadow does not, so half of what is pinned here is what must
/// come back nil — an underline, a border, a page that shades from dark to
/// light, a reflection — and every one of them is offered with the whole scene
/// marked as readable background, so the reader has to refuse on the merits
/// rather than being saved by a mask.
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("Reading a shadow off a picture")
struct ShadowReadTests {

    /// Everything outside the card is fair game to read. Deliberately generous.
    private func anywhereOutside(_ box: CGRect) -> (Int, Int) -> Bool {
        { x, y in !box.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) }
    }

    private let page = (242.0, 242.0, 247.0)

    // MARK: - A shadow that is there

    @Test func aSoftShadowComesBackWithTheNumbersItWasDrawnWith() throws {
        let box = CGRect(x: 120, y: 100, width: 400, height: 200)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        scene.castShadow(box, radius: 16, sigma: 4, offset: CGSize(width: 0, height: 6),
                         opacity: 0.25)
        scene.paint(box, radius: 16, (255, 255, 255))

        let reading = try #require(ShadowRead.read(box, in: scene.field,
                                                   isBackdrop: anywhereOutside(box)))
        print("READ drawn sigma 4, offset (0,6), black 25% -> "
            + "sigma \(reading.style.radius), offset \(reading.style.offset), "
            + "\(reading.style.colorHex) at \(Int(reading.style.opacity * 100))%, "
            + "reach \(reading.reach)")
        #expect(abs(reading.style.radius - 4) <= 0.4)
        #expect(abs(reading.style.offset.width) <= 0.4)
        #expect(abs(reading.style.offset.height - 6) <= 0.4)
        #expect(abs(reading.style.opacity - 0.25) <= 0.02)
        #expect(reading.style.colorHex == "#000000")
        #expect(reading.style.kind == .drop)
    }

    @Test func aShadowThrownSidewaysSaysWhichWay() throws {
        let box = CGRect(x: 140, y: 120, width: 360, height: 180)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        scene.castShadow(box, radius: 12, sigma: 3, offset: CGSize(width: -5, height: 4),
                         opacity: 0.3)
        scene.paint(box, radius: 12, (255, 255, 255))

        let reading = try #require(ShadowRead.read(box, in: scene.field,
                                                   isBackdrop: anywhereOutside(box)))
        print("READ drawn offset (-5,4) -> \(reading.style.offset)")
        #expect(abs(reading.style.offset.width + 5) <= 0.5)
        #expect(abs(reading.style.offset.height - 4) <= 0.5)
    }

    @Test func aTightContactShadowIsStillAShadow() throws {
        let box = CGRect(x: 140, y: 120, width: 360, height: 180)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        scene.castShadow(box, radius: 10, sigma: 1.5, offset: CGSize(width: 0, height: 1),
                         opacity: 0.45)
        scene.paint(box, radius: 10, (255, 255, 255))

        let reading = try #require(ShadowRead.read(box, in: scene.field,
                                                   isBackdrop: anywhereOutside(box)))
        print("READ drawn sigma 1.5, offset (0,1), 45% -> sigma \(reading.style.radius), "
            + "offset \(reading.style.offset), \(Int(reading.style.opacity * 100))%")
        #expect(abs(reading.style.radius - 1.5) <= 0.4)
        #expect(abs(reading.style.opacity - 0.45) <= 0.03)
    }

    @Test func theReachCoversEveryPixelTheShadowDarkened() throws {
        let box = CGRect(x: 120, y: 100, width: 400, height: 200)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        scene.castShadow(box, radius: 16, sigma: 4, offset: CGSize(width: 0, height: 6),
                         opacity: 0.25)
        scene.paint(box, radius: 16, (255, 255, 255))
        let reading = try #require(ShadowRead.read(box, in: scene.field,
                                                   isBackdrop: anywhereOutside(box)))

        // Everything the reach covers is painted over, so nothing outside it
        // may still be darker than the page: that is what "no dark smudge left
        // behind" means, expressed as a number.
        let grown = box.insetBy(dx: -reading.reach, dy: -reading.reach)
        let field = scene.field
        var worst = 0.0
        for y in 0..<field.height {
            for x in 0..<field.width where !grown.contains(CGPoint(x: x, y: y)) {
                let c = field.color(x, y)
                worst = max(worst, max(reading.page.r - c.r,
                                       max(reading.page.g - c.g, reading.page.b - c.b)))
            }
        }
        print("REACH \(reading.reach) px; worst darkening left outside it: "
            + "\(Int((worst * 255).rounded()))/255")
        #expect(worst * 255 < 0.6)
    }

    @Test func twoCardsStackedEachKeepTheirOwnShadow() throws {
        // The commonest real page there is, and the one that breaks a reader
        // that looks a fixed distance out: each card's shadow ends a few pixels
        // short of the next card's shadow beginning, so reading all the way
        // down finds the neighbour's darkness in this one's tail.
        let top = CGRect(x: 80, y: 60, width: 480, height: 140)
        let bottom = CGRect(x: 80, y: 236, width: 480, height: 140)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        for card in [top, bottom] {
            scene.castShadow(card, radius: 14, sigma: 3, offset: CGSize(width: 0, height: 3),
                             opacity: 0.22)
        }
        for card in [top, bottom] { scene.paint(card, radius: 14, (255, 255, 255)) }
        let outside: (Int, Int) -> Bool = { x, y in
            let p = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
            return !top.contains(p) && !bottom.contains(p)
        }
        let first = try #require(ShadowRead.read(top, in: scene.field, isBackdrop: outside))
        let second = try #require(ShadowRead.read(bottom, in: scene.field, isBackdrop: outside))
        print("READ stacked cards, both drawn sigma 3 offset (0,3) at 22% -> "
            + "top sigma \(first.style.radius) offset \(first.style.offset) "
            + "\(Int(first.style.opacity * 100))%, bottom sigma \(second.style.radius) "
            + "offset \(second.style.offset) \(Int(second.style.opacity * 100))%")
        for reading in [first, second] {
            #expect(abs(reading.style.radius - 3) <= 0.4)
            #expect(abs(reading.style.offset.height - 3) <= 0.5)
            #expect(abs(reading.style.opacity - 0.22) <= 0.02)
        }
    }

    // MARK: - Things that are not shadows

    @Test func aCardWithNoShadowGetsNone() throws {
        let box = CGRect(x: 120, y: 100, width: 400, height: 200)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        scene.paint(box, radius: 16, (255, 255, 255))
        #expect(ShadowRead.read(box, in: scene.field, isBackdrop: anywhereOutside(box)) == nil)
    }

    @Test func anUnderlineIsNotAShadow() throws {
        // A dark rule four pixels under the card, spanning it — the thing a
        // one-sided falloff test would happily call a shadow with a big offset.
        let box = CGRect(x: 120, y: 100, width: 400, height: 200)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        scene.paint(CGRect(x: 120, y: 304, width: 400, height: 2), radius: 0, (170, 170, 175))
        scene.paint(box, radius: 16, (255, 255, 255))
        #expect(ShadowRead.read(box, in: scene.field, isBackdrop: anywhereOutside(box)) == nil)
    }

    @Test func anEdgeRoundTheCardIsNotAShadow() throws {
        // A hairline border, hard on all four sides. It is part of the card,
        // not something cast behind it, and reading it as a shadow would put a
        // grey rectangle under every bordered box in the picture.
        let box = CGRect(x: 120, y: 100, width: 400, height: 200)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        scene.paint(box.insetBy(dx: -2, dy: -2), radius: 18, (200, 200, 205))
        scene.paint(box, radius: 16, (255, 255, 255))
        // Read against the border's own outer box, the way the sweep hands it
        // over: the border travels with the card.
        let whole = box.insetBy(dx: -2, dy: -2)
        #expect(ShadowRead.read(whole, in: scene.field, isBackdrop: anywhereOutside(whole)) == nil)
    }

    @Test func aPageThatShadesFromDarkToLightIsNotAShadow() throws {
        let box = CGRect(x: 120, y: 140, width: 400, height: 160)
        var scene = ShadowScene(width: 640, height: 440, page: (255, 255, 255))
        // A page ramping 200 -> 250 down its height. Above the card it is
        // darker than below it, which is exactly the asymmetry a dropped
        // shadow makes — and it never comes back to one page colour.
        var ramp = [Double](repeating: 0, count: 640 * 440)
        for y in 0..<440 {
            let t = Double(y) / 439
            for x in 0..<640 { ramp[y * 640 + x] = 1 - (200 + 50 * t) / 255 }
        }
        scene.composite((0, 0, 0), alpha: ramp)
        scene.paint(box, radius: 16, (255, 255, 255))
        #expect(ShadowRead.read(box, in: scene.field, isBackdrop: anywhereOutside(box)) == nil)
    }

    @Test func aReflectionIsNotAShadow() throws {
        // The card mirrored below itself and faded: dark near the card, gone
        // further down, and with the card's own two tones still in it.
        let box = CGRect(x: 120, y: 80, width: 400, height: 160)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        var alpha = [Double](repeating: 0, count: 640 * 440)
        for y in 240..<400 {
            let mirrored = 240 - (y - 240)
            let fade = max(0, 1 - Double(y - 240) / 160) * 0.45
            for x in 120..<520 {
                // The card is two-tone: a header band and a body.
                let band = mirrored < 120 ? 0.45 : 1.0
                alpha[y * 640 + x] = fade * band
            }
        }
        scene.composite((40, 40, 60), alpha: alpha)
        scene.paint(box, radius: 16, (255, 255, 255))
        #expect(ShadowRead.read(box, in: scene.field, isBackdrop: anywhereOutside(box)) == nil)
    }

    @Test func aSoftDarkeningThatIsNotAGaussianFalloffIsNotAShadow() throws {
        // Dark against the card and gone thirty pixels out, on all four sides,
        // falling off in a straight line rather than the way a blur does. It
        // passes every cheap test — it darkens, it is even along each edge, it
        // only ever gets lighter, it comes back to the page — and it is still
        // not a shadow, so the fit has to be the thing that says so.
        let box = CGRect(x: 140, y: 120, width: 360, height: 180)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        var alpha = [Double](repeating: 0, count: 640 * 440)
        for y in 0..<440 {
            for x in 0..<640 {
                let dx = max(box.minX - Double(x), max(Double(x) - box.maxX, 0))
                let dy = max(box.minY - Double(y), max(Double(y) - box.maxY, 0))
                let d = max(dx, dy)
                guard d > 0 else { continue }
                alpha[y * 640 + x] = max(0, 1 - d / 30) * 0.3
            }
        }
        scene.composite((0, 0, 0), alpha: alpha)
        scene.paint(box, radius: 16, (255, 255, 255))
        #expect(ShadowRead.read(box, in: scene.field, isBackdrop: anywhereOutside(box)) == nil)
    }

    @Test func aShadowTooFaintToBeSureOfIsLeftAlone() throws {
        // One level of grey at its darkest. There is no honest reading of that
        // and the card is better off flat than wearing a guess.
        let box = CGRect(x: 120, y: 100, width: 400, height: 200)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        scene.castShadow(box, radius: 16, sigma: 4, offset: CGSize(width: 0, height: 4),
                         opacity: 0.006)
        scene.paint(box, radius: 16, (255, 255, 255))
        #expect(ShadowRead.read(box, in: scene.field, isBackdrop: anywhereOutside(box)) == nil)
    }

    @Test func aShadowThatRunsOffThePictureIsLeftAlone() throws {
        // The card sits three pixels from the frame: most of its shadow was
        // never in the screenshot, so what it was is not knowable.
        let box = CGRect(x: 3, y: 3, width: 400, height: 200)
        var scene = ShadowScene(width: 440, height: 300, page: page)
        scene.castShadow(box, radius: 16, sigma: 6, offset: CGSize(width: 0, height: 6),
                         opacity: 0.3)
        scene.paint(box, radius: 16, (255, 255, 255))
        #expect(ShadowRead.read(box, in: scene.field, isBackdrop: anywhereOutside(box)) == nil)
    }

    @Test func somethingSittingInTheShadowStopsTheReading() throws {
        // A neighbour eight pixels below the card, marked as not-background the
        // way the sweep marks every island. Its own pixels must not vote, and
        // with the shadow only half visible the card keeps it.
        let box = CGRect(x: 120, y: 100, width: 400, height: 160)
        let neighbour = CGRect(x: 120, y: 268, width: 400, height: 80)
        var scene = ShadowScene(width: 640, height: 440, page: page)
        scene.castShadow(box, radius: 16, sigma: 5, offset: CGSize(width: 0, height: 5),
                         opacity: 0.3)
        scene.paint(box, radius: 16, (255, 255, 255))
        scene.paint(neighbour, radius: 16, (90, 90, 100))
        let backdrop: (Int, Int) -> Bool = { x, y in
            let p = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
            return !box.contains(p) && !neighbour.insetBy(dx: -1, dy: -1).contains(p)
        }
        #expect(ShadowRead.read(box, in: scene.field, isBackdrop: backdrop) == nil)
    }
}
