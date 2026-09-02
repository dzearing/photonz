import Foundation

/// Every feature flag the app knows about, and which releases each one appears
/// in. This is the source of truth: storage only ever holds enabled bits and
/// parameter values, so adding, renaming or retiring a flag here is safe —
/// `FeatureFlagSettings.reconciled(with:)` folds old state onto the new list.
///
/// Adding a flag: append a `Definition` below with the releases it belongs to
/// and where it starts on. Read it at the call site through the app's
/// `Experiments` object. Remember the porting rule: every change to Current has
/// to reach Next, and nothing in Next is ever back-ported (see
/// `docs/design/experiments.md`).
public enum FeatureCatalog {

    // MARK: - Names (stable identifiers; call sites use these, never literals)

    public static let releaseTagFlag = "release-tag-in-window-title"
    public static let releaseTagLabel = "label"
    public static let releaseTagPlacement = "placement"
    public static let releaseTagUppercase = "uppercase"

    public static let captureToastTimingFlag = "capture-toast-timing"
    public static let captureToastHold = "hold"
    public static let captureToastFade = "fade"

    /// The built-in toast timing, used whenever the flag is off. Kept here so
    /// the flag's defaults and the app's own behavior can't drift apart.
    public static let captureToastHoldSeconds: Double = 7
    public static let captureToastFadeSeconds: Double = 3

    public static let captureToastEditFlag = "next-capture-toast-edit"

    public static let measureModesFlag = "next-measure-modes"

    public static let measureAlignFlag = "next-measure-align"
    public static let measureAlignTolerance = "tolerance"

    public static let measureCenterSnapFlag = "next-measure-center-snap"

    public static let measureGuideSnapFlag = "next-measure-guide-snap"

    public static let measureReadoutSlideFlag = "next-measure-readout-slide"

    public static let measureRolesFlag = "next-measure-roles"

    public static let measurePanelFlag = "next-measure-panel"

    public static let arrowCaptionsFlag = "next-arrow-captions"

    public static let grabCueFlag = "next-grab-cue"

    public static let toolOptionsFlag = "next-tool-options"

    public static let toolGroupsFlag = "next-tool-groups"

    public static let toolBarFeedbackFlag = "next-tool-bar-feedback"

    public static let toolTipsFlag = "next-tool-tips"

    public static let windowCaptureFlag = "next-window-capture"
    public static let windowCaptureShadow = "shadow"

    public static let captureLoupeFlag = "next-capture-loupe"
    public static let captureLoupePixels = "pixels"

    // MARK: - Definitions

    private struct Definition {
        let flag: FeatureFlag
        /// Releases this flag shows up in at all.
        let releases: Set<Release>
        /// Releases it starts switched on in.
        let enabledByDefaultIn: Set<Release>
    }

    private static func definitions(for release: Release) -> [Definition] {
        [
            Definition(
                flag: FeatureFlag(
                    name: releaseTagFlag,
                    title: "Release tag in window titles",
                    description: "Adds the release name to editor window titles, so you can tell at a glance which experience a window is running.",
                    isEnabled: false,
                    parameters: [
                        FeatureParameter(name: releaseTagLabel, label: "Tag text",
                                         value: .string(release.title)),
                        FeatureParameter(name: releaseTagPlacement, label: "Position",
                                         value: .enumeration(cases: ReleaseTag.Placement.allNames,
                                                             selection: ReleaseTag.Placement.suffix.name)),
                        FeatureParameter(name: releaseTagUppercase, label: "All caps",
                                         value: .boolean(false)),
                    ]),
                releases: [.current, .next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: captureToastTimingFlag,
                    title: "Capture toast timing",
                    description: "Sets how long the toast after a capture stays on screen and how slowly it fades. Off means the built-in timing.",
                    isEnabled: false,
                    parameters: [
                        FeatureParameter(name: captureToastHold, label: "Hold (seconds)",
                                         value: .number(captureToastHoldSeconds),
                                         bounds: NumberBounds(minimum: 1, maximum: 30, step: 1)),
                        FeatureParameter(name: captureToastFade, label: "Fade (seconds)",
                                         value: .number(captureToastFadeSeconds),
                                         bounds: NumberBounds(minimum: 0, maximum: 15, step: 1)),
                    ]),
                releases: [.current, .next],
                enabledByDefaultIn: []),
            Definition(
                flag: FeatureFlag(
                    name: captureToastEditFlag,
                    title: "Edit from the capture toast",
                    description: "The toast after a capture shows an Edit button under the picture and names its key, Shift Command 6, so the way into the editor is on screen without hovering. Off means Edit only appears while the pointer is over the toast.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureModesFlag,
                    title: "Measure modes",
                    description: "The Measure tool gets modes you pick in its own tool button: Distance is the two-point caliper and draws nothing until you click, Size measures the element under the pointer in one click (with [ and ] to grow or shrink the pick), and Gap turns a click in the space between two elements into one spacing measurement. Off means the Measure tool is the plain two-point caliper.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureAlignFlag,
                    title: "Alignment checks",
                    description: "Adds an Alignment mode to the Measure tool: drag a guide along an edge and every element it crosses is checked. The guide reads aligned, or calls out the element that is off and by how much.",
                    isEnabled: false,
                    parameters: [
                        FeatureParameter(name: measureAlignTolerance, label: "Tolerance (px)",
                                         value: .number(1),
                                         bounds: NumberBounds(minimum: 0, maximum: 8, step: 0.5)),
                    ]),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: arrowCaptionsFlag,
                    title: "Arrow captions",
                    description: "Right after you draw an arrow, type a label and it lands in a pill at the arrow's tail, styled like the measure readout. Press Esc to skip, or drag again to draw the next arrow. Double-click an arrow to add or edit its caption.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: grabCueFlag,
                    title: "Grab cue on draggable pills",
                    description: "Some pills on the canvas can be dragged on their own: an arrow's caption, and a measurement's number. When the pointer rests on one of them, it becomes an open hand, and a closed hand while you drag, so the drag is findable without being told about it.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureRolesFlag,
                    title: "Measurement roles",
                    description: "Each measurement is a Size or a Spacing callout with its own remembered colors. Adds a Role control to the measure inspector, a legend on the canvas while the tool is active, and a Show filter in the Measure Tool section of the inspector.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measurePanelFlag,
                    title: "Measurements panel",
                    description: "Lists every measurement in the layers panel with its own eye, name, and value, adds a count to the toolbar, and puts From, To, Distance, and export shortcuts in the inspector. The panel menu can show, hide, or clear them all, or copy them as a text spec list.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureCenterSnapFlag,
                    title: "Snap to centers",
                    description: "Adds a Snap option to the Measure Tool section of the inspector. With Edges and centers, measure points also magnetize to element and gap centers, the midpoint between neighboring edges. Hold Command to drag free.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureGuideSnapFlag,
                    title: "Snap to other measurements",
                    description: "Measurements line up with each other. Drag a readout chip and it snaps into line with the other chips on the picture; drag a foot and it snaps to the feet and lines of the other measurements, so two calipers can share a start line. The yellow guide shows what it lined up with. Hold Command to drag free.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureReadoutSlideFlag,
                    title: "Slide a measurement's number along its line",
                    description: "Dragging the number moves it both ways: away from the measurement as before, and now left and right along it too. Slide a number and it stays exactly where you put it. Off means the number can only be pushed away from what it measures.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: windowCaptureFlag,
                    title: "Capture a window by clicking it",
                    description: "During a region capture, the window under the pointer lights up with its app, its window title and its size. Click it to capture exactly that window, the way the built-in window capture does: its shadow around it and see-through rounded corners. Hold Option while clicking for the other choice. Drag to select a region as before. Off means the overlay is drag only.",
                    isEnabled: false,
                    parameters: [
                        FeatureParameter(name: windowCaptureShadow, label: "Include the window shadow",
                                         value: .boolean(true)),
                    ]),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: captureLoupeFlag,
                    title: "Loupe during a region capture",
                    description: "While you pick or drag a capture region, a small magnified view beside the pointer shows the pixels under it, boxes the one the crop will land on, and reads out the pointer's position in points and pixels plus the selection's size. It keeps to the outside of the box you are drawing and steps aside near the edge of the display. Off means the plain crosshair.",
                    isEnabled: false,
                    parameters: [
                        FeatureParameter(name: captureLoupePixels, label: "Pixels across",
                                         value: .number(Double(CaptureLoupe.defaultPixelsAcross)),
                                         bounds: NumberBounds(minimum: 11, maximum: 51, step: 2)),
                    ]),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolOptionsFlag,
                    title: "Tool options off the tool bar",
                    description: "Picking up the Crop tool or the Magic Wand stops widening the floating tool bar. Crop keeps its aspect locks inside its own tool button and shows Cancel and Crop on the canvas while a crop is live; the wand's tolerance moves to a Magic Wand section in the inspector. Off means both tools lay their options out along the bar, which grows it and pushes tools into the overflow menu on a narrow window.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolGroupsFlag,
                    title: "Tool bar families",
                    description: "The floating tool bar groups its tools into families in a fixed order: pick, cut and measure the picture; draw on it; paint it. Line, Rectangle and Ellipse share one Shapes button that remembers the last one you used (Shift plus their letter cycles), and Resize Image moves into the Crop button's list and the Image menu. Off means one button per tool in the old order.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolBarFeedbackFlag,
                    title: "Tool bar buttons respond to the pointer",
                    description: "Pointing at a tool in the floating tool bar shows the soft fill every other icon button in the app shows, and pressing one shows the stronger fill with a slight shrink. The tool in hand keeps its accent circle and still lights up under the pointer. Off means the buttons sit still until clicked.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolTipsFlag,
                    title: "Tools explain themselves with a tooltip",
                    description: "Resting the pointer on a tool in the floating tool bar shows a small label with the tool's name and the key that picks it, in the app's own tooltip style: it appears once the pointer has been still for a moment, follows the pointer from tool to tool without flicker, and never gets in the way of a click. Off means the buttons show the plain system help tag, which may not appear at all.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
        ]
    }

    // MARK: - Lookup

    /// The flags this release offers, in dialog order, with their defaults.
    public static func flags(for release: Release) -> [FeatureFlag] {
        definitions(for: release)
            .filter { $0.releases.contains(release) }
            .map { definition in
                var flag = definition.flag
                flag.isEnabled = definition.enabledByDefaultIn.contains(release)
                return flag
            }
    }

    /// A fresh, untouched state for one release.
    public static func defaultSettings(for release: Release) -> FeatureFlagSettings {
        FeatureFlagSettings(flags: flags(for: release))
    }
}
