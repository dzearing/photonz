// Where everything inside the panel BEGINS, for the scripted playtest.
//
// The mirror of `PanelEdgeProbe`. "The rows in Appearance start further in than
// the panel's own margin" is a claim about pixels, and a screenshot only proves
// it to somebody who lays a ruler on it. This records the live leading edge of
// every row, heading and folded subsection in the dock, so a walk can read them
// back as numbers and a drift shows up as a failing measurement rather than as
// a picture nobody compared.
//
// Probe builds only: the shipping app compiles the no-ops at the bottom.
import PhotonzCore
import SwiftUI

#if PHOTONZ_PLAYTEST

/// The panel's last measured left edge. Held by reference and deliberately NOT
/// observable, for the same reason `PanelEdgeProbe` is not: these frames are
/// written on every layout pass, and redrawing the dock to remember a number
/// nothing draws is the jank `InspectorPanel`'s own comments are about.
@MainActor final class PanelStartProbe {
    static let shared = PanelStartProbe()

    /// What a thing inside a panel is allowed to be, which is the whole point:
    /// a heading and a row both start on the margin, and only a subsection is
    /// allowed to step in.
    enum Kind: String {
        /// A section's own header: its chevron, its title, its buttons.
        case heading
        /// One row of a section's body.
        case row
        /// Content folded under the row above it, behind a rule.
        case subsection
    }

    struct Mark {
        let kind: Kind
        /// Which section or row it belongs to, so the log reads as the panel does.
        let owner: String
        let frame: CGRect
        /// When it was last measured, so the newest reading of a row SwiftUI
        /// has rebuilt is the one the walk reads.
        let at: Date
    }

    /// Keyed by the VIEW rather than by what it is called, for the reason
    /// spelled out in `PanelEdgeProbe`: a rebuilt row's replacement appears
    /// before the original disappears, and keying by name let the old view's
    /// goodbye delete the new view's measurement.
    private var marks: [UUID: Mark] = [:]

    func record(token: UUID, kind: Kind, owner: String, frame: CGRect) {
        marks[token] = Mark(kind: kind, owner: owner, frame: frame, at: Date())
    }

    func forget(token: UUID) {
        marks.removeValue(forKey: token)
    }

    /// Everything measured, top to bottom, one entry per thing, the newest
    /// reading winning if a rebuild has left two.
    var measured: [Mark] {
        var newest: [String: Mark] = [:]
        for mark in marks.values {
            let key = "\(mark.owner)/\(mark.kind.rawValue)"
            if let held = newest[key], held.at > mark.at { continue }
            newest[key] = mark
        }
        return newest.values.sorted {
            $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX
                                           : $0.frame.minY < $1.frame.minY
        }
    }
}

/// Watches one thing's leading edge for as long as it is on screen.
private struct PanelStartProbeModifier: ViewModifier {
    let kind: PanelStartProbe.Kind
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
            .onDisappear { PanelStartProbe.shared.forget(token: token) }
    }

    private func record(_ frame: CGRect) {
        PanelStartProbe.shared.record(token: token, kind: kind, owner: owner, frame: frame)
    }
}

extension View {
    /// Registers this view as something inside the panel with a leading edge a
    /// walk can measure. Put it on the row, the header or the folded block
    /// itself, never on a label inside one.
    func panelStartProbe(_ kind: PanelStartProbe.Kind, owner: String) -> some View {
        modifier(PanelStartProbeModifier(kind: kind, owner: owner))
    }
}

#else

extension View {
    func panelStartProbe(_ kind: PanelStartProbeKind, owner: String) -> some View { self }
}

/// The shipping build still has to name the kinds, so every call site compiles
/// unchanged with the probe out.
enum PanelStartProbeKind {
    case heading, row, subsection
}

#endif
