import PhotonzCore
import SwiftUI

/// Rows of a dock section that are built a run-loop pass or more after the
/// section itself, so a big section arrives top down in pieces rather than in
/// one long pass.
///
/// The dock already brings sections in one per pass (`PanelSectionArrival`),
/// and that keeps most of them short. Captions is the exception: its style
/// tiles, colour wells, switch, sliders and dropdowns all land in the one
/// pass, and a frame or so later SwiftUI pays for every control it just added
/// in a single accessibility and focus pass of its own. On a captioned five
/// minute recording that pass held the window for 115-130 ms after a click
/// from a cut back to a clip; with only the section's top rows it was 44 ms
/// (2026-10-06, `clip-click-cost-walk`). In pieces, each piece pays for its
/// own controls.
///
/// While they wait the rows hold the height they were last drawn at, so
/// nothing under them moves when they land.
///
/// On a video, with `next-panel-builds-what-you-see` on, they also wait for
/// the section to come near the view, and they are let go again once a pick
/// has carried them far out of it for `PanelBodyReach.letGoAfter`. A clip pick
/// after nothing was picked carries Captions from the middle of the dock to
/// 1400pt down; its rows were still built when the next click, on a cut, took
/// the section away, and pulling them down was most of that cut's extra 10ms
/// (`clip-click-cost-walk`, 2026-10-07). Coming back near, they arrive the
/// same way they first did, a pass at a time.
struct PanelRowsArrival<Content: View>: View {
    /// How many passes after the section appears these rows are built.
    let after: Int
    /// The name their last drawn height is kept under.
    let remembering: String
    @ViewBuilder let content: () -> Content
    @State private var isHere = false
    /// Within reach of the view, as last measured. True until measured, so a
    /// dock that cannot say builds them as it always has.
    @State private var isNear = true

    var body: some View {
        let mayWait = PanelBuildsEverything.dockMayWait
        let wanted = isNear || !mayWait
        Group {
            if isHere {
                content()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        PanelRowsArrivalHeights.drawn[remembering] = $0
                    }
            } else {
                Color.clear
                    .frame(height: PanelRowsArrivalHeights.drawn[remembering] ?? 0)
                    .task(id: wanted) {
                        guard wanted else { return }
                        for _ in 0..<after { await NextRunLoopPass.start() }
                        guard !Task.isCancelled else { return }
                        isHere = true
                    }
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            guard let visible = proxy.bounds(of: .scrollView) else { return true }
            return PanelBodyReach.isWithinReach(top: -visible.minY,
                                                bottom: proxy.size.height - visible.minY,
                                                viewport: visible.height)
        } action: { near in
            isNear = near
            if !near { letGoSoon() }
        }
    }

    /// Lets the rows go once they have stayed out of reach for a moment.
    private func letGoSoon() {
        guard isHere, PanelBuildsEverything.dockMayWait else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(PanelBodyReach.letGoAfter))
            guard isHere, !isNear, PanelBuildsEverything.dockMayWait else { return }
            PanelBuildsEverything.shared.rowsHaveWaited = true
            isHere = false
        }
    }
}

/// How tall each set of arriving rows was last drawn, by name.
@MainActor enum PanelRowsArrivalHeights {
    static var drawn: [String: CGFloat] = [:]
}
