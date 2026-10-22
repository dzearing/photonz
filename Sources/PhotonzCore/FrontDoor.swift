import CoreGraphics
import Foundation

/// What File > New makes: an Image or a Video, and nothing else.
///
/// The user's call on 2026-10-22, over the front door mock's four templates
/// and its Open buttons ("Sometimes i just want to create an image", "new
/// should not have load image in it", "use straightforward IA"). Opening a
/// file is File > Open, capturing is the capture keys, and a UI design is the
/// Design mode and the Library's Components inside an image.
public enum FrontDoorKind: String, CaseIterable, Sendable {
    case image, video

    /// What the New window opens on, so Return alone makes a picture.
    public static let `default`: FrontDoorKind = .image

    /// What the choice says.
    public var title: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        }
    }

    /// The primary button with this kind picked.
    public var createTitle: String { "New \(title)" }

    /// The row the empty window's card shows for it, in the card's sentence
    /// case ("Open a file", "Paste an image").
    public var cardTitle: String { "New \(title.lowercased())" }

    /// The SF Symbol the choice draws. A plain name, so this file stays pure.
    public var symbol: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        }
    }

    /// The mode the new window starts in (`WindowModes`).
    public var modeID: String {
        switch self {
        case .image: WindowModes.imageID
        case .video: WindowModes.videoID
        }
    }

    /// The sizes offered, the same lists the New Image and New Video sheets
    /// offer, so the two ways in never disagree.
    public var sizes: [FrontDoorSize] {
        switch self {
        case .image: BlankCanvas.presets.map { FrontDoorSize(id: $0.id, title: $0.title, size: $0.size) }
        case .video: BlankVideo.presets.map { FrontDoorSize(id: $0.id, title: $0.title, size: $0.size) }
        }
    }

    /// The size the window opens on for this kind.
    public var defaultSize: CGSize {
        switch self {
        case .image: BlankCanvas.defaultPreset.size
        case .video: BlankVideo.defaultPreset.size
        }
    }

    /// Whether this kind asks how long it is.
    public var hasLength: Bool { self == .video }

    /// Whether a typed size can be made as it stands: the primary button's
    /// enablement.
    public func isValid(_ size: CGSize) -> Bool {
        switch self {
        case .image: BlankCanvas.isValid(size)
        case .video: BlankVideo.isValid(size)
        }
    }
}

/// One size on offer in the New window.
public struct FrontDoorSize: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let size: CGSize
}

/// The New window's words.
public enum FrontDoor {
    /// The title bar, as the mock draws it: the app's name, then "· New".
    public static let subtitle = "New"
    public static let sizeHeader = "Size"
    public static let customTitle = "Custom"
    public static let lengthTitle = "Length"
    /// The prompt bar's placeholder. The mock's line, with its example, is
    /// the field's tip.
    public static let promptPlaceholder = "Describe what to create"
    public static let promptTip =
        "Describe what you want to create \u{00B7} \u{201C}a pricing card with our brand gradient\u{201D}\u{2026}"
    /// The tip while Ask is off in this release.
    public static let promptTipNotReady = promptTip + " The agent that answers this is still to come."
    public static let createTitle = "Create"

    /// A size as the list prints it.
    public static func dimensions(_ size: CGSize) -> String {
        "\(Int(size.width)) \u{00D7} \(Int(size.height))"
    }
}
