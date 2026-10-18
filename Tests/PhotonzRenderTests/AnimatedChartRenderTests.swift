import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Animated charts, drawn by the real renderer (task
/// `animated-charts-you-can-drop-into-a-video`).
///
/// The visual bar the task sets: a chart has to visibly BUILD. Its ink (every
/// pixel its data puts on the picture, measured against the same moment drawn
/// with its background alone) is under a tenth of its held ink at its first
/// frame, and part way up, not all there, half way through its in. And at 1080p
/// a frame of it, counting numbers and all, draws inside the frame budget.
@Suite("Animated charts drawn")
struct AnimatedChartRenderTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func placed(_ kind: ChartKind) throws -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#20242E")),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 8_000, sourceInMS: 0, sourceLengthMS: 8_000)
        doc.layers = [clip]
        doc.durationMS = 8_000
        let landed = doc.insertTitle(chart: kind, atTimeMS: 0)
        let inserted = try #require(landed)
        return (doc, inserted.layerID)
    }

    /// The document at `ms` with everything of the chart but its background
    /// hidden: what its ink is measured against.
    static func backgroundOnly(_ doc: PhotonzDocument, _ id: UUID, atMS ms: Int) -> PhotonzDocument {
        var shown = doc.drawn(atTimeMS: ms)
        shown.updateLayer(id: id) { title in
            title.children = title.children.map { piece in
                var piece = piece
                if piece.name != "Background" { piece.isVisible = false }
                return piece
            }
        }
        return shown
    }

    /// How many pixels the chart's data changes at `ms`, out of the picture.
    static func ink(_ doc: PhotonzDocument, _ id: UUID, atMS ms: Int, store: ImageStore,
                    renderer: DocumentRenderer) throws -> Int {
        let full = try #require(renderer.render(doc.drawn(atTimeMS: ms), store: store, scale: 0.25))
        let bare = try #require(renderer.render(backgroundOnly(doc, id, atMS: ms), store: store, scale: 0.25))
        let a = TitleBackgroundsRenderTests.bytes(full), b = TitleBackgroundsRenderTests.bytes(bare)
        var count = 0
        for index in stride(from: 0, to: min(a.count, b.count), by: 4) {
            let diff = abs(Int(a[index]) - Int(b[index])) + abs(Int(a[index + 1]) - Int(b[index + 1]))
                + abs(Int(a[index + 2]) - Int(b[index + 2]))
            if diff > 48 { count += 1 }
        }
        return count
    }

    @Test("Every chart builds: under a tenth of its ink at its first frame, part way half way in",
          arguments: ChartKind.allCases)
    func builds(_ kind: ChartKind) throws {
        let (doc, id) = try Self.placed(kind)
        let store = ImageStore()
        let renderer = DocumentRenderer()
        let arrived = doc.titleArrivalMS(layerID: id)
        let held = try Self.ink(doc, id, atMS: arrived + 200, store: store, renderer: renderer)
        let first = try Self.ink(doc, id, atMS: 0, store: store, renderer: renderer)
        let midway = try Self.ink(doc, id, atMS: arrived / 2, store: store, renderer: renderer)
        print("[chart ink] \(kind.name): first \(first), half way \(midway), held \(held) (arrived at \(arrived) ms)")
        #expect(held > 500, "\(kind.name) puts almost nothing on the picture")
        #expect(Double(first) < Double(held) * 0.1, "\(kind.name) is already there at its first frame")
        #expect(Double(midway) > Double(held) * 0.05, "\(kind.name) has not started half way through its in")
        guard kind == .bigNumber else {
            #expect(Double(midway) < Double(held) * 0.95, "\(kind.name) has fully arrived half way through its in")
            return
        }
        // A big number's build is its count: its ink is all there early, its
        // value is not. A third of the way into the count it reads well
        // under its value.
        let spec = try #require(doc.chartSpec(layerID: id))
        let early = doc.drawn(atTimeMS: 200 + 1_500 / 3).layer(id: id)
            .flatMap { TitleDesign.find("Number", in: $0) }?.text?.string
        let reading = try #require(early.flatMap(CountedNumber.init(parsing:))?.value)
        print("[chart ink] Big Number reads \(reading) of \(spec.rows[0].value) a third of the way into its count")
        #expect(reading < spec.rows[0].value * 0.7)
    }

    @Test("Playback and export draw a building bar chart the same")
    func playbackMatchesExport() throws {
        let (doc, _) = try Self.placed(.bar)
        let store = ImageStore()
        let playback = DocumentRenderer()
        var played: [Int: [UInt8]] = [:]
        let moments = [600, 1_100, 2_400]
        for ms in stride(from: 0, through: 2_400, by: 50) {
            let image = try #require(playback.render(doc.drawn(atTimeMS: ms), store: store, scale: 0.5))
            if moments.contains(ms) { played[ms] = TitleBackgroundsRenderTests.bytes(image) }
        }
        for ms in moments {
            let exported = try #require(DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: store, scale: 0.5))
            #expect(played[ms] == TitleBackgroundsRenderTests.bytes(exported), "differs at \(ms)")
        }
    }

    /// Every chart at 1080p through the canvas's own render, over twenty
    /// frames of its build, the numbers counting. Printed for the perf note.
    @Test("Every chart at 1080p draws inside a frame while it builds")
    func insideAFrame() throws {
        let store = ImageStore()
        var report: [String] = []
        var worstMedian = 0.0
        for kind in ChartKind.allCases {
            let (doc, _) = try Self.placed(kind)
            let renderer = DocumentRenderer(privateContext: CIContext(options: [.cacheIntermediates: true]))
            // Warmed up the way playback is: the moving background's kernels
            // compile on a fresh context's first frames.
            for ms in stride(from: 200, to: 600, by: 50) { _ = renderer.renderInteractive(doc.drawn(atTimeMS: ms), store: store) }
            var samples: [Double] = []
            for ms in stride(from: 616, to: 616 + 20 * 50, by: 50) {
                let shown = doc.drawn(atTimeMS: ms)
                let began = ContinuousClock.now
                _ = renderer.renderInteractive(shown, store: store)
                samples.append(TitleBackgroundsRenderTests.milliseconds(ContinuousClock.now - began))
            }
            let median = samples.sorted()[samples.count / 2]
            worstMedian = max(worstMedian, median)
            report.append(String(format: "%@: median %.1fms, worst %.1fms over %d frames",
                                 kind.name, median, samples.max() ?? 0, samples.count))
        }
        print("[perf] animated charts building, 1920x1080:\n  " + report.joined(separator: "\n  "))
        let factor = MachineSpeed.factor(.filterGraph)
        if MachineSpeed.isGating {
            // Measured alone at 5.1 to 10.3 ms a chart on 2026-10-17 (the donut
            // the dearest); the gate is the shared one, scaled by this machine.
            #expect(worstMedian < MachineSpeed.budget(baselineMS: 10.5, factor: factor), "worst median \(worstMedian)ms")
        }
    }
}
