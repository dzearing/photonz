import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A motion set to Forever repeats at its OWN length, not at the lap's.
///
/// The mock (`icon-loop-wt.html`): "with Forever on it, a length becomes a
/// rate", and Over "becomes how long one turn takes". Every other motion in an
/// icon shares one lap as long as the longest of them, and before this a
/// Forever spinner shorter than that lap reached 360 degrees and sat there
/// until the lap came round: an 800 ms spinner beside a 900 ms bell stood still
/// for a tenth of a second every turn, on the canvas and in the file.
@Suite("A Forever motion repeats at its own pace")
struct ForeverMotionPaceTests {

    static func square(_ size: CGFloat = 24) -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: size, y: 0)),
            PathAnchor(point: CGPoint(x: size, y: size)),
            PathAnchor(point: CGPoint(x: 0, y: size))
        ], isClosed: true, paint: Paint(hex: "#112233"), strokeWidth: 2,
           fill: Paint(hex: "#AABBCC"))
    }

    static func layer(_ name: String, _ motions: [LayerMotion]) -> Layer {
        var layer = Layer(name: name, content: .path(square()),
                          frame: CGRect(x: 8, y: 10, width: 24, height: 24))
        layer.motions = motions
        return layer
    }

    /// The bell exactly as Add Rotation makes it: 900 ms, there and back.
    static var bell: LayerMotion {
        LayerMotion.starting(.rotation, on: layer("Bell", []))
    }

    static func spinner(startMS: Int = 0, durationMS: Int = 800) -> LayerMotion {
        LayerMotion(property: .rotation, from: .number(0), to: .number(360),
                    timing: MotionTiming(startMS: startMS, durationMS: durationMS),
                    curve: .linear, repeats: .forever, pivot: .centre)
    }

    static func document(spinner: LayerMotion) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 48, height: 48),
                        layers: [layer("Bell", [bell]), layer("Spinner", [spinner])])
    }

    static func angle(_ motion: LayerMotion, atMS ms: Int, cycleMS: Int) -> Double {
        guard case let .number(degrees) = motion.value(atMS: ms, cycleMS: cycleMS) else { return .nan }
        return degrees
    }

    /// Preview frames, thirty a second, on which the spinner did not move.
    static func stillFrames(_ motion: LayerMotion, cycleMS: Int,
                            fromMS: Int = 0, toMS: Int = 2700) -> [Int] {
        var still: [Int] = []
        var ms = fromMS
        while ms + 33 <= toMS {
            let a = angle(motion, atMS: ms, cycleMS: cycleMS)
            let b = angle(motion, atMS: ms + 33, cycleMS: cycleMS)
            var turned = (b - a).truncatingRemainder(dividingBy: 360)
            if turned < 0 { turned += 360 }
            if turned < 1 { still.append(ms) }
            ms += 33
        }
        return still
    }

    // MARK: - On the canvas

    @Test("The bell sets the lap, and the bell is the default 900 ms swing")
    func theCaseIsTheOneInTheTask() {
        let document = Self.document(spinner: Self.spinner())
        #expect(Self.bell.timing.durationMS == 900)
        #expect(Self.bell.repeats == .foreverThereAndBack)
        #expect(document.motionCycleLengthMS == 900)
    }

    @Test("An 800 ms Forever spinner beside a 900 ms bell never stands still")
    func theSpinnerNeverPauses() {
        let document = Self.document(spinner: Self.spinner())
        let spinner = Self.spinner()
        #expect(Self.stillFrames(spinner, cycleMS: document.motionCycleLengthMS) == [])
    }

    @Test("It turns at its own rate: 850 ms in is 50 ms into its second turn")
    func itTurnsAtItsOwnRate() {
        let cycle = Self.document(spinner: Self.spinner()).motionCycleLengthMS
        #expect(abs(Self.angle(Self.spinner(), atMS: 850, cycleMS: cycle) - 22.5) < 0.01)
        #expect(abs(Self.angle(Self.spinner(), atMS: 1700, cycleMS: cycle) - 45) < 0.01)
    }

    @Test("A late start waits once, then turns without a pause")
    func aLateStartWaitsOnce() {
        let late = Self.spinner(startMS: 100)
        let cycle = Self.document(spinner: late).motionCycleLengthMS
        #expect(Self.angle(late, atMS: 50, cycleMS: cycle) == 0)
        #expect(abs(Self.angle(late, atMS: 950, cycleMS: cycle) - 22.5) < 0.01)
        #expect(Self.stillFrames(late, cycleMS: cycle, fromMS: 100) == [])
    }

    @Test("A Forever motion longer than a written lap is not cut short by it")
    func aLongerSpinnerIsNotCut() {
        let long = Self.spinner(durationMS: 1200)
        #expect(Self.stillFrames(long, cycleMS: 900) == [])
        #expect(abs(Self.angle(long, atMS: 1000, cycleMS: 900) - 300) < 0.01)
    }

    @Test("The bell still swings on the shared lap")
    func theBellIsUnchanged() {
        let bell = Self.bell
        let cycle = 900
        // There and back: out to +12 at the half way mark, home at the lap.
        guard case let .number(half) = bell.value(atMS: 450, cycleMS: cycle),
              case let .number(lap) = bell.value(atMS: 900 + 450, cycleMS: cycle) else {
            Issue.record("not a number")
            return
        }
        #expect(abs(half - 12) < 0.01)
        #expect(abs(lap - 12) < 0.01)
    }

    @Test("A Forever spinner never settles, so the preview keeps running")
    func itNeverSettles() {
        #expect(!Self.spinner().hasSettled(atMS: 100_000, cycleMS: 900))
    }

    // MARK: - In the file

    static func animationLine(_ svg: String, containing needle: String) -> String? {
        svg.split(separator: "\n").map(String.init).first {
            $0.contains("<animateTransform") && $0.contains(needle)
        }
    }

    static func attribute(_ name: String, in line: String) -> String? {
        guard let range = line.range(of: " \(name)=\"") else { return nil }
        let rest = line[range.upperBound...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<close])
    }

    static func file(_ document: PhotonzDocument) -> String {
        SVGExport.write(document, animation: .moving(cycleMS: document.motionCycleLengthMS)).text
    }

    @Test("The file turns the spinner once every 800 ms, with no hold in it")
    func theFileTurnsAtItsOwnRate() throws {
        let svg = Self.file(Self.document(spinner: Self.spinner()))
        let spin = try #require(Self.animationLine(svg, containing: "values=\"0 "))
        #expect(Self.attribute("dur", in: spin) == "800ms")
        #expect(Self.attribute("repeatCount", in: spin) == "indefinite")
        #expect(Self.attribute("keyTimes", in: spin) == "0;1")
        #expect(Self.attribute("values", in: spin) == "0 20 22;360 20 22")
        #expect(Self.attribute("begin", in: spin) == nil)
        // The bell keeps the shared lap.
        let swing = try #require(Self.animationLine(svg, containing: "values=\"-12 "))
        #expect(Self.attribute("dur", in: swing) == "900ms")
    }

    @Test("A late start goes into the file as when it begins, once")
    func theFileWaitsOnceForALateStart() throws {
        let svg = Self.file(Self.document(spinner: Self.spinner(startMS: 100)))
        let spin = try #require(Self.animationLine(svg, containing: "values=\"0 "))
        #expect(Self.attribute("dur", in: spin) == "800ms")
        #expect(Self.attribute("begin", in: spin) == "100ms")
        #expect(Self.attribute("keyTimes", in: spin) == "0;1")
    }

    // MARK: - On the timing strip

    @Test("The strip draws the spinner's later turns, past where the lap restarts")
    func theStripShowsTheTurns() throws {
        let document = Self.document(spinner: Self.spinner())
        let lanes = document.motionStrip().flatMap(\.lanes)
        let spin = try #require(lanes.first { $0.timing.durationMS == 800 })
        #expect(spin.turnMS == 800)
        // The ruler is a lap and a third: 1200 ms.
        #expect(spin.laterTurns(throughMS: 1200) == [MotionTiming(startMS: 800, durationMS: 800)])
        let swing = try #require(lanes.first { $0.timing.durationMS == 900 })
        #expect(swing.turnMS == nil)
        #expect(swing.laterTurns(throughMS: 1200).isEmpty)
    }

    @Test("A late spinner's turns follow on from its own start")
    func lateTurnsFollowTheStart() {
        let lane = MotionStripLane(layerID: UUID(), motionID: UUID(), title: "Rotation",
                                   timing: MotionTiming(startMS: 100, durationMS: 300),
                                   isOn: true, turnMS: 300)
        #expect(lane.laterTurns(throughMS: 1000).map(\.startMS) == [400, 700])
    }

    @Test("A bar dragged shorter draws its turns at the new length")
    func aRetimedBarKeepsTurningAtItsNewLength() {
        let lane = MotionStripLane(layerID: UUID(), motionID: UUID(), title: "Rotation",
                                   timing: MotionTiming(startMS: 0, durationMS: 800),
                                   isOn: true, turnMS: 800)
        let shorter = lane.retimed(to: MotionTiming(startMS: 0, durationMS: 500))
        #expect(shorter.laterTurns(throughMS: 1200).map(\.startMS) == [500, 1000])
    }
}
