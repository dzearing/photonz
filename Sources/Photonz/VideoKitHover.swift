import SwiftUI

/// How a video kit piece learns the pointer is over it, inside the app.
///
/// The kit (`VideoKit/`) compiles on its own, so it cannot name
/// `playtestHover`, and a bare `.onHover` is a hover no walk can reach
/// (`PlaytestHoverIsReachableTests`). So the kit asks for `kitHover`, and this
/// file, which lives outside the kit's folder, answers with `playtestHover`.
/// The gallery script answers with a plain `.onHover` of its own.
extension View {
    func kitHover(_ name: String = "", perform: @escaping (Bool) -> Void) -> some View {
        playtestHover(name, perform: perform)
    }
}

/// How a kit piece names something a walk can press, for the same reason:
/// the kit cannot name `playtestControl`, so it asks for this. A segment of
/// `VideoKit.Segmented` is pressed by its words, the way a segment of a
/// system segmented control already is.
extension View {
    func kitControl(_ name: String, detail: String = "") -> some View {
        playtestControl(name, detail: detail)
    }
}
