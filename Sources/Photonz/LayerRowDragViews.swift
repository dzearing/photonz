// What a row carried up or down the layers list looks like: the row lifted over the list, the gap it will land in, and the rows standing aside.

import AppKit
import PhotonzCore
import SwiftUI

/// Where a row of the list is drawn while another is carried: moved one row
/// out of the way when the gap has passed it, and not drawn at all when it is
/// the row in the air or rides along with it. `id` nil is the Canvas row
/// under the last layer, which closes up over any row tucked away.
///
/// Reads only the part of the drag that changes when the gap moves, so the
/// rows stay still (and are not redrawn) while the pointer moves inside a row.
struct LayerRowDragPlacement: ViewModifier {
    let id: UUID?
    let session: LayerRowDragSession

    func body(content: Content) -> some View {
        Placed(id: id, session: session, content: content)
    }

    /// A view of its own, so what it reads of the drag is ITS dependency and
    /// not the list's: read in the modifier's body, the whole list was rebuilt
    /// every time the gap moved.
    private struct Placed: View {
        let id: UUID?
        let session: LayerRowDragSession
        let content: Content

        var body: some View {
            let layout = session.layout
            if let id {
                content
                    .offset(y: layout.offsets[id] ?? 0)
                    .opacity(layout.travelling.contains(id) ? 0 : 1)
            } else {
                content.offset(y: layout.trailingOffset)
            }
        }
    }
}

/// The place the carried row will land: a soft recess exactly one row tall,
/// drawn in at the indent of the list it will join, so the foot of an open
/// group reads differently from the row under it.
struct LayerDragGap: View {
    let session: LayerRowDragSession

    var body: some View {
        if session.isCarrying {
            let layout = session.layout
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .frame(height: session.rowHeight)
                .padding(.leading, CGFloat(layout.gapDepth) * LayerRowDragSession.indentPerLevel)
                .offset(y: layout.gapTop)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The carried row itself, the real row rather than a picture of it, lifted
/// off the list on a plate of its own with a shadow under it. It goes up and
/// down with the pointer and nowhere else, and slides to its new indent only
/// as it settles.
struct LiftedLayerRow<Row: View>: View {
    let session: LayerRowDragSession
    /// How deep the row sat when it was picked up.
    let depth: Int
    let row: Row

    var body: some View {
        let lift = session.lift
        row
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .padding(.leading, CGFloat(depth) * LayerRowDragSession.indentPerLevel)
                    .shadow(color: .black.opacity(0.28 * lift), radius: 10 * lift, y: 4 * lift)
            }
            // Several layers carried as one stack say how many, the way the
            // Finder does, so the rows that tucked away are not a surprise.
            .overlay(alignment: .topTrailing) {
                if session.carriedCount > 1 {
                    Text("\(session.carriedCount)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(Color.accentColor))
                        .offset(x: 4, y: -5)
                        .opacity(lift)
                }
            }
            .scaleEffect(1 + 0.025 * lift, anchor: .center)
            .offset(x: session.settleShift, y: session.liftedTop)
            .allowsHitTesting(false)
    }
}

/// Finds the AppKit scroll view a SwiftUI `ScrollView` is drawn with, so a
/// carried row can scroll the list sixty times a second without going through
/// the list's own scroll position. Scrolled through SwiftUI state, every tick
/// of the edge scroll rebuilt the whole list (measured 2026-09-30 on 173 rows:
/// fifteen list bodies for one carry); scrolled here, the list hears about it
/// the way it hears about a trackpad, once per row that goes by.
struct EnclosingScrollViewReader: NSViewRepresentable {
    let found: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.found = found
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.found = found
    }

    final class ProbeView: NSView {
        var found: (NSScrollView?) -> Void = { _ in }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            found(enclosingScrollView)
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension NSScrollView {
    /// Scrolls so `offset` points of the content are above the top edge.
    func scrollContent(toTop offset: CGFloat) {
        guard let document = documentView else { return }
        let clip = contentView
        let y = document.isFlipped
            ? offset
            : document.bounds.height - clip.bounds.height - offset
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        reflectScrolledClipView(clip)
    }
}
