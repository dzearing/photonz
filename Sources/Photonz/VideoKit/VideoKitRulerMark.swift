// Where the timeline's ruler and playhead were really DRAWN, for a walk.
//
// The ruler's sums can be right while its numbers land somewhere else: on
// 2026-09-24, zoomed in, every number sat seconds left of the moment it named
// because of how the numbers were laid out, and nothing that read the ruler's
// model could see it. So each number, the ruler itself and the playhead line
// hang an invisible marker behind themselves, and `expectTimeline` reads the
// markers' frames, which are where a person sees them.
//
// Probe builds only; the shipping app compiles the no-op at the bottom. It
// lives in the video kit, not with the rest of the walk harness, because the
// kit's ruler wears it and the kit has to compile on its own (the gallery and
// `Scripts/test.sh` typecheck it with nothing else), where the no-op is what
// it gets.
import SwiftUI

/// What a marker stands behind.
enum PlaytestRulerMarkRole: Equatable {
    /// The whole ruler, lane width and all: what every fraction is of.
    case ruler
    /// One number on the ruler. `atTrailingEdge` is the number at the very end,
    /// which sets itself inside the edge, so its tick is its RIGHT side.
    case label(String, fraction: Double, atTrailingEdge: Bool)
    /// The playhead line, whose middle is where it stands.
    case playhead(fraction: Double)
}

#if PHOTONZ_PLAYTEST

final class PlaytestRulerMarkView: NSView {
    var role: PlaytestRulerMarkRole

    init(role: PlaytestRulerMarkRole) {
        self.role = role
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct PlaytestRulerMarkAnchor: NSViewRepresentable {
    let role: PlaytestRulerMarkRole

    func makeNSView(context: Context) -> PlaytestRulerMarkView { PlaytestRulerMarkView(role: role) }

    func updateNSView(_ view: PlaytestRulerMarkView, context: Context) { view.role = role }
}

extension View {
    /// Marks this as the ruler, one of its numbers, or the playhead line, so a
    /// walk can read where it was drawn.
    func playtestRulerMark(_ role: PlaytestRulerMarkRole) -> some View {
        background(PlaytestRulerMarkAnchor(role: role))
    }
}

#else

extension View {
    func playtestRulerMark(_ role: PlaytestRulerMarkRole) -> some View { self }
}

#endif
