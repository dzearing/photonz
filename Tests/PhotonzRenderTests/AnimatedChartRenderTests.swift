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
        if kind == .comparison {
            // A comparison's build is its numbers counting: its faint cards
            // only fade up (task `a-chart-is-your-data-given-to-it-the-
            // obvious-way`: nothing moves that is not data), so most of its
            // ink is there early and its last number is not.
            let spec = try #require(doc.chartSpec(layerID: id))
            let last = spec.rows.count
            let shown = doc.drawn(atTimeMS: arrived / 2).layer(id: id)
                .flatMap { TitleDesign.find("Number \(last)", in: $0) }
            let reading = shown?.style.opacity == 0 ? 0
                : (shown?.text?.string).flatMap(CountedNumber.init(parsing:))?.value ?? 0
            #expect(reading < spec.rows[last - 1].value * 0.7, "Comparison's last number has already counted")
            return
        }
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
}

/// The animated charts' frame budget. Serialized and named ...PerfTests, so
/// `Scripts/test.sh` holds it until every other test has finished.
@Suite("Animated charts draw inside a frame", .serialized)
struct AnimatedChartPerfTests {

    /// Every chart at 1080p through the canvas's own render, over twenty
    /// frames of its build, the numbers counting, each frame beside the 1080p
    /// frame yardstick taken in the same round. Printed for the perf note.
    ///
    /// It was a stopwatch against a bound scaled once, when the process
    /// started, by the filter graph: that factor read 1.08x to 3.76x across
    /// five full runs on one Mac, and the worst chart read 19 to 72 ms, so the
    /// gate failed on unchanged code in releases v0.20.0 and v0.21.0 and
    /// passed alone at a fifth of its bound. Beside a ruler drawn in the same
    /// round, the machine's mood divides out.
    @Test("Every chart at 1080p draws inside a frame while it builds")
    func insideAFrame() throws {
        let store = ImageStore()
        var report: [String] = []
        var dearest: (kind: ChartKind, reading: MachineSpeed.Interleaved)?
        for kind in ChartKind.allCases {
            let (doc, _) = try AnimatedChartRenderTests.placed(kind)
            let renderer = MachineSpeed.timedRenderer()
            // Warmed up the way playback is: the moving background's kernels
            // compile on a fresh context's first frames.
            for ms in stride(from: 200, to: 600, by: 50) { _ = renderer.renderInteractive(doc.drawn(atTimeMS: ms), store: store) }
            let reading = MachineSpeed.measureFrames(frames: 20) { frame in
                _ = renderer.renderInteractive(doc.drawn(atTimeMS: 616 + frame * 50), store: store)
            }
            if reading.rawMS > (dearest?.reading.rawMS ?? -1) { dearest = (kind, reading) }
            report.append(String(format: "%@: median %.1fms here, %.1fms on the calibration machine's clock",
                                 kind.name, reading.rawMS, reading.normalizedMS))
        }
        print("[perf] animated charts building, 1920x1080:\n  " + report.joined(separator: "\n  "))
        let worst = try #require(dearest)
        // The dearest chart alone on the calibration machine: 8.8 to 9.3 ms
        // beside a frame ruler reading 2.0 against its own 3.3, and 9.1 to
        // 10.5 in the stopwatch run (2026-10-30). Twice the drawing read 19.4
        // and fails 1.5 times that. Judged on its own clock, the yardstick
        // only loosening the bound when it reads slow: divided by it, the
        // same doubling read 25.4 against 24, by a hair.
        MachineSpeed.judgeScaled("the dearest animated chart (\(worst.kind.name)) at 1080p", worst.reading,
                                 baselineMS: 9.5, tolerance: 1.5,
                                 sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath,
                                                                line: #line, column: #column))
    }
}
