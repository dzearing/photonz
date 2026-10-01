import AppKit
import PhotonzCore
import SwiftUI

/// Each click of a recording as a small tick along the foot of its clip's bar
/// (`ClickEffect.swift`, `EditorState+ClickEffects`).
///
/// A press on a tick puts the playhead on the click, a drag slides the click
/// to when it really happened, and a right click hides it (or shows it again).
/// A hidden click keeps a faint tick, so it can be found and shown again.
struct ClickTicksView: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let laneWidth: CGFloat
    let height: CGFloat
    var isLocked = false

    var body: some View {
        let ruler = editorState.motionStripRuler
        let ticks = editorState.clickTicks(ofClip: layerID)
        ForEach(Array(ticks.enumerated()), id: \.element.mark.id) { index, tick in
            ClickTick(layerID: layerID, mark: tick.mark, ms: tick.ms, number: index + 1,
                      x: laneWidth * ruler.fraction(ofMS: Double(tick.ms)),
                      laneWidth: laneWidth, height: height, isLocked: isLocked)
        }
    }
}

private struct ClickTick: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let mark: ClickMark
    let ms: Int
    let number: Int
    let x: CGFloat
    let laneWidth: CGFloat
    let height: CGFloat
    let isLocked: Bool

    @State private var travel: CGFloat = 0
    @State private var dragging = false

    /// The hand's room either side of the mark.
    static let grip: CGFloat = 9
    /// How tall the mark is, from the foot of the bar.
    static let markHeight: CGFloat = 10

    var body: some View {
        let target = min(height, 14)
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(mark.isHidden ? Color.white.opacity(0.35) : Color.white)
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.45), lineWidth: 0.5))
                .frame(width: 3, height: Self.markHeight)
                .padding(.bottom, 3)
        }
        .frame(width: Self.grip, height: target, alignment: .bottom)
        .contentShape(Rectangle())
        .gesture(press)
        .contextMenu {
            MenuRowsView(rows: editorState.clickTickMenuRows(clickID: mark.id, onClip: layerID))
        }
        .onContinuousHover { phase in
            switch phase {
            case .active: NSCursor.resizeLeftRight.set()
            case .ended: NSCursor.arrow.set()
            }
        }
        .help(mark.isHidden ? "Hidden click" : "Click")
        .accessibilityElement()
        .accessibilityLabel("Click \(number)")
        .accessibilityValue(mark.isHidden ? "hidden" : "")
        .playtestControl("Click \(number)", detail: "Timeline")
        // Placed by padding rather than an offset, so where the tick is
        // drawn is where it is laid out, and a hand (or a walk) finds it there.
        .padding(.leading, max(0, x - Self.grip / 2 + travel))
        .padding(.top, height - target)
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(TimelineDock.tracksSpace))
            .onChanged { value in
                guard !isLocked else { return }
                if !dragging {
                    guard abs(value.translation.width) >= 3 else { return }
                    dragging = true
                }
                travel = value.translation.width
            }
            .onEnded { value in
                defer {
                    dragging = false
                    travel = 0
                }
                if dragging {
                    let moved = editorState.motionStripRuler.msSpanning(
                        fraction: Double(value.translation.width / max(1, laneWidth)))
                    editorState.moveClick(mark.id, onClip: layerID, toTimelineMS: ms + Int(moved.rounded()))
                } else {
                    // A press is a way to find the click: the clip is picked
                    // and the playhead goes to it.
                    editorState.selectLayer(layerID)
                    editorState.moveDocumentPlayhead(toMS: ms)
                }
            }
    }
}
