import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A clicked window is shot bare and flattened with a lighter copy of macOS's
/// shadow drawn from a layer style (task
/// `a-captured-window-s-shadow-is-much-lighter-and-c`).
@Suite("A clicked window's lighter shadow, drawn at render time")
struct WindowCaptureShadowTests {

    /// An opaque white window, `width` by `height` pixels.
    static func window(width: Int = 400, height: Int = 300) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Alpha 0...1 at a pixel, x from the left and y from the TOP.
    static func alpha(_ image: CGImage, _ x: Int, _ y: Int) -> Double {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Double(data[(y * width + x) * 4 + 3]) / 255
    }

    static func gaussianEdge(_ x: Double) -> Double { 0.5 * (1 + erf(x / 2.0.squareRoot())) }

    @Test func theCanvasFitsTheShadowAndIsClearAroundIt() throws {
        let bare = Self.window()
        let built = try #require(WindowCaptureShadow.build(bare: bare, scale: 2, shadowed: nil,
                                                           renderer: DocumentRenderer(compositing: .sRGB)))
        let margin = WindowShot.margins(for: WindowShot.shadows(for: nil, pixelScale: 2))
        #expect(built.image.width == 400 + Int(margin.left + margin.right))
        #expect(built.image.height == 300 + Int(margin.top + margin.bottom))
        // Transparent in every corner: a paste lands on the page, not a box.
        let w = built.image.width - 1, h = built.image.height - 1
        for (x, y) in [(0, 0), (w, 0), (0, h), (w, h)] {
            #expect(Self.alpha(built.image, x, y) == 0)
        }
        // Nothing of the shadow reaches the picture's own edge, so none was cut.
        let midX = built.image.width / 2
        #expect(Self.alpha(built.image, midX, h) < 1.0 / 255 + 0.0001)
        #expect(Self.alpha(built.image, 0, built.image.height / 2) < 1.0 / 255 + 0.0001)
        // The window itself comes through untouched.
        #expect(Self.alpha(built.image, Int(margin.left) + 200, Int(margin.top) + 150) == 1)
    }

    @Test func theShadowIsFortyPercentOfMacOSAtThreePointsBelowTheWindow() throws {
        let reading = WindowShot.Reading(look: .active, opacity: 0.684, ringOpacity: 0.95)
        let shape = WindowShot.SystemShadow.active
        // The shot macOS would hand back, at full strength, stands in for the
        // real one: drawn from the same shape at the opacity read off it.
        let built = try #require(WindowCaptureShadow.build(bare: Self.window(), scale: 2,
                                                           reading: reading,
                                                           renderer: DocumentRenderer(compositing: .sRGB)))
        let margin = WindowShot.margins(for: WindowShot.shadows(for: reading, pixelScale: 2))
        let midX = Int(margin.left) + 200
        let sill = Int(margin.top) + 300
        let sigma = Double(shape.blur * 2), reach = Double((shape.spread + shape.offsetY) * 2)
        for t in [8, 40, 80] {
            let macOS = reading.opacity * Self.gaussianEdge((reach - (Double(t) + 0.5)) / sigma)
            let ours = Self.alpha(built.image, midX, sill + t)
            // Two levels of 8 bit alpha either way.
            #expect(abs(ours - macOS * WindowShot.shadowStrength) < 2.5 / 255,
                    "\(t)px below: ours \(ours), macOS \(macOS)")
        }
    }

    @Test func aShotWithMacOSShadowIsReadBackToItsOwnShapeAndOpacity() throws {
        // Draw macOS's active shadow at full strength the way a shot has it,
        // then read it the way a click does.
        let store = ImageStore()
        let ref = store.register(Self.window())
        var document = WindowShot.document(window: ref, pixelScale: 2,
                                           reading: .init(look: .active, opacity: 0.684, ringOpacity: 0.9))
        document.layers[0].style.shadows = document.layers[0].style.shadows.map {
            var full = $0
            full.opacity = min(1, $0.opacity / WindowShot.shadowStrength)
            return full
        }
        let shot = try #require(DocumentRenderer(compositing: .sRGB).render(document, store: store))
        let profiles = try #require(WindowCaptureShadow.edgeProfiles(of: shot))
        let reading = try #require(WindowShot.readSystemShadow(profiles, pixelScale: 2))
        #expect(reading.look == .active)
        #expect(abs(reading.opacity - 0.684) < 0.02)
    }

    /// What macOS hands back for a dark window with its shadow: the window,
    /// with a light two pixel rim drawn over its own edge, inside a dark
    /// margin. `bare` is the same window shot without the shadow, which the
    /// window server draws without the rim.
    static func darkWindowShots() -> (bare: CGImage, shadowed: CGImage) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let bare = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 800,
                             space: space, bitmapInfo: info)!
        bare.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1))
        bare.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                            cornerWidth: 20, cornerHeight: 20, transform: nil))
        bare.fillPath()
        let shot = CGContext(data: nil, width: 260, height: 180, bitsPerComponent: 8, bytesPerRow: 1040,
                             space: space, bitmapInfo: info)!
        shot.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
        shot.fill(CGRect(x: 0, y: 0, width: 260, height: 180))
        // Window at x 30, 50 px from the top (CG y-up: 180 - 50 - 100 = 30).
        let window = CGRect(x: 30, y: 30, width: 200, height: 100)
        shot.setFillColor(CGColor(red: 0.32, green: 0.33, blue: 0.33, alpha: 1))
        shot.fill(window)
        shot.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1))
        shot.fill(window.insetBy(dx: 2, dy: 2))
        return (bare.makeImage()!, shot.makeImage()!)
    }

    @Test func theWindowKeepsTheRimMacOSDrawsOnItsEdge() throws {
        let (bare, shadowed) = Self.darkWindowShots()
        let window = try #require(WindowCaptureShadow.windowPixels(bare: bare, shadowed: shadowed))
        #expect(window.width == 200 && window.height == 100)
        // The rim is there, from the shadowed shot, in the middle of an edge...
        #expect(Self.alpha(window, 0, 50) == 1)
        let rim = KeyedShadowRenderTests.ink(window, at: CGPoint(x: 0, y: 50))
        let inside = KeyedShadowRenderTests.ink(window, at: CGPoint(x: 10, y: 50))
        #expect(rim.r > inside.r + 25, "rim \(rim), inside \(inside)")
        // ...and the rounded corner stays as clear as the bare shot has it:
        // none of macOS's shadow comes along.
        #expect(Self.alpha(window, 0, 0) == 0)
        #expect(Self.alpha(window, 199, 99) == 0)
    }

    @Test func aShadowedShotThatDoesNotHoldTheWindowLeavesTheBareOne() {
        let (bare, _) = Self.darkWindowShots()
        // A shot of some other size: the window cannot be found in it.
        #expect(WindowCaptureShadow.windowPixels(bare: bare, shadowed: Self.window(width: 150, height: 90)) == nil)
    }

    @Test func aWindowShotInDisplayP3StaysInDisplayP3() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8,
                                             bytesPerRow: 480, space: p3,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // A green sRGB cannot hold.
        context.setFillColor(CGColor(colorSpace: p3, components: [0, 1, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let bare = try #require(context.makeImage())
        let built = try #require(WindowCaptureShadow.build(bare: bare, scale: 2, shadowed: nil))
        #expect(built.image.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func aBareShotHasNoShadowToRead() {
        // Nothing past the window's edge at all.
        let profiles = WindowCaptureShadow.edgeProfiles(of: Self.window())
        #expect(profiles.flatMap { WindowShot.readSystemShadow($0, pixelScale: 2) } == nil)
    }
}
