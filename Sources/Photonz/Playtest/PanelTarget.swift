// What a scripted walk can reach in the right hand panel, and by what name.
//
// The canvas is easy to drive: it is one AppKit view and a point in it means
// something. The dock is SwiftUI, so a walk that wants the tile called Button
// or the layer row called Label has no way to find either, and no way to pick
// one up. Every audit written on 2026-09-03 that touched the dock had to admit
// it: a menu in the panel was covered by a test rather than a picture, and the
// drop line in the layers list came from a one-off build.
//
// So the panel says who it is. Each tile and each row hangs an invisible marker
// behind itself carrying the name a person reads, what kind of thing it is, and
// the SAME drag payload its own `onDrag` hands over — one closure, used by both,
// so a walk can never drag something the pointer would not.
//
// Probe builds only; the shipping app compiles the no-ops at the bottom.
import SwiftUI

#if PHOTONZ_PLAYTEST

/// What sort of thing in the panel a marker stands for. A walk names these in
/// its steps, so they are words, not ids.
enum PanelTargetKind: String {
    /// One thing on the Library shelf.
    case tile
    /// One row in the layers list.
    case row
}

/// The invisible marker behind one tile or row. Like `HintAnchorView` it is a
/// position and nothing else: it never takes a click and never draws. The
/// harness reads its frame fresh at the moment of a drag, so a shelf that
/// scrolled a beat ago is still dragged from where it actually is.
final class PanelTargetView: NSView {
    var name: String
    var kind: PanelTargetKind
    /// What the panel would say this is, for the log: which shelf scope, or
    /// whether the row is a group.
    var detail: String
    /// Exactly the closure the view's own `onDrag` uses. Nil for something
    /// that cannot be picked up, so a walk that tries is told so.
    var payload: (@MainActor () -> NSItemProvider)?

    init(name: String, kind: PanelTargetKind, detail: String,
         payload: (@MainActor () -> NSItemProvider)?) {
        self.name = name
        self.kind = kind
        self.detail = detail
        self.payload = payload
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct PanelTargetAnchor: NSViewRepresentable {
    let name: String
    let kind: PanelTargetKind
    let detail: String
    let payload: (@MainActor () -> NSItemProvider)?

    func makeNSView(context: Context) -> PanelTargetView {
        PanelTargetView(name: name, kind: kind, detail: detail, payload: payload)
    }

    func updateNSView(_ view: PanelTargetView, context: Context) {
        view.name = name
        view.kind = kind
        view.detail = detail
        view.payload = payload
    }
}

extension View {
    /// Names this tile or row for a scripted walk, and tells it what picking
    /// the thing up hands over. Pass the very closure `onDrag` is given.
    func playtestTarget(_ name: String, kind: PanelTargetKind, detail: String = "",
                        payload: (@MainActor () -> NSItemProvider)? = nil) -> some View {
        background(PanelTargetAnchor(name: name, kind: kind, detail: detail, payload: payload))
    }
}

#else

enum PanelTargetKind: String {
    case tile, row
}

extension View {
    func playtestTarget(_ name: String, kind: PanelTargetKind, detail: String = "",
                        payload: (@MainActor () -> NSItemProvider)? = nil) -> some View { self }
}

#endif
