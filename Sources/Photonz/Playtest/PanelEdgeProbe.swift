// Where everything parked on the panel's right edge actually sits.
//
// "The eyes make a line and the grips miss it" is a claim about pixels, and a
// screenshot only proves it to a person who looks at it closely with a ruler.
// This records the live frame of every icon on that edge, in the window's
// coordinates, so a walk can read the centres back as numbers and a drift
// shows up as a failing measurement rather than as a picture nobody compared.
//
// Probe builds only: the shipping app compiles the no-ops at the bottom.
import SwiftUI

#if PHOTONZ_PLAYTEST

/// The panel edge's last measured layout. Held by reference and deliberately
/// NOT observable: these frames are written on every layout pass, and redrawing
/// the dock to remember a number nothing draws is the jank `InspectorPanel`'s
/// own comments are about.
@MainActor final class PanelEdgeProbe {
    static let shared = PanelEdgeProbe()

    struct Control {
        /// What it is: "eye", "lock", "section grip".
        let kind: String
        /// Which row or section it belongs to, so the log reads as the panel does.
        let owner: String
        let frame: CGRect
        /// When it was last measured, so the newest reading of a row that has
        /// been rebuilt is the one the walk reads.
        let at: Date
    }

    /// The panel's own frame, so every centre can be given as a distance from
    /// the edge it is measured against rather than as a window coordinate that
    /// changes with the window.
    var panel: CGRect = .zero

    /// Keyed by the VIEW, not by what it is called.
    ///
    /// Keying by name looked tidier and quietly lost icons: a row SwiftUI
    /// rebuilds (every row in the Appearance list does, on any change) has its
    /// replacement appear before the original disappears, so the old view's
    /// goodbye deleted the new view's measurement and the walk reported a
    /// column with the effect rows missing from it.
    private var controls: [UUID: Control] = [:]

    func record(token: UUID, kind: String, owner: String, frame: CGRect) {
        controls[token] = Control(kind: kind, owner: owner, frame: frame, at: Date())
    }

    func forget(token: UUID) {
        controls.removeValue(forKey: token)
    }

    /// Everything on the edge, top to bottom, then left to right — one entry
    /// per icon, the newest reading winning if a rebuild has left two.
    var measured: [Control] {
        var newest: [String: Control] = [:]
        for control in controls.values {
            let key = "\(control.owner)/\(control.kind)"
            if let held = newest[key], held.at > control.at { continue }
            newest[key] = control
        }
        return newest.values.sorted {
            $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX
                                           : $0.frame.minY < $1.frame.minY
        }
    }
}

@MainActor func recordPanelEdgeFrame(_ frame: CGRect) {
    PanelEdgeProbe.shared.panel = frame
}

/// Watches one icon's slot for as long as that icon is on screen.
private struct PanelEdgeProbeModifier: ViewModifier {
    let kind: String
    let owner: String
    /// This view's own name in the probe's book, so its goodbye takes its own
    /// measurement away and never a replacement's.
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { record(proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in record(frame) }
            })
            .onDisappear { PanelEdgeProbe.shared.forget(token: token) }
    }

    private func record(_ frame: CGRect) {
        PanelEdgeProbe.shared.record(token: token, kind: kind, owner: owner, frame: frame)
    }
}

extension View {
    /// Registers this view as one of the icons on the panel's trailing edge,
    /// under the words a walk reads it back by. Put it on the slot, so the
    /// measurement is the slot the glyph is centred in.
    func panelEdgeProbe(kind: String, owner: String) -> some View {
        modifier(PanelEdgeProbeModifier(kind: kind, owner: owner))
    }
}

#else

@MainActor func recordPanelEdgeFrame(_ frame: CGRect) {}

extension View {
    func panelEdgeProbe(kind: String, owner: String) -> some View { self }
}

#endif
