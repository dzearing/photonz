import CoreGraphics

/// How wide the column of track names down the left of the timeline is.
///
/// The person drags its right edge (user 2026-10-03: "the labels area of the
/// tracks can't be resized, and it's so small the buttons overlap"), and the
/// width is theirs: one for every recording and window, kept across launches.
///
/// - The floor is the fullest header there can be (a track in a group, its
///   arrow, all three switches up under the pointer and the key diamond) with
///   a few letters of its name still showing. Below that something would have
///   to overlap, so the column does not go there.
/// - The default shows "V10" whole on that same fullest header, and "Audio 2"
///   whole on an ordinary one. The mock's 84 points did neither once the
///   switches came up.
/// - Nothing chosen (nothing on file, or a double-click on the edge) is the
///   default.
public enum TrackColumn {
    /// What is written to the settings for "nothing chosen".
    public static let defaultStored: Double = 0
    public static let defaultWidth: CGFloat = 140
    public static let maximumWidth: CGFloat = 320
    /// The fullest header's fixed parts plus `TrackHeaderLayout.nameMinimum`,
    /// rounded up to a whole point.
    public static let minimumWidth: CGFloat = (TrackHeaderLayout.fullestFixedWidth
                                               + TrackHeaderLayout.nameMinimum).rounded(.up)

    /// Any width, held between the floor and the ceiling.
    public static func clamped(_ width: CGFloat) -> CGFloat {
        min(maximumWidth, max(minimumWidth, width))
    }

    /// The width on file, or the default when nothing usable is.
    public static func width(stored: Double) -> CGFloat {
        guard stored.isFinite, stored > 0 else { return defaultWidth }
        return clamped(CGFloat(stored))
    }

    /// Where a drag on the edge leaves the column, given its width when the
    /// drag began and how far the pointer has moved right since.
    public static func dragged(from base: CGFloat, pointerMovedRight dx: CGFloat) -> CGFloat {
        clamped(base + dx)
    }
}

/// Where everything in one track's header goes, left to right: the group's
/// indent, the arrow that opens its lanes, the name (with the kind icon in
/// front when there is room for it), then the switches and the key diamond
/// kept to the right edge.
///
/// The name takes whatever the rest leave and is the only thing that gives:
/// every control keeps `gap` from its neighbours at any width the column
/// allows, and the name's text shortens with an ellipsis instead.
public struct TrackHeaderLayout: Sendable, Hashable {
    public static let groupIndent: CGFloat = 10
    public static let twistWidth: CGFloat = 12
    /// A hide, solo or lock switch, square.
    public static let switchSize: CGFloat = 15
    /// Between two switches.
    public static let switchSpacing: CGFloat = 4
    /// Between the name, the switches and the key.
    public static let gap: CGFloat = 4
    public static let keySize: CGFloat = 16
    /// Air after the last control, before the gap to the lanes.
    public static let trailing: CGFloat = 2
    /// The kind icon and the space after it.
    public static let iconRoom: CGFloat = 14
    /// A few letters and an ellipsis: "V1…" is 21.7 points in the header's font.
    public static let nameMinimum: CGFloat = 22

    /// Everything but the name, on the fullest header there can be.
    static var fullestFixedWidth: CGFloat {
        groupIndent + twistWidth + gap + clusterWidth(switches: 3) + gap + keySize + trailing
    }

    /// The switches side by side.
    public static func clusterWidth(switches: Int) -> CGFloat {
        switches <= 0 ? 0 : CGFloat(switches) * switchSize + CGFloat(switches - 1) * switchSpacing
    }

    public let width: CGFloat
    /// Where the arrow starts, when there is one.
    public let twistX: CGFloat?
    /// Where the name (icon and text) starts and how much room it has.
    public let nameX: CGFloat
    public let nameWidth: CGFloat
    /// Whether the kind icon is drawn before the text.
    public let showsIcon: Bool
    /// Where each switch starts, left to right.
    public let switchXs: [CGFloat]
    /// Where the key diamond starts, when there is one.
    public let keyX: CGFloat?

    /// - Parameters:
    ///   - switches: how many of hide, solo and lock are up.
    ///   - wantsIcon: whether the header would like its kind icon. It is
    ///     drawn only when the text keeps `nameMinimum` beside it.
    public init(width: CGFloat, inGroup: Bool, hasTwist: Bool, switches: Int, hasKey: Bool, wantsIcon: Bool) {
        self.width = width
        let leading = inGroup ? Self.groupIndent : 0
        twistX = hasTwist ? leading : nil
        nameX = leading + (hasTwist ? Self.twistWidth : 0)
        var right = width - Self.trailing
        if hasKey {
            right -= Self.keySize
            keyX = right
            right -= Self.gap
        } else {
            keyX = nil
        }
        let count = max(0, switches)
        if count > 0 {
            let start = right - Self.clusterWidth(switches: count)
            switchXs = (0..<count).map { start + CGFloat($0) * (Self.switchSize + Self.switchSpacing) }
            right = start - Self.gap
        } else {
            switchXs = []
        }
        nameWidth = max(0, right - nameX)
        showsIcon = wantsIcon && nameWidth - Self.iconRoom >= Self.nameMinimum
    }

    /// The room the name's words have, after the icon when it shows.
    public var textWidth: CGFloat { showsIcon ? nameWidth - Self.iconRoom : nameWidth }
}
