import CoreGraphics
import Foundation

/// One window as the window server describes it, in whatever coordinate space
/// the caller chose (the capture overlay uses each display's own top-left
/// points space, the same space its selection rectangle lives in).
public struct ScreenWindow: Hashable, Sendable, Codable {
    /// The window server's id for the window.
    public var id: Int
    public var frame: CGRect
    /// The window server's layer: 0 is a normal app window; the menu bar, the
    /// Dock, menus and floating panels sit on other layers.
    public var layer: Int
    public var alpha: Double
    /// The owning app's name, for the highlight's label. Empty when unknown.
    public var ownerName: String
    /// The window's title, for telling one of an app's windows from another.
    /// Empty when unknown: the window server only names windows for clients
    /// holding the Screen Recording grant.
    public var title: String

    public init(id: Int, frame: CGRect, layer: Int, alpha: Double, ownerName: String = "",
                title: String = "") {
        self.id = id
        self.frame = frame
        self.layer = layer
        self.alpha = alpha
        self.ownerName = ownerName
        self.title = title
    }
}

/// What the highlight pill says about a window, in parts so the app can set
/// the title in a lighter weight than the app name and the size.
public struct WindowLabel: Hashable, Sendable {
    /// The owning app's name; empty when unknown.
    public var app: String
    /// The window's title, tidied and possibly shortened; nil when there is
    /// nothing worth saying beyond the app name.
    public var title: String?
    /// "1440 × 900".
    public var size: String

    public init(app: String, title: String? = nil, size: String) {
        self.app = app
        self.title = title
        self.size = size
    }

    /// The pill's text as one line: "Safari · Apple  1440 × 900", dropping
    /// whichever of the app and the title is missing.
    public var text: String {
        let name = [app, title ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return name.isEmpty ? size : "\(name)  \(size)"
    }
}

/// Capture a window by clicking it: which window sits under the pointer during
/// a region capture, what a click (as opposed to a drag) is, and what the
/// highlight says about the window it found.
public enum WindowPick {

    /// Windows narrower or shorter than this are helper specks, never
    /// something a person meant to capture.
    public static let minimumSide: CGFloat = 8

    /// How far the pointer may travel between press and release and still be
    /// a click on the window under it rather than the start of a region drag.
    public static let dragThreshold: CGFloat = 4

    /// The frontmost pickable window containing `point`. `windows` is
    /// front-to-back, the order the window server lists them in. `excluding`
    /// names windows that can never be the answer, such as the capture
    /// overlay's own full-screen shield panels.
    public static func frontmost(at point: CGPoint, in windows: [ScreenWindow],
                                 excluding: Set<Int> = []) -> ScreenWindow? {
        windows.first { isPickable($0, excluding: excluding) && $0.frame.contains(point) }
    }

    /// A normal-layer, visible, non-excluded window big enough to mean something.
    public static func isPickable(_ window: ScreenWindow, excluding: Set<Int> = []) -> Bool {
        window.layer == 0
            && window.alpha > 0
            && !excluding.contains(window.id)
            && window.frame.width >= minimumSide
            && window.frame.height >= minimumSide
    }

    /// Whether a press at `from` released at `to` counts as a click.
    public static func isClick(from: CGPoint, to: CGPoint) -> Bool {
        abs(to.x - from.x) < dragThreshold && abs(to.y - from.y) < dragThreshold
    }

    /// The part of `window` that exists on a display with `bounds`, snapped to
    /// whole points so the crop lands on pixel boundaries. Nil when the window
    /// is not on that display at all.
    public static func captureRect(for window: ScreenWindow, within bounds: CGRect) -> CGRect? {
        let visible = window.frame.integral.intersection(bounds)
        guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { return nil }
        return visible
    }

    /// The pill is never wider than this, however wide the window: a title
    /// that runs on past it is shortened.
    public static let maxLabelWidth: CGFloat = 400

    /// A shortened title keeps at least this many characters before its
    /// ellipsis; anything less says nothing and is dropped instead.
    public static let minimumTitleLength = 3

    /// "Safari · Apple  1440 × 900": the app, the window's title when it adds
    /// something, and the size. Just the size when the owner is unknown.
    public static func label(for window: ScreenWindow, includingTitle: Bool = true) -> WindowLabel {
        let app = window.ownerName.trimmingCharacters(in: .whitespaces)
        let title = includingTitle ? displayTitle(window.title, app: app) : nil
        return WindowLabel(app: app, title: title, size: sizeLabel(for: window.frame.size))
    }

    /// The window's title as the pill should show it, or nil when it would
    /// only repeat the app's name. Whitespace and line breaks are tidied, and
    /// an app name the title carries at either end ("Apple - Microsoft Edge",
    /// "Photonz — Untitled") goes, since the pill names the app already.
    public static func displayTitle(_ raw: String, app: String) -> String? {
        var title = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let name = app.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            let separators = [" - ", " — ", " – ", " | "]
            var stripped = true
            while stripped {
                stripped = false
                for separator in separators {
                    let tail = separator + name
                    if title.lowercased().hasSuffix(tail.lowercased()) {
                        title = String(title.dropLast(tail.count))
                        stripped = true
                    }
                    let head = name + separator
                    if title.lowercased().hasPrefix(head.lowercased()) {
                        title = String(title.dropFirst(head.count))
                        stripped = true
                    }
                }
            }
            title = title.trimmingCharacters(in: .whitespaces)
            // The app name alone, or the name with a stray separator: nothing new.
            let bare = ["", "-", "—", "–", "|"]
            if title.lowercased().hasSuffix(name.lowercased()),
               bare.contains(String(title.dropLast(name.count)).trimmingCharacters(in: .whitespaces)) {
                return nil
            }
            if title.lowercased().hasPrefix(name.lowercased()),
               bare.contains(String(title.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)) {
                return nil
            }
        }
        return title.isEmpty ? nil : title
    }

    /// The label for `window` no wider than `maxWidth` as `measure` sees it:
    /// the title is shortened with a trailing ellipsis until the whole label
    /// fits, and dropped when fewer than `minimumTitleLength` characters of
    /// it would survive. The app and the size are never shortened, so a label
    /// that cannot fit even without the title comes back whole regardless.
    public static func label(for window: ScreenWindow, fitting maxWidth: CGFloat,
                             measure: (WindowLabel) -> CGFloat) -> WindowLabel {
        let full = label(for: window)
        guard let title = full.title, measure(full) > maxWidth else { return full }
        let plain = WindowLabel(app: full.app, title: nil, size: full.size)
        let characters = Array(title)
        func shortened(_ count: Int) -> String? {
            let kept = String(characters.prefix(count)).trimmingCharacters(in: .whitespaces)
            return kept.count >= minimumTitleLength ? kept + "…" : nil
        }
        func fits(_ count: Int) -> Bool {
            guard let short = shortened(count) else { return false }
            return measure(WindowLabel(app: full.app, title: short, size: full.size)) <= maxWidth
        }
        // The longest prefix that fits, found by bisection: fits(n) is
        // monotone in n for any measure that grows with the text.
        var low = 0, high = characters.count - 1
        guard high >= minimumTitleLength, fits(minimumTitleLength) else { return plain }
        low = minimumTitleLength
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(mid) { low = mid } else { high = mid - 1 }
        }
        guard let short = shortened(low) else { return plain }
        return WindowLabel(app: full.app, title: short, size: full.size)
    }

    /// The label for `window` sized for where `labelOrigin` will put it. When
    /// the plain app-and-size pill fits inside the window (`rect`, the part on
    /// this display) the pill lives there and the title is cut to keep it
    /// inside; otherwise the pill hangs below or above the window and the
    /// display is the limit. Never wider than `maxLabelWidth` either way.
    /// `measure` returns the pill's full size for a label, padding included.
    public static func fittedLabel(for window: ScreenWindow, in rect: CGRect, within bounds: CGRect,
                                   inset: CGFloat, measure: (WindowLabel) -> CGSize) -> WindowLabel {
        let plainSize = measure(label(for: window, includingTitle: false))
        let insideWindow = rect.width >= plainSize.width + inset * 2
            && rect.height >= plainSize.height + inset * 2
        let room = (insideWindow ? rect.width : bounds.width) - inset * 2
        return label(for: window, fitting: min(maxLabelWidth, room)) { measure($0).width }
    }

    /// "1440 × 900", in whole points.
    public static func sizeLabel(for size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    /// Where the highlight's label goes: tucked inside the window's top-left
    /// corner when it fits, otherwise just below the window, or above it when
    /// the window sits at the bottom of the display. Always kept on the display.
    public static func labelOrigin(for frame: CGRect, labelSize: CGSize, inset: CGFloat,
                                   within bounds: CGRect) -> CGPoint {
        var origin: CGPoint
        if frame.width >= labelSize.width + inset * 2, frame.height >= labelSize.height + inset * 2 {
            origin = CGPoint(x: frame.minX + inset, y: frame.minY + inset)
        } else if frame.maxY + inset + labelSize.height <= bounds.maxY {
            origin = CGPoint(x: frame.minX, y: frame.maxY + inset)
        } else {
            origin = CGPoint(x: frame.minX, y: frame.minY - inset - labelSize.height)
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - labelSize.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - labelSize.height)
        return origin
    }
}
