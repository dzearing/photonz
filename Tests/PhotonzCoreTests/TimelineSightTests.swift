import Foundation
import Testing
@testable import PhotonzCore

/// What the timeline builds views for: the window on screen and a margin each
/// side, so an hour-long edit's 500 clips are not all built on every frame of
/// a zoom or a scroll (`the-timeline-of-an-hour-long-edit-scrolls-zooms`).
@Suite("The timeline builds what is in sight")
struct TimelineSightTests {
    static let hour = 3_600_000

    /// A clip a minute long every minute of the hour.
    static func clips(count: Int = 60) -> [MotionStripGroup] {
        (0..<count).map { index in
            MotionStripGroup(layerID: UUID(), layerName: "Clip \(index)", lanes: [],
                             bar: LayerTime(inMS: index * 60_000, outMS: (index + 1) * 60_000),
                             trackKind: .video, mark: .video)
        }
    }

    static func ruler(startMS: Double, scale: Double) -> MotionStripRuler {
        MotionStripRuler(documentMS: hour, zoom: TimelineZoom(scale: scale, startMS: startMS))
    }

    @Test("The whole edit on screen keeps every clip")
    func fitKeepsAll() {
        let clips = Self.clips()
        let sight = TimelineSight(ruler: MotionStripRuler(documentMS: Self.hour))
        #expect(sight.clips(clips).count == clips.count)
    }

    @Test("Zoomed in, only the clips that reach the window and its margin are kept")
    func zoomedInKeepsWhatIsNear() {
        let clips = Self.clips()
        // Six minutes on screen from 30:00.
        let ruler = Self.ruler(startMS: 1_800_000, scale: 10)
        let sight = TimelineSight(ruler: ruler)
        let kept = sight.clips(clips)
        // Every clip that touches the window itself is there...
        for clip in clips {
            guard let bar = clip.bar else { continue }
            let onScreen = Double(bar.outMS) > ruler.startMS && Double(bar.inMS) < ruler.startMS + ruler.spanMS
            if onScreen { #expect(kept.contains { $0.id == clip.id }, "\(clip.layerName) is on screen") }
        }
        // ...and the far ends of the hour are not.
        #expect(kept.count < 20)
        #expect(!kept.contains { $0.layerName == "Clip 0" })
        #expect(!kept.contains { $0.layerName == "Clip 59" })
    }

    @Test("A clip picked or in a hand is kept wherever it is")
    func keptWherever() {
        let clips = Self.clips()
        let sight = TimelineSight(ruler: Self.ruler(startMS: 1_800_000, scale: 10))
        let far = clips[0].id
        #expect(sight.clips(clips, keeping: [far]).contains { $0.id == far })
    }

    @Test("A clip with no bar is kept")
    func noBarKept() {
        let loose = MotionStripGroup(layerID: UUID(), layerName: "Loose", lanes: [], mark: .text)
        let sight = TimelineSight(ruler: Self.ruler(startMS: 1_800_000, scale: 10))
        #expect(sight.clips([loose]).count == 1)
    }

    @Test("Edit points and gaps are kept by where they are")
    func editPointsAndGaps() {
        let track = UUID()
        let points = (1..<60).map {
            TimelineEditPoint(trackID: track, outgoing: UUID(), incoming: UUID(), atMS: $0 * 60_000)
        }
        let gaps = (0..<60).map { TimelineGap(trackID: track, range: ($0 * 60_000)..<($0 * 60_000 + 1000)) }
        let ruler = Self.ruler(startMS: 1_800_000, scale: 10)
        let sight = TimelineSight(ruler: ruler)
        let keptPoints = sight.editPoints(points)
        #expect(keptPoints.contains { $0.atMS == 1_860_000 })
        #expect(!keptPoints.contains { $0.atMS == 60_000 })
        #expect(keptPoints.count < 20)
        let keptGaps = sight.gaps(gaps)
        #expect(keptGaps.contains { $0.range.lowerBound == 1_860_000 })
        #expect(keptGaps.count < 20)
    }

    @Test("A scroll of a few frames keeps the same sight, so the lists built from it do not change")
    func steadyWhileScrolling() {
        // The window moves a tenth of a second a frame: the sight is snapped
        // to steps of a quarter of the window, so most frames reuse it.
        var changes = 0
        var last = TimelineSight(ruler: Self.ruler(startMS: 1_800_000, scale: 10))
        for step in 1...100 {
            let sight = TimelineSight(ruler: Self.ruler(startMS: 1_800_000 + Double(step) * 100, scale: 10))
            if sight != last { changes += 1 }
            last = sight
        }
        #expect(changes <= 2)
    }

    @Test("The sight always covers the window, however the window is snapped")
    func alwaysCoversTheWindow() {
        for scale in [1.0, 1.5, 3, 10, 37, 120] {
            for start in stride(from: 0.0, through: 3_000_000, by: 77_777) {
                let ruler = Self.ruler(startMS: start, scale: scale)
                let sight = TimelineSight(ruler: ruler)
                #expect(sight.fromMS <= ruler.startMS)
                #expect(sight.toMS >= ruler.startMS + ruler.spanMS)
            }
        }
    }
}
