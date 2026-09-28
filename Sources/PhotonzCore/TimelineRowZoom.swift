import CoreGraphics
import Foundation

/// **How tall the timeline's rows are** (`TimelineRowZoomTests`).
///
/// User 2026-09-28: a pinch on the timeline zooms both ways, "vertical zoom to
/// make the rows larger, but centered where my mouse is". Time already opens
/// out about the moment under the pointer (`TimelineZoom`); this is the other
/// half: every track's lane and header grow together by one factor, from the
/// compact rows the mock draws to about four times them.
///
/// Like the time zoom it is how you are looking at a recording, not part of
/// it, so it lives beside the document (`TimelineViewMemory`) and never in it.
public struct TimelineRowZoom: Hashable, Sendable, Codable {

    /// How many times the compact height a row is.
    public var scale: Double

    /// The mock's rows.
    public static let compact = TimelineRowZoom()
    /// As tall as a row goes: a clip lane of a hundred and ten points or so,
    /// which is a filmstrip you can read and a waveform you can aim at, and
    /// still leaves a second track on screen in the dock.
    public static let tallest: Double = 4

    public init(scale: Double = 1) {
        self.scale = min(max(1, scale), Self.tallest)
    }

    public var isCompact: Bool { scale <= 1.0001 }

    /// Grown (or shrunk) by the factor a pinch moved, within its limits.
    public func zoomed(by factor: Double) -> TimelineRowZoom {
        guard factor > 0, factor.isFinite else { return self }
        return TimelineRowZoom(scale: scale * factor)
    }

    /// A compact height at this scale.
    public func height(_ compact: CGFloat) -> CGFloat {
        compact * CGFloat(scale)
    }

    /// Where the rows' scroll has to go so the spot under the pointer is still
    /// under it after the rows changed height.
    ///
    /// The spot is held as "this far into this row": the same row, the same
    /// share of it. Between two rows it keeps its distance from the row above,
    /// because the gaps do not grow. The answer never scrolls past either end,
    /// which is the one place the promise gives: shrinking rows that already
    /// fit leave nothing to scroll.
    ///
    /// - Parameters:
    ///   - viewportY: the pointer, measured down from the top of the rows' view.
    ///   - offset: how far the rows are scrolled now.
    ///   - before: each row's top and height as they are drawn now.
    ///   - after: the same rows, in the same order, at the new height.
    public static func offset(keepingViewportY viewportY: CGFloat, offset: CGFloat,
                              from before: [TimelineRowExtent], to after: [TimelineRowExtent],
                              contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        guard !before.isEmpty, before.count == after.count else { return offset }
        let spot = offset + viewportY
        let landed = mapped(spot, from: before, to: after)
        let deepest = max(0, contentHeight - viewportHeight)
        return min(max(0, landed - viewportY), deepest)
    }

    static func mapped(_ y: CGFloat, from before: [TimelineRowExtent],
                       to after: [TimelineRowExtent]) -> CGFloat {
        // Above the first row: the padding over it does not move.
        guard let first = before.first, y >= first.top else { return y }
        for index in before.indices {
            let row = before[index], new = after[index]
            if y <= row.bottom {
                let share = row.height > 0 ? (y - row.top) / row.height : 0
                return new.top + share * new.height
            }
            // In the gap under this row: the same distance under it.
            if index + 1 == before.count || y < before[index + 1].top {
                return new.bottom + (y - row.bottom)
            }
        }
        return y
    }
}

/// One row as it is laid out in the tracks' scroll.
public struct TimelineRowExtent: Hashable, Sendable {
    public var top: CGFloat
    public var height: CGFloat
    public var bottom: CGFloat { top + height }

    public init(top: CGFloat, height: CGFloat) {
        self.top = top
        self.height = height
    }
}

/// Which way a pinch on the timeline zooms: both at once, time alone with ⌥
/// held, rows alone with ⇧.
public enum TimelinePinchAxes: Hashable, Sendable {
    case both, time, rows

    public init(option: Bool, shift: Bool) {
        if option, !shift {
            self = .time
        } else if shift, !option {
            self = .rows
        } else {
            self = .both
        }
    }

    public var zoomsTime: Bool { self != .rows }
    public var zoomsRows: Bool { self != .time }
}

/// **How far a recording's timeline was opened out, and how tall its rows
/// were, kept per file** (`TimelineViewMemoryTests`).
///
/// Kept beside the document in the app's own settings, the same way the
/// layers list remembers which groups were open (`OpenGroupMemory`): never in
/// the file and never an undo step. A timeline at its defaults leaves no
/// record, and files fall off the end oldest first past `capacity`.
public struct TimelineViewMemory: Codable, Sendable, Equatable {

    public static let capacity = 60

    public struct Entry: Codable, Sendable, Equatable {
        public var scale: Double
        public var startMS: Double
        public var rowScale: Double
        public var usedAt: Date
    }

    /// Keyed by the file's path.
    public private(set) var files: [String: Entry]

    public init(files: [String: Entry] = [:]) {
        self.files = files
    }

    public var isEmpty: Bool { files.isEmpty }
    public var fileCount: Int { files.count }

    /// How this file's timeline was left, or nil where it was at its defaults.
    public func recall(for key: String) -> (zoom: TimelineZoom, rows: TimelineRowZoom)? {
        guard let entry = files[key] else { return nil }
        return (TimelineZoom(scale: entry.scale, startMS: entry.startMS),
                TimelineRowZoom(scale: entry.rowScale))
    }

    public mutating func remember(zoom: TimelineZoom, rows: TimelineRowZoom, for key: String,
                                  at now: Date = Date()) {
        guard !zoom.isFit || !rows.isCompact else {
            files[key] = nil
            return
        }
        files[key] = Entry(scale: zoom.scale, startMS: zoom.isFit ? 0 : zoom.startMS,
                           rowScale: rows.scale, usedAt: now)
        guard files.count > Self.capacity else { return }
        let stale = files
            .sorted { ($0.value.usedAt, $0.key) < ($1.value.usedAt, $1.key) }
            .prefix(files.count - Self.capacity)
        for (key, _) in stale { files[key] = nil }
    }
}
