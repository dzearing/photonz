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
/// nothing under them moves when they land, and they arrive once: a section
/// that stays on screen never waits again.
struct PanelRowsArrival<Content: View>: View {
    /// How many passes after the section appears these rows are built.
    let after: Int
    /// The name their last drawn height is kept under.
    let remembering: String
    @ViewBuilder let content: () -> Content
    @State private var isHere = false

    var body: some View {
        if isHere {
            content()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    PanelRowsArrivalHeights.drawn[remembering] = $0
                }
        } else {
            Color.clear
                .frame(height: PanelRowsArrivalHeights.drawn[remembering] ?? 0)
                .task {
                    for _ in 0..<after { await NextRunLoopPass.start() }
                    isHere = true
                }
        }
    }
}

/// How tall each set of arriving rows was last drawn, by name.
@MainActor enum PanelRowsArrivalHeights {
    static var drawn: [String: CGFloat] = [:]
}
