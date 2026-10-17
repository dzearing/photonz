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
        guard case .measureColor(let first, nil, nil, false) = script.steps[0],
              case .measureColor(let warm, "untouched", 20, false) = script.steps[1],
              case .measureColor(let back, "untouched", nil, true) = script.steps[2] else {
            Issue.record("measureColor steps: \(script.steps)"); return
        }
        #expect(first == "untouched" && warm == "warm" && back == "back")
        #expect(script.steps[0].name == "measureColor")
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("measureColor"))
    }
}
