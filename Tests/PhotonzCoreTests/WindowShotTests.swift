import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Window shot (a clicked window keeps its shadow and rounded corners)")
struct WindowShotTests {

    @Test func shadowIsTheDefaultAndOptionFlipsIt() {
        // The built-in macOS window capture: shadow on, Option drops it.
        #expect(WindowShot.style(includeShadow: true, optionHeld: false) == .withShadow)
        #expect(WindowShot.style(includeShadow: true, optionHeld: true) == .bareBounds)
        // With the setting off, Option gives the other choice again.
        #expect(WindowShot.style(includeShadow: false, optionHeld: false) == .bareBounds)
        #expect(WindowShot.style(includeShadow: false, optionHeld: true) == .withShadow)
    }

    @Test func aBareShotMustCoverTheWholeWindow() {
        let window = CGSize(width: 400, height: 300)
        #expect(WindowShot.isFaithful(pixelSize: CGSize(width: 800, height: 600),
                                      windowSize: window, scale: 2, style: .bareBounds))
        // A pixel of rounding either way is still the window.
        #expect(WindowShot.isFaithful(pixelSize: CGSize(width: 799, height: 599),
                                      windowSize: window, scale: 2, style: .bareBounds))
        // Anything visibly smaller means the content was scaled or clipped.
        #expect(!WindowShot.isFaithful(pixelSize: CGSize(width: 790, height: 600),
                                       windowSize: window, scale: 2, style: .bareBounds))
        #expect(!WindowShot.isFaithful(pixelSize: CGSize(width: 800, height: 580),
                                       windowSize: window, scale: 2, style: .bareBounds))
        // Larger is fine: a sheet or popover hanging outside the frame.
        #expect(WindowShot.isFaithful(pixelSize: CGSize(width: 820, height: 640),
                                      windowSize: window, scale: 2, style: .bareBounds))
    }

    @Test func aShadowedShotMustBeLargerThanTheWindow() {
        let window = CGSize(width: 400, height: 300)
        // A shadow adds margin on every side.
        #expect(WindowShot.isFaithful(pixelSize: CGSize(width: 900, height: 700),
                                      windowSize: window, scale: 2, style: .withShadow))
        // Exactly the window's size means the shadow was squeezed into the
        // frame (shrinking the window) or dropped; either way not the shot asked for.
        #expect(!WindowShot.isFaithful(pixelSize: CGSize(width: 800, height: 600),
                                       windowSize: window, scale: 2, style: .withShadow))
        #expect(!WindowShot.isFaithful(pixelSize: CGSize(width: 801, height: 601),
                                       windowSize: window, scale: 2, style: .withShadow))
        #expect(!WindowShot.isFaithful(pixelSize: CGSize(width: 900, height: 600),
                                       windowSize: window, scale: 2, style: .withShadow))
    }

    @Test func emptyOrDegenerateSizesAreNeverFaithful() {
        #expect(!WindowShot.isFaithful(pixelSize: .zero, windowSize: CGSize(width: 400, height: 300),
                                       scale: 2, style: .bareBounds))
        #expect(!WindowShot.isFaithful(pixelSize: CGSize(width: 800, height: 600), windowSize: .zero,
                                       scale: 2, style: .bareBounds))
    }

    @Test func theShadowChoiceLivesOnTheWindowCaptureFlag() {
        let flag = FeatureCatalog.flags(for: .next).first { $0.name == FeatureCatalog.windowCaptureFlag }
        #expect(flag?.boolean(FeatureCatalog.windowCaptureShadow) == true)
        #expect(FeatureCatalog.windowCaptureShadow == "shadow")
    }
}
