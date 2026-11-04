import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// A blank canvas's page is a picture; Ask reads words against its colour.
@Suite("A picture that is one flat colour says which")
struct ImageStoreFlatColourTests {

    static func image(_ paint: (CGContext) -> Void, opaque: Bool = true) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        paint(context)
        return try #require(context.makeImage())
    }

    @Test func aWhitePageIsWhite() throws {
        let page = try Self.image { $0.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 300, height: 200)) }
        let store = ImageStore()
        #expect(store.flatColourHex(for: store.register(page)) == "#FFFFFF")
    }

    @Test func aPictureWithTwoColoursIsNotFlat() throws {
        let page = try Self.image {
            $0.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            $0.setFillColor(red: 0, green: 0, blue: 0, alpha: 1); $0.fill(CGRect(x: 100, y: 50, width: 100, height: 100))
        }
        #expect(ImageStore.flatColourHex(of: page) == nil)
    }

    @Test func aSeeThroughPictureIsNotFlat() throws {
        #expect(ImageStore.flatColourHex(of: try Self.image { _ in }) == nil)
    }

    @Test func aPictureNotInTheStoreIsNotFlat() {
        #expect(ImageStore().flatColourHex(for: ImageRef(pixelSize: CGSize(width: 1, height: 1))) == nil)
    }
}
