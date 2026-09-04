import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Performance baseline for the composite path (CLAUDE.md target: <16ms for a
/// 12-megapixel document with 10 layers). The assertion bound is deliberately
/// loose (CI machines vary); the printed numbers are the real deliverable and
/// get recorded in docs/progress/perf.md.
// Serialized: these 12-megapixel renders are heavy, and letting them run
// concurrently with the rest of the (parallel) render suite thrashes GPU memory
// on constrained machines. Timings are meaningful only when run alone anyway.
@Suite("Render performance", .serialized)
struct RenderPerfTests {

    private func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                                     blue: CGFloat(b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// 12MP canvas (4000x3000) with 10 layers exercising every content type
    /// and the expensive style paths (blur, shadow, corner radius, blends).
    private func makeBenchmarkDocument(store: ImageStore) -> PhotonzDocument {
        let base = store.register(solidImage(width: 4000, height: 3000, r: 200, g: 200, b: 200))
        let photo = store.register(solidImage(width: 1600, height: 1200, r: 80, g: 120, b: 200))
        let patch = store.register(solidImage(width: 800, height: 600, r: 220, g: 90, b: 60))

        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Photo", content: .image(photo),
                           frame: CGRect(x: 200, y: 200, width: 1600, height: 1200),
                           style: LayerStyle(cornerRadius: 48, shadow: ShadowStyle())))
        doc.addLayer(Layer(name: "Rotated", content: .image(patch),
                           frame: CGRect(x: 2200, y: 300, width: 800, height: 600),
                           transform: LayerTransform(rotation: .pi / 8),
                           style: LayerStyle(borderWidth: 8, borderColorHex: "#FFFFFF")))
        doc.addLayer(Layer(name: "Blurred", content: .image(patch),
                           frame: CGRect(x: 400, y: 1700, width: 800, height: 600),
                           style: LayerStyle(blurRadius: 20)))
        doc.addLayer(Layer(name: "Screened", content: .image(patch),
                           frame: CGRect(x: 2600, y: 1700, width: 800, height: 600),
                           style: LayerStyle(blendMode: .screen)))
        doc.addLayer(Layer(name: "Title", content: .text(TextContent(string: "Benchmark Title", fontSize: 120, colorHex: "#111111")),
                           frame: CGRect(x: 300, y: 60, width: 2400, height: 200)))
        doc.addLayer(Layer(name: "Caption", content: .text(TextContent(string: "Caption text for the perf run", fontSize: 64, colorHex: "#333333")),
                           frame: CGRect(x: 300, y: 2700, width: 2400, height: 160)))
        doc.addLayer(Layer(name: "Arrow", content: .annotation(AnnotationContent(shape: .arrow, strokeWidth: 16, colorHex: "#FF3B30", start: CGPoint(x: 200, y: 200), end: CGPoint(x: 1400, y: 1000))),
                           frame: CGRect(x: 0, y: 0, width: 4000, height: 3000)))
        doc.addLayer(Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 12, colorHex: "#34C759", start: CGPoint(x: 2300, y: 400), end: CGPoint(x: 3600, y: 1200))),
                           frame: CGRect(x: 0, y: 0, width: 4000, height: 3000)))
        doc.addLayer(Layer(name: "Highlight", content: .annotation(AnnotationContent(shape: .highlight, strokeWidth: 0, colorHex: "#FFF200", start: CGPoint(x: 300, y: 2650), end: CGPoint(x: 2800, y: 2900))),
                           frame: CGRect(x: 0, y: 0, width: 4000, height: 3000)))
        return doc
    }

    @Test func renders12MPTenLayerDocumentWithinBudget() {
        let store = ImageStore()
        let doc = makeBenchmarkDocument(store: store)
        #expect(doc.layers.count == 10)
        let renderer = DocumentRenderer()

        // Warm up: first render pays one-time filter/pipeline compilation.
        #expect(renderer.render(doc, store: store) != nil)

        var samples: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<10 {
            let duration = clock.measure {
                _ = renderer.render(doc, store: store)
            }
            samples.append(Double(duration.components.seconds) * 1000
                           + Double(duration.components.attoseconds) / 1e15)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        print("[perf] 12MP/10-layer render — median \(String(format: "%.1f", median))ms, " +
              "min \(String(format: "%.1f", samples[0]))ms, " +
              "max \(String(format: "%.1f", samples[samples.count - 1]))ms over \(samples.count) runs")

        // Loose regression guard; the 16ms product target is tracked in docs/progress/perf.md.
        // Shared CI runners jitter above the local bound (observed 260ms on a run whose
        // identical code passed the next run) — give them extra headroom.
        let bound: Double = ProcessInfo.processInfo.environment["CI"] != nil ? 350 : 250
        #expect(median < bound, "median render time regressed badly: \(median)ms")
    }

    /// The same 12MP document with five of its layers wrapped in one styled
    /// group. A styled group composites its children into a private buffer
    /// before the group's own shadow and fade apply, which is the expensive
    /// group path — the plain-group path costs nothing at all.
    @Test func renders12MPDocumentWithAGroupOfFiveWithinBudget() {
        let store = ImageStore()
        var doc = makeBenchmarkDocument(store: store)
        let members = Set(doc.layers[1...5].map(\.id))
        let group = doc.groupLayers(ids: members, name: "Card")
        #expect(group != nil)
        guard let group else { return }
        doc.updateLayer(id: group.id) {
            $0.style = LayerStyle(opacity: 0.9, shadow: ShadowStyle(radius: 24, offset: CGSize(width: 0, height: 12)))
        }
        #expect(doc.allLayers.count == 11, "ten original layers plus the group that holds five of them")
        let renderer = DocumentRenderer()
        #expect(renderer.render(doc, store: store) != nil)

        var samples: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<10 {
            let duration = clock.measure {
                _ = renderer.render(doc, store: store)
            }
            samples.append(Double(duration.components.seconds) * 1000
                           + Double(duration.components.attoseconds) / 1e15)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        print("[perf] 12MP/10-layer render, five of them in one styled group — " +
              "median \(String(format: "%.1f", median))ms, " +
              "min \(String(format: "%.1f", samples[0]))ms, " +
              "max \(String(format: "%.1f", samples[samples.count - 1]))ms over \(samples.count) runs")

        let bound: Double = ProcessInfo.processInfo.environment["CI"] != nil ? 350 : 250
        #expect(median < bound, "grouped render time regressed badly: \(median)ms")
    }

    /// The 16ms budget, on the path the budget is about, with a group in the
    /// document: dragging a layer that lives INSIDE a group of five. A plain
    /// group draws its children straight onto the canvas, so only the dragged
    /// layer repaints; a styled group is one object, so the whole group does.
    @Test func interactiveEditInsideAGroupMeetsBudget() {
        func median(groupStyle: LayerStyle, label: String) -> Double {
            let store = ImageStore()
            var doc = makeBenchmarkDocument(store: store)
            let members = Set(doc.layers[1...5].map(\.id))
            guard let group = doc.groupLayers(ids: members, name: "Card") else {
                Issue.record("grouping five layers should succeed")
                return .infinity
            }
            doc.updateLayer(id: group.id) { $0.style = groupStyle }
            let renderer = DocumentRenderer()
            #expect(renderer.renderInteractive(doc, store: store) != nil)

            // The rotated patch, now a child of the group. Its frame is stored
            // against the group, so nudging it moves it inside the group.
            let dragged = doc.layer(id: group.id)!.children[1].id
            let start = doc.layer(id: dragged)!.frame
            var samples: [Double] = []
            let clock = ContinuousClock()
            for step in 1...10 {
                doc.updateLayer(id: dragged) {
                    $0.frame = start.offsetBy(dx: CGFloat(step) * 8, dy: CGFloat(step) * 6)
                }
                let duration = clock.measure {
                    #expect(renderer.renderInteractive(doc, store: store) != nil)
                }
                samples.append(Double(duration.components.seconds) * 1000
                               + Double(duration.components.attoseconds) / 1e15)
            }
            samples.sort()
            let median = samples[samples.count / 2]
            print("[perf] 12MP/10-layer interactive edit inside \(label) — " +
                  "median \(String(format: "%.1f", median))ms, " +
                  "min \(String(format: "%.1f", samples[0]))ms, " +
                  "max \(String(format: "%.1f", samples[samples.count - 1]))ms over \(samples.count) runs")
            return median
        }

        let plain = median(groupStyle: LayerStyle(), label: "a plain group of five")
        let styled = median(groupStyle: LayerStyle(opacity: 0.9,
                                                   shadow: ShadowStyle(radius: 24, offset: CGSize(width: 0, height: 12))),
                            label: "a styled group of five")
        // A plain group costs what the same layers cost loose.
        #expect(plain < 100, "interactive re-render inside a plain group regressed badly: \(plain)ms")
        #expect(styled < 200, "interactive re-render inside a styled group regressed badly: \(styled)ms")
    }

    /// Zoomed in, the canvas asks for a crisp tile of just the part of the
    /// document it can see, at the resolution it is about to show it at. That
    /// keeps the cost tied to the size of the WINDOW rather than the size of
    /// the picture: the same 12-megapixel document costs the same whether you
    /// are at 200% or 800%, because you can see proportionally less of it.
    @Test func crispTileWhileZoomedInMeetsBudget() {
        let store = ImageStore()
        let doc = makeBenchmarkDocument(store: store)
        let renderer = DocumentRenderer()

        /// A 1600x1000-point editor window on a 2x display, at `zoom`.
        func median(zoom: CGFloat) -> Double {
            let scale = zoom * 2
            let region = CGRect(x: 1200, y: 900,
                                width: 1600 / zoom, height: 1000 / zoom)
            #expect(renderer.renderTile(doc, store: store, region: region, scale: scale,
                                        magnifyNearest: zoom >= 2) != nil)
            var samples: [Double] = []
            let clock = ContinuousClock()
            for step in 0..<10 {
                // Panning a little, so no frame is served straight from a cache
                // that the real thing would also be missing.
                let moved = region.offsetBy(dx: CGFloat(step), dy: CGFloat(step))
                let duration = clock.measure {
                    #expect(renderer.renderTile(doc, store: store, region: moved, scale: scale,
                                                magnifyNearest: zoom >= 2) != nil)
                }
                samples.append(Double(duration.components.seconds) * 1000
                               + Double(duration.components.attoseconds) / 1e15)
            }
            samples.sort()
            let median = samples[samples.count / 2]
            print("[perf] 12MP/10-layer crisp tile at \(Int(zoom * 100))% zoom — " +
                  "median \(String(format: "%.1f", median))ms, " +
                  "min \(String(format: "%.1f", samples[0]))ms, " +
                  "max \(String(format: "%.1f", samples[samples.count - 1]))ms over \(samples.count) runs")
            return median
        }

        let at200 = median(zoom: 2)
        let at400 = median(zoom: 4)
        let at800 = median(zoom: 8)
        // Loose CI bound; the real numbers land in docs/progress/perf.md. What
        // matters is that zooming further in does not cost more.
        #expect(at200 < 100, "crisp tile at 200% regressed badly: \(at200)ms")
        #expect(at400 < 100, "crisp tile at 400% regressed badly: \(at400)ms")
        #expect(at800 < 100, "crisp tile at 800% regressed badly: \(at800)ms")
    }

    /// The benchmark document's shapes span the whole canvas, so they are the
    /// case that CANNOT be crisped. A real redline is the opposite: a capture
    /// with a dozen calipers and captioned arrows the size of what they point
    /// at, every one of them now baked at the zoom's resolution. That is where
    /// crisping actually costs something, so that is where it gets a budget.
    @Test func crispTileOnARedlinedCaptureMeetsBudget() {
        let store = ImageStore()
        let capture = store.register(solidImage(width: 4000, height: 3000, r: 240, g: 240, b: 245))
        var doc = PhotonzDocument.withBaseImage(capture)
        for i in 0..<6 {
            let x = CGFloat(300 + i * 560), y = CGFloat(700)
            let measure = MeasureContent(start: .zero, end: CGPoint(x: 220, y: 0), mode: .horizontal)
            doc.addLayer(MeasureBuilder.layer(content: measure,
                                              from: CGPoint(x: x, y: y),
                                              to: CGPoint(x: x + 220, y: y)))
            var arrow = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
            arrow.caption = "Gap \(i * 4 + 8)"
            doc.addLayer(AnnotationBuilder.layer(content: arrow,
                                                 from: CGPoint(x: x + 260, y: y + 400),
                                                 to: CGPoint(x: x + 40, y: y + 120)))
        }
        let renderer = DocumentRenderer()

        // A 1600x1000-point window on a 2x display at 400%.
        let region = CGRect(x: 200, y: 500, width: 400, height: 250)
        #expect(renderer.renderTile(doc, store: store, region: region, scale: 8) != nil)
        var samples: [Double] = []
        let clock = ContinuousClock()
        for step in 0..<10 {
            let moved = region.offsetBy(dx: CGFloat(step), dy: CGFloat(step))
            let duration = clock.measure {
                #expect(renderer.renderTile(doc, store: store, region: moved, scale: 8) != nil)
            }
            samples.append(Double(duration.components.seconds) * 1000
                           + Double(duration.components.attoseconds) / 1e15)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        print("[perf] 12MP capture with 12 redline marks, crisp tile at 400% zoom — " +
              "median \(String(format: "%.1f", median))ms, " +
              "min \(String(format: "%.1f", samples[0]))ms, " +
              "max \(String(format: "%.1f", samples[samples.count - 1]))ms over \(samples.count) runs")
        #expect(median < 100, "crisp tile over a redlined capture regressed badly: \(median)ms")
    }

    /// The 16ms budget applies to *re-renders during editing* — that's what
    /// the user feels on every drag tick and slider tweak. The interactive
    /// path patches dirty regions, so measure it the way the app uses it:
    /// an edit followed by a re-render, repeatedly.
    @Test func interactiveEditReRenderMeetsBudget() {
        let store = ImageStore()
        var doc = makeBenchmarkDocument(store: store)
        let renderer = DocumentRenderer()

        // First interactive render fills the accumulation buffer.
        #expect(renderer.renderInteractive(doc, store: store) != nil)

        // Drag the rotated 800×600 patch — a typical mid-size edit.
        let dragged = doc.layers[2].id
        var samples: [Double] = []
        let clock = ContinuousClock()
        for step in 1...10 {
            doc.updateLayer(id: dragged) {
                $0.frame = CGRect(x: 2200 + step * 8, y: 300 + step * 6, width: 800, height: 600)
            }
            let duration = clock.measure {
                #expect(renderer.renderInteractive(doc, store: store) != nil)
            }
            samples.append(Double(duration.components.seconds) * 1000
                           + Double(duration.components.attoseconds) / 1e15)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        print("[perf] 12MP/10-layer interactive edit — median \(String(format: "%.1f", median))ms, " +
              "min \(String(format: "%.1f", samples[0]))ms, " +
              "max \(String(format: "%.1f", samples[samples.count - 1]))ms over \(samples.count) runs")

        // Loose CI bound; the real numbers land in docs/progress/perf.md.
        #expect(median < 100, "interactive re-render regressed badly: \(median)ms")
    }
}
