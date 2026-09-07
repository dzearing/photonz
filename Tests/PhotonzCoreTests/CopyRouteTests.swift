import Foundation
import Testing
@testable import PhotonzCore

@Suite("Copy route")
struct CopyRouteTests {
    private let layer = UUID()

    // MARK: - Plain copy

    @Test func aPickedLayerWithAMarqueeCopiesThatLayersPixelsInTheMarquee() {
        #expect(CopyRoute.copy(picked: layer, pixelRegion: true, hasDocument: true)
                == .layerRegion(layer))
    }

    @Test func aPickedLayerWithNoMarqueeCopiesTheWholeLayer() {
        #expect(CopyRoute.copy(picked: layer, pixelRegion: false, hasDocument: true)
                == .layer(layer))
    }

    @Test func nothingPickedWithAMarqueeCopiesEveryLayerInTheMarquee() {
        #expect(CopyRoute.copy(picked: nil, pixelRegion: true, hasDocument: true)
                == .mergedRegion)
    }

    @Test func nothingPickedAndNoMarqueeCopiesTheWholeCanvasAsAPastableLayer() {
        #expect(CopyRoute.copy(picked: nil, pixelRegion: false, hasDocument: true)
                == .mergedRegion)
    }

    @Test func noDocumentCopiesNothing() {
        #expect(CopyRoute.copy(picked: layer, pixelRegion: true, hasDocument: false) == .nothing)
        #expect(CopyRoute.copy(picked: nil, pixelRegion: false, hasDocument: false) == .nothing)
    }

    // MARK: - Copy merged

    @Test func copyMergedWithAMarqueeTakesEveryLayerInsideIt() {
        #expect(CopyRoute.copyMerged(pixelRegion: true, hasDocument: true) == .mergedRegion)
    }

    @Test func copyMergedWithNoMarqueeHandsOffTheWholePicture() {
        #expect(CopyRoute.copyMerged(pixelRegion: false, hasDocument: true) == .mergedImage)
    }

    @Test func copyMergedWithNoDocumentCopiesNothing() {
        #expect(CopyRoute.copyMerged(pixelRegion: true, hasDocument: false) == .nothing)
    }

    // MARK: - The two commands differ only where a layer is picked

    @Test func theOnlyDifferenceBetweenTheTwoIsThePickedLayer() {
        // With nothing picked, plain copy and copy merged agree: there is no
        // layer to prefer, so both take everything inside the marquee.
        #expect(CopyRoute.copy(picked: nil, pixelRegion: true, hasDocument: true)
                == CopyRoute.copyMerged(pixelRegion: true, hasDocument: true))
        // With a layer picked they part company, which is the whole point.
        #expect(CopyRoute.copy(picked: layer, pixelRegion: true, hasDocument: true)
                != CopyRoute.copyMerged(pixelRegion: true, hasDocument: true))
    }
}
