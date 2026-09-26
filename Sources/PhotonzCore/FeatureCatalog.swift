import Foundation

/// Every feature flag the app knows about, and which releases each one appears
/// in. This is the source of truth: storage only ever holds enabled bits and
/// parameter values, so adding, renaming or retiring a flag here is safe —
/// `FeatureFlagSettings.reconciled(with:)` folds old state onto the new list.
///
/// Adding a flag: append a `Definition` below with the part of the app it
/// changes (`area:`), the releases it belongs to and where it starts on. The
/// area is what the Experiments window groups by, so a flag without one is a
/// compile error rather than a row that lands in a pile. Read it at the call site through the app's
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

    public static let measureLayerSnapFlag = "next-measure-layer-snap"

    public static let measureReadoutSlideFlag = "next-measure-readout-slide"

    public static let measureRolesFlag = "next-measure-roles"

    public static let measurePanelFlag = "next-measure-panel"

    public static let arrowCaptionsFlag = "next-arrow-captions"

    public static let shapePartsFlag = "next-shape-parts"

    public static let panelSectionsFlag = "next-panel-sections"

    public static let windowModesFlag = "next-window-modes"

    public static let cornerHandlesFlag = "next-corner-handles"

    public static let grabCueFlag = "next-grab-cue"

    public static let edgeGrabFlag = "next-edge-grab"

    public static let toolOptionsFlag = "next-tool-options"

    public static let toolSettingsFlag = "next-tool-settings"

    public static let toolGroupsFlag = "next-tool-groups"

    public static let toolBarFeedbackFlag = "next-tool-bar-feedback"

    public static let toolTipsFlag = "next-tool-tips"

    public static let blankCanvasFlag = "next-blank-canvas"

    public static let windowCaptureFlag = "next-window-capture"
    public static let windowCaptureShadow = "shadow"

    public static let geometryFieldsFlag = "next-geometry-fields"

    public static let layerGroupsFlag = "next-layer-groups"

    public static let layersFollowPickFlag = "next-layers-follow-pick"

    public static let canvasMenuFlag = "next-canvas-menu"

    public static let alignLayersFlag = "next-align-layers"

    public static let framesFlag = "next-frames"

    public static let iconFramesFlag = "next-icon-frames"

    public static let iconPreviewsFlag = "next-icon-previews"

    public static let libraryFlag = "next-library"

    public static let componentsFlag = "next-components"

    public static let stylesFlag = "next-styles"

    public static let starterComponentsFlag = "next-starter-components"

    public static let sharedLibraryFlag = "next-shared-library"

    public static let placementFlag = "next-placement"

    public static let autoLayoutFlag = "next-auto-layout"

    public static let colorPickerFlag = "next-color-picker"

    public static let colorDragFlag = "next-color-drag"

    public static let crispZoomFlag = "next-crisp-zoom"

    public static let calloutShapeFlag = "next-callout-shape"

    public static let calloutMagnificationFlag = "next-callout-magnification"

    public static let canvasGridFlag = "next-canvas-grid"

    public static let copyPicksYourLayerFlag = "next-copy-picks-your-layer"

    public static let pasteHandsYouThePointerFlag = "next-paste-hands-you-the-pointer"

    public static let cutSaysWhatItCannotDoFlag = "next-cut-says-what-it-cannot-do"

    public static let selectionUndoFlag = "next-undo-puts-back-your-marquee"

    public static let settingsWindowFlag = "next-settings-window"

    public static let marqueeIntentFlag = "next-a-box-says-what-it-picks"

    public static let layerBoxIsItsPixelsFlag = "next-a-layer-is-its-pixels"

    public static let lensFlag = "next-lens"

    public static let penFlag = "next-pen"

    public static let drawLandingFlag = "next-where-the-point-will-land"

    public static let dragReadoutFlag = "next-a-drag-says-its-numbers"

    public static let reshapePathFlag = "next-reshape-a-path"

    public static let turnIntoPathFlag = "next-turn-into-path"

    public static let svgExportFlag = "next-export-svg"

    public static let blendModeFlag = "next-blend-mode"

    public static let layersCombineFlag = "next-layers-combine"

    public static let tutorialsFlag = "next-tutorials"

    public static let setupTakesNoForAnAnswerFlag = "next-setup-takes-no-for-an-answer"

    public static let separateIntoLayersFlag = "next-separate-into-layers"

    public static let doubleClickReadsALabelFlag = "next-double-click-reads-a-label"

    public static let readEveryLabelFlag = "next-read-every-label"

    public static let newLayerViaCutFlag = "next-new-layer-via-cut"

    public static let copyALookFlag = "next-copy-a-look"

    public static let motionFlag = "next-motion"

    public static let motionStripFlag = "next-motion-strip"

    public static let exportQualityFlag = "next-export-quality"

    public static let webPExportFlag = "next-export-webp"

    public static let animatedSVGExportFlag = "next-export-animated-svg"

    public static let cutRecordingFlag = "next-cut-a-recording"

    public static let recordingIsADocumentFlag = "next-a-recording-is-a-document"

    public static let openingARecordingFlag = "next-opening-a-recording"

    public static let droppingMediaFlag = "next-dropping-a-sound-or-a-video"

    public static let soundOnTheTimelineFlag = "next-sound-on-the-timeline"

    public static let scrubAuditionFlag = "next-hear-the-scrub"

    public static let mixLoudnessFlag = "next-the-mix-says-how-loud-it-is"

    public static let transitionsAtACutFlag = "next-transitions-at-a-cut"

    public static let punchInFlag = "next-punch-in-and-hold"

    public static let titleOnTheTimelineFlag = "next-a-title-has-an-in-and-an-out"

    public static let captionsFromTheSoundFlag = "next-captions-from-the-sound"

    public static let componentOnTheTimelineFlag = "next-a-component-on-the-timeline"

    public static let drawnOnTheTimelineFlag = "next-anything-drawn-on-a-video-is-on-the-timeline"

    public static let recordingExportSheetFlag = "next-recording-export-sheet"

    public static let videoExportFlag = "next-export-the-video"

    public static let timelineZoomFlag = "next-open-out-the-timeline"

    public static let savingARecordingSaysSoFlag = "next-saving-a-recording-says-so"

    public static let lineEndsFlag = "next-line-ends"

    public static let rowSaysItsWordsFlag = "next-a-row-says-its-words"

    public static let separatedRowSaysItsWordsFlag = "next-a-separated-row-says-its-words"

    public static let findALayerFlag = "next-find-a-layer"

    public static let separationArrivesShutFlag = "next-a-separation-arrives-shut"

    public static let whatIsLeftInThePictureFlag = "next-what-a-separation-left-behind"

    public static let timelineIsTheLayerListFlag = "next-the-timeline-is-the-layer-list"

    // MARK: - Definitions

    private struct Definition {
        let flag: FeatureFlag
        /// Releases this flag shows up in at all.
        let releases: Set<Release>
        /// Releases it starts switched on in.
        let enabledByDefaultIn: Set<Release>
        /// Flags this one does nothing without, because what it changes only
        /// exists inside what they open. A flag on by default in a release
        /// must find everything it needs on by default there too
        /// (`FeatureDependencyTests`).
        var needs: Set<String> = []
    }

    private static func definitions(for release: Release) -> [Definition] {
        [
            Definition(
                flag: FeatureFlag(
                    name: releaseTagFlag,
                    title: "Release tag in window titles",
                    description: "Adds the release name to editor window titles, so you can tell at a glance which experience a window is running.",
                    area: .app,
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
                    area: .capture,
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
                    area: .capture,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureModesFlag,
                    title: "Measure modes",
                    description: "The Measure tool gets modes you pick in its own tool button: Distance is the two-point caliper and draws nothing until you click, Size measures the element under the pointer in one click (with [ and ] to grow or shrink the pick), and Gap turns a click in the space between two elements into one spacing measurement. Off means the Measure tool is the plain two-point caliper.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureAlignFlag,
                    title: "Alignment checks",
                    description: "Adds an Alignment mode to the Measure tool: drag a guide along an edge and every element it crosses is checked. The guide reads aligned, or calls out the element that is off and by how much.",
                    area: .measuring,
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
                    description: "Right after you draw an arrow, type a label and it lands in a pill at the arrow's tail, styled like the measure readout. Return starts another line, Command and Return lands the label, Esc skips it, and dragging again draws the next arrow. Double-click an arrow to add or edit its caption.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: shapePartsFlag,
                    title: "Appearance is what it is, Effects is what you add",
                    description: "The panel splits on one rule. Appearance, straight under Layers, holds what a shape simply HAS, always in the same order: opacity, fill, outline, and a corner radius only where there are corners. Effects, under it, starts EMPTY and is a list you add to from one plus: a shadow, a glow, an extra border, a blur. A shadow and a glow each carry a Kind, so one control throws it behind the layer or casts it into the layer, and a border carries a Position. The same kind can arrive more than once, so two shadows are two rows with their own settings, and a row can be switched off, taken out, or dragged to change what paints over what. Each row\'s own settings sit behind a rule of their own, so a shadow\'s blur can never be mistaken for the layer\'s. A rectangle\'s outline can be taken off for the first time, and a box\'s Thickness row and a picture\'s Border row are both the Outline part now.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: panelSectionsFlag,
                    title: "The panel shows the sections that matter",
                    description: "You choose which of the panel\'s sections you want. A small Sections row at the foot of the panel opens a list of every section that answers for a job rather than for every layer: the Library shelf, Measurements, Motion, Layout, Columns, Component, Arrange and Shadow. Turn one off and it stays off in every document and after a relaunch; turn one on and it stays on. Left alone, each follows one written rule: it waits until the document is doing the job it is for, so a document with no measurement in it has no Measurements section and the shelf stays away until you ask for it. What you pick never adds or removes one of them, so the panel holds still as you click from layer to layer. Beside each switch is a word saying why that section is where it is, the row says how many are hidden, and one press hands the lot back to automatic.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: windowModesFlag,
                    title: "Set the window up for the job in front of you",
                    description: "A quiet chip beside the traffic lights says what this window is set up for, and opens a list to change it: Icon, Redline, Video or Design, also on Control 1 to Control 4 and on View, Mode. Picking one folds away the panel sections that job does not need, in one go, instead of you turning them off one at a time. Nothing about it touches the document: nothing is written into the file, an old document opens with no question asked, and the layers, the selection, the zoom and every tool shortcut are exactly where you left them. Everything it folds is one visible click from coming back: a folded section is listed at the foot of the panel and says you turned this off, turning one back on by hand keeps the mode and the chip says edited, Reset This Mode puts it back, and Show Everything hands the lot back in one press. Swap away and swap back and you land on the arrangement you left, bends and all.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: cornerHandlesFlag,
                    title: "Drag a corner to round it",
                    description: "A picked shape with corners wears a small dot just inside each of its four corners. Pull one in and that corner rounds under your hand, live, while the other three stay as they are; pull it back out and the corner squares off again. Hold Option and all four go together. Letting go is one undo step, and the Corner Radius rows in the panel show what you dragged. The dot sits at the centre of the corner's curve, so it travels a point for every point your hand does rather than creeping while you drag, and a shape too small to keep its edge handles does not wear the dots at all.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: edgeGrabFlag,
                    title: "Pull the side of a label to set where it wraps",
                    description: "The outline round a picked object is the handle, not just the small squares on it. Take hold of any part of an edge and pull, and that side moves: the pointer shows the left-right or up-down arrows before you press, so you can see it coming. It matters most on a one line label, which is too short to wear a square in the middle of its side edges — until now the only way to set the width the words wrap at was to drag a corner or type a number. The middle of the object still picks it up and moves it, and a box too small to spare the room keeps its whole body for moving and offers no edges at all.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: grabCueFlag,
                    title: "Every handle says what it does",
                    description: "Rest the pointer on any handle around a selected object and it says what a press would do before you press it. An open hand over the parts that drag on their own (an arrow\'s caption, either end of a line, a measurement\'s number and its two feet), and a closed hand while you drag one. The matching resize arrows over the eight handles round a layer, round the canvas, or round the crop box. A curved arrow over the knob that turns it. Over a screen it says which of the two drags you are about to get: the hand means the screen itself travels, and it is on the screen's name at all times and on the screen's own surface once the screen is picked, while empty room that would sweep a band keeps the plain arrow.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: marqueeIntentFlag,
                    title: "A box says what it picks",
                    description: "There are two boxes you can draw on the picture and they used to look the same. One picks up the layers it encloses, so delete takes those layers away; the other picks a piece of the picture to work on, so delete clears pixels out of the layer you already had. Now they look different, from the moment you start dragging. A box that has caught nothing keeps the familiar crawling dashes. The moment it goes right round something, it stops crawling, its edge becomes one unbroken blue line, and the inside washes blue over what it is about to pick up. Shrink it back off and the dashes come straight back. A box that landed goes on wearing the look it had while you drew it.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureRolesFlag,
                    title: "Measurement roles",
                    description: "Each measurement is a Size or a Spacing callout with its own remembered colors. Adds a Role control to the Measurement section of the panel, a legend on the canvas while the tool is active, and a Show filter in the Measure Tool section of the panel.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measurePanelFlag,
                    title: "Measurements panel",
                    description: "Lists every measurement in the panel with its own eye, name, and value, adds a count to the toolbar, and puts From, To and Distance behind a Details fold in the panel, beside Copy Measurement. The panel menu can show, hide, or clear them all, or copy them as a text spec list.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureCenterSnapFlag,
                    title: "Snap to centers",
                    description: "Adds a Snap option to the Measure Tool section of the panel. With Edges and centers, measure points also magnetize to element and gap centers, the midpoint between neighboring edges. Hold Command to drag free.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureGuideSnapFlag,
                    title: "Snap to other measurements",
                    description: "Measurements line up with each other. Drag a readout chip and it snaps into line with the other chips on the picture; drag a foot and it snaps to the feet and lines of the other measurements, so two calipers can share a start line. The yellow guide shows what it lined up with. Hold Command to drag free.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureLayerSnapFlag,
                    title: "Snap to the edges of what you drew",
                    description: "A caliper foot catches the exact edge of any layer on the canvas, not just the edges found in the picture underneath. Measure a box you drew and you get its real size rather than wherever your hand landed on its outline. A known edge wins over one guessed from the picture. Hold Command to drag free.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureReadoutSlideFlag,
                    title: "Slide a measurement's number along its line",
                    description: "Dragging the number moves it both ways: away from the measurement as before, and now left and right along it too. Slide a number and it stays exactly where you put it. Off means the number can only be pushed away from what it measures.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: windowCaptureFlag,
                    title: "Capture a window by clicking it",
                    description: "During a region capture, the window under the pointer lights up with its app, its window title and its size. Click it to capture exactly that window, the way the built-in window capture does: its shadow around it and see-through rounded corners. Hold Option while clicking for the other choice. Drag to select a region as before. Off means the overlay is drag only.",
                    area: .capture,
                    isEnabled: false,
                    parameters: [
                        FeatureParameter(name: windowCaptureShadow, label: "Include the window shadow",
                                         value: .boolean(true)),
                    ]),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: geometryFieldsFlag,
                    title: "Type a layer's position and size",
                    description: "Layer \u{25B8} Position and Size\u{2026}, on Option Command P, and on a right click on the layer\u{2019}s own row: X, Y, W, H and A for everything you have picked, as numbers you can type, opened over the thing they are about and gone again the moment the number lands. A is the angle a layer has been turned to, in degrees, so a shape you turned with the knob reads back a number you can write down, and typing 0 puts it straight again. One button can be made exactly 296 by 118, and a whole row of them can be made one width, or lined up on one left edge, in a single move and a single undo. Where the picked layers differ, a field says Mixed rather than a number. Up and down arrow steps a field by 1, Shift and an arrow by 10. A number the app worked out for you, like how tall a paragraph came out or anything on a locked layer, is shown as plain text with no box around it, and clicking it says why it takes nothing. With a marquee live the numbers are the selection\u{2019}s, not the layer\u{2019}s, and say so. Off means position, size and angle are drag only.",
                    area: .layout,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: alignLayersFlag,
                    title: "Line layers up with each other",
                    description: "Two jobs at once. Select two or more layers and an Arrange row appears at the top of the panel, mirrored in the Layer menu: line their left edges, centres, right edges, tops, middles or bottoms up in one press, and with three or more, space them out evenly across or down so every gap matches. And while you drag a layer, it now sticks to the edges and centres of the other layers as well as the picture\u{2019}s, with a short line showing what it just lined up with; holding Command drags free. Off means dragging pulls to the edges and middle of the picture only, and there is no Arrange row.",
                    area: .layout,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolOptionsFlag,
                    title: "Tool options off the tool bar",
                    description: "Picking up the Crop tool or the Magic Wand stops widening the floating tool bar. Crop keeps its aspect locks inside its own tool button and shows Cancel and Crop on the canvas while a crop is live; the wand's tolerance moves to a Magic Wand section in the panel. Off means both tools lay their options out along the bar, which grows it and pushes tools into the overflow menu on a narrow window.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolSettingsFlag,
                    title: "Tool settings ride above the tool bar",
                    description: "The settings that belong to the tool in your hand, rather than to anything you have picked, get their own small capsule floating just above the tool bar: the Zoom Callout\u{2019}s shape, the Magic Wand\u{2019}s tolerance, and what Measure snaps to and shows. It is open without pressing anything, it changes as you change tools, and it disappears entirely for a tool with nothing to set, so the arrow leaves the picture clear. It is its own capsule on its own row, so the tool bar never changes width, and it wraps on a narrow window. The same settings stay in the right hand panel and the two are one thing: change either and both move. Off means these settings live only in the panel, so hiding the panel takes them away.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolGroupsFlag,
                    title: "Tool bar families",
                    description: "The floating tool bar groups its tools into families in a fixed order: pick, cut and measure the picture; draw on it; paint it. Line, Rectangle and Ellipse share one Shapes button that remembers the last one you used (Shift plus their letter cycles), and Resize Image moves into the Crop button's list and the Image menu. Off means one button per tool in the old order.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolBarFeedbackFlag,
                    title: "Tool bar buttons respond to the pointer",
                    description: "Pointing at a tool in the floating tool bar shows the soft fill every other icon button in the app shows, and pressing one shows the stronger fill with a slight shrink. The tool in hand keeps its accent circle and still lights up under the pointer. Off means the buttons sit still until clicked.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: setupTakesNoForAnAnswerFlag,
                    title: "Saying no to the setup window sticks",
                    description: "Closing the first run setup window without turning on Screen Recording is taken as an answer and remembered, so it never opens itself at you again. The Screen Recording step says \"Needed to capture\" instead of \"Required\" and says in plain words that everything else works without it, and the way out says Done rather than Not Now. Try to take a screenshot later and the capture strip tells you what is missing with a button that opens setup, and Welcome & Permissions in the menu bar opens it any time. Off means the window comes back at every single launch until the permission is on.",
                    area: .app,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: tutorialsFlag,
                    title: "Guided tutorials",
                    description: "Adds a Help menu with guided tutorials, organised in tracks, and a Tutorials window listing every guide with how long it takes and which ones you have finished. A guide opens a small sample picture of its own, puts a ring around the control it is talking about, and floats a card beside it with one short thing to read and one button. Some steps wait for you to actually do the thing before moving on. Back, Skip and close work at every step, nothing is ever blocked while a guide runs, and closing part way keeps your place. Off means no Help menu and no guides.",
                    area: .app,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolTipsFlag,
                    title: "Buttons explain themselves with a tooltip",
                    description: "Resting the pointer on a button that is only a picture shows a small label with its name and the key that presses it, in the app's own tooltip style: it appears once the pointer has been still for a moment, follows the pointer from button to button without flicker, and never gets in the way of a click. The tools in the floating bar, the panel toggle, the capture history and the row of buttons under a recording all answer this way. Off means they show the plain system help tag, which macOS draws in its own style and may not show at all.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: layersFollowPickFlag,
                    title: "The layers list follows what you pick",
                    description: "Click something on the picture and the layers list brings that layer's row into view, so what you have in your hand and what the list is showing are never two different things. It moves as little as it has to and never centres the row, a row you can already see does not move the list at all, and a layer inside a shut group opens that group first. It follows the arrow keys, a newly drawn shape and an undo that puts a selection back, the same as a click. Off means the list stays exactly where it was and the row you picked can be sitting off the bottom of a long list with nothing to say so.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: canvasMenuFlag,
                    title: "Right click the picture",
                    description: "Right click something on the picture and get a menu of what you can do with it: duplicate it, group it with the rest of what you picked, send it behind, hide it, delete it. It is the same menu the layers list on the right has always had, on the thing itself. Right clicking something you have not picked yet picks it first, the way it works everywhere else on a canvas. Right click the empty picture instead and you get what belongs there: paste, select all, zoom to fit. Off means a right click on the picture does nothing, which is how it was.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: layerGroupsFlag,
                    title: "Group what you selected",
                    description: "Select two or more layers and press Command G to make them one thing you can move, hide, lock and delete together; Shift Command G takes it apart again and leaves the pieces exactly where they were. On the canvas a click picks the whole group, and a double click goes inside it so you can pick one piece; Escape comes back out. Off means the Layer menu has no Group or Ungroup rows and a click always picks a single layer. Groups already in a document keep drawing either way.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: separateIntoLayersFlag,
                    title: "Separate a screenshot into layers",
                    description: "Right click the picture in the layers list, or use Layer then Separate into Layers, and every run of text and every box in the screenshot becomes its own layer you can pick up and move, arranged the way the screen was: a label that sat in a button comes out inside that button, so picking the button up picks the label up too. Where a piece came from, the picture is filled in with what was around it, so dragging a label off a dark button leaves the button looking untouched rather than punching a hole in it. A box that is really one flat colour comes out as a real rounded rectangle you can resize and repaint, and a card sitting on a soft shadow brings that shadow with it as a real shadow effect, so moving the card moves its shadow and the page it came off is clean. You get two things and not three: the pieces on their own layers and the picture with the gaps filled. Anything the app cannot read confidently is left in the picture and not mentioned. It is one undo step however many layers come out. A run of text that came out can then be read: right click it and choose Turn into Text and it becomes the words themselves, in the face, size and colour the screenshot was set in, sitting exactly where the old ones sat, so you can retype a label instead of covering it up. Where no face the app can set is close enough to the one in the picture, the run stays a picture and says why. Off means both commands are absent from both menus.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: doubleClickReadsALabelFlag,
                    title: "Double click a label in a separated screenshot to retype it",
                    description: "After Separate into Layers, double clicking the words on a button or a row reads them and puts the caret in them, so changing a label is one gesture instead of finding Turn into Text in a menu first. Double clicking already means \"I want to change these words\" everywhere else in the app, and this makes it mean the same thing on a label that is still a picture. The reading is the same one Turn into Text does, on the one label you pointed at, and it lands in its own step: one undo takes the reading back, a second takes back what you typed. Where no face the app can set is close enough to the one in the picture, nothing opens and a line at the bottom of the canvas says why, exactly as the menu row does. Off means a double click on a label that has not been read yet picks it and nothing more, and Turn into Text is the only way to the words.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: readEveryLabelFlag,
                    title: "Read every label in a separated screenshot at once",
                    description: "After Separate into Layers, the line at the bottom of the canvas offers to read the words in every label it found. One press turns them all into real text you can retype, and one undo press takes the whole lot back. Reading them together is also the only way the app can tell which typeface the screenshot is set in: the labels vote, every one of them is held to the family that won, and a label that family cannot account for stays a picture instead of coming back a weight heavier than the identical label beside it. The line then says how many labels are words and how many stayed pictures, so nothing goes missing quietly, and that answer is kept: pointing Turn into Text at the picture again brings the same line back at once, without reading anything a second time. The same batch is on the Layer menu and on a layer row's right click menu, so picking five labels and choosing Turn into Text reads all five rather than only the row you clicked, and picking the group a big separation arrives in reads the whole screenshot. Off means the offer is absent from the line and Turn into Text reads one label at a time.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: newLayerViaCutFlag,
                    title: "Cut a piece onto its own layer and heal behind it",
                    description: "Draw a marquee round something in a picture, press Shift Command J, and that piece lifts onto a layer of its own while the space it came from fills in with the colours that were around it. Move the piece and what it came off still looks whole, instead of showing a hole or a second copy of the same thing sitting underneath. It works for any marquee: a box, an ellipse, or a selection made with the wand. Where the surroundings are one flat colour, the space comes back exactly that colour; where they ramp evenly, the ramp carries on through the space. Where they are too busy to read, it still cuts, because you asked it to, fills with the middle colour of what was around it, and says the fill was a guess. The new layer is the size of the piece and is picked afterwards, so you can drag it straight away, and one undo puts back the piece, the hole and the fill together. It also sits in the Layer menu under New Layer via Copy, which is the same command without the healing. Off means the row and the key are absent and Command J still copies a piece to a new layer as before.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: copyALookFlag,
                    title: "Copy the look of one shape onto another",
                    description: "Pick a shape, choose Copy Look, pick one or several others and choose Paste Look, and they end up looking like the first one. It takes across the colour of every part the shape paints, the line round it and how thick that line is, how round its corners are, how see through it is, how it mixes, and everything in its Effects list. It takes across nothing about where the shape is, how big it is, which way round it is, or what it actually is, so a line pasted from a circle is still a line. It is best effort: the line round a circle lands as the line a line IS, so making a line match a circle's border is two moves, and a part the shape you paste onto does not have is skipped rather than refused. Nothing ever fails because one setting did not fit, and a line at the bottom of the canvas says what was skipped so a result that is not quite a match is explained. A colour that was wearing a saved style arrives still wearing it, so the link survives the moment it is most useful. However many shapes it reaches, one undo puts them all back. Both rows sit in the Layer menu and on a layer's right click menu, on Option Shift Command C and Option Shift Command V. Off means neither row is anywhere and the keys do nothing.",
                    area: .appearance,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: motionFlag,
                    title: "Tell a layer to change one of its properties over time",
                    description: "Adds Motion to the right hand panel, directly under Effects and read the same way: a list you add to with the plus on its header. An entry is one property of the layer you have picked that changes over time. The plus offers only what that layer actually has, each with the value it is wearing right now: where it sits, how big it is, how far it is turned, how see-through it is, what colour it is, and on a drawn line how thick that line is. There is no menu of canned motions with names like Pulse or Wiggle, because those are combinations of these and combinations are what you make. Each entry says what it goes from and to, how long after the start of the loop it begins, how long it takes, on which curve, and how often it repeats: once, three times, for ever, or for ever there and back, which is what an icon nearly always wants and what a new entry starts as. The curves are one named set with the shape drawn beside each name, from linear through the four standard eases to back, elastic and steps, plus one you draw yourself by dragging two handles. The picture plays it in the canvas, and the play button on the Motion header starts and stops the preview, as does the space bar with the picture in focus. How fast it plays is a rate you pick, full speed or a quarter or a tenth, and everything slows together: a ninety millisecond gap between two parts of one drawing is under six frames at full speed, so slowing the loop is how you judge one at all. Nothing is ever baked in: a motion is worked out at the moment the canvas is drawn, exactly like a blur or a shadow, so the layer you can still drag is the layer you drew, and every change is one step for undo. Off means no Motion section and nothing in any document moves.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: animatedSVGExportFlag,
                    title: "An animated icon leaves the app as an animated SVG",
                    description: "Export asks where the file is going before it asks for a format, because that is the question that decides whether the animation survives the trip and it is the one most people can answer. Four destinations: a web page, a README on a code host, a design tool and an app bundle. A web page gets an animated SVG, and the motion, the repeat, the curve and the colours are written into the file itself as text, so the icon keeps swinging in an image tag, stays sharp at every size and is small enough to read. The other three cannot run it: a code host cleans what it is given and gets a picture instead, and a design tool and an app take the shapes and draw their own motion. The sheet says which of those it is, and lists what makes the trip and what does not, including the one thing nothing carries: an icon in a page receives no clicks, so whatever it reacts to is the page's job. The format picker sits right where it always did and the destination simply moves it, so nothing is taken away from somebody who knows what they want. Needs SVG export and the Motion list, and a drawing with nothing moving in it exports exactly the file it did before. Off means Export never asks about the destination and an SVG is always a still one.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: recordingExportSheetFlag,
                    title: "A recording leaves through the same Export sheet as everything else",
                    description: "Saving a copy of a recording goes through the same Export sheet every picture in the app already goes through, instead of a bare system save box with the format already decided for you. Shift Command S on a recording, or Export in the Video menu, opens the sheet: MP4, GIF and HEIC sit side by side in one row rather than being three separate menu items you had to choose between before the save box appeared, and the size and frame rate preset that GIF and HEIC have moved out of a submenu and onto the sheet beside the format, where you can see what it does. The video has the same three choices, and on a video they mean something the animated formats do not: High is the recording as it is, every pixel and every frame, and the other two make it smaller to send, capping the long side at 1440 or at 960 and spending a budget the app sets rather than whatever the encoder felt like. Under the choices, one sentence saying who each is for, because High and Small say which is bigger and nothing about which you want. Under the format the sheet says how big the picture will be, how fast it runs, and how much of the recording is in it, so a trim is legible right where the file is about to be written. Under that it says what the file will weigh. An untouched recording saved as video at High is copied rather than re-encoded, so that number is exact and the export is instant; anything else is the smaller of what the app is about to allow the encoder and what this very recording already costs per second and per pixel, and the line says about, because it is an estimate and not a promise. A write long enough to wait for puts a card on screen with a bar on it and the encoder's own count of how far through it is, and a Stop that leaves no half a file behind. A GIF or a HEIC is written frame by frame into a different kind of file, and nothing about the recording predicts its size, so rather than invent a number the sheet says the size comes with the file. Cancel writes nothing. Off means Save As on a recording opens the save box straight away as it always did, and the three Export items stay in the Video menu.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: savingARecordingSaysSoFlag,
                    title: "Saving a recording says it saved",
                    description: "Saving a trimmed recording tells you it worked. Today the only sign is a small arrow on the floating controller quietly going away, and on a recording long enough for the save to take real seconds the only sign it is happening at all is a spinner the size of a fingernail in the same spot, which is easy to miss entirely. With this on, a save that writes something ends with the recording's own thumbnail in the bottom right corner saying it saved, named, in the same place copying a recording already says so, and it says it however you started the save: the arrow on the controller, Command S, or Save in the box that asks before the window closes. That last one is the reason it is a corner and not something inside the window, because by the time that save lands the window has gone. A save long enough to wait for grows a progress bar in the same corner with the recording's name on it and the encoder's own count of how far through it is. A save that takes less than about half a second shows no progress at all, so the quick ones stay quiet rather than flashing something nobody can read. Off means saving is silent again and the spinner on the controller is all there is.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: cutRecordingFlag,
                    title: "Cut a recording into pieces and drop the one you do not want",
                    description: "A recording you have just made has a start handle and an end handle, so you can shorten it from either end and that is all. If the bit you want rid of is in the middle, the only answer today is to record the whole thing again. This puts a cut wherever the playhead is: press B while it plays, or pick Split at Playhead in the Video menu, and the one clip becomes two pieces that meet at that moment. The line under the picture stops being a plain progress bar and becomes the pieces themselves, one block each, sized by how long they last, with the one you are watching lit up. Press Delete and that piece goes, and everything after it slides up to meet what came before, so there is no hole to drag shut and no silence at the join: what is left plays straight through as one recording. Nothing is thrown away while you work, because a piece is a start and an end onto the same file rather than a copy of it, so Command Z puts a cut back or brings a piece back, and only saving or exporting writes the shortened version out. Opening the trim handles keeps the pieces on screen instead of putting a plain bar back: each piece is still its own block, the part the handles would keep is lit and the part they would drop is not, so a handle coming up on a cut shows what it is about to eat into, and the count beside the scissors reads how many of the pieces the window still keeps. Off means the line under the picture is the progress bar it always was, B types nothing and Delete does nothing.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: droppingMediaFlag,
                    title: "Drop a sound or a video on the window and it lands, or says why not",
                    description: "Dragging a picture onto an open document lands it as a layer, which is the app\u{2019}s whole promise: everything is a layer. Dragging a sound file or a video onto the same window does nothing at all. The pointer shows the no-entry sign and never says why, so the first thing most people try reads as the app being broken. With this on, the gesture works for both. A sound let go on a document that runs in time lands on the timeline where the playhead is, as the same layer Add Sound would have made, ready to cut, slide, name and undo. A video let go on a document that runs in time lands as a clip over the picture, at the playhead, in the box the drag drew. A video let go on a still picture opens in a window of its own, exactly as a Photonz document dropped on a canvas always has, because a recording is a document. And the one case that genuinely cannot be taken says so in words, in the place a yes would have appeared: a sound needs a timeline to sit on, a picture has none, so the canvas says there is no timeline here and names the one move that works. Every one of these is said while the file is still in the air, under the pointer, so nobody lets go into a void. Off means a sound or a video dropped anywhere in the window is refused without a word, exactly as it is today.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: openingARecordingFlag,
                    title: "Opening a recording lands you somewhere you can work",
                    description: "A recording only has one way in today, and everything else about opening one fails quietly. History opens the recordings it lists, and that is the whole of it: File then Open greys movies out, so a recording sitting on your Desktop or handed to you by somebody else cannot be opened at all, and asking for one anyway opens a window that never becomes anything, because the app tries to read a video as if it were a photograph. A recording that has been moved or deleted since, or one that is still landing on disk while it is copied in, does the same thing: an empty window and no word about why. With this on, a recording has one way in wherever you ask from. File then Open offers movies, the app appears under Finder's Open With for them without ever taking .mp4 off whatever opens it today, and a movie asked for by any of those routes opens as a recording rather than as a broken picture. Before any window opens, the file is checked: one that has gone says so by name in the corner of the screen and opens nothing, one with nothing playable in it says that instead, and one that is still being written says it is still being saved and then opens by itself the moment it has finished, up to twenty seconds. And the app remembers where you were: leave a recording part way through, come back to it later, and the playhead is where you left it rather than back at the start, unless you had barely started or had watched it out, in which case it starts over. A recording saved since is started over too, because the moment you left may no longer be in it. Off means history is the only door, and everything else is a window with nothing in it.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: recordingIsADocumentFlag,
                    title: "A recording opens in the editor you already know",
                    description: "A recording opens in its own little window today: one clip, a play button, handles to shorten it from either end, and none of the rest of the app. You cannot put a title on it, you cannot draw an arrow on it, you cannot see it in a layers list, and nothing you learned about editing a picture applies. With this on, opening a recording opens the ordinary editor window instead. The recording is a layer in it, named after the file, sitting in the layers list with everything else, and it takes a corner radius, an opacity, a drop shadow, an effect and a place in the stack exactly like a picture does, because as far as the rest of the app is concerned it is one. What is different is that the document now has a length, and that one fact is what puts a timeline across the bottom with the clip drawn as a bar on it and a transport under the picture: play, pause, step a frame either way, and a playhead you can drag. Whatever moment the playhead is on is the picture on the canvas, composited with everything else in the document at that moment, so an arrow you draw over the video is over the video. A document with no length in it, which is every screenshot and every drawing, is exactly what it was: no timeline, no transport, nothing new anywhere. Off means a recording opens the small window it opens today.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: videoExportFlag,
                    title: "An edited recording comes out as a video file",
                    description: "Everything the timeline can do to a recording could not leave the app. You can cut it into pieces, throw one away, carry them into a different order, speed a piece up, hold a frame, take the sound off the picture, put music under it and duck the music under a voice, and then Export wrote the recording you opened, ignoring every edit, while Export Sound wrote the sound on its own. With this on, Export on a document that has time writes a VIDEO of what plays in the window: the pieces in the order they are in, the ones you threw away absent, speed and held frames respected, every title, arrow and shape drawn over the picture, and the sound the mix you hear on space, level line and all, in step from the first frame to the last. The sheet offers the same three formats a recording already leaves through, MP4, GIF and HEIC, and the same size presets, because they mean the same thing whichever door they are asked for through. While it writes, a card says how far along it is and can stop it, and stopping leaves no half a file behind. A recording nobody has touched still goes out as a straight copy of its own file, so what is instant today stays instant. A document with no duration is untouched: a screenshot still leaves through the picture sheet it always did. Off means Export on a recording writes a still picture of it.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: timelineZoomFlag,
                    title: "Open the timeline out and work on one second of it",
                    description: "The timeline draws the whole recording across the width of the window, however long the recording is. Eight seconds fits and reads fine. Five minutes, which is what a real screen recording is, is a bar a few hundred points wide: a piece is a sliver, a join is a hairline, the waveform under it is a smear, and every cut is aimed by guesswork. With this on the timeline's own bar gets a zoom. Open it out and the ruler stops measuring the whole recording and measures the stretch you are working on, as far in as a second across the width, which is enough to put a cut in the middle of a spoken word rather than near it. Everything on the strip follows: the numbers along the top count in tenths of a second where they need to, the waveform is drawn again at the scale you are looking at rather than stretched, and a join you could not see is a join you can take hold of. It opens out around the moment you are looking at, so the playhead stays where it is on screen instead of the strip throwing you back to the start on every press. While it is open a thin bar above the ruler shows the whole recording with your window marked on it, so you always know where you are, and dragging that bar moves along the recording. Fit puts the whole thing back across the width in one press. Playing a recording that is opened out carries the window along with the playhead, a screenful at a time, so what is coming next is on screen rather than arriving under the pointer. Off means the timeline is the whole document across the width, exactly as it has always been.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: transitionsAtACutFlag,
                    title: "Put a transition on a cut, and change an effect over a shot",
                    description: "A cut is hard: one shot stops and the next starts on the same frame. With this on, every join in a clip is something you can pick, and picking one opens Transition in the panel, where the cut says what it is made of and what it can afford. Cross dissolve puts both shots on screen together, which needs spare media either side of the cut to pay for; Dip to black and Dip to white need none, because each shot fades inside the time it already has and the picture goes through a colour between them. Nothing on the timeline ever moves: an overlap is paid for with frames the recording already has and the clip is not playing, and the panel says exactly how much of that spare each side is spending. A cut with no spare says so and offers the dips instead of quietly making something shorter than you asked for. The transition is drawn as a band over the join, and its length is dragged there. The same switch also lets an EFFECT change over a shot: a layer with a blur on it is offered Blur in the Motion list, so a shot can come out of focus over a second, on the same lane, the same easing curves and the same undo as everything else that moves. Off means every cut is hard and a blur is one number for the whole clip.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: punchInFlag,
                    title: "Punch in on something and hold there",
                    description: "Half of what makes a screen recording watchable is moving the eye: start wide, push in on the thing being talked about, hold there while it is explained, and pull back out. With this on that is two moves rather than an exercise. Pick a clip, drag a box round the part of the picture that matters, put the playhead on the moment it matters, and Punch In: by that moment the camera has arrived on it, having leaned in over about a second, and it stays there until you say otherwise. Put the playhead where you are done with it and Pull Back Out, and everything between the two is a hold nobody had to ask for. Punch in a second time and the camera travels from where it is rather than cutting back to wide. It is not a zoom tool and there is no crop mode: a reframe is Scale and Centre on the clip, the same two properties a title or a piece of clip art would be animated on, so it gets the easing, the lanes on the timing strip, undo and the export with nothing written for it. The move is nailed to the FRAME it was made on rather than to a moment of the finished cut, so trimming the front of the clip, cutting it or throwing a piece away carries the move along with the frames instead of leaving it pointing at the wrong thing. The panel says how far in you are, what is in the middle of the frame, and how far in the recording itself can go before there are no pixels left to show, because a screen recording is usually captured at twice the size it is laid out at and most punch-ins never spend that. Off means a clip is framed one way for its whole length.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: titleOnTheTimelineFlag,
                    title: "Words over the picture arrive and leave",
                    description: "Type words on a recording today and they are on screen for the whole of it, from the first frame to the last, because a document with a length in it makes no difference to where text lives. With this on, text placed on a document that has time gets a moment it arrives and a moment it leaves: it starts where the playhead is and runs for three seconds, and it draws a bar on the timeline beside the clip, named after the words. A title starts white, bold and a tenth of the picture tall, so it reads on a dark recording. Drag either end of that bar to say when it comes on and when it goes, drag the middle to move the whole thing, and the Time section in the panel says the two moments in words with a button for each that puts it on the playhead. A title can come on rather than snap on: pick a fade length and the words arrive and leave over that long, written as an ordinary Opacity animation on the layer, so it turns up in the Motion list with a lane on the strip, takes a different curve, and undoes like anything else. Otherwise it is the same text tool, fonts and saved text styles, and what plays is what exports. The same is true of anything else simply placed in time, which is why picking one stops offering a speed, a held frame and a split: those are about the frames behind a clip, and a title has none. Off means text on a recording is on screen for all of it.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: captionsFromTheSoundFlag,
                    title: "Have the app write the captions off the sound",
                    description: "Every video needs words on it, and typing them out by hand while scrubbing back and forth is the worst job in editing. With this on, open a recording with somebody talking in it and the captions write themselves: the app listens ON THIS MAC, using the speech recognition macOS already ships, so nothing is uploaded, no account is needed and it works with the network off. The words land on one Captions track, one cue per line side by side, with a Words lane under it showing each word at the moment it was said, and the word being said lights up there and on the picture as the playhead passes it. Each cue is an ordinary text layer with an in and an out: double click it on the track or on the picture to fix a word, drag its ends to retime it, and every change undoes. One look dresses every caption at once from the Captions section: Caption, Lower third or Karaoke, then the font, size, colour, background, lit word and position. A long recording is heard in pieces so the panel can say how far along it is, Stop keeps every word already heard, and a recording it hears no words in says so. Auto, in the same section, turns the writing-by-itself off. What plays is what exports: a film comes out with the captions burned in, or with a clean picture and an SRT or WebVTT file beside it. Off means no captions are written and no caption rows appear; captions already in a document draw either way.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: componentOnTheTimelineFlag,
                    title: "Put something you built on the timeline and animate it",
                    description: "A component you drew, an icon you made, a badge you styled: drop one on a recording today and it stands over the whole film, from the first frame to the last, because a component knows nothing about time. With this on, anything you place on a document that has time arrives where the playhead is and runs for three seconds, with a bar on the timeline beside the clip. Drag either end to say when it comes on and when it goes, drag the middle to move it, and the Time section says the two moments with a button for each that puts it on the playhead. It stays the thing you built: it keeps its link to the original, so editing the original changes it on the timeline too, and a copy dropped twice is the same component in two places. And it animates with the machinery everything else animates with, which is the point of it: a move recorded on a part of the original is a real motion with a lane on the strip, a curve of its own and an ending you choose, so two parts of one badge can move out of phase, and each copy runs that animation from the moment IT arrives rather than from the start of the film. What plays is what leaves: the file written out has the component on it, over the shot, moving. Off means a component on a recording is on screen for the whole of it and stands still.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: drawnOnTheTimelineFlag,
                    title: "Anything you draw on a video is on the timeline",
                    description: "A shape, line or picture drawn on a video gets its own timeline row, from the playhead to the end of the shot. The diamond on its row keys it; move the playhead, drag it, and it tweens.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: timelineIsTheLayerListFlag,
                    title: "On a video, the timeline is the layer list",
                    description: "On a video, the panel drops its Layers list while the timeline shows, because the timeline already lists every clip, and opens on the clip you picked. Fold the timeline away and Layers comes back. Pictures are untouched.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: soundOnTheTimelineFlag,
                    title: "Take a recording's sound off its picture, bring more in, see it and shape it",
                    description: "A recording arrives with its sound welded to its picture, so a cut to the picture is a cut to the sound and there is no way to put music under anything. With this on, Detach Sound in the Video menu takes a clip's sound off its picture and lays it on a layer of its own directly above, in step and with the same cuts, and from that moment the two are ordinary layers: cut the picture and the voiceover over it is untouched, move one and the other stays put, switch one off and the other plays on. Add Sound puts a file on the timeline at the playhead as another layer, so music and a voice can sit under a cut. Every layer that makes a sound draws its own waveform on its bar in the timeline, following its cuts, so a cut can be aimed at a word or a beat instead of guessed at. Its level is a row in the panel, read in decibels, and a line drawn across its bar: click the line to pin the level at a moment and drag the dot up or down, and two dots either side of a dip is a duck, while a dot at the start and one a second and a half in is a fade in. A Fades section sets its fade in, fade out and their curve. What you hear when you press space is worked out from exactly the same plan Export Sound writes out, so the mix on disk is the mix in the room. Off means a recording plays silently and there is nowhere to put a sound.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: scrubAuditionFlag,
                    title: "Hear the sound under the playhead while you drag it",
                    description: "Dragging the playhead over a recording is silent, so the only way to find the exact word somebody says, or the exact beat to cut on, is to read the shape of the sound and guess. With this on, the sound plays under the playhead as you drag it: a short piece of whatever is under it, over and over, for as long as your hand is moving. Drag backwards and it plays backwards. Two sounds laid over each other are both heard, each at the level its own line says at that moment. Stop moving and it is quiet within a fraction of a second, let go and it stops; a single click to put the playhead somewhere makes no sound at all, because a click is not a drag. It is the same plan that plays when you press space and the same plan that exports, read a sliver at a time, so what you hunt with is what you get. Needs the sound on the timeline to be on, because without it there is nothing to hear. Off means dragging the playhead is silent and the waveform on the bar is the only answer.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: mixLoudnessFlag,
                    title: "See how loud the mix is, and be told when it has to come down",
                    description: "Sound adds up. Three things playing at the level they were recorded at are three times as loud as one of them where they overlap, and a sound file has no room for that: everything past the top is sheared off flat, so what should have been three sounds comes out as noise. Nothing on screen said how loud the mix was, so the first anybody knew was listening to the file afterwards. With this on, a meter sits in the transport beside the play button and rises and falls with the mix as it plays. It moves while you drag the playhead as well, not only while it plays, so the loudest moment can be found by hand. When the mix adds up to more than a file can carry the meter turns amber and says by how much it is over, and Export Sound says in its notice that it had to hold the mix down. Needs the sound on the timeline to be on, because without it there is no mix to measure. Off means the meter is not there. Keeping the mix inside what a file can hold is not part of this switch and happens either way, because writing a file that is distorted is a fault rather than an experiment: the whole mix comes down by exactly the amount it is over, so the balance between the layers and the shape of every fade survive, and a mix that already fits is never touched.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next],
                needs: [recordingIsADocumentFlag]),
            Definition(
                flag: FeatureFlag(
                    name: motionStripFlag,
                    title: "See every moving part on one strip across the bottom",
                    description: "Adds a strip across the bottom of the window showing one lap of the animation, measured in milliseconds, with a bar for every moving property grouped under the layer it belongs to. It is there only while something in the document moves. The side column can say what changes and by how much; what it cannot say is how two parts of one drawing sit against each other in time, because that is a comparison and a comparison needs width. Drag a bar sideways to change when that motion starts, drag either end to change how long it takes, and while you drag, the gap to the nearest other bar is drawn as a bracket with the number on it, named after the layer it is measured from, so a lag is a distance you can see rather than a number you have to hold in your head. The bars and the Start and Over fields in the side column are the same two numbers: move one and the other follows at once. A dashed line marks where the lap starts over, and a bar is allowed to run past it, which is what a lag in something that loops is. The lap's length is on the strip and can be typed, and until it is, it simply follows the longest motion. Picking a bar picks its layer. Option Command T puts the strip away and brings it back. Needs the Motion list to be on, because without a motion there is nothing to draw.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: penFlag,
                    title: "Draw any shape with the Pen",
                    description: "Adds the Pen, P, at the end of the drawing tools. Click to drop a corner, or press and drag to pull a curve out of the point you are placing, so one outline can have hard edges and curves in it: a triangle, a teardrop, a rounded box, the sort of shape an icon is made of. The run between the last point and the pointer is drawn while you move, so you see the curve before you commit it. Click the first point to close the shape and it fills; Return finishes it as an open line; Escape throws the drawing away. Holding Shift puts the next point on one of the usual angles. With the grid on and Snap to grid on, a point lands on the nearest crossing of the lines you can see, the same lines a drag catches, and holding Command puts it exactly where the pointer is. Holding Option means the two sides of a point are not tied together, which is what lets a straight edge run into a curve: drag a point out with Option held and the edge arriving at it stays straight, and press Option on the point you just placed to pull its handle back in so the next edge leaves straight. That is how a rounded corner gets drawn. Command Z steps back one point at a time while you draw instead of losing the whole path. The colour the next path comes out in is the swatch on the tool bar, the same place every other drawing tool keeps its colour, so you choose it before you draw rather than repainting afterwards. What you get is an ordinary layer: move it, resize it, turn it, repaint its inside and its edge, give it a shadow, undo it. It also brings Combine Shapes, in the Layer menu and on a layer row's right click menu, which is how most icons are really built: pick two or more shapes that have an inside and Join them into one, Cut Out the ones on top from the one at the bottom, Keep Overlap to keep only where they all meet, or Drop Overlap to keep everything except that. Other drawing programs call those four union, subtract, intersect and exclude. Rectangles, ovals and highlighter washes count as shapes here, so you can rough an icon out with the shape tools and combine what you drew; a line has no inside, so it is left alone. What comes back is one path with real points on it, not a picture: a circle with a smaller circle cut out of it is a ring you can still pull the points of, it keeps its hole when you move, resize or turn it, and it survives being saved. The result sits where the bottom shape sat and wears its fill, its outline and its effects, and one line under the canvas says which shape that was and whether the result has a hole in it or came out in several pieces. The whole thing is one undo step. Off means no Pen tool, P does nothing and Combine Shapes is not offered; a path already in a document draws either way.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: dragReadoutFlag,
                    title: "A drag says where it is and how big it is while it happens",
                    description: "A drag says nothing about itself while it is in flight. Move a layer and there is no number anywhere saying where it has got to; pull a handle and nothing says how big it is becoming; sweep a selection box and its size is a thing you find out after you let go. The numbers used to follow a drag in the right hand panel, and now that Position and Size is something you ask for rather than something always open, the watching half of that reading had nowhere to live. With this on, a small dark pill rides under whatever is being dragged and says the reading the drag is changing: where it is going while you move it, and how big it is becoming while you resize it, sweep a selection box, or pull a point or a lever on a path. It is one reading rather than four numbers, because the half you are not changing is noise under a moving box. It sits centred just below the thing it describes and never on top of it, steps above instead when the thing is against the bottom of the window, and slides sideways to stay readable at the edges. It is there only while the button is down: the moment you let go it is gone, and the shape you landed on is what the panel and the Position and Size fields read. Off means a drag stays silent and you find out what you got after you release.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: drawLandingFlag,
                    title: "See where a point will land before you press",
                    description: "Every tool that starts a shape is magnetic: with the grid on, the first point goes to the nearest crossing of the lines you can see, and on a screenshot it goes to the border it is near. None of that showed until after the click, so placing a point was a press followed by finding out where it went, and the only way to correct it was undo. With this on, a small ring appears under the pointer on the exact spot the press would land, while you are still only hovering, and it steps from crossing to crossing as you move. It is there for the Pen, the rectangle, the ellipse, the line, the arrow, the highlighter, the zoom callout, the lens and the frame, because aiming is one rule rather than one tool's feature. The ring is open in the middle so it sits on the crossing without hiding it. Holding Command takes the point off the magnets, the way it does everywhere on the canvas, and the ring goes away to say so: with nothing pulling, the point lands exactly where the pointer is. With no grid on a plain canvas the ring stays away too, and appears only when something really would move the point. While the shape is being drawn the grid lines its ends came to rest on light up, the same as a dragged box. Off means the tools snap exactly as they do now, silently, and you find out where the point went after you press.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: turnIntoPathFlag,
                    title: "Turn a rectangle into a path",
                    description: "A rectangle, an ellipse, a line or a highlighter wash is a fixed thing: you can resize it, but you cannot take one corner and pull it somewhere else. Turn Into Path, in the layer's right click menu and in the Layer menu, stops it being a rectangle and makes it an outline, keeping exactly the look it had. Round the corners first and the curves you get are real ones you can pull on, which is how most icons actually get made. Pick several shapes and it acts on all of them at once, and it does one more thing: shapes whose ends meet are welded into ONE path, so three lines drawn end to end become a single triangle you can fill and reshape, closed because the last end came back to the first. Two outlines you drew with the Pen weld the same way, and over those the command calls itself Join Paths instead, because neither of them is a shape any more; ask for it when nothing is near enough and it changes nothing and says under the canvas how far apart the ends are. Ends within two points of each other count as meeting and are pulled together; ends further apart are left alone, and the question tells you which happened before you press the button. Pick ONE outline you already finished and the row calls itself Close Path instead: it lays a straight run between that outline's own two ends, however far apart they are, so a shape you stopped drawing before the last point is no longer open for good. Neither end moves, the colour and line stay exactly as they were, and the Fill row turns up on the panel for you to switch on. An outline whose points are all in a line is refused, because joining them up has no inside, and the line under the canvas says so in the same words the Pen uses while you are drawing. The shapes keep their fill, their edge, their shadow and everything else they were wearing, and the whole thing is one undo step, so if it was not what you wanted the separate shapes come straight back. A highlighter wash comes across still mixing with what is under it, so it goes on highlighting and is no longer stuck being a box: a run of words that wraps onto two lines, or a panel with a notch out of it, can be one mark. An ARROW is the one shape that does not convert, and the command is missing rather than dimmed on one: its head is part of how it is painted rather than part of an outline, so a path of it would be the silhouette of the whole arrow with its points on the outside, which is not the arrow you drew. You are told once, plainly, what the command will leave you with, and there is a Don't ask again on that question; after the turn, one line under the canvas says what you now have, which is what stands in for the question once it is silenced. Needs Reshape a path, and so the Pen, because a shape you turn and then cannot edit is a command with no payoff. Off means the command is not offered and the shapes stay shapes.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: whatIsLeftInThePictureFlag,
                    title: "What a separation left behind stays on the picture's row",
                    description: "Separating a screenshot answers in a pill at the bottom of the canvas: how many pieces came out, how many are still in the picture, and that running the command again takes the next batch. On a dense page that is 142 out and 580 left, and three seconds later the pill has faded and nothing on screen says so. The only way back to the number is to run the command again and read fast, which is the one thing that changes it. With this on, the picture's own row in the layers list keeps the count: a second line under its name reads 580 left, with Separate again beside it, and one click takes the next batch without going near a menu. A picture that came apart completely says Nothing left on its row, so finished looks different from nobody ever told me. Pieces the app read but could not be confident about say so instead and offer no second run, because another run would find exactly those and refuse them exactly the same way. A photograph, where the sweep finds hundreds of pieces in the grass and can read none of them, says Nothing readable rather than counting its texture out loud. Hovering the line spells the whole thing out in a sentence. Nothing about the document changes, so it costs no undo step, and undoing the separation takes the line away with it rather than leaving a count over a picture that holds everything again. Off means the pill is the only thing that ever says it.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: rowSaysItsWordsFlag,
                    title: "A row says the words that are in it",
                    description: "A piece of text in the layers list says Text, then Text 2, Text 3, whatever it actually holds, and a screenshot taken apart hands back a hundred and forty rows called Text 1 to Text 142 with nothing to tell them apart. With this on, a piece of text nobody has named by hand simply wears its own words: the row under a button's label says Save Changes, the heading's row says General, and a list you had to click through one row at a time is a list you can read. Retype the words on the canvas and the row follows them as you type, because the name is not written down anywhere, it IS the words. Long words are cut at a word boundary and end in an ellipsis, so one long paragraph cannot push every other row off the edge of the list. The moment you type a name of your own it is yours: it stays put whatever the words do afterwards, and opening the rename field and pressing Return without changing anything leaves the row following the words rather than quietly pinning it. Nothing about the document changes, so it costs no undo step and a document made with this on is byte for byte an ordinary document. Off means a piece of text says Text and its number, which is what it has always said.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: separatedRowSaysItsWordsFlag,
                    title: "A separated run of text says the words in it",
                    description: "Take a screenshot apart and the pieces that are text arrive as pictures of words: the layers list calls them Text 1 to Text 142 and the only way to tell one from another is a thumbnail the size of a postage stamp. With this on the app reads each piece as soon as the command has landed, and the rows fill in with what is actually written in them: the row under a button's label says Save Changes, the heading's row says General, and typing a word you can see on the canvas into the find field goes straight to the piece holding it. The reading happens in the background, a dozen pieces at a time from the top of the list down, so Separate into Layers is exactly as fast as it was and the names appear behind it. It reads the WORDS only, never what face they are set in, which is both the quick half and the reliable half. Nothing is written onto the canvas: the row works its name out as it is drawn, so no undo step is spent, the picture is untouched, and turning a piece into real text or naming it yourself takes over from the reading straight away. What the reading found is kept with the document, so opening a file you separated last week shows every name at once instead of reading it all again, and a row says the words it said last time. It is saved alongside your next save rather than making the file look edited on its own. A piece with nothing readable in it, an icon or a switch, keeps the name the app gave it. Off means every piece says Text and its number.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: findALayerFlag,
                    title: "Find a layer by typing",
                    description: "A screenshot taken apart can put well over a hundred pieces in the layers list, and the list shows about five rows at a time, so reaching the one label you wanted is a very long scroll. With this on there is a find field over the list: type a few letters and the list shows only the layers whose row says them, wherever they are, including ones inside groups that are shut. Every word you type has to appear somewhere in the row, in any order, and capitals and accents do not count, so \"save ch\" finds Save Changes and so does \"changes save\". Results are plain rows with no indent and no twist, because a result is something you click to get to rather than a branch to read, and the line under the list says how many of how many. Click one and the canvas picks it, exactly as clicking any row does. Clear the field and the list comes back as it was, with the same groups open and the list scrolled where you left it. Nothing about the document changes, so it costs no undo step, and while a search is showing rows cannot be dragged into a new order, because the row above a result is not its real neighbour. The field only appears once the list is longer than the panel can show, so an ordinary picture with ten layers looks exactly as it always has. Off means no field and no searching.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: separationArrivesShutFlag,
                    title: "A big separation arrives in one shut group",
                    description: "The other answer to a hundred and forty pieces arriving at once: instead of a hundred and forty new rows, Separate into Layers puts everything it made into one group named after the picture it came from, and leaves it shut. The layers list is one row longer than it was, you open the twist when you want to go in, and the pieces are all still there on the canvas exactly where they were. Only a separation big enough to fill the list does this, so taking a card or a small pane apart still hands the pieces straight to you. Be warned that the pieces are then INSIDE something: one click on the canvas picks the whole group and dragging it carries the entire page, and reaching a single word means double clicking into the group first. This is here to be compared against finding a layer by typing, not because both should ship. Off means the pieces arrive loose over the picture, which is what the command has always done.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: []),
            Definition(
                flag: FeatureFlag(
                    name: lineEndsFlag,
                    title: "Say how a line and an arrow end",
                    description: "A line and an arrow have always ended in a half circle, with nothing anywhere to say otherwise. That is the right look for pointing at something in a screenshot and the wrong one for drawing, because what makes a set of line drawings read as a set is that every line ends the same way, and it is the one thing about a line that cannot be fixed afterwards. With this on, a line or an arrow you have picked shows Ends under Outline in Appearance, right beside its Thickness, offering the same three shapes a path drawn with the Pen already offers: Flat, which stops dead on the last point; Round, the half circle it has always drawn; and Square, a half square past the last point, so the line reaches as far as a round one does but keeps its corners. Each is a small picture drawn with the setting it stands for, so you compare them at a glance rather than reading three words. Pick several lines at once and one choice sets all of them; pick a mixture and the row says so rather than pretending they agree. The choice is one undo step, it is saved with the document, and it comes across into an exported SVG, so a file opened in a browser ends its lines the way the canvas does. A box, an oval and a highlighter wash are closed or are not a line at all, so they are not asked. Off means a line and an arrow end in a half circle and the row is not there.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: reshapePathFlag,
                    title: "Reshape a path after you have drawn it",
                    description: "Pick a path drawn with the Pen and its points appear on it, so a shape that came out nearly right can be put right instead of drawn again. Drag a point and the curves either side follow it. Click a point and its two levers appear: drag one to bend the curve, and on a smooth point the far lever swings round to match so the outline runs through without a kink. Double click a point to turn a hard corner into a smooth bend, and double click it again to turn it back. Hold Option while dragging a lever to free the two sides of a point from each other, and Option click a lever to pull it in so that side runs straight, which is how you get a point that is curved on one side and straight on the other. Double click the outline itself to add a point exactly where you clicked, without the shape moving at all. Select a point and press Delete to take it out, and the curve closes over the gap. Shift click to gather several points and move them together, with the arrow keys nudging them like anything else. Every one of these is a single undo step. Off means a path is an ordinary box you can move, resize and repaint, with no points on it.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: svgExportFlag,
                    title: "Export what you drew as SVG",
                    description: "Adds SVG beside PNG, JPEG and HEIC in Export, so an icon you drew leaves the app as the icon rather than as a picture of it. What you get is a real vector file any website, app or icon set can use: every shape is a shape, so it stays sharp at any size and can be opened and edited in any drawing tool. Paths keep their straight edges straight and their curves curved, a rounded box keeps its rounding, an oval is an oval, groups stay grouped in the order the layers list shows, and fills, outlines and gradients come across as they look on the canvas. Words are written as the outlines of their letters rather than as type, so the file looks the same on a machine that does not have the font, and the words themselves ride along inside it so the file can still be searched and read aloud. A drop shadow and a blur come across as themselves, so a shape wearing one is still a shape you can edit. Anything with no way of being said in shapes, a photograph or a glow, is embedded as a picture exactly where it sits, and the Export sheet says so before you save rather than leaving you to find out. Choosing SVG hides the 1x and 2x row, which means nothing for a file with no pixels in it. This goes with the Pen, Draw any shape with the Pen, which is what draws the shapes worth exporting, and turns itself off when the Pen is off. Off means Export offers the three picture formats it always did.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: exportQualityFlag,
                    title: "Choose the quality of an export and see what it will weigh",
                    description: "Adds a Quality slider to Export for the two formats that throw pixels away, JPEG and HEIC, and says exactly what the file will weigh at the quality you pick, before you save it. The number is not a guess and not a formula: the picture really is encoded while you watch, so the size on the line is the size of the file that lands on disk, down to the byte. Move the slider and the number follows, with a plain word beside it saying what that quality is, Best, High, Good, Low or Rough, so somebody after a file small enough to send can find it without knowing which percentage that is. Changing 1x to 2x changes the number too, because that is a different file. The slider stops at thirty percent: low enough to make a file a fraction of the size, high enough that the words in a screenshot do not break into blocks on the way past. Each format keeps its own answer for next time, because eighty for a JPEG and eighty for a HEIC are not the same picture. PNG and SVG show no slider at all, since a PNG keeps every pixel and an SVG has none, so a quality would mean nothing for either. A PNG still says what it will weigh, on the same line in the same place, which is how you watch the file get smaller when you leave the canvas out from behind an icon. Off means Export writes what it always wrote, at the quality it always used.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: webPExportFlag,
                    title: "Export as WebP",
                    description: "Adds WebP beside PNG, JPEG and HEIC in Export, which is the format to reach for when a picture is going on a web page: every browser reads it, and it is usually a good deal smaller than the same picture as a PNG or a JPEG. It takes the same Quality slider as the other lossy formats, so eighty percent means the same amount of picture whichever you pick, and the size on the line under it is the real size of the file that will land. The top of that slider does something WebP alone can do: at one hundred percent it writes a lossless file, keeping every pixel exactly, and for a screenshot of flat panels that file is usually SMALLER than the same picture as a PNG as well as sharper than any lossy setting, so the line says Lossless rather than Best to make it findable. Transparency comes across either way, including the soft edge of a shadow or a rounded corner. Opening a WebP already worked and is untouched. Needs Choose the quality of an export, which owns the slider. Off means Export offers the formats it always did.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: lensFlag,
                    title: "A layer that changes what is under it",
                    description: "Replaces the Zoom Callout with the Lens tool, K, in the same slot on the bar. Drag a box over anything and the picture underneath is drawn through it: Blur to soften an address until it cannot be read, Pixelate to break a name into blocks, Greyscale to drain the colour out of a region, Invert to flip it, Brightness to lift it or push it down, or Magnify to draw a bigger copy of the bit you dragged, with a line back to where it came from. Magnify is the Zoom Callout, which is why there is one box on the bar and one Lens section in the panel instead of two of each; Z still hands you the Lens set to Magnify. Each kind has its own settings, in the capsule over the tool bar before you draw and in the Lens section of the panel after, and switching a layer between them in that section is one undo step. It is an ordinary layer otherwise: move it, resize it, turn it, round its corners, give it a border or a shadow, fade it, reorder it, undo it. What leaves the app is flattened, so a pixelated region really is pixelated in the picture you export or copy. Off means the Zoom Callout and its own section come back and there is no Lens; a lens already in a document keeps drawing either way.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: layersCombineFlag,
                    title: "A layer can key a colour out and take its shape from the layer below",
                    description: "Compositing is layers with a rule for how they combine, and this adds the two rules the app was missing, both of them right under Blending where Opacity already lives. Key out a colour takes one click: press Key it on a photo or a clip and the colour round the edges of the picture, the wall behind whoever is talking, goes transparent, with Tolerance, Softness and Spill underneath for tuning it by hand. It measures colour rather than brightness, so a wall lit from one side keys out with its own shadow instead of leaving a grey rind, and Spill pulls the green rim off a shoulder without darkening it. Masked by cuts a layer to the shape, or to the brightness, of the layer directly under it in the layers list: the layer below stops drawing and becomes the shape instead, so a gradient under a colour wash turns it into a fade, and dragging a different layer under it changes what it is cut to. Both are properties of the layer, both survive being saved, and both are drawn at whatever moment the playhead is on, so what you scrub past is what exports. The timeline reads top down the way the layers list does, so the bar on top is the layer on top. Off means no Key or Masked by rows; a document that already has either keeps drawing that way.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: blendModeFlag,
                    title: "A layer can say how it mixes with what is under it",
                    description: "Adds a Blending row to the Appearance section, right under Opacity, where Opacity says how much of what is below shows through and Blending says how the two are mixed once it does. Five choices, each with a plain sentence beside it: Normal paints straight over, Multiply darkens the way a highlighter pen does so a tint burns into a screenshot and the detail underneath still shows, Screen lightens, and Darken and Lighten keep whichever of the two is darker or lighter. Moving down the list previews each one on the canvas as you go, and the one you click is a single undo step over every layer you picked. What leaves the app carries it, so a tint really is burnt into the picture you export or copy. A highlight mark has no row, because mixing is what makes it a highlighter. Off means no Blending row; a layer already set to mix keeps drawing either way.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: framesFlag,
                    title: "Build on a frame",
                    description: "A frame is a screen you build on: press F and drag one out at any size, or click once to drop the size you picked last. It carries its name above its top left corner, paints a white surface, and hides anything that hangs off its edge, and several of them sit side by side on one canvas so a document can hold more than one screen. Layer \u{25B8} New Frame picks a size from a short list, Layer \u{25B8} Frame Selection puts a frame around what you already have, and Export offers a single frame as the picture to write. Needs Group what you selected. Off means no frame tool and no frame rows; frames already in a document keep drawing either way.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: iconFramesFlag,
                    title: "Make a frame the size of an icon",
                    description: "Every size New Frame offered was a screen, and the smallest of them was a thousand pixels across, so somebody sitting down to draw a 24 pixel glyph had nowhere to draw it. On, the size list grows an Icons group under the screens: 16, 24, 32, 48, 64 and 512, as a row of buttons rather than six more rows of numbers, and the frame\u{2019}s own Size menu in the panel offers the same sizes under their own heading. A frame made at one of them is an ordinary frame in every other way: it clips, it carries its name, it exports, and it holds what you draw on it. It is simply small. The canvas comes with it: a frame you picked a size for, rather than dragged out, arrives in the middle of the view at a zoom you can actually draw at, so a 16 pixel canvas opens as a square the size of your hand instead of a speck. That zoom lands on a whole multiple, so the pixels stay square. A frame that is already big enough to work in does not move the camera at all. Needs Build on a frame. Off means the size list is the five screens again and the camera stays where it was; an icon-sized frame already in a document keeps drawing either way.",
                    area: .icons,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: iconPreviewsFlag,
                    title: "See an icon at the size it will be used",
                    description: "An icon is the only thing in this app that is drawn at one size and looked at at another, and a line that reads beautifully on a 512 point canvas can be gone at 16. On, working in an icon frame puts a small row in the top left of the canvas: the same drawing at 16, 24, 32, 48 and 64 pixels, with the number under each one, redrawn as the picture changes. A frame is never shown bigger than it is drawn, so a 24 point frame shows 16 and 24 and nothing else, and the smallest frames still show themselves at true size, which is the one size a canvas at 3200% never shows you. Each preview is the frame COMPOSITED at that many pixels, the same picture exporting it at that size would write, rather than the big picture shrunk down: a smooth shrink averages a hairline into a plausible grey and hides the very thing the row exists to show. Once something in that frame moves, the row grows a Real size header with a play button and the rate the loop is running at, and every picture in it plays: the swing you are judging is shown at the sizes it will really be seen, which is the only place a swing that reads beautifully at 512 is caught being a shimmer at 16. The space bar is the same switch as the button, and the rate is the one the timing strip uses, so slowing the loop slows the playhead on the ruler with it. With nothing moving the row is exactly what it was, chrome that takes no clicks. It never lands in an export, and it goes the moment you pick something that is not in an icon frame. Needs Make a frame the size of an icon. Off means the canvas exactly as it is today.",
                    area: .icons,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: libraryFlag,
                    title: "Keep reusable pieces in a Library",
                    description: "Adds a Library to the right dock, under View \u{25B8} Show Library. It is one shelf with four scopes you switch between, Media, Components, Styles and Systems, and a search field that narrows whichever one you are in. Media shows the captures you have taken: click one to see its details, double click or drag it onto the picture to place it. Components, Styles and Systems are empty until there is something to put in them, and each says so. Needs Group what you selected. Off means the right dock exactly as it is today and no Show Library row.",
                    area: .library,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: componentsFlag,
                    title: "Make a component out of what you drew",
                    description: "Draw something, group it, and press Option Command K to turn it into a component: it takes a name, wears a small mark on the canvas and in the layers list so you never mistake it for an ordinary group, and lands on the Library's Components shelf where you can find it again. Renaming it anywhere renames it everywhere, because it only has one name. Placing copies of it, exposing properties and detaching come later. Needs Keep reusable pieces in a Library. Off means no Make Component row and no components on the shelf; components already in a document keep drawing either way.",
                    area: .library,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: stylesFlag,
                    title: "Save a color, a text style or an effect and reuse it",
                    description: "Save a fill, an outline or a text color under a name, and any layer can wear it. The Fill and Color rows in the panel grow a small styles button: save what is there as a style, or pick one you already have. Text goes further: the Style row at the top of the Text section saves the font, size, weight and color together under one name, so changing the heading size across a screen is one edit instead of one per heading. An effect goes the same way: the Style row at the top of a shadow, a glow, a border or a blur saves all of its settings under one name, and the plus on the Effects header puts that name on any other layer. Saved styles sit on the Library\u{2019}s Styles shelf, where you rename one, change it, or take it off the shelf. Changing a style re-sets every layer wearing it in one step, which one undo puts back. Needs Keep reusable pieces in a Library. Off means colors, text and effects are one-offs again and the Styles shelf is empty; styles already in a document keep painting either way.",
                    area: .library,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: sharedLibraryFlag,
                    title: "Use a component you made in every document",
                    description: "A component you make belongs to the document you made it in. The Component section grows a Share across documents switch: turn it on and the component joins a shelf every document on this Mac can reach, so the button, card and nav bar you built for one screen are already in the Library when you start a file tomorrow. Drop one in and it stays linked \u{2014} edit the original in any document and every other document takes the change the next time you look at it, copies and all. The colors it paints from travel with it, and a document that already has a color of that name keeps its own. A document whose shared original has been taken off the shelf keeps its drawing and says the link broke rather than losing the picture. Needs Make a component out of what you drew. Off means components stay in the document they were made in and the shelf holds only what this document has; a component already shared keeps drawing either way.",
                    area: .library,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: starterComponentsFlag,
                    title: "Components in the Library from the start",
                    description: "The Library\u{2019}s Components shelf comes with five ready components on it \u{2014} a button, a text field, a card, a nav bar and a badge \u{2014} so the first thing you do is drag one out instead of building one. Each is an ordinary component: it takes copies, its wording and its parts are adjustable on every copy, and it comes apart. They paint from named styles, so recoloring Accent once repaints every one of them. Dropping one brings it and its colors into the document; a document you never drop one into carries none of it. Needs Make a component out of what you drew. Off means the shelf holds only the components you made yourself; starters already dropped into a document keep working either way.",
                    area: .library,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: colorPickerFlag,
                    title: "One color picker, everywhere a color is chosen",
                    description: "Every swatch in the app opens the same picker, whether it paints a shape\u{2019}s outline, its inside, a shadow, a backdrop, text, a measurement or a tool. It opens with the color you are changing shown beside the one you started from, so you can tell whether you improved it. Inside: a shade and saturation square you drag in, a slider and a number for each channel, and a switch between HSL, RGB and HEX \u{2014} paste \u{201C}#7C4DFF\u{201D}, \u{201C}rgb(124, 77, 255)\u{201D} or \u{201C}hsl(256 100% 65%)\u{201D} into the HEX field and it takes all three. Under that, one row of swatches that switches between nine shades of the color you are on, six colors related to it, the colors this document already uses, and the ones you picked recently. An eyedropper samples any pixel on screen, a live reading says whether the color can be read on white, and Save style puts it in the Library under a name. A shape\u{2019}s fill, its outline and a screen\u{2019}s surface can also hold a gradient rather than one flat color: a top row offers Solid, Linear, Radial and Angular drawn with the colors you are already using, and choosing one brings up a ramp you can add, move, delete and reverse stops on plus a square you drag to aim it. A color that can only ever be flat, like a drop shadow, never shows that row. Off means the color rows open the picker the app shipped with and a few of them open the system color panel instead.",
                    area: .appearance,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: autoLayoutFlag,
                    title: "Groups that arrange their own contents",
                    description: "A group can be made a stack or a grid, so the things inside it space themselves instead of being nudged into place one at a time. Pick a group and set Arrangement in the Layout section, or pick several layers and choose Layer \u{25B8} Stack Selection (\u{2303}\u{2318}G) or Grid Selection. A stack lays everything along one axis with a gap you type; a grid fills rows of equal cells with a column count you type. Add a layer, delete one, hide one or drag one past another and everything re-flows on its own. Any group can also be given a size of its own: Width and Height are each Hug or Fixed, the number is typed in W and H like any other layer\u{2019}s, and rows set to Stretch fill it. Hug means the group is as big as what is inside it plus the room at its edges, so a button is as wide as its label and gets wider the moment the label does, with nothing to drag. A piece inside a stack or a grid can be the surface behind the rest instead of one of the things being arranged: it is painted to the group\u{2019}s own edges and the others sit on top of it, which is what a button\u{2019}s fill is. Pick it and set Role to Surface behind the rest in the Layout section, or choose Layer \u{25B8} Surface Behind the Rest. Both name it before you pick it, both are one step, and one undo puts it back. A piece can also be taken out of the line and left where you drag it, in FRONT of the rest: pick In front of the rest on the same Role row, or choose Layer \u{25B8} In Front of the Rest. The others then arrange themselves as though it were not there, which is how a notification dot sits on the corner of a card. One piece in a stack can take whatever room the stack has left over instead of keeping the size it was drawn at, which is how a search field between a logo and a row of buttons is built: pick it and choose Layer \u{25B8} Fill the Row (\u{2325}F), or set Horizontal to Fill the row in the Layout section. Press it again and the piece is handed back the size it had. A stack with a size of its own can share the room it has left over between its rows instead of holding one gap: press the switch beside Gap and the first and the last go to the two ends, which is how a bar with a logo at one end and buttons at the other is built. Type a number straight over it to hold one gap again, and it is the number that was there before. Turning a group you arranged by hand into a stack reads the direction and the gap it already has, so nothing moves when you switch it on. Off means the Arrangement rows and the menu items are gone; a group already set to a stack keeps arranging itself.",
                    area: .layout,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: placementFlag,
                    title: "Say where the pieces sit when something is resized",
                    description: "The panel gains a Layout section. A group says how its contents line up \u{2014} left, centre, right or stretch across, top, middle, bottom or stretch down \u{2014} and any one piece inside can say something different for itself, so a button dragged wider keeps its label in the middle while the fill behind it grows. A row that has not been set says which setting it is following from the group it sits in. Text gains an Align control in the Text section for where its words sit inside their own box, and telling text to stretch moves its words to the middle of the box it now fills, so the choice does something you can see. The five Library components arrive already set up this way whether this is on or off. Off means the section is gone and a resize multiplies everything proportionally, which is what a layer with nothing set does anyway.",
                    area: .layout,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: crispZoomFlag,
                    title: "Words stay sharp when you zoom in",
                    description: "Zoom past 100% and the labels, captions, measurement readouts and borders you have placed are drawn again at the size you are looking at them, instead of the whole picture being blown up. A label you place reads exactly as crisply as the one you are still typing, at any zoom. The picture underneath is untouched: a screenshot still goes square and blocky past 2x, which is what you want when you are counting pixels. Only the part of the canvas you can see is redrawn, so it costs the same at 800% as at 200%. Off means the whole canvas is stretched from one picture the way it always was, and placed text goes soft as you zoom in.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: calloutShapeFlag,
                    title: "Choose a zoom callout\u{2019}s shape before you draw it",
                    description: "Picking up the Zoom Callout tool puts a Zoom Callout Tool section in the panel with one choice in it: Rectangle or Circle. The box you drag out previews in the shape you chose and the callout lands in it, and the tool keeps that choice for the next one and after a relaunch. Off means every callout is drawn as a rectangle and the only way to a circle is to draw one first and change it in the callout\u{2019}s own section.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: calloutMagnificationFlag,
                    title: "Choose how much a callout magnifies before you draw it",
                    description: "The Zoom Callout tool carries a Magnification slider beside its Shape, in the settings capsule above the tool bar and in the Zoom Callout Tool section of the panel, so you can say how much the next callout blows up what it points at before you drag it out. It starts at 2\u{00D7}, which is what callouts have always been drawn at, and the tool keeps whatever you last set for the next one and after a relaunch. Drawing at the right size the first time also means the callout is placed clear of the picture\u{2019}s other callouts at that size, instead of growing over them when you resize it afterwards. A callout already on the canvas is still resized by its own Magnification slider, and pulling its corners never changes what the tool holds. Off means every new callout comes out at 2\u{00D7} and the only way to a bigger one is to draw it and then resize it.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: canvasGridFlag,
                    title: "A grid to build against",
                    description: "Switch on a grid over the whole canvas and build to it: View \u{25B8} Show Grid, or the Grid row in the Canvas section of the panel. The grid is then worked from the tool bar: a capsule beside the zoom reads the grid's unit and the cell it is working to right now (\"4 \u{2192} 32 pt\"), a slider makes that cell finer or coarser through the sizes real UI is built in, and Adjust Grid takes the canvas over. Spacing, how often a line is bold and columns-or-both stay in the settings the readout opens. It thins and thickens as you zoom, so the lines are never closer together than you can read and never disappear: zoom out and the fine ones fade away leaving the coarse ones, zoom in and they fade back. Inside Adjust Grid you place where the grid counts from — drag the dot at the crossing of its two markers, or nudge it with the arrow keys, catching layer edges and canvas edges on the way — and you pin GUIDES: hover and the grid line nearest the pointer lights yellow, down or across, and clicking pins it there. A pinned guide stays for good, including with the grid switched off, and a drag or a resize catches it exactly the way it catches a grid line, with Command to get away from it. Click a guide to pick it up and move it, backspace to take it off, Clear Guides to take them all off in one undo step; Return keeps everything and Escape puts it all back. Guides and the zero point belong to the DOCUMENT, saved with it and different in every picture; everything else about the grid is an app preference remembered between launches. The grid and its guides are drawn on the canvas, not into the picture, so neither ever lands in an export, a copied picture or a redline sheet. Off means the canvas has no grid and the View row and the Grid controls are gone.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: colorDragFlag,
                    title: "Carry a colour from one swatch to another",
                    description: "Colour swatches are something you can pick a colour up off and drop a colour onto, the way a colour well on a Mac always has been. Drag the Fill swatch onto the Outline swatch and the outline takes that colour, in one step one undo puts back. The swatch about to take it draws a ring around itself before you let go; a swatch that would not change, the one the colour came from or one already wearing it, stays dark and the pointer shows the no entry sign. Beside whatever you are aiming at, one line says what letting go would do in plain words, and says why when it would do nothing, so a dark swatch is never a mystery and a bright one tells you how many layers it is about to paint. A swatch wearing a saved colour still takes the drop, and the ring wears the palette mark first to say that letting go stops it following that name. The bar's swatches are handles too: the colour the next shape comes out in can be carried off the bar and dropped on the Library to keep it under a name, and a box's inside and border can pass their colour to each other. A colour you have saved is a handle too: drag its tile off the Library shelf onto any swatch and that swatch paints with it, keeping the name, so it still follows the saved colour the day you recolour it. A swatch that cannot wear a name, a shadow’s colour or the pair the bucket fills with, takes the colour on its own and says so before you let go. A row in the layers list takes one too, and paints the layer's main colour: the Fill of a box, the Text of a piece of writing, the Border of a picture that wears a ring. The line under the list names that part before you let go, and a layer with no colour at all says so and stays dark. Colours travel in and out of other Mac apps too, so a colour dragged from a swatch lands in another app’s colour well and one dragged in from the system Colours panel lands here. Off means the swatches are click only, exactly as before.",
                    area: .appearance,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: blankCanvasFlag,
                    title: "Start from a blank canvas",
                    description: "You can start a picture from nothing instead of only opening, pasting or capturing one. Choose File \u{25B8} New Blank Canvas from any window, or click Blank canvas on an empty window\u{2019}s card: pick a size (Desktop, Phone, Tablet, Square, or type your own) and you land on a white canvas every tool draws on right away. Asking from a window that already holds a picture leaves that picture alone and opens the canvas in a new window. Off means the File menu row is gone and a new window offers open, capture and paste only.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: copyPicksYourLayerFlag,
                    title: "Copy takes the layer you picked",
                    description: "Copy takes the layer you picked, and a marquee crops it. Pick a layer, drag a marquee over part of it and press Command C: what lands on the clipboard is that layer’s pixels inside the marquee and nothing from the layers around it, trimmed to what is actually drawn there, so pasting it back gives you the piece rather than a big transparent box. A marquee that misses the layer copies nothing and beeps instead of handing back an invisible rectangle. Everything flattened together is still one keystroke away as Edit ▸ Copy Merged on Command Shift C, of the marquee when there is one and of the whole picture when there is not, which is where Photoshop keeps it. Command X follows copy: with a marquee up it takes that layer’s pixels out of the marquee instead of deleting the whole layer. Command J, New Layer via Copy, agrees with it too: with a layer picked and a marquee drawn it makes a new layer out of that layer’s pixels inside the marquee, named after the layer it came from, so the same marquee gives you the same pixels whichever way you take them, and a marquee that misses the layer beeps instead of making an empty layer. With no layer picked, both keys copy everything inside the marquee, since there is nothing to prefer. Off means a marquee beats the layer you picked, Command C hands back every layer flattened together, and Command Shift C is File ▸ Copy Image.",
                    area: .clipboard,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: cutSaysWhatItCannotDoFlag,
                    title: "Say when a piece cannot be taken out or filled in",
                    description: "A marquee only works on a piece of a picture. Drag one over half a rectangle or a piece of text and press Command X and, before this, the whole shape vanished onto the clipboard with nothing on screen to say why; Backspace and Option Backspace did nothing at all, just as quietly. On, all three keys refuse and the canvas says so in one line at the bottom: what did not happen, why, and that clearing the marquee cuts, deletes or fills the whole layer instead. The paint bucket clicked inside the marquee says the same thing rather than going quiet where the key explains itself. A picture that has been cropped or turned gets its own line, since it is pixels and the crop is what is in the way. Taking a piece out of a plain picture and filling one are untouched, and so is working with no marquee up, which still acts on the whole layer. Off means cut silently takes the lot and the other two silently do nothing.",
                    area: .clipboard,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: pasteHandsYouThePointerFlag,
                    title: "A new picture hands you the pointer",
                    description: "Paste something, or drag a picture in from the Finder, and you are left holding the pointer with the new thing picked, so the obvious next move, dragging it where you want it, works straight away. Before this you kept whatever tool you had, and a drag on the thing you just added drew a new shape over it instead of moving it. The marquee you had up is cleared, since the new thing is what you are working on now. Undo hands your tool back: press Command Z and the rectangle, arrow or brush you were using is in your hand again, and redo takes the pointer back up. Pasting several times in a row still steps each copy past the last, each one picked in turn, and undoing the run puts back the tool you started with. A picture let go on a row in the layers list, and one placed off the Library shelf, arrive the same way. Off means paste and drop leave the tool alone, the way they always did.",
                    area: .clipboard,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: layerBoxIsItsPixelsFlag,
                    title: "A layer is the size of the pixels on it",
                    description: "A layer's box follows what is painted on it. Make a new layer and it has nothing on it, so it has no size at all: no handles, and Position and Size read as dashes with a line saying to paint something. Before this a new layer claimed the whole picture the moment it was made, so the handles went round the entire image and the numbers described nothing, and it cost a full sheet of transparent pixels nobody could see. Fill a marquee box on it and the layer becomes exactly that box, in one undo step with the colour. Paint again somewhere else on the same layer and the box grows to take the new paint in and no further, stopping at the edge of the picture. This is the other half of a rule the app already had: taking a piece out of a layer with Backspace already shrinks it to the pixels that survive. The locked Background is the exception either way and keeps the size of the picture. Filling with no marquee up still fills the whole layer, and on a layer with nothing on it that means the whole picture. Off means a new layer is picture-sized from birth and a filled box leaves it that way.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: selectionUndoFlag,
                    title: "Undo puts back a marquee you lost",
                    description: "A marquee is something you place by hand, so Command Z takes it back like everything else. Draw one, nudge it with the arrow keys, drag the outline somewhere better, invert it or clear it, and each of those is one press to undo and one to put back. Before this, a marquee never entered the undo history at all: press Command Z after spending a minute lining one up and it stepped over your last edit to the picture instead, and the outline was gone for good. Steps interleave, so undo always takes back whatever you did last, paint or outline, in the order you did it. A run of arrow-key nudges counts as one act, the way letting go of a drag does, so holding the key down is still a single press to undo. An edit that consumes the marquee, like grouping layers or New Layer via Copy, still undoes in one press and hands the outline back with it. Off means the marquee stays outside the undo history and is lost the moment it changes.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: settingsWindowFlag,
                    title: "Turn a silenced question back on",
                    description: "A command that is about to take away something you cannot see going asks you first, and that question carries a “Don’t ask again” box. Ticking it used to be permanent: the question went quiet for good and there was nowhere in the app to bring it back, so somebody who ticked it on their first day, or by accident, had given up that warning forever. With this on, Photonz has a Settings window, on Command-comma and in the menu bar menu, and its page lists every question you have silenced by the name of the command that asks it, one line saying what that question was protecting, and a button that starts it asking again from the very next time you use the command. Silence nothing and the page says so in one sentence rather than showing a row of switches, because a list of warnings you have not turned off is an invitation to go and turn them off. Off means there is no Settings window and “Don’t ask again” is a door that locks behind you.",
                    area: .app,
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

    /// The flags `name` does nothing without, whichever release asks.
    public static func dependencies(of name: String) -> Set<String> {
        for release in Release.allCases {
            if let definition = definitions(for: release).first(where: { $0.flag.name == name }) {
                return definition.needs
            }
        }
        return []
    }

    /// A fresh, untouched state for one release.
    public static func defaultSettings(for release: Release) -> FeatureFlagSettings {
        FeatureFlagSettings(flags: flags(for: release))
    }
}
