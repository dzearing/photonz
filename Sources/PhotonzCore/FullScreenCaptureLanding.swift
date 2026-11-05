import CoreGraphics

/// How a full screen capture of several displays lands.
///
/// Every display is kept in history, and exactly one goes on the clipboard: the
/// one under the pointer, because that is the one being looked at. It used to
/// be whichever display came last, each one replacing the one before, so on a
/// Mac with two displays the paste was often of the other screen (one picture
/// joining them was the other candidate; it would mix two pixel densities and
/// paste as a strip nobody asked for).
///
/// The clipboard's display lands last, so it is the newest thing in history and
/// the toast nearest the corner, and the clipboard is written once.
public enum FullScreenCaptureLanding {

    public struct Step: Equatable, Sendable {
        /// Which of the displays handed in.
        public let display: Int
        public let goesOnClipboard: Bool

        public init(display: Int, goesOnClipboard: Bool) {
            self.display = display
            self.goesOnClipboard = goesOnClipboard
        }
    }

    /// `displays` and `pointer` are in the same coordinates.
    public static func steps(displays: [CGRect], pointer: CGPoint) -> [Step] {
        guard let chosen = display(under: pointer, of: displays) else { return [] }
        return displays.indices.filter { $0 != chosen }.map { Step(display: $0, goesOnClipboard: false) }
            + [Step(display: chosen, goesOnClipboard: true)]
    }

    /// The display holding the pointer, or the nearest one: the pointer at the
    /// very top of a display reads as sitting on its far edge, which a rect does
    /// not contain.
    private static func display(under pointer: CGPoint, of displays: [CGRect]) -> Int? {
        displays.indices.min { distance(pointer, displays[$0]) < distance(pointer, displays[$1]) }
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
