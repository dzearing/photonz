// A counter for view bodies, so a walk can prove a list builds only the rows
// you can see rather than assert it. Probe-only, like the rest of the harness:
// `PHOTONZ_PLAYTEST` is defined for the dev and probe bundles, so the shipping
// build does not contain this file at all.
#if PHOTONZ_PLAYTEST
import Foundation
import PhotonzCore

/// How many times a view body ran since the last reset.
///
/// This exists because "the layers list builds only the rows you can see" is
/// not something a screenshot can show and not something a timing can prove:
/// once the per-row cost is small, a hundred wasted rows and five useful ones
/// look the same on a stopwatch. Counting the bodies says it outright.
@MainActor
final class ViewBuildMeter {
    static let shared = ViewBuildMeter()

    /// The things worth counting. One case per list that claims to be lazy.
    enum Subject: String, CaseIterable {
        case layersRow
        /// Every time the layers list asks for a picture of a layer. The list
        /// asks only for the rows near the screen, and "near" is not something
        /// a screenshot can show either.
        case layerThumbnail
        /// The whole editor's body: canvas, tool bar, zoom bar, dock, the lot.
        /// Picking a layer must not run this. It used to, and re-measuring
        /// every stack in the window is where the click's 50ms went
        /// (`layer-pick-latency-walk`).
        case editorBody
        /// The dock's body: which sections exist and in what order.
        case inspectorPanel
        /// The layers list's body, which is one step under the dock's.
        case layersList
        /// One colour row of the right hand panel: the chip, the word and the
        /// saved-colours menu beside them. Clicking from one shape to an
        /// identical one must not build a single one of them, and a stopwatch
        /// cannot tell "rebuilt cheaply" from "not rebuilt" once the row is
        /// small (`ColorStyleRow`).
        case colorRow
        /// One clip's bar on the timeline, a caption cue included. A long
        /// talk has 170 of them, so a key that rebuilds every one is a key
        /// that freezes (`a-long-captioned-recording-walk`).
        case clipBar
        /// The Words lane under a Captions track: one body draws every word.
        case wordsLane
        /// One track of the timeline, header and lane.
        case trackRow
        /// The lane of one track on its own, which a scroll along time redraws
        /// while the track's header stands still.
        case trackLane
        /// The timeline dock's grid of tracks, the ruler over them and the
        /// scroller under: a scroll along time must not build it again.
        case timelineGrid
        /// The bodies of the panel's sections, for the claim that a key on
        /// where a layer is builds only the section that shows keys
        /// (`keying-a-value-redraws-only-what-the-key-changes`): Properties
        /// must build, and Text, Appearance, Effects and Time must not.
        case keysSection
        case textSection
        case appearanceSection
        case effectsSection
        case timeSection
        /// One capture tile of the history strip. A filter switch builds the
        /// tiles it brings on screen and no others (`history-filter-switch-speed-walk`).
        case historyTile
        /// The menu bar's commands body (`EditorCommands`). Every pass hands
        /// SwiftUI a whole new set of menus to compare with the bar, so a
        /// video playing must not run it once a frame
        /// (`the-menu-bar-stays-still-while-playing-walk`).
        case menuCommands
        /// What AppKit says happened to the bar (`MenuBarMeter`): a title on
        /// the bar itself, a row in one of its menus, and of those a row
        /// added or taken out rather than changed in place.
        case menuBarTitle
        case menuBarRow
        case menuBarRowAddedOrRemoved
    }

    private var counts: [Subject: Int] = [:]

    /// Called from a view body. Cheap on purpose: a dictionary bump, and only
    /// in a build that carries the harness at all.
    func built(_ subject: Subject) {
        counts[subject, default: 0] += 1
    }

    /// A line per pass, for the subjects where the COUNT is the question and
    /// the answer is "why four". `report` keeps counting; this says what was
    /// different about each one.
    private var trace: [String] = []

    func note(_ line: String) { if trace.count < 12 { trace.append(line) } }

    var traced: String { trace.isEmpty ? "" : "passes: " + trace.joined(separator: " | ") }

    func reset() { counts.removeAll(); trace.removeAll(); ticks.removeAll() }

    /// When the playback clock moved the playhead on, for how evenly a video
    /// plays: the gaps between ticks, which a busy main thread stretches.
    private var ticks: [CFAbsoluteTime] = []

    func playbackTicked() { ticks.append(CFAbsoluteTimeGetCurrent()) }

    /// "playback ticks 300, every 33.4ms on average, 95% within 36.1ms,
    /// longest 41.0ms, 0 late" — late is a gap over twice the frame step.
    var playbackReport: String {
        guard ticks.count > 2 else { return "" }
        let gaps = zip(ticks.dropFirst(), ticks).map { ($0 - $1) * 1000 }.sorted()
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        let p95 = gaps[min(gaps.count - 1, Int(Double(gaps.count) * 0.95))]
        let late = gaps.filter { $0 > Double(MovieRef.frameStepMS) * 2 }.count
        return String(format: "playback ticks %d, every %.1fms on average, 95%% within %.1fms, longest %.1fms, %d late",
                      ticks.count, mean, p95, gaps.last ?? 0, late)
    }

    func count(_ subject: Subject) -> Int { counts[subject] ?? 0 }

    /// "layer rows built 6" — the phrase a walk's log line carries.
    var report: String {
        (playbackReport.isEmpty ? "" : playbackReport + "; ") + countsReport
    }

    private var countsReport: String {
        counts.isEmpty
            ? "no view bodies counted"
            : counts.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue) bodies \($0.value)" }
                .joined(separator: ", ")
    }
}
#endif
