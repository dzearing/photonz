import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// What a walk's `measureColor` step reads off a picture: its mean colour,
/// how warm that is, and whether two pictures are the same pixel for pixel
/// (task `a-clip-can-be-colour-graded-from-add-effect`).
@Suite("Frame colour")
struct FrameColorTests {

    static func picture(_ r: UInt8, _ g: UInt8, _ b: UInt8, width: Int = 40, height: Int = 20,
                        dot: (Int, Int)? = nil) -> CGImage {
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for index in stride(from: 0, to: data.count, by: 4) {
            data[index] = r; data[index + 1] = g; data[index + 2] = b
        }
        if let dot {
            let index = (dot.1 * width + dot.0) * 4
            data[index] = r &+ 1
        }
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    @Test func itReadsTheMeanColourAndItsWarmth() throws {
        let reading = try #require(FrameColor.mean(of: Self.picture(200, 100, 50)))
        #expect(abs(reading.red - 200) < 1.5)
        #expect(abs(reading.green - 100) < 1.5)
        #expect(abs(reading.blue - 50) < 1.5)
        #expect(abs(reading.warmth - 150) < 2)
        #expect(reading.text == "red 200 green 100 blue 50, red over blue 150")
    }

    @Test func twoPicturesAreTheSameOnlyPixelForPixel() {
        let one = Self.picture(10, 20, 30)
        #expect(FrameColor.identical(one, Self.picture(10, 20, 30)))
        #expect(FrameColor.identical(one, Self.picture(10, 20, 30, dot: (3, 4))) == false,
                "one pixel one level apart is a different picture")
        #expect(FrameColor.identical(one, Self.picture(10, 20, 30, width: 41)) == false)
    }

    @Test func aMeasureColorStepSaysWhatItChecks() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "measureColor", "name": "untouched" },
                     { "do": "measureColor", "name": "warm", "against": "untouched", "warmerBy": 20 },
                     { "do": "measureColor", "name": "back", "against": "untouched", "same": true } ] }
        """.utf8))
        guard case .measureColor(let first, nil, nil, false, nil, 0) = script.steps[0],
              case .measureColor(let warm, "untouched", 20, false, nil, 0) = script.steps[1],
              case .measureColor(let back, "untouched", nil, true, nil, 0) = script.steps[2] else {
            Issue.record("measureColor steps: \(script.steps)"); return
        }
        #expect(first == "untouched" && warm == "warm" && back == "back")
        #expect(script.steps[0].name == "measureColor")
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("measureColor"))
    }

    /// Part of the frame, for a grade that is meant to show in one place and
    /// not another: a box given as fractions of the canvas, or the middle of a
    /// named layer's box (task `a-colour-grade-can-be-its-own-track-over-the-cli`).
    @Test func aMeasureColorStepCanReadPartOfTheFrame() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "measureColor", "name": "corner", "region": [0.0, 0.0, 0.1, 0.2] },
                     { "do": "measureColor", "name": "middle", "inside": "Ellipse", "against": "corner", "same": true, "within": 1 } ] }
        """.utf8))
        guard case .measureColor(_, _, _, _, .fraction(let box)?, 0) = script.steps[0],
              case .measureColor(_, "corner", _, true, .inside("Ellipse")?, 1) = script.steps[1] else {
            Issue.record("measureColor steps: \(script.steps)"); return
        }
        #expect(box == CGRect(x: 0, y: 0, width: 0.1, height: 0.2))
        #expect(throws: (any Error).self) {
            try PlaytestScript.decode(Data(#"{ "steps": [ { "do": "measureColor", "name": "x", "region": [0.5, 0.5] } ] }"#.utf8))
        }
    }

    @Test func theLargestDifferenceIsInLevelsOfOneChannel() {
        let one = Self.picture(10, 20, 30)
        #expect(FrameColor.largestDifference(one, Self.picture(10, 20, 30)) == 0)
        #expect(FrameColor.largestDifference(one, Self.picture(10, 20, 30, dot: (3, 4))) == 1)
        #expect(FrameColor.largestDifference(one, Self.picture(10, 20, 30, width: 41)) == nil)
    }

    @Test func aRegionIsCutOutOfThePictureInItsOwnPixels() throws {
        // A 40 by 20 picture: a box of fractions lands on whole pixels of it,
        // top-left origin, and a box off the edge is held to the picture.
        #expect(FrameColorRegion.pixelBox(CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.5),
                                          in: CGSize(width: 40, height: 20))
            == CGRect(x: 20, y: 10, width: 10, height: 10))
        #expect(FrameColorRegion.pixelBox(CGRect(x: 0.9, y: 0, width: 0.5, height: 1),
                                          in: CGSize(width: 40, height: 20))
            == CGRect(x: 36, y: 0, width: 4, height: 20))
        // The middle of a layer's box, in fractions of the canvas: its central
        // half each way, so an ellipse's middle is well inside its curve.
        #expect(FrameColorRegion.middle(of: CGRect(x: 40, y: 20, width: 80, height: 40),
                                        canvas: CGSize(width: 160, height: 80))
            == CGRect(x: 0.375, y: 0.375, width: 0.25, height: 0.25))
    }
}
