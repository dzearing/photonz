import CoreGraphics
import PhotonzCore
import Testing

/// The quiet second line on a Library card (`video.html`, `.libtile .mt`):
/// a recording's length, a picture's size, what a component is, and which
/// kind of style a style is. The mock prints "0:06", "2560 × 1440",
/// "3 variants", "paint", "type" and "effect" there.
@Suite("Library tile caption")
struct LibraryTileCaptionTests {
    @Test func aPictureSaysItsSizeInPixels() {
        #expect(LibraryTileCaption.pictureSize(CGSize(width: 2560, height: 1440)) == "2560 × 1440")
        #expect(LibraryTileCaption.pictureSize(CGSize(width: 1279.6, height: 800.2)) == "1280 × 800")
    }

    @Test func eachKindOfStyleSaysWhichKindItIs() {
        #expect(LibraryTileCaption.colorStyle == "paint")
        #expect(LibraryTileCaption.textStyle == "type")
        #expect(LibraryTileCaption.effectStyle == "effect")
    }

    @Test func everyLineFitsTheCardsWidth() {
        // 98 points of caption at 9 point mono is about 18 characters.
        for line in [LibraryTileCaption.pictureSize(CGSize(width: 12000, height: 12000)),
                     LibraryTileCaption.colorStyle, LibraryTileCaption.textStyle,
                     LibraryTileCaption.effectStyle] {
            #expect(line.count <= 18, "\(line)")
        }
    }
}
