// Where the panel's scrollers stop at the top, so a walk can say what of the
// panel is drawn beside the title bar's buttons.
//
// A control's own box says where it is laid out, not what of it is drawn: a
// row scrolled up past the panel's top edge (`PanelTopEdge`) still has a box
// up under Ask, and nothing of it is on screen. `expectTitleBarClear` cuts
// every control to the top edge recorded here before measuring it against the
// title bar's controls, so a row that is masked away does not count and a row
// that is drawn does.
//
// Probe builds only: the shipping app compiles the no-ops at the bottom.
import SwiftUI

#if PHOTONZ_PLAYTEST

/// The panel's top edges, one per scroller wearing `PanelTopEdge`, in SwiftUI's
/// global space (top left origin). Not observable, for the reason
/// `PanelEdgeProbe` gives: these are written on layout passes nothing draws.
@MainActor final class PanelTopEdgeProbe {
    static let shared = PanelTopEdgeProbe()

    /// Keyed by the view, so a scroller SwiftUI rebuilds does not lose its
    /// replacement's reading to the old one's goodbye.
    private(set) var frames: [UUID: CGRect] = [:]

    func record(token: UUID, frame: CGRect) { frames[token] = frame }
    func forget(token: UUID) { frames.removeValue(forKey: token) }
}

private struct PanelTopEdgeProbeModifier: ViewModifier {
    @State private var token = UUID()

    func body(content: Content) -> some View {
        if PlaytestMarkers.areHung {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    PanelTopEdgeProbe.shared.record(token: token, frame: frame)
                }
                .onDisappear { PanelTopEdgeProbe.shared.forget(token: token) }
        } else {
            content
        }
    }
}

extension View {
    /// Registers this scroller's frame as one of the panel's top edges.
    func panelTopEdgeProbe() -> some View {
        modifier(PanelTopEdgeProbeModifier())
    }
}

#else

extension View {
    func panelTopEdgeProbe() -> some View { self }
}

#endif
