import CoreGraphics
import Foundation

/// One thing the tool in your hand has to set, as opposed to something a layer
/// you have picked has to set.
///
/// The distinction that matters is MODE versus SETTING, drawn on 2026-08-23:
/// a mode changes what the next click DOES and lives inside the tool's own
/// button, where press-and-hold reaches it whatever else is on screen. A
/// setting changes what the drag PRODUCES, and until now it lived only in the
/// right hand panel, so hiding the panel took it away. These are the settings
/// that were stranded.
public enum ToolSetting: String, CaseIterable, Hashable, Sendable {
    /// Whether the next zoom callout is drawn in a box or in a circle.
    case calloutShape
    /// How much the next zoom callout magnifies the region it points at.
    case calloutMagnification
    /// How far a color may drift and still join the wand's selection.
    case wandTolerance
    /// What a measure point magnetizes to: edges, or edges and centers.
    case measureSnap
    /// Which measurements the canvas draws.
    case measureShow

    /// The word on the setting, the same one the right hand panel uses, so
    /// the two places read as one thing rather than two.
    public var title: String {
        switch self {
        case .calloutShape: "Shape"
        case .calloutMagnification: "Magnification"
        case .wandTolerance: "Tolerance"
        case .measureSnap: "Snap"
        case .measureShow: "Show"
        }
    }
}

/// What the capsule above the floating tool bar carries, for a given tool.
///
/// Pure policy, so "the arrow gets no capsule" and "Measure gets Snap then
/// Show" are tested product decisions rather than whatever the view happened
/// to build. The view reads this list and lays out one control per entry.
///
/// Crop's aspect and Measure's mode are deliberately NOT here. They are modes,
/// they already live in their tool's press-and-hold list, and that list is
/// reachable with the panel hidden — repeating them would only make the
/// capsule wider over the bottom of the picture for nothing.
public enum ToolSettingsBar {

    /// Which settings this release has switched on at all. A setting behind an
    /// off flag is not shown, so the capsule never offers a control that does
    /// nothing.
    public struct Availability: Hashable, Sendable {
        public var calloutShape: Bool
        public var calloutMagnification: Bool
        public var measureSnap: Bool
        public var measureShow: Bool

        public init(calloutShape: Bool, calloutMagnification: Bool,
                    measureSnap: Bool, measureShow: Bool) {
            self.calloutShape = calloutShape
            self.calloutMagnification = calloutMagnification
            self.measureSnap = measureSnap
            self.measureShow = measureShow
        }

        public static let all = Availability(calloutShape: true, calloutMagnification: true,
                                             measureSnap: true, measureShow: true)
        public static let none = Availability(calloutShape: false, calloutMagnification: false,
                                              measureSnap: false, measureShow: false)
    }

    /// The settings `tool` puts in the capsule, in the order they are laid
    /// out. Empty means no capsule at all: no glass, no gap, nothing over the
    /// picture.
    public static func settings(for tool: Tool, availability: Availability) -> [ToolSetting] {
        switch tool {
        case .zoomCallout:
            // Shape first because it was there first: a setting added later
            // goes after the one whose position a person has already learned.
            [.calloutShape, .calloutMagnification].filter {
                $0 == .calloutShape ? availability.calloutShape : availability.calloutMagnification
            }
        case .wand:
            // The wand's tolerance answers to no flag of its own: a wand with
            // no tolerance is not a wand.
            [.wandTolerance]
        case .measure:
            [.measureSnap, .measureShow].filter {
                $0 == .measureSnap ? availability.measureSnap : availability.measureShow
            }
        default:
            []
        }
    }

    /// How a row of settings of these widths packs into `width`, as the
    /// indices on each row.
    ///
    /// The capsule floats over the picture, so it can never be wider than the
    /// picture: on a window too narrow to hold its settings side by side they
    /// stack instead. Hiding one was never an option — a setting that
    /// disappears on a narrow window is the exact disappearance this whole
    /// feature exists to end.
    ///
    /// Pure arithmetic so the packing is tested rather than trusted. Today's
    /// widest capsule (Measure's Snap and Show) fits the narrowest window the
    /// app allows, so this is insurance the next setting cannot break rather
    /// than something a person sees now.
    public static func rows(ofWidths widths: [CGFloat], spacing: CGFloat,
                            within width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var row: [Int] = []
        var used: CGFloat = 0
        for (index, itemWidth) in widths.enumerated() {
            let next = row.isEmpty ? itemWidth : used + spacing + itemWidth
            // A single setting wider than the room it has still gets its own
            // row: there is nowhere narrower to put it, and dropping it would
            // take the setting away.
            if !row.isEmpty, next > width {
                rows.append(row)
                row = [index]
                used = itemWidth
            } else {
                row.append(index)
                used = next
            }
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}
