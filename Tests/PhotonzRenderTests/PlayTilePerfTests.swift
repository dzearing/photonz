import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// What a sharp tile of a playing icon costs, frame by frame.
///
/// A picture playing on a zoomed-in canvas gets a tile of what you can see
/// drawn for every frame (`TileScheduler`), where it used to show the
/// composite blown up into blocks. The preview runs at thirty frames a second,
/// so a tile has 33ms, and it shares them with the composite it sits over.
/// Each case is a ten layer icon turning, measured beside the frame ruler.
@Suite("What a playing icon's sharp tile costs", .serialized)
struct PlayTilePerfTests {

    /// Ten stroked and filled paths across a `side` unit icon, turned by
    /// `degrees`, each a little more than the one before, as a playing
    /// picture's moving parts are.
    static func tenLayerIcon(side: CGFloat, canvas: CGSize, at origin: CGPoint,
                             degrees: CGFloat) -> PhotonzDocument {
        let unit = side / 24
        var layers: [Layer] = []
        for index in 0..<10 {
            let i = CGFloat(index)
            let points = [CGPoint(x: 0, y: 0), CGPoint(x: 8 + i, y: 2),
                          CGPoint(x: 12, y: 10 - i * 0.5), CGPoint(x: 3, y: 12)]
            let anchors = points.map { PathAnchor(point: CGPoint(x: $0.x * unit, y: $0.y * unit)) }
            let closed = index % 3 == 0
            let path = PathContent(anchors: anchors, isClosed: closed,
                                   paint: Paint(hex: "#1C1C1E"), strokeWidth: 1.75 * unit,
                                   fill: closed ? Paint(hex: "#0A84FF") : nil)
            var layer = Layer(name: "Part \(index)", content: .path(path),
                              frame: CGRect(x: origin.x + (2 + i) * unit, y: origin.y + (3 + i * 0.6) * unit,
                                            width: (12 + i) * unit, height: 12 * unit))
            layer.transform.rotation = (degrees + i * 9) * .pi / 180
            layers.append(layer)
        }
        return PhotonzDocument(canvasSize: canvas, layers: layers)
    }

    private func measure(_ label: String, side: CGFloat, canvas: CGSize, origin: CGPoint,
                         region: CGRect, scale: CGFloat, nearest: Bool) -> MachineSpeed.Interleaved {
        let store = ImageStore()
        let renderer = MachineSpeed.timedRenderer()
        var frame = 0
        let reading = MachineSpeed.measureInterleaved(yardstick: .frame, rounds: 32) {
            let doc = Self.tenLayerIcon(side: side, canvas: canvas, at: origin, degrees: CGFloat(frame) * 11)
            _ = renderer.renderTile(doc, store: store, region: region, scale: scale, magnifyNearest: nearest)
            frame += 1
        }
        print(String(format: "%@, typical of 32 frames: %.1fms (frame ruler %.1fms)",
                     label, reading.rawMS, reading.yardstickMS))
        return reading
    }

    @Test("A ten layer 24 unit icon at 800% gets a sharp tile per frame well inside a frame")
    func smallIconAt800() {
        let reading = measure("24 unit icon at 800%, 384 pixels square", side: 24,
                              canvas: CGSize(width: 24, height: 24), origin: .zero,
                              region: CGRect(x: 0, y: 0, width: 24, height: 24), scale: 16, nearest: true)
        MachineSpeed.judgeScaled("a ten layer 24 unit icon's tile at 800%", reading,
                                 // 1.8ms alone beside a frame ruler reading 2.1 (2026-11-09).
                                 baselineMS: 1.8, tolerance: 2,
                                 sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath,
                                                                line: #line, column: #column))
    }

    @Test("A ten layer 512 Icon picture at fit zoom gets a sharp tile per frame well inside a frame")
    func bigIconAtFit() {
        let reading = measure("512 Icon at 100% on Retina, 1024 pixels square", side: 512,
                              canvas: CGSize(width: 512, height: 512), origin: .zero,
                              region: CGRect(x: 0, y: 0, width: 512, height: 512), scale: 2, nearest: false)
        MachineSpeed.judgeScaled("a ten layer 512 Icon picture's tile at fit", reading,
                                 // 4.1ms alone beside a frame ruler reading 2.1 (2026-11-09).
                                 baselineMS: 4.1, tolerance: 2,
                                 sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath,
                                                                line: #line, column: #column))
    }

    @Test("A whole window at 800% over a big canvas still tiles inside a frame")
    func wholeWindowAt800() {
        // The icon-on-a-frame walk: a 24 unit frame on a 1600 by 1100 canvas,
        // a 1280 point window at 800% showing 127 by 93 points of it.
        let reading = measure("whole window at 800% over a 1600x1100 canvas, 2030x1493 pixels", side: 24,
                              canvas: CGSize(width: 1600, height: 1100), origin: CGPoint(x: 788, y: 538),
                              region: CGRect(x: 736, y: 503, width: 126.9, height: 93.3), scale: 16,
                              nearest: true)
        MachineSpeed.judgeScaled("a whole window's tile at 800%", reading,
                                 // 3.1ms alone beside a frame ruler reading 2.3 (2026-11-09):
                                 // most of the window is empty canvas.
                                 baselineMS: 3.1, tolerance: 2,
                                 sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath,
                                                                line: #line, column: #column))
    }
}
