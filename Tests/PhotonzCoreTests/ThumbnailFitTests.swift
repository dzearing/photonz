import CoreGraphics
import Testing
@testable import PhotonzCore

@Suite("ThumbnailFit")
struct ThumbnailFitTests {
    /// The history strip: a fixed 100pt row height and as much width as the tile wants.
    private let strip = CGSize(width: CGFloat.infinity, height: 100)

    @Test("A very wide capture is cropped to the ratio cap, keeping the leading edge")
    func wideIsCropped() {
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: 2400, height: 300),
                                   pixelScale: 1, available: strip)
        // 2.5:1 of a 300-tall picture is 750 wide, taken from the leading edge.
        #expect(fit.cropPixels == CGRect(x: 0, y: 0, width: 750, height: 300))
        #expect(fit.drawnSize == CGSize(width: 250, height: 100))
        #expect(fit.croppedEdge == ThumbnailFit.CroppedEdge.trailing)
    }

    @Test("A tiny capture is drawn at its own size, never blown up")
    func tinyIsNotUpscaled() {
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: 60, height: 30),
                                   pixelScale: 1, available: strip)
        #expect(fit.cropPixels == CGRect(x: 0, y: 0, width: 60, height: 30))
        #expect(fit.drawnSize == CGSize(width: 60, height: 30))
        #expect(fit.croppedEdge == nil)
    }

    @Test("A Retina capture's natural size is its POINT size, not its pixel count")
    func retinaNaturalSizeIsPoints() {
        // A 2x capture of a 60x30 point region arrives as a 120x60 bitmap. It is
        // a 60x30 picture, so that is the biggest it may ever be drawn.
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: 120, height: 60),
                                   pixelScale: 2, available: strip)
        #expect(fit.drawnSize == CGSize(width: 60, height: 30))
        #expect(fit.cropPixels == CGRect(x: 0, y: 0, width: 120, height: 60))
    }

    @Test("An ordinary capture is unchanged: scaled down to the row height, no crop")
    func ordinaryIsUnchanged() {
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: 1200, height: 800),
                                   pixelScale: 1, available: strip)
        #expect(fit.cropPixels == CGRect(x: 0, y: 0, width: 1200, height: 800))
        #expect(fit.drawnSize == CGSize(width: 150, height: 100))
        #expect(fit.croppedEdge == nil)
    }

    @Test("A tall narrow capture is cropped from the top to the same ratio cap")
    func tallIsCropped() {
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: 40, height: 600),
                                   pixelScale: 1, available: strip)
        #expect(fit.cropPixels == CGRect(x: 0, y: 0, width: 40, height: 100))
        #expect(fit.drawnSize == CGSize(width: 40, height: 100))
        #expect(fit.croppedEdge == ThumbnailFit.CroppedEdge.bottom)
    }

    @Test("A wide Retina capture crops in pixels and draws in points")
    func wideRetina() {
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: 4800, height: 600),
                                   pixelScale: 2, available: strip)
        #expect(fit.cropPixels == CGRect(x: 0, y: 0, width: 1500, height: 600))
        #expect(fit.drawnSize == CGSize(width: 250, height: 100))
        #expect(fit.croppedEdge == ThumbnailFit.CroppedEdge.trailing)
    }

    @Test("A capture exactly at the cap is not cropped")
    func atTheCap() {
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: 500, height: 200),
                                   pixelScale: 1, available: strip)
        #expect(fit.croppedEdge == nil)
        #expect(fit.drawnSize == CGSize(width: 250, height: 100))
    }

    @Test("A bounded box (the card) fits both ways and still never upscales")
    func boundedBox() {
        let card = CGSize(width: 200, height: 200)
        let big = ThumbnailFit.fit(pixelSize: CGSize(width: 1200, height: 800),
                                   pixelScale: 1, available: card)
        #expect(big.drawnSize.width == 200)
        #expect(abs(big.drawnSize.height - 400.0 / 3) < 0.001)

        let small = ThumbnailFit.fit(pixelSize: CGSize(width: 60, height: 30),
                                     pixelScale: 1, available: card)
        #expect(small.drawnSize == CGSize(width: 60, height: 30))
    }

    @Test("The capture toast's 196x124 box obeys the same two rules")
    func toastBox() {
        let box = CGSize(width: 196, height: 124)
        // The ordinary case must not move: a full-screen 2x capture still fills
        // the box exactly as it did before any of this.
        let ordinary = ThumbnailFit.fit(pixelSize: CGSize(width: 2880, height: 1800),
                                        pixelScale: 2, available: box)
        #expect(ordinary.croppedEdge == nil)
        #expect(abs(ordinary.drawnSize.width - 196) < 0.001)
        #expect(abs(ordinary.drawnSize.height - 122.5) < 0.001)

        // A very wide one is cropped instead of shrinking to a sliver in the box.
        let wide = ThumbnailFit.fit(pixelSize: CGSize(width: 2400, height: 300),
                                    pixelScale: 1, available: box)
        #expect(wide.croppedEdge == ThumbnailFit.CroppedEdge.trailing)
        #expect(abs(wide.drawnSize.width - 196) < 0.001)
        #expect(abs(wide.drawnSize.height - 78.4) < 0.001)

        // A tiny one sits in the box at its own size rather than filling it.
        let tiny = ThumbnailFit.fit(pixelSize: CGSize(width: 60, height: 30),
                                    pixelScale: 1, available: box)
        #expect(tiny.drawnSize == CGSize(width: 60, height: 30))
    }

    @Test("A 3:1 cap crops less than a 2.5:1 one")
    func configurableCap() {
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: 2400, height: 300),
                                   pixelScale: 1, available: strip, maxAspect: 3)
        #expect(fit.cropPixels == CGRect(x: 0, y: 0, width: 900, height: 300))
        #expect(fit.drawnSize == CGSize(width: 300, height: 100))
    }

    @Test("Nonsense input gives an empty fit rather than a crash or a NaN")
    func degenerateInput() {
        for size in [CGSize.zero, CGSize(width: 100, height: 0), CGSize(width: -5, height: 10)] {
            let fit = ThumbnailFit.fit(pixelSize: size, pixelScale: 1, available: strip)
            #expect(fit.drawnSize == .zero)
            #expect(fit.croppedEdge == nil)
        }
        // A bad scale falls back to 1 rather than dividing by zero.
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: 60, height: 30),
                                   pixelScale: 0, available: strip)
        #expect(fit.drawnSize == CGSize(width: 60, height: 30))
    }

    @Test("An unbounded box draws the picture at its natural point size")
    func unboundedBox() {
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: 1200, height: 800), pixelScale: 2,
                                   available: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
        #expect(fit.drawnSize == CGSize(width: 600, height: 400))
    }

    @Test("The crop is whole pixels, so a cropped bitmap is never a fractional rect")
    func cropIsIntegral() {
        let fit = ThumbnailFit.fit(pixelSize: CGSize(width: 1001, height: 101),
                                   pixelScale: 1, available: strip)
        #expect(fit.cropPixels.width == fit.cropPixels.width.rounded())
        #expect(fit.cropPixels.height == fit.cropPixels.height.rounded())
        #expect(fit.cropPixels.width == 253)   // 101 * 2.5 = 252.5, rounded
    }
}
