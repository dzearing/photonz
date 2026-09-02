import AppKit
import PhotonzCore

/// The window server's list of on-screen windows, front to back, for the
/// capture overlay's window picking (`WindowPick`). Listed once when the
/// overlay freezes the screen, so the highlight always agrees with the frozen
/// picture underneath it.
@MainActor
enum WindowLister {

    /// Every on-screen window (this Space, desktop elements excluded), front
    /// to back, with frames in CG global coordinates: primary display top-left
    /// origin, y down, points. Filtering to what is pickable is `WindowPick`'s
    /// job, so this list keeps the menu bar, panels and helpers.
    static func onScreenWindows() -> [ScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            return ScreenWindow(
                id: number,
                frame: bounds,
                layer: info[kCGWindowLayer as String] as? Int ?? 0,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
                // Only populated for clients with the Screen Recording grant.
                title: info[kCGWindowName as String] as? String ?? "")
        }
    }

    /// The same windows with frames in `screen`'s own top-left-origin points
    /// space, the space the selection overlay covering that screen draws in.
    /// Windows that do not touch the screen are dropped.
    static func windows(_ windows: [ScreenWindow], localTo screen: NSScreen) -> [ScreenWindow] {
        // NSScreen frames are global Cocoa coords (primary bottom-left origin,
        // y up); CG global space shares X and flips Y at the primary's top.
        let primaryMaxY = NSScreen.screens[0].frame.maxY
        let originX = screen.frame.minX
        let originY = primaryMaxY - screen.frame.maxY
        let local = CGRect(origin: .zero, size: screen.frame.size)
        return windows.compactMap { window in
            var converted = window
            converted.frame = window.frame.offsetBy(dx: -originX, dy: -originY)
            return converted.frame.intersects(local) ? converted : nil
        }
    }
}
