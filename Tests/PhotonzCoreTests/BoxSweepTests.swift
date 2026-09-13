import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The box half of Separate into Layers, on scenes whose right answer is known
/// because the test drew them.
///
/// Every scene here is painted the way real UI is painted: a page colour, a
/// thing sitting on it, antialiasing down its rounded edges. The fixture tests
/// in PhotonzRenderTests do the same against a real capture, which is the only
/// place a heuristic can really be caught out.
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("Boxes in a picture")
struct BoxSweepTests {

    // MARK: - Painting scenes

    /// A picture being drawn, in premultiplied sRGB bytes.
    struct Scene {
        let width: Int
        let height: Int
        var bytes: [UInt8]

        init(width: Int, height: Int, background: RGBA) {
            self.width = width
            self.height = height
            bytes = [UInt8](repeating: 0, count: width * height * 4)
            fill(CGRect(x: 0, y: 0, width: width, height: height), background)
        }

        mutating func set(_ x: Int, _ y: Int, _ color: RGBA) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let i = (y * width + x) * 4
            func byte(_ v: Double) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
            bytes[i] = byte(color.r)
            bytes[i + 1] = byte(color.g)
            bytes[i + 2] = byte(color.b)
            bytes[i + 3] = byte(color.a)
        }

        mutating func fill(_ rect: CGRect, _ color: RGBA) {
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) { set(x, y, color) }
            }
        }

        /// A rounded rectangle with the same antialiasing a real renderer
        /// leaves: a pixel on the curve is a blend of the shape and whatever it
        /// is sitting on.
        mutating func rounded(_ rect: CGRect, radius: CGFloat, _ color: RGBA,
                              over background: RGBA) {
            let r = min(radius, min(rect.width, rect.height) / 2)
            for y in Int(rect.minY - 2)..<Int(rect.maxY + 2) {
                for x in Int(rect.minX - 2)..<Int(rect.maxX + 2) {
                    let d = Self.distance(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5),
                                          rect, r)
                    let coverage = min(max(0.5 - d, 0), 1)
                    guard coverage > 0 else { continue }
                    set(x, y, RGBA(r: color.r * coverage + background.r * (1 - coverage),
                                   g: color.g * coverage + background.g * (1 - coverage),
                                   b: color.b * coverage + background.b * (1 - coverage),
                                   a: 1))
                }
            }
        }

        /// Signed distance from a point to a rounded rectangle: negative inside.
        static func distance(_ p: CGPoint, _ rect: CGRect, _ radius: CGFloat) -> Double {
            let cx = rect.midX, cy = rect.midY
            let hx = rect.width / 2 - radius, hy = rect.height / 2 - radius
            let dx = max(abs(p.x - cx) - hx, 0), dy = max(abs(p.y - cy) - hy, 0)
            let inside = min(max(abs(p.x - cx) - hx, abs(p.y - cy) - hy), 0)
            return Double(sqrt(dx * dx + dy * dy) + inside - radius)
        }

        var field: PixelField { PixelField(width: width, height: height, samples: bytes) }
    }

    private static let page = RGBA(r: 0.95, g: 0.95, b: 0.96)
    private static let card = RGBA(r: 1, g: 1, b: 1)
    private static let blue = RGBA(r: 0, g: 0.478, b: 1)

    // MARK: - What comes out

    @Test func aBoxSittingOnThePageComesOut() {
        var scene = Scene(width: 400, height: 300, background: Self.page)
        scene.rounded(CGRect(x: 100, y: 100, width: 160, height: 48), radius: 8,
                      Self.blue, over: Self.page)
        let sweep = BoxSweep.sweep(in: scene.field)
        #expect(sweep.boxes.count == 1)
        let box = try? #require(sweep.boxes.first)
        #expect(box?.rect == CGRect(x: 100, y: 100, width: 160, height: 48))
    }

    @Test func thePageItselfIsNeverOffered() {
        var scene = Scene(width: 400, height: 300, background: Self.page)
        scene.rounded(CGRect(x: 100, y: 100, width: 160, height: 48), radius: 8,
                      Self.blue, over: Self.page)
        // Nothing the size of the picture, and nothing starting at its corner.
        #expect(!BoxSweep.sweep(in: scene.field).boxes.contains { $0.rect.minX == 0 })
    }

    @Test func aBoxTooSmallToBeWorthMovingIsLeftAlone() {
        var scene = Scene(width: 400, height: 300, background: Self.page)
        scene.rounded(CGRect(x: 100, y: 100, width: 12, height: 12), radius: 2,
                      Self.blue, over: Self.page)
        #expect(BoxSweep.sweep(in: scene.field).boxes.isEmpty)
    }

    @Test func aBoxRunningOffTheEdgeOfThePictureIsLeftAlone() {
        // Half a card is not a card: the picture cut it off, so its real shape
        // is not in the picture and the app does not pretend to know it.
        var scene = Scene(width: 400, height: 300, background: Self.page)
        scene.fill(CGRect(x: 300, y: 100, width: 100, height: 60), Self.blue)
        #expect(BoxSweep.sweep(in: scene.field).boxes.isEmpty)
    }

    @Test func aThingSittingOnABoxComesOutInsideIt() {
        // One level, deliberately. The card is what a person grabs; the two
        // buttons on it travel with it rather than arriving as their own rows.
        var scene = Scene(width: 500, height: 400, background: Self.page)
        scene.rounded(CGRect(x: 40, y: 40, width: 420, height: 240), radius: 12,
                      Self.card, over: Self.page)
        scene.rounded(CGRect(x: 80, y: 80, width: 120, height: 44), radius: 8,
                      Self.blue, over: Self.card)
        scene.rounded(CGRect(x: 240, y: 80, width: 120, height: 44), radius: 8,
                      Self.blue, over: Self.card)
        let boxes = BoxSweep.sweep(in: scene.field).boxes
        #expect(boxes.count == 1)
        #expect(boxes.first?.rect == CGRect(x: 40, y: 40, width: 420, height: 240))
    }

    @Test func aPanelFillingThePictureIsLookedInsideRatherThanTakenWhole() {
        // A screenshot of one window: the thing that fills the picture is the
        // picture, so what is worth taking is what sits ON it.
        var scene = Scene(width: 500, height: 400, background: Self.page)
        scene.fill(CGRect(x: 2, y: 2, width: 496, height: 396), Self.card)
        scene.rounded(CGRect(x: 80, y: 80, width: 120, height: 44), radius: 8,
                      Self.blue, over: Self.card)
        let boxes = BoxSweep.sweep(in: scene.field).boxes
        #expect(boxes.count == 1)
        #expect(boxes.first?.rect == CGRect(x: 80, y: 80, width: 120, height: 44))
    }

    @Test func aRunOfTextAlreadySpokenForIsNotTakenTwice() {
        var scene = Scene(width: 400, height: 300, background: Self.page)
        scene.rounded(CGRect(x: 100, y: 100, width: 160, height: 48), radius: 8,
                      Self.blue, over: Self.page)
        let reserved = [CGRect(x: 96, y: 96, width: 168, height: 56)]
        #expect(BoxSweep.sweep(in: scene.field, avoiding: reserved).boxes.isEmpty)
    }

    // MARK: - A box that is really a shape

    @Test func aFlatBoxComesOutAsAShapeWithItsColourAndItsRounding() throws {
        var scene = Scene(width: 400, height: 300, background: Self.page)
        scene.rounded(CGRect(x: 100, y: 100, width: 160, height: 48), radius: 12,
                      Self.blue, over: Self.page)
        let box = try #require(BoxSweep.sweep(in: scene.field).boxes.first)
        let shape = try #require(box.shape)
        #expect(abs(shape.fill.r - Self.blue.r) < 0.01)
        #expect(abs(shape.fill.g - Self.blue.g) < 0.01)
        #expect(abs(shape.fill.b - Self.blue.b) < 0.01)
        #expect(abs(shape.radii.topLeft - 12) <= 1)
        #expect(abs(shape.radii.topRight - 12) <= 1)
        #expect(abs(shape.radii.bottomRight - 12) <= 1)
        #expect(abs(shape.radii.bottomLeft - 12) <= 1)
        #expect(shape.borderWidth == 0)
    }

    @Test func aSquareBoxDoesNotComeOutRounded() throws {
        var scene = Scene(width: 400, height: 300, background: Self.page)
        scene.fill(CGRect(x: 100, y: 100, width: 160, height: 48), Self.blue)
        let box = try #require(BoxSweep.sweep(in: scene.field).boxes.first)
        let shape = try #require(box.shape)
        #expect(shape.radii == .none)
    }

    @Test func aBoxWithAPlainEdgeKeepsThatEdge() throws {
        // A text field: white inside, one grey line round it.
        let border = RGBA(r: 0.7, g: 0.7, b: 0.72)
        var scene = Scene(width: 400, height: 300, background: Self.page)
        scene.rounded(CGRect(x: 100, y: 100, width: 200, height: 60), radius: 10,
                      border, over: Self.page)
        scene.rounded(CGRect(x: 102, y: 102, width: 196, height: 56), radius: 8,
                      Self.card, over: border)
        let box = try #require(BoxSweep.sweep(in: scene.field).boxes.first)
        let shape = try #require(box.shape)
        #expect(shape.borderWidth == 2)
        let ink = try #require(shape.borderColor)
        #expect(abs(ink.r - border.r) < 0.02)
        #expect(abs(shape.fill.r - Self.card.r) < 0.02)
    }

    @Test func aBoxWithSomethingInsideItStaysAPicture() throws {
        // A switch: a green track with a white knob in it. Nobody can say what
        // shape that is, so it comes out as pixels and keeps every one of them.
        let green = RGBA(r: 0.2, g: 0.78, b: 0.35)
        var scene = Scene(width: 400, height: 300, background: Self.page)
        scene.rounded(CGRect(x: 100, y: 100, width: 86, height: 46), radius: 23,
                      green, over: Self.page)
        scene.rounded(CGRect(x: 142, y: 103, width: 40, height: 40), radius: 20,
                      Self.card, over: green)
        let box = try #require(BoxSweep.sweep(in: scene.field).boxes.first)
        #expect(box.rect == CGRect(x: 100, y: 100, width: 86, height: 46))
        #expect(box.shape == nil)
    }

    @Test func aBoxPaintedWithARampStaysAPicture() throws {
        // Not one colour, so not one fill. Guessing a gradient is exactly the
        // guess the user asked us not to make.
        var scene = Scene(width: 400, height: 300, background: Self.page)
        for y in 100..<148 {
            let t = Double(y - 100) / 48
            scene.fill(CGRect(x: 100, y: y, width: 160, height: 1),
                       RGBA(r: 0.1 + 0.5 * t, g: 0.2, b: 0.8 - 0.4 * t))
        }
        let box = try #require(BoxSweep.sweep(in: scene.field).boxes.first)
        #expect(box.shape == nil)
    }

    @Test func nothingIsOfferedWhenThePictureHasNoBackgroundToReadFromIt() {
        // A photograph: no two neighbouring pixels agree, so there is no page
        // for anything to be sitting on and nothing is claimed.
        var scene = Scene(width: 200, height: 200, background: Self.page)
        for y in 0..<200 {
            for x in 0..<200 {
                let shade = 0.4 + 0.3 * sin(Double(x) / 3) * cos(Double(y) / 4)
                scene.set(x, y, RGBA(r: shade, g: shade * 0.8, b: shade * 0.6))
            }
        }
        #expect(BoxSweep.sweep(in: scene.field).boxes.isEmpty)
    }

    // MARK: - What the renderer needs back

    @Test func everyPixelOfABoxIsMarkedSoItCanBeCutOutExactly() throws {
        var scene = Scene(width: 400, height: 300, background: Self.page)
        scene.rounded(CGRect(x: 100, y: 100, width: 160, height: 48), radius: 12,
                      Self.blue, over: Self.page)
        let sweep = BoxSweep.sweep(in: scene.field)
        let box = try #require(sweep.boxes.first)
        // The middle of it belongs to the box.
        #expect(sweep.isIsland(180, 124, box.island))
        // A corner of its bounding box does not: that is the page showing
        // through the rounding, and it has to stay behind.
        #expect(!sweep.isIsland(100, 100, box.island))
        // And neither does anything outside it.
        #expect(!sweep.isIsland(50, 50, box.island))
        #expect(sweep.isBackdrop(50, 50))
    }
}
