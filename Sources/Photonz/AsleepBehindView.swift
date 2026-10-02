import SwiftUI

/// One of Edit's pieces kept behind View (`EditModeArrival`), standing still
/// while it is out of sight. The views holding the tracks and the tool bar
/// draw again on every frame a recording plays (the transport and the canvas
/// read the playhead), and handing the hidden pieces those passes cost a
/// recording playing in View about a quarter more of the main thread
/// (2026-10-02). Awake it is never equal to itself, so nothing about Edit
/// changes.
struct AsleepBehindView<Content: View>: View, Equatable {
    let asleep: Bool
    @ViewBuilder let content: () -> Content

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.asleep && rhs.asleep }

    var body: some View { content() }
}
