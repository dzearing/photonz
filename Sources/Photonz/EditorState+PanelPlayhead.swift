import Foundation
import Observation

// MARK: What the panel knows about the playhead
//
// The panel's Time section (Speed, the speed stops, a held frame, the fades)
// and the facts that decide whether the panel shows a cut talk about "the clip
// picked, else the one under the playhead" (`clipInHandID`), its piece, its
// cut and its speed stop. Read as they were, the playhead moving on re-ran
// them thirty times a second while a video played, rows, menus and all.
//
// And a pass of SwiftUI's is not paid for by the views it re-runs alone. On
// the 6 minute reference edit, every pass cost about as much again as the
// number of views in the timeline's tracks, whatever started it: playing a
// minute with the panel hidden showed 575 of 606 frames against 500 with it,
// and with the tracks hidden 605 (2026-11-13,
// `a-long-edit-with-transitions-plays-scrubs-and-ed`). So a view that does
// not need the playhead on every frame must not be woken by it.
//
// So, as the menu bar does (`MenuPlayhead`): inside `readingThePlayheadForThePanel`
// reading the playhead is not watched, and what is watched instead is
// `panelPlayhead`, the answers that depend on it, worked out again whenever
// anything they read changes and written only when one of them is different.
// The clock moving on inside one piece writes nothing; crossing into the next
// clip, piece, cut or stop re-runs the section, which then reads the live
// playhead for every row.
//
// The rule for using it: only round a view that shows nothing that moves
// with the playhead inside a piece. Anything that does (a timecode, a keyed
// value at the playhead) reads the playhead as usual.

/// The playhead-dependent answers the panel's Time section shows, as one value
/// that is equal for as long as none of them changes.
struct PanelPlayhead: Equatable {
    var clipInHand: UUID?
    var pieceInHand: Int?
    var cutInHand: Int?
    var speedStopInHand: Int?
}

extension EditorState {
    /// True while a panel view reads the playhead through `panelPlayhead`:
    /// reading `documentTimeMS` then is not watched.
    @MainActor static var readingForThePanel = false

    /// Builds what `build` builds with the playhead read unwatched, and
    /// `panelPlayhead` watched in its place (see the top of this file).
    func readingThePlayheadForThePanel<T>(_ build: () -> T) -> T {
        _ = panelPlayhead
        if !watchesPanelPlayhead {
            // Never written while a body is being built: the first answers
            // land on the next turn of the run loop.
            watchesPanelPlayhead = true
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.watchPanelPlayhead() } }
        }
        let was = Self.readingForThePanel
        Self.readingForThePanel = true
        defer { Self.readingForThePanel = was }
        return build()
    }

    /// Works the answers out, watching everything they read, and does it again
    /// the moment any of that changes. The value is written only when it is
    /// different, so a clock moving on inside one piece writes nothing.
    func watchPanelPlayhead() {
        let answers = withObservationTracking { workOutPanelPlayhead() } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.watchPanelPlayhead() } }
        }
        if answers != panelPlayhead { panelPlayhead = answers }
    }

    func workOutPanelPlayhead() -> PanelPlayhead {
        guard documentHasTime else { return PanelPlayhead() }
        return PanelPlayhead(clipInHand: clipInHandID,
                             pieceInHand: clipPieceInHand,
                             cutInHand: clipCutInHand?.index,
                             speedStopInHand: speedStopInHand)
    }
}
