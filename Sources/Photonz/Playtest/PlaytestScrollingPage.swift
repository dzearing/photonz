// A screen recording of a page of text scrolling past fast, for the walk that
// checks a busy MP4 lands at the size the Export sheet said
// (`a-busy-recording-says-what-it-weighs-walk`). Probe-only, like the rest of
// the harness.
#if PHOTONZ_PLAYTEST
import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzMedia

/// Six seconds of fine text scrolling up at 900 pixels a second at 1280 by 800:
/// the hardest thing an ordinary screen recording asks of the encoder, and the
/// picture whose MP4 used to land at two and a half times what the sheet
/// quoted. The same picture `VideoExportBudgetTests.scrollingFrames` draws.
/// Written fresh for every walk, which takes a moment.
enum PlaytestScrollingPage {

    static let fileName = "Scrolling Page.mov"
    static let size = CGSize(width: 1280, height: 800)
    static let seconds = 6
    static let pixelsPerSecond = 900.0

    static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photonz/Tutorials", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func fresh() async -> URL? {
        let url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        for leftover in [url, VideoOriginals.url(for: url), VideoEditsSidecar.url(for: url)] {
            try? FileManager.default.removeItem(at: leftover)
        }
        let plan = DocumentVideoExport.plan(durationMS: seconds * 1000, canvasSize: size,
                                            format: .mp4, quality: .high)
        do {
            try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: url,
                                                frames: frames(size: plan.size))
        } catch {
            return nil
        }
        return url
    }

    private static func frames(size: CGSize) -> DocumentMovieWriter.FrameSource {
        let width = Int(size.width), height = Int(size.height)
        let lineHeight = 14.0
        let speed = pixelsPerSecond
        return { ms in
            guard let context = CGContext(data: nil, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)
                                              ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let scrolled = Double(ms) / 1000 * speed
            var line = Int(scrolled / lineHeight)
            while Double(line) * lineHeight - scrolled < Double(height) {
                let y = Double(line) * lineHeight - scrolled
                var x = 8.0, word = 0
                while x < Double(width) - 20 {
                    let wordWidth = Double(12 + (line * 31 + word * 17) % 50)
                    var stroke = x
                    while stroke < x + wordWidth {
                        let w = Double(1 + (line + word + Int(stroke)) % 3)
                        let h = Double(6 + (line * 7 + Int(stroke)) % 5)
                        context.setFillColor(red: Double((line * 13) % 7) / 10, green: 0.1,
                                             blue: Double((word * 5) % 9) / 12, alpha: 1)
                        context.fill(CGRect(x: stroke, y: y + 10 - h, width: w, height: h))
                        stroke += w + 1.5
                    }
                    x += wordWidth + 7
                    word += 1
                }
                line += 1
            }
            return context.makeImage()
        }
    }
}
#endif
