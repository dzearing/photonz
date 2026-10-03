// What system alerts are on screen, for Scripts/probe-crash-alert.mjs.
//
//   swift Scripts/system-alerts.swift
//   maxWindowId=735262          the newest window number anywhere on the Mac
//   alert=735262                one line per alert window on screen now
//
// An alert here is a window of UserNotificationCenter, the system process that
// draws "Photonz (Probe) quit unexpectedly" (and other apps' alerts). Window
// numbers only ever count up, so an alert numbered above the newest window at
// the probe's launch was put up after that launch.
//
// Needs no grant: a window's owner and number are readable without Screen
// Recording, only its title is not, and nothing here reads a title.
import CoreGraphics
import Foundation

let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let newest = all.compactMap { $0[kCGWindowNumber as String] as? Int }.max() ?? 0
print("maxWindowId=\(newest)")

let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in onScreen where (window[kCGWindowOwnerName as String] as? String) == "UserNotificationCenter" {
    if let id = window[kCGWindowNumber as String] as? Int { print("alert=\(id)") }
}
