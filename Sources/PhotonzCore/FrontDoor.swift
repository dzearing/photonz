import Foundation

/// A starting template on the front door New Window opens
/// (`docs/design/mocks/pages/ui-entry-wt.html`, steps 2 to 4).
///
/// A template is a MODE PRESET, never a document type (the user's call on
/// 2026-09-15, `work-out-whether-the-app-needs-project-types-at`): picking one
/// puts the window in a mode and names what the primary button will make.
/// Nothing about it is written into the document, so a file made from Design
/// UI is an ordinary file that opens anywhere without a question.
public enum FrontDoorTemplate: String, CaseIterable, Sendable {
    case designUI, editImage, editVideo, captureRedline

    /// What the tile says, in the mock's words.
    public var title: String {
        switch self {
        case .designUI: "Design UI"
        case .editImage: "Edit an image"
        case .editVideo: "Edit video"
        case .captureRedline: "Capture & redline"
        }
    }

    /// The line the mock prints under the title, word for word.
    public var mockDetail: String {
        switch self {
        case .designUI: "Components, tokens, auto-layout"
        case .editImage: "Adjust, mask, retouch, effects"
        case .editVideo: "Timeline, transitions, captions"
        case .captureRedline: "\u{21E7}\u{2318}4 \u{00B7} measure + annotate"
        }
    }

    /// The line the tile draws: the mock's, when it fits the chrome budget,
    /// and nothing when it does not. A line over the budget moves into the
    /// tile's tip in the mock's words (UX-PATTERNS §4).
    public var detail: String? {
        mockDetail.count <= CopyBudget.chromeLine ? mockDetail : nil
    }

    /// What the tile says under the pointer.
    public var tip: String {
        "\(title): \(mockDetail)"
    }

    /// The SF Symbol the tile draws. A plain name, so this file stays pure.
    public var symbol: String {
        switch self {
        case .designUI: "square.on.square"
        case .editImage: "photo"
        case .editVideo: "play.fill"
        case .captureRedline: "ruler"
        }
    }

    /// The mode the window goes into (`WindowModes`). Edit an image has no
    /// mode of its own, so it is the mode that folds nothing.
    public var modeID: String {
        switch self {
        case .designUI: "design"
        case .editImage: WindowModes.everythingID
        case .editVideo: "video"
        case .captureRedline: "redline"
        }
    }
}

/// The front door's words and its one rule: what the primary button says.
public enum FrontDoor {
    /// The title bar, as the mock draws it: the app's name, then "· New".
    public static let subtitle = "New"
    public static let openTitle = "Open\u{2026}"
    /// The mock's "Start a project · pick a template" is over the chrome
    /// budget, so the label is its first half and the rest is the tip.
    public static let startHeader = "Start a project"
    public static let startHeaderTip = "Start a project \u{00B7} pick a template"
    public static let recentHeader = "Recent"
    /// The prompt bar's placeholder. The mock's line, with its example, is
    /// the field's tip.
    public static let promptPlaceholder = "Describe what to create"
    public static let promptTip =
        "Describe what you want to create \u{00B7} \u{201C}a pricing card with our brand gradient\u{201D}\u{2026} "
        + "The agent that answers this is still to come."
    public static let createTitle = "Create"

    /// What the primary button makes with `picked` chosen, or with nothing
    /// chosen yet. The mock gives Design UI's; the others name their own job
    /// the same way.
    public static func primaryTitle(picked: FrontDoorTemplate?) -> String {
        switch picked {
        case nil: "New canvas"
        case .designUI?: "New UI canvas"
        case .editImage?: "Open Image\u{2026}"
        case .editVideo?: "New Video\u{2026}"
        case .captureRedline?: "Capture"
        }
    }

    /// How many captures Recent shows. The mock draws three in a window 640
    /// wide; four still fit and make the row read as a strip.
    public static let recentCount = 4

    /// The captures Recent shows: the newest few, in the order history lists
    /// them, and none at all when there are none (an empty state is empty).
    public static func recent(_ entries: [CaptureEntry]) -> [CaptureEntry] {
        Array(entries.prefix(recentCount))
    }
}
