import Foundation

/// The part of the app a feature flag changes. Every flag in the catalog names
/// one, and the Experiments window draws its flags under these headings in the
/// order the cases are written here, so the list reads as a map of what a
/// release contains rather than the order somebody happened to add things.
///
/// The order is deliberate: roughly the way you meet the app. A picture comes
/// in, you work on it, you measure and draw on it, you reuse and animate
/// pieces of it, you send it out, and last comes the app around all of that.
public enum FeatureArea: String, Codable, Sendable, Hashable, CaseIterable {
    case capture
    case canvas
    case selecting
    case layers
    case separating
    case clipboard
    case measuring
    case drawing
    case panel
    case appearance
    case layout
    case tools
    case library
    case icons
    case motion
    case export
    case app

    /// The heading the Experiments window draws. Plain words for a part of the
    /// app, not a code name.
    public var title: String {
        switch self {
        case .capture: "Capture"
        case .canvas: "The canvas"
        case .selecting: "Selecting and moving"
        case .layers: "Layers"
        case .separating: "Separating a screenshot"
        case .clipboard: "Copy and paste"
        case .measuring: "Measure and redline"
        case .drawing: "Drawing"
        case .panel: "The panel"
        case .appearance: "Appearance and color"
        case .layout: "Layout and alignment"
        case .tools: "Tools"
        case .library: "Library and components"
        case .icons: "Icons"
        case .motion: "Motion and video"
        case .export: "Export"
        case .app: "The app itself"
        }
    }

    /// Display order, which is declaration order.
    public static var displayOrder: [FeatureArea] { allCases }
}

/// One heading's worth of flags in the Experiments window: the area and the
/// flags that belong to it, already in catalog order.
public struct FeatureFlagGroup: Sendable, Hashable, Identifiable {
    public let area: FeatureArea
    public let flags: [FeatureFlag]

    public var id: String { area.rawValue }

    public init(area: FeatureArea, flags: [FeatureFlag]) {
        self.area = area
        self.flags = flags
    }
}
