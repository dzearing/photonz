import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Frame budgets that used to be judged beside the rest of the suite, against
/// a flat number of milliseconds or a machine factor taken once at process
/// start, and failed there on unchanged code while passing alone
/// (`the-full-test-suite-stays-green-on-a-busy-mac-wh` in the queue): the
/// Width drag on a drawn package read 50 to 82 ms against 48 while costing
/// 5 ms alone, Aurora 36.5 and 38.5 ms against 33, and a live backdrop over
/// its bar once (2026-11-02 to 11-07).
///
/// Each is now read in the same rounds as the 1080p frame ruler
/// (`MachineSpeed.checkFrames`), in the stopwatch run. They share one
/// serialized suite so at most one of them draws at a time: as three suites
/// they took up to all three of the stopwatch run's places at once, and the
/// animated chart's tight budget read 15.4 ms against 14.2 beside two of them
/// (2026-11-09).
@Suite("Drawn pages and drags redraw inside a frame", .serialized)
struct FrameBudgetPerfTests {

    @Test("The shape ring follows a Width drag inside a frame")
    func dragTheWidthInsideAFrame() {
        let store = ImageStore()
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: [])
        let package = ShapeBorderDragCostTests.package()
        doc.addLayer(package)
        // One document per new width, built ahead so only the redraw is timed.
        let widths = (0...24).map { step -> PhotonzDocument in
            var border = BorderEffect(width: CGFloat(1 + step), colorHex: "#000000",
                                      position: .outside)
            border.follows = .shape
            var dragged = package
            dragged.style.effects = [.border(border)]
            var drawn = doc
            drawn.layers[drawn.layers.count - 1] = dragged
            return drawn
        }
        let renderer = DocumentRenderer()
        // Measured 5.0 to 5.2 ms alone on the calibration machine (2026-11-06).
        MachineSpeed.checkFrames("a Width drag redrawing a drawn package's shape ring at 2x",
                                 baselineMS: 5.5, frames: 24) { step in
            _ = renderer.render(widths[step], store: store, scale: 2)
        }
    }

    @Test("Aurora and Behind Glass at 1080p each draw inside a frame")
    func pagesInsideAFrame() throws {
        let store = ImageStore()
        var report: [String] = []
        for preset in [BuiltInTitle.aurora, .glass] {
            var doc = TitleBackgroundsRenderTests.timed(
                [TitleBackgroundsRenderTests.stripes(store: store)], lengthMS: 10_000)
            let landed = doc.insertTitle(preset, atTimeMS: 0)
            _ = try #require(landed)
            let renderer = MachineSpeed.timedRenderer()
            _ = renderer.renderInteractive(doc.drawn(atTimeMS: 1_000), store: store)
            // Built ahead, so only the render is timed.
            let frames = (0...20).map { doc.drawn(atTimeMS: 1_000 + $0 * 16) }
            // Measured alone at 8.9 to 10.4 ms (Aurora) and 4.7 to 5.5 ms
            // (Behind Glass) on 2026-10-10.
            let baseline = preset == .aurora ? 10.0 : 5.5
            let median = MachineSpeed.checkFrames("\(preset.name) title page at 1080p",
                                                  baselineMS: baseline, frames: 20) { frame in
                _ = renderer.renderInteractive(frames[frame], store: store)
            }
            report.append(String(format: "%@: median %.1fms over 20 frames", preset.name, median))
        }
        // The mesh grid on its own, the CPU part of a drifting frame.
        let began = ContinuousClock.now
        for ms in stride(from: 0, to: 20 * 16, by: 16) {
            _ = MeshPainter.image(TitleBackgroundsRenderTests.aurora,
                                  size: TitleBackgroundsRenderTests.canvas, atMS: ms)
        }
        let grid = TitleBackgroundsRenderTests.milliseconds(ContinuousClock.now - began) / 20
        report.append(String(format: "mesh grid alone: %.2fms a frame", grid))
        print("[perf] title backgrounds, 1920x1080:\n  " + report.joined(separator: "\n  "))
    }

    @Test("Every look draws a 1080p frame inside 16 ms at Normal")
    func fastEnough() throws {
        let renderer = MachineSpeed.timedRenderer()
        let store = ImageStore()
        for look in LiveLook.allCases {
            let doc = LiveBackdropRenderTests.document(LiveBackdropRenderTests.paint(look))
            _ = try LiveBackdropRenderTests.frame(doc, atMS: 0, renderer: renderer)
            let frames = (0...6).map { doc.drawn(atTimeMS: ($0 + 1) * 33) }
            // At most 5.4ms on the calibration machine (2026-10-13).
            MachineSpeed.checkFrames("\(look.title) live backdrop at 1080p",
                                     baselineMS: 5.5, frames: 6) { frame in
                _ = renderer.render(frames[frame], store: store)
            }
        }
    }
}
