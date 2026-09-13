import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
@testable import PhotonzRender
import Testing

/// A bench, not a test: runs Separate into Layers over whatever pictures you
/// point it at and prints what came out, what was left behind, how deep and how
/// wide the tree got, and how long it took.
///
/// It exists because the only way to know whether this feature feels
/// intelligent is to run it on real captures — a settings pane, a toolbar, a
/// dialog, a list of rows, a dense web page, a photograph — and every one of
/// those lives outside the repo. So it is off unless you name the files:
///
/// ```
/// PHOTONZ_SEPARATE_BENCH="$HOME/Pictures/Screenshots/a.png,/tmp/b.png" \
///   Scripts/test.sh -c release --filter SeparateBench 2>&1 | grep BENCH
/// ```
///
/// It reads each file the way the app opens it, DPI and all, so the gap and the
/// minimum element are the numbers a real document would use.
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("Separate into Layers bench")
struct SeparateBenchTests {

    private static var files: [URL] {
        let list = ProcessInfo.processInfo.environment["PHOTONZ_SEPARATE_BENCH"] ?? ""
        return list.split(separator: ",").map {
            URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces))
        }
    }

    /// The picture, and the backing scale its DPI implies, exactly as
    /// `EditorState.openImage` reads them.
    private func load(_ url: URL) -> (image: CGImage, scale: CGFloat)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = props?[kCGImagePropertyDPIWidth] as? Double
        return (image, dpi.map { DisplayScale.pixelScale(forDPI: $0) } ?? 1)
    }

    private func widest(_ nodes: [LayerNesting.Node]) -> Int {
        max(nodes.count, nodes.map { widest($0.children) }.max() ?? 0)
    }

    @Test(.enabled(if: !SeparateBenchTests.files.isEmpty))
    func whatItDoesToRealScreenshots() throws {
        for url in Self.files {
            guard let (image, scale) = load(url) else {
                print("BENCH \(url.lastPathComponent): could not be read")
                continue
            }
            let gap = Double(AlignmentScan.visibleGap * max(1, scale))
            let minElement = Double(max(10, 10 * scale))
            let megapixels = Double(image.width * image.height) / 1_000_000

            var started = Date()
            let analysis = EdgeMapAnalyzer.analyzeFully(image)
            let reading = Date().timeIntervalSince(started)

            started = Date()
            let result = LayerSeparator.separate(image, luma: analysis.luma, gap: gap,
                                                 minElement: minElement)
            let whole = Date().timeIntervalSince(started)

            guard let result else {
                print("BENCH \(url.lastPathComponent): unreadable")
                continue
            }
            let nested = result.nested
            print(String(
                format: "BENCH %@ | %d x %d (%.1f MP) at %.0fx | %d runs, %d boxes, "
                    + "%d left (%d unclear, %d crowded out) | %d top rows, %d deep, "
                    + "%d widest | reading %.0f ms, separating %.0f ms (%.0f ms/MP)",
                url.lastPathComponent, image.width, image.height, megapixels, scale,
                result.runs.count, result.boxes.count, result.left,
                result.skipped, result.crowded,
                nested.count, LayerNesting.depth(of: nested), widest(nested),
                reading * 1000, whole * 1000, whole * 1000 / max(megapixels, 0.001)))

            // The other half of the promise: what was left in the picture is
            // still IN the picture, so running the command again reaches it.
            guard result.crowded > 0 else { continue }
            let again = EdgeMapAnalyzer.analyzeFully(result.background)
            guard let second = LayerSeparator.separate(result.background, luma: again.luma,
                                                       gap: gap, minElement: minElement)
            else { continue }
            print(String(format: "BENCH   run again | %d runs, %d boxes, %d left "
                         + "(%d unclear, %d crowded out)",
                         second.runs.count, second.boxes.count, second.left,
                         second.skipped, second.crowded))
        }
    }
}
