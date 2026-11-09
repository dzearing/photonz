import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A picture playing on a zoomed-in canvas is drawn sharp frame by frame: each
/// frame's visible patch goes to a tile scheduler, which draws one at a time
/// and skips straight to the newest frame asked for while it was busy, so a
/// slow tile never builds a queue the playhead has already left behind.
@Suite("Tile scheduler")
struct TileSchedulerTests {

    private actor Collector {
        private(set) var deliveries: [TileScheduler.Delivery] = []
        func add(_ delivery: TileScheduler.Delivery) { deliveries.append(delivery) }
    }

    /// A 24 point icon: one dark stroke across the middle.
    private func icon(turnedBy degrees: CGFloat = 0) -> PhotonzDocument {
        let bar = PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 0)),
                                        PathAnchor(point: CGPoint(x: 16, y: 0))],
                              paint: Paint(hex: "#1C1C1E"), strokeWidth: 2, fill: nil)
        var layer = Layer(name: "Bar", content: .path(bar),
                          frame: CGRect(x: 4, y: 12, width: 16, height: 0))
        layer.transform.rotation = degrees * .pi / 180
        return PhotonzDocument(canvasSize: CGSize(width: 24, height: 24), layers: [layer])
    }

    @Test("One frame asked for is one tile, at the scale it was asked at")
    func oneFrameIsOneTile() async throws {
        let collector = Collector()
        let scheduler = TileScheduler(store: ImageStore()) { await collector.add($0) }
        await scheduler.submit(icon(), region: CGRect(x: 0, y: 0, width: 24, height: 24),
                               scale: 16, magnifyNearest: true, stamp: 7)
        await scheduler.waitUntilIdle()
        let deliveries = await collector.deliveries
        #expect(deliveries.count == 1)
        let tile = try #require(deliveries.first?.tile)
        #expect(tile.image.width == 384)
        #expect(tile.image.height == 384)
        #expect(tile.scale == 16)
        #expect(deliveries.first?.stamp == 7)
    }

    @Test("Frames asked for while one draws are skipped to the newest")
    func latestWins() async throws {
        let collector = Collector()
        let scheduler = TileScheduler(store: ImageStore()) { await collector.add($0) }
        for frame in 0..<30 {
            await scheduler.submit(icon(turnedBy: CGFloat(frame) * 12),
                                   region: CGRect(x: 0, y: 0, width: 24, height: 24),
                                   scale: 16, magnifyNearest: true, stamp: frame)
        }
        await scheduler.waitUntilIdle()
        let stamps = await collector.deliveries.map(\.stamp)
        // The first one starts at once; everything after it that arrived while
        // it drew is overtaken by the last.
        #expect(stamps.count < 30)
        #expect(stamps.last == 29)
        #expect(stamps == stamps.sorted())
    }

    @Test("A frame dropped before it starts is never drawn")
    func dropPending() async throws {
        let collector = Collector()
        let scheduler = TileScheduler(store: ImageStore()) { await collector.add($0) }
        await scheduler.submit(icon(), region: CGRect(x: 0, y: 0, width: 24, height: 24),
                               scale: 16, magnifyNearest: true, stamp: 1)
        await scheduler.submit(icon(turnedBy: 45), region: CGRect(x: 0, y: 0, width: 24, height: 24),
                               scale: 16, magnifyNearest: true, stamp: 2)
        await scheduler.dropPending()
        await scheduler.waitUntilIdle()
        let stamps = await collector.deliveries.map(\.stamp)
        #expect(!stamps.contains(2))
    }

    @Test("A playing frame's tile is sharp where the stretched composite is blocks")
    func playingTileIsSharp() async throws {
        let doc = icon(turnedBy: 30)
        let collector = Collector()
        let scheduler = TileScheduler(store: ImageStore()) { await collector.add($0) }
        await scheduler.submit(doc, region: CGRect(x: 0, y: 0, width: 24, height: 24),
                               scale: 16, magnifyNearest: true, stamp: 0)
        await scheduler.waitUntilIdle()
        let tile = try #require(await collector.deliveries.first?.tile)
        // The composite is 24 pixels across; the canvas blows each up 16 times.
        let composite = try #require(DocumentRenderer().render(doc, store: ImageStore()))
        #expect(composite.width == 24)
        // Grey pixels along a turned stroke: one in sixteen of a stretched
        // composite's are a whole block of grey, while a tile drawn at 16x has
        // its antialiasing a pixel wide.
        #expect(Self.greyShare(tile.image) < Self.greyShare(composite) / 4)
    }

    /// Share of inked pixels that are neither the stroke nor the ground.
    static func greyShare(_ image: CGImage) -> Double {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var inked = 0, grey = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            let l = Int(data[i])
            if l < 250 { inked += 1 }
            if l > 50 && l < 200 { grey += 1 }
        }
        return inked == 0 ? 0 : Double(grey) / Double(inked)
    }
}
