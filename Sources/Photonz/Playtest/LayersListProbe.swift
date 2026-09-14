// Where the layers list is scrolled to, for the scripted playtest.
//
// "Picking a layer on the canvas brings its row into view" is a claim about a
// list that shows five rows out of forty, and a snapshot only proves it to a
// person who looks at it. This records the rows the list holds and how far down
// it is, so a walk can read back, as words, which rows a person can see and
// what the last pick did about it. Probe builds only: the shipping app compiles
// the no-ops at the bottom.
import PhotonzCore
import SwiftUI

#if PHOTONZ_PLAYTEST

/// The layers list's last known scroll state. Held by reference and
/// deliberately NOT observable, for the same reason the list keeps its own
/// offset in a box: these numbers are written on every frame of a scroll.
@MainActor final class LayersListProbe {
    static let shared = LayersListProbe()

    /// The rows the list is drawing, top down, by name.
    var rowNames: [String] = []
    /// One row's height, and the gap under it is `LayerListMetrics.spacing`.
    var rowHeight: CGFloat = 0
    /// How tall the scrolling area is.
    var viewport: CGFloat = 0
    /// How far down the list is, in points from the top of the first row.
    var offset: CGFloat = 0
    /// What the last pick did about the list, in words: which rows it was
    /// asked for, where the list was, and where it went. A reveal that decided
    /// to do nothing says so too, since "it was already on screen" is the
    /// answer half the time and a walk reading an empty line could not tell
    /// that from a reveal that never ran.
    var lastReveal: String?

    /// A row counts as in view when all of it is inside the scrolling area —
    /// the same call the reveal itself makes, so a walk reading this is asking
    /// about pixels rather than about the decision.
    func isInView(_ name: String) -> Bool {
        guard let index = rowNames.firstIndex(of: name) else { return false }
        return isInView(row: index)
    }

    func isInView(row index: Int) -> Bool {
        guard viewport > 0, rowHeight > 0 else { return false }
        return DockReveal.action(
            sectionTop: LayerListMetrics.rowTop(index: index, rowHeight: rowHeight) - offset,
            sectionHeight: rowHeight,
            viewportHeight: viewport) == .none
    }

    /// The rows a person can see whole, in order, which is the line a walk
    /// reads back.
    var rowsInView: [String] {
        rowNames.indices.filter { isInView(row: $0) }.map { rowNames[$0] }
    }
}

@MainActor func recordLayerListScroll(_ offset: CGFloat) {
    LayersListProbe.shared.offset = offset
}

@MainActor func recordLayerListRows(_ names: [String], rowHeight: CGFloat, viewport: CGFloat) {
    LayersListProbe.shared.rowNames = names
    LayersListProbe.shared.rowHeight = rowHeight
    LayersListProbe.shared.viewport = viewport
}

@MainActor func recordLayerReveal(rows: [Int], from: CGFloat, to: CGFloat?, viewport: CGFloat) {
    func points(_ value: CGFloat) -> String { "\(Int(value.rounded()))" }
    let asked = rows.sorted().map(String.init).joined(separator: ", ")
    let where_ = "rows [\(asked)] at \(points(from))pt, list \(points(viewport))pt"
    LayersListProbe.shared.lastReveal = to.map {
        "\(where_): scrolled to \(points($0))pt"
    } ?? "\(where_): already on screen, nothing moved"
}

extension View {
    /// Tells the probe which rows the list is drawing and how big it is.
    func layersListProbe(rows: [String], rowHeight: CGFloat, viewport: CGFloat) -> some View {
        onChange(of: RowReport(names: rows, rowHeight: rowHeight, viewport: viewport),
                 initial: true) { _, report in
            recordLayerListRows(report.names, rowHeight: report.rowHeight,
                                viewport: report.viewport)
        }
    }
}

/// One value for the three things the probe is told, so the list reports them
/// in one watch rather than three.
private struct RowReport: Equatable {
    let names: [String]
    let rowHeight: CGFloat
    let viewport: CGFloat
}

#else

@MainActor func recordLayerListScroll(_ offset: CGFloat) {}
@MainActor func recordLayerListRows(_ names: [String], rowHeight: CGFloat, viewport: CGFloat) {}
@MainActor func recordLayerReveal(rows: [Int], from: CGFloat, to: CGFloat?, viewport: CGFloat) {}

extension View {
    func layersListProbe(rows: [String], rowHeight: CGFloat, viewport: CGFloat) -> some View { self }
}

#endif
