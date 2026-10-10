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
    /// Edit's panel built behind View with the rest of Edit, so its sections
    /// come in with the slide rather than just after it (`EditModeArrival`).
    public static let panelWithTheSlideFlag = "next-panel-with-the-slide"

    /// A sound clip drawn as video-audio.html draws it: the panel's own ground
    /// with a thin edge in its lane's colour, instead of video.html's green.
    public static let soundOnThePanelGroundFlag = "next-sound-on-the-panel-ground"

    public static let edgeGrabFlag = "next-edge-grab"

    public static let toolOptionsFlag = "next-tool-options"

    public static let toolSettingsFlag = "next-tool-settings"

    public static let toolGroupsFlag = "next-tool-groups"

    public static let videoToolBarFlag = "next-video-tool-bar"

    public static let toolBarFeedbackFlag = "next-tool-bar-feedback"

    public static let oneGlassToolBarFlag = "next-one-glass-tool-bar"

    public static let canvasZoomControlFlag = "next-canvas-zoom-control"

    public static let toolTipsFlag = "next-tool-tips"

    public static let designedSegmentedFlag = "next-designed-segmented"

    public static let blankCanvasFlag = "next-blank-canvas"

    public static let blankVideoFlag = "next-blank-video"

    public static let designUIStartFlag = "next-design-ui-start"

    public static let frontDoorFlag = "next-front-door"

    public static let recentDocumentsFlag = "next-recent-documents"

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

    public static let mirrorAcrossCenterFlag = "next-mirror-across-center"

    public static let iconShapeCommandsFlag = "next-icon-shape-commands"

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

    public static let copyLeavesTheCanvasOutFlag = "next-copy-leaves-the-canvas-out"

    public static let menuKeysDoWhatTheySayFlag = "next-menu-keys-do-what-they-say"

    public static let proMenuBarFlag = "next-a-pro-menu-bar"

    public static let pasteHandsYouThePointerFlag = "next-paste-hands-you-the-pointer"

    public static let cutSaysWhatItCannotDoFlag = "next-cut-says-what-it-cannot-do"

    public static let selectionUndoFlag = "next-undo-puts-back-your-marquee"

    public static let settingsWindowFlag = "next-settings-window"

    public static let marqueeIntentFlag = "next-a-box-says-what-it-picks"

    public static let layerBoxIsItsPixelsFlag = "next-a-layer-is-its-pixels"

    public static let lensFlag = "next-lens"

    public static let penFlag = "next-pen"

    public static let handToolFlag = "next-hand-tool"

    public static let drawLandingFlag = "next-where-the-point-will-land"

    public static let clickClickLineFlag = "next-click-click-draws-a-line"

    public static let dragReadoutFlag = "next-a-drag-says-its-numbers"

    public static let reshapePathFlag = "next-reshape-a-path"

    public static let turnIntoPathFlag = "next-turn-into-path"

    public static let svgExportFlag = "next-export-svg"

    public static let blendModeFlag = "next-blend-mode"

    /// See-through paint mixed the way a browser mixes it (`CompositingSpace`).
    public static let webCompositingFlag = "next-web-compositing"

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

    public static let openingARecordingFlag = "next-opening-a-recording"

    public static let recordingReadyAtStopFlag = "next-a-recording-is-ready-at-stop"

    public static let droppingMediaFlag = "next-dropping-a-sound-or-a-video"

    public static let soundOnTheTimelineFlag = "next-sound-on-the-timeline"

    public static let scrubAuditionFlag = "next-hear-the-scrub"

    public static let transitionsAtACutFlag = "next-transitions-at-a-cut"

    public static let punchInFlag = "next-punch-in-and-hold"

    public static let zoomRegionsFlag = "next-zoom-regions"

    public static let clickEffectsFlag = "next-click-effects"

    public static let pictureFadesFlag = "next-picture-fades"

    public static let titlePresetsFlag = "next-title-pages-and-name-cards"

    public static let titleOnTheTimelineFlag = "next-a-title-has-an-in-and-an-out"

    public static let captionsFromTheSoundFlag = "next-captions-from-the-sound"

    public static let componentOnTheTimelineFlag = "next-a-component-on-the-timeline"

    public static let drawnOnTheTimelineFlag = "next-anything-drawn-on-a-video-is-on-the-timeline"

    public static let recordingExportSheetFlag = "next-recording-export-sheet"

    public static let videoExportFlag = "next-export-the-video"

    public static let timelineZoomFlag = "next-open-out-the-timeline"

    public static let savingARecordingSaysSoFlag = "next-saving-a-recording-says-so"

    public static let lineEndsFlag = "next-line-ends"

    public static let arrowStylesFlag = "next-arrow-styles"

    public static let arrowBendFlag = "next-arrow-bend"

    public static let rowSaysItsWordsFlag = "next-a-row-says-its-words"

    public static let separatedRowSaysItsWordsFlag = "next-a-separated-row-says-its-words"

    public static let findALayerFlag = "next-find-a-layer"

    public static let draggedLayerLiftsFlag = "next-a-dragged-layer-lifts"

    public static let separationArrivesShutFlag = "next-a-separation-arrives-shut"

    public static let whatIsLeftInThePictureFlag = "next-what-a-separation-left-behind"

    public static let timelineIsTheLayerListFlag = "next-the-timeline-is-the-layer-list"

    public static let panelRowsInOneColumnFlag = "next-panel-rows-in-one-column"

    public static let libraryTilesAsCardsFlag = "next-library-tiles-as-cards"

    public static let dockHeadersFlag = "next-dock-headers"

    public static let noticesSayWhatHappenedFlag = "next-notices-say-what-happened"
    /// The dock builds a section's settings only once they are near enough to
    /// be seen (`PanelBodyReach`).
    public static let panelBuildsWhatYouSeeFlag = "next-panel-builds-what-you-see"

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
                    description: "The toast after a capture shows an Edit button and its key, Shift Command 6, without hovering. Off means Edit appears only while the pointer is over the toast.",
                    area: .capture,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureModesFlag,
                    title: "Measure modes",
                    description: "The Measure tool's own button picks a mode: Distance, the two-point caliper; Size, one click on an element; or Gap, one click between two elements. Off means Measure is the plain two-point caliper.",
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
                    description: "Right after drawing an arrow, type a caption and it lands in a pill at the arrow's tail; double-click an arrow to edit it. Off means arrows carry no caption.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: shapePartsFlag,
                    title: "Appearance is what it is, Effects is what you add",
                    description: "The panel splits into Appearance, what a shape has (opacity, fill, outline, corners), and Effects, a list you add shadows, glows, borders and blurs to. Off means the panel's earlier layout.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: panelSectionsFlag,
                    title: "The panel shows the sections that matter",
                    description: "A Sections row at the foot of the panel turns sections like Library, Measurements, Motion and Layout on or off for good. Left alone, each appears only once the document needs it.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: windowModesFlag,
                    title: "Set the window up for the job in front of you",
                    description: "A chip beside the traffic lights sets the window up for Icon, Redline, Video or Design, folding away the sections that job does not need. The document is never touched, and Show Everything brings them back.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: cornerHandlesFlag,
                    title: "Drag a corner to round it",
                    description: "A picked shape shows a dot inside each corner: drag one to round that corner, or hold Option to round all four. Off means corners round only from the panel.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: edgeGrabFlag,
                    title: "Pull the side of a label to set where it wraps",
                    description: "Grab any part of a picked object's outline to move that side, so a one-line label's wrap width can be dragged. Off means only the square handles resize.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: grabCueFlag,
                    title: "Every handle says what it does",
                    description: "Resting the pointer on a handle shows what a press will do: an open hand on parts that drag, resize arrows on edges, a curved arrow on the knob that turns.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: marqueeIntentFlag,
                    title: "A box says what it picks",
                    description: "A box that picks layers and a box that picks pixels look different: crawling dashes until it surrounds something, then a solid blue edge and wash. Off means both boxes look the same.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureRolesFlag,
                    title: "Measurement roles",
                    description: "Each measurement is a Size or Spacing callout with its own colors, set from a Role control in the panel, with a legend on the canvas and a Show filter.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measurePanelFlag,
                    title: "Measurements panel",
                    description: "The panel lists every measurement with its eye, name and value, and its menu can show, hide, clear or copy them all as a text spec list. The toolbar shows a count.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureCenterSnapFlag,
                    title: "Snap to centers",
                    description: "A Snap option in the Measure Tool section lets measure points also magnetize to element and gap centers, the midpoint between neighboring edges. Hold Command to drag free.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureGuideSnapFlag,
                    title: "Snap to other measurements",
                    description: "Drag a measurement's readout chip or foot and it snaps into line with the other measurements, shown by a yellow guide. Hold Command to drag free.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureLayerSnapFlag,
                    title: "Snap to the edges of what you drew",
                    description: "A caliper foot snaps to the exact edge of any layer you drew, not just edges found in the picture. Hold Command to drag free.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureReadoutSlideFlag,
                    title: "Slide a measurement's number along its line",
                    description: "Drag a measurement's number along its line as well as away from it, and it stays where you put it. Off means the number can only be pushed away from what it measures.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: windowCaptureFlag,
                    title: "Capture a window by clicking it",
                    description: "During a region capture, click the highlighted window to capture just that window, with its shadow and rounded corners; hold Option for the other choice. Off means the overlay is drag only.",
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
                    description: "Layer ▸ Position and Size, on Option Command P, opens X, Y, W, H and angle fields to type exact numbers for everything picked, in one undo. Off means position, size and angle are drag only.",
                    area: .layout,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: alignLayersFlag,
                    title: "Line layers up with each other",
                    description: "With two or more layers picked, an Arrange row lines up edges or centres and spaces them evenly, and a dragged layer snaps to other layers. Off means dragging snaps to the picture only.",
                    area: .layout,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolOptionsFlag,
                    title: "Tool options off the tool bar",
                    description: "Crop keeps its aspect locks in its own tool button and the Magic Wand's tolerance moves to the panel, so the tool bar never widens. Off means both tools lay their options along the bar.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolSettingsFlag,
                    title: "Tool settings ride above the tool bar",
                    description: "The tool in your hand shows its settings in a small capsule above the tool bar, kept in step with the panel. Off means these settings live only in the panel.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolGroupsFlag,
                    title: "Tool bar families",
                    description: "The tool bar groups tools into families, and Line, Rectangle and Ellipse share one Shapes button that remembers your last pick. Off means one button per tool in the old order.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: videoToolBarFlag,
                    title: "A video has its own tool bar",
                    description: "A document with time shows Select, Blade, Title / Text, Shape and Measure, and every other tool waits under More, still on its key. Off means a video shows the whole picture tool bar.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: oneGlassToolBarFlag,
                    title: "The tool bar is one glass bar",
                    description: "The tools, More, the colour pair and the zoom sit in one glass bar with a hairline between each, on pictures and videos alike. Off means each is its own glass capsule.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: canvasZoomControlFlag,
                    title: "Zooming shows a zoom control",
                    description: "Zooming brings up a small zoom control in the canvas's bottom right corner that fades 5 seconds after the last zoom and returns when you point at it. Off means zoom shows no control.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: designedSegmentedFlag,
                    title: "Side-by-side choices slide",
                    description: "Every row of side-by-side choices is a soft capsule with a tinted glass chip that slides to what you pick, the View and Edit switch included. Off means the system's segmented control.",
                    area: .appearance,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolBarFeedbackFlag,
                    title: "Tool bar buttons respond to the pointer",
                    description: "Tool bar buttons show a soft fill when pointed at and a stronger fill with a slight shrink when pressed. Off means the buttons sit still until clicked.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: setupTakesNoForAnAnswerFlag,
                    title: "Saying no to the setup window sticks",
                    description: "Closing the setup window without Screen Recording is remembered, and a later capture offers a button to open setup. Off means the setup window returns at every launch until the permission is on.",
                    area: .app,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: tutorialsFlag,
                    title: "Guided tutorials",
                    description: "Adds a Help menu of guided tutorials in tracks, where a card beside each control walks you through one step at a time. Off means no Help menu and no guides.",
                    area: .app,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolTipsFlag,
                    title: "Buttons explain themselves with a tooltip",
                    description: "Buttons that are only an icon show the app's own tooltip with their name and key. Off means the plain system help tag, which may not show at all.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: layersFollowPickFlag,
                    title: "The layers list follows what you pick",
                    description: "Picking something on the canvas scrolls the layers list just enough to show its row, opening a shut group if needed. Off means the list stays where it was.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: canvasMenuFlag,
                    title: "Right click the picture",
                    description: "Right click something on the canvas for its actions, like duplicate, group, hide or delete, or empty canvas for paste, select all and zoom to fit. Off means a right click there does nothing.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: layerGroupsFlag,
                    title: "Group what you selected",
                    description: "Command G groups the picked layers so they move, hide and delete together, Shift Command G ungroups, and a double click goes inside. Off means no Group or Ungroup; existing groups still draw.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: separateIntoLayersFlag,
                    title: "Separate a screenshot into layers",
                    description: "Separate into Layers turns each run of text and each box in a screenshot into its own layer, filling in behind them, and Turn into Text makes a run editable. Off means both commands are absent.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: doubleClickReadsALabelFlag,
                    title: "Double click a label in a separated screenshot to retype it",
                    description: "After Separate into Layers, double click a label to read its words and start typing, the same as Turn into Text. Off means a double click only picks the label.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: readEveryLabelFlag,
                    title: "Read every label in a separated screenshot at once",
                    description: "After Separate into Layers, one press reads every label into editable text in one undo, matching them all to one typeface. Off means Turn into Text reads one label at a time.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: newLayerViaCutFlag,
                    title: "Cut a piece onto its own layer and heal behind it",
                    description: "Shift Command J lifts the marquee's piece onto its own layer and heals the space behind it from the colours around it. Off means the command is absent and Command J copies without healing.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: copyALookFlag,
                    title: "Copy the look of one shape onto another",
                    description: "Copy Look and Paste Look, on Option Shift Command C and V, carry one shape's colours, outline, corners, opacity, blending and effects onto others. Off means neither command exists.",
                    area: .appearance,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: motionFlag,
                    title: "Tell a layer to change one of its properties over time",
                    description: "Adds a Motion list to the panel: animate a layer's position, size, rotation, opacity or colour over time, with timing, curve and repeat. Off means no Motion section and nothing moves.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: animatedSVGExportFlag,
                    title: "An animated icon leaves the app as an animated SVG",
                    description: "Export first asks where the file is going, and a web page gets an animated SVG that keeps its motion. Off means Export never asks and an SVG is always still.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: recordingExportSheetFlag,
                    title: "A recording leaves through the same Export sheet as everything else",
                    description: "Export on a recording, Shift Command S, opens the same sheet as a picture, with MP4, GIF and HEIC, size presets and an estimated file size. Off means Save As opens the plain save box.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: savingARecordingSaysSoFlag,
                    title: "Saving a recording says it saved",
                    description: "Saving a trimmed recording shows its thumbnail in the corner saying it saved, with a progress bar for a long save. Off means saving is silent apart from the spinner on the controller.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: cutRecordingFlag,
                    title: "Cut a recording into pieces and drop the one you do not want",
                    description: "Press B or Split at Playhead to cut a recording into pieces, and Delete removes the piece you are on with no gap left behind. Off means B and Delete do nothing.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: droppingMediaFlag,
                    title: "Drop a sound or a video on the window and it lands, or says why not",
                    description: "Drop a sound or a video on the window and it lands on the timeline at the playhead, opens in its own window, or says why it cannot. Off means a drop is refused without a word.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: openingARecordingFlag,
                    title: "Opening a recording lands you somewhere you can work",
                    description: "File ▸ Open and Open With in the Finder open a movie as a recording, a missing file says so, and a recording reopens where you left it. Off means History is the only way in.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: recordingReadyAtStopFlag,
                    title: "A recording is ready the moment you stop it",
                    description: "Stop puts the recording's last frame on its tile at once, opening it shows that frame while the file finishes, and the corner says Copying until it is copied. Off means the tile and the editor wait for the file.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: videoExportFlag,
                    title: "An edited recording comes out as a video file",
                    description: "Export on an edited recording writes a video of what plays, with every cut, title and the sound mix, as MP4, GIF or HEIC. Off means Export on a recording writes a still picture.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: timelineZoomFlag,
                    title: "Open the timeline out and work on one second of it",
                    description: "Zoom the timeline in as far as one second across its width, with a bar above the ruler showing where you are; Fit shows it all again. Off means the timeline always shows the whole recording.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: transitionsAtACutFlag,
                    title: "Put a transition on a cut, and change an effect over a shot",
                    description: "Pick a cut to give it a cross dissolve or a dip to black or white, and animate a blur over a shot in the Motion list. Off means every cut is hard and a blur stays fixed.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: punchInFlag,
                    title: "Punch in on something and hold there",
                    description: "Drag a box on a clip and Punch In to move the camera onto it at the playhead and hold, then Pull Back Out. Off means a clip is framed one way for its whole length.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: zoomRegionsFlag,
                    title: "Zoom in on a spot of a recording, and follow the pointer",
                    description: "Add Zoom on a recording frames one spot of it for a while: a bar under the clip, a box on the picture, and it can follow the recorded pointer. Off means a recording is always shown whole.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: clickEffectsFlag,
                    title: "An effect at each click of a recording",
                    description: "A Clicks row on a recording's Properties draws a ripple, a pulse or a spotlight at every click the recorder took down, and marks each click on the clip's bar. Off means clicks are never drawn.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: titlePresetsFlag,
                    title: "Title pages and name cards",
                    description: "Sequence and an empty track's right-click insert a title page or name card preset at the playhead, animated in and out, and Save as Preset keeps your own. Off means titles are typed with the Text tool only.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: pictureFadesFlag,
                    title: "Fade a clip in and out",
                    description: "Right click anything on the timeline for Fade In and Fade Out, or drag the handle at a top corner of its bar, to bring its picture up out of black and back down. Off means only sounds fade.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: titleOnTheTimelineFlag,
                    title: "Words over the picture arrive and leave",
                    description: "Text on a video gets an in and an out, a bar on the timeline you drag, and an optional fade. Off means text on a recording is on screen for all of it.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: captionsFromTheSoundFlag,
                    title: "Have the app write the captions off the sound",
                    description: "Right click a clip and choose Add Captions to write captions from its speech on this Mac, on a Captions track you can edit and style. Off means no captions are written.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: componentOnTheTimelineFlag,
                    title: "Put something you built on the timeline and animate it",
                    description: "A component placed on a video gets an in and an out on the timeline, stays linked to its original and plays its own animation. Off means it shows for the whole video and stands still.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: drawnOnTheTimelineFlag,
                    title: "Anything you draw on a video is on the timeline",
                    description: "A shape, line or picture drawn on a video gets its own timeline row, from the playhead to the end of the shot. The diamond on its row keys it; move the playhead, drag it, and it tweens.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: timelineIsTheLayerListFlag,
                    title: "On a video, the timeline is the layer list",
                    description: "On a video, the panel drops its Layers list while the timeline shows, because the timeline already lists every clip. Fold the timeline away and Layers comes back; pictures are untouched.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: soundOnTheTimelineFlag,
                    title: "Take a recording's sound off its picture, bring more in, see it and shape it",
                    description: "Detach Sound puts a clip's sound on its own layer, Add Sound brings in music, and each sound shows a waveform with a level line and fades. Off means a recording plays silently.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: scrubAuditionFlag,
                    title: "Hear the sound under the playhead while you drag it",
                    description: "Dragging the playhead plays the sound under it, backwards too, so you can find a word or a beat by ear. Off means scrubbing is silent.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: motionStripFlag,
                    title: "See every moving part on one strip across the bottom",
                    description: "A strip across the bottom shows every moving part as a bar in time: drag a bar to change when it starts or how long it takes. Option Command T hides it.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: penFlag,
                    title: "Draw any shape with the Pen",
                    description: "Adds the Pen, P, for drawing corners and curves, and Combine Shapes to join shapes, cut one out of another, or keep or drop their overlap. Off means no Pen and no Combine Shapes.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: handToolFlag,
                    title: "Move around the picture with the Hand",
                    description: "Adds the Hand to the end of the tool bar: pick it and drag the canvas to move the view without moving anything on it. Off means no Hand.",
                    area: .tools,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: dragReadoutFlag,
                    title: "A drag says where it is and how big it is while it happens",
                    description: "While you move or resize something, a small pill under it shows its position or size, gone when you let go. Off means a drag shows no numbers.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: drawLandingFlag,
                    title: "See where a point will land before you press",
                    description: "Before you press, a ring under the pointer shows where a drawing tool's point will snap; hold Command to place it freely. Off means points still snap, but silently.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: clickClickLineFlag,
                    title: "Click, let go, click again draws a line",
                    description: "With the Line or Arrow tool, a click starts a line that follows the pointer until a second click ends it; Escape calls it off. Off means a line is only drawn by dragging.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: turnIntoPathFlag,
                    title: "Turn a rectangle into a path",
                    description: "Turn Into Path makes a rectangle, ellipse, line or wash an outline you can reshape, and welds shapes whose ends meet into one path, with Join Paths and Close Path for Pen outlines. Off means shapes stay shapes.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: whatIsLeftInThePictureFlag,
                    title: "What a separation left behind stays on the picture's row",
                    description: "After Separate into Layers, the picture's row in the layers list shows how many pieces are left, with Separate again beside it. Off means only the passing pill says so.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: rowSaysItsWordsFlag,
                    title: "A row says the words that are in it",
                    description: "A text layer you have not named shows its own words in the layers list and follows them as you type. Off means it says Text and a number.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: separatedRowSaysItsWordsFlag,
                    title: "A separated run of text says the words in it",
                    description: "After Separate into Layers, text pieces are read in the background so their rows in the layers list show their words. Off means every piece says Text and a number.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: findALayerFlag,
                    title: "Find a layer by typing",
                    description: "A find field over a long layers list shows only the layers whose rows hold what you type, even inside shut groups. Off means no field and no searching.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: draggedLayerLiftsFlag,
                    title: "A dragged layer lifts and the list makes room",
                    description: "Dragging a layer row or a track's header lifts it under the pointer, and the rows around it move aside to open the gap it lands in. Off: a drag image and drop line, and tracks stay put.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: separationArrivesShutFlag,
                    title: "A big separation arrives in one shut group",
                    description: "A big Separate into Layers puts every piece into one shut group named after the picture. Off means the pieces arrive loose over the picture.",
                    area: .separating,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: []),
            Definition(
                flag: FeatureFlag(
                    name: lineEndsFlag,
                    title: "Say how a line and an arrow end",
                    description: "A picked line or arrow gets an Ends row under Outline: Flat, Round or Square. Off means a line and an arrow always end round.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: arrowStylesFlag,
                    title: "Draw arrows by hand",
                    description: "An arrow gets a Style row of picture tiles: Clean, Hand-drawn, Marker, Brush and Sketch, with Reshuffle on its right-click menu for a new hand. Off means every arrow is the clean geometric one.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: arrowBendFlag,
                    title: "Bend an arrow",
                    description: "A picked arrow shows a handle in the middle of its line that curves it, the head turning to follow, and double clicking the handle straightens it. Off means an arrow has only its two end handles.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: reshapePathFlag,
                    title: "Reshape a path after you have drawn it",
                    description: "Pick a Pen path to show its points: drag points and levers, double click to add a point or smooth a corner, Delete to remove one. Off means a path is a box you move and resize.",
                    area: .drawing,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: svgExportFlag,
                    title: "Export what you drew as SVG",
                    description: "Adds SVG to Export, so what you draw leaves as sharp, editable shapes, with anything that cannot be a shape embedded as a picture. Off means only the picture formats.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: exportQualityFlag,
                    title: "Choose the quality of an export and see what it will weigh",
                    description: "Adds a Quality slider for JPEG and HEIC to Export, with the exact file size shown before you save. Off means Export uses the quality it always did.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: webPExportFlag,
                    title: "Export as WebP",
                    description: "Adds WebP to Export, with the same Quality slider and a lossless file at 100 percent. Off means Export offers the formats it always did.",
                    area: .export,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: lensFlag,
                    title: "A layer that changes what is under it",
                    description: "The Lens tool, K, replaces the Zoom Callout: drag a box to blur, pixelate, greyscale, invert, brighten or magnify what is under it. Off means the Zoom Callout comes back.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: layersCombineFlag,
                    title: "A layer can key a colour out and take its shape from the layer below",
                    description: "Adds Key out a colour, to make a background like a green wall transparent, and Masked by, to cut a layer to the shape of the one below. Off means neither row appears.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: blendModeFlag,
                    title: "A layer can say how it mixes with what is under it",
                    description: "Adds a Blending row under Opacity: Normal, Multiply, Screen, Darken or Lighten, previewed on the canvas as you move down the list. Off means no Blending row.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: webCompositingFlag,
                    title: "See-through things are the shade a browser draws",
                    description: "Shadows, faded layers and soft edges mix with what is under them the way a browser, Figma and an exported file do, so what you approve is what you hand over. Off means the lighter mix Photonz has always drawn.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: framesFlag,
                    title: "Build on a frame",
                    description: "Press F to draw a frame, a screen to build on that clips what hangs off it, and hold several side by side on one canvas. Off means no frame tool.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: iconFramesFlag,
                    title: "Make a frame the size of an icon",
                    description: "New Frame offers icon sizes from 16 to 512 pixels, and opens a small frame zoomed in far enough to draw on. Off means the size list has screens only.",
                    area: .icons,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: iconPreviewsFlag,
                    title: "See an icon at the size it will be used",
                    description: "Working in an icon frame shows it at 16 to 64 pixels in the corner of the canvas, playing when it moves. Off means no preview row.",
                    area: .icons,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: mirrorAcrossCenterFlag,
                    title: "Mirror a shape across the center",
                    description: "Layer ▸ Mirror Across Center (⇧⌘M) copies the picked shape reflected about the middle of its frame, so a symmetrical icon is exact. Off means no Mirror command.",
                    area: .icons,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: iconShapeCommandsFlag,
                    title: "Center, Union and Outline Stroke",
                    description: "Center on the Artboard, Union (⌥⌘U) and Outline Stroke (⇧⌘O) in the Layers panel menu, the Layer menu and a shape's right-click menu, as the icon drawing mock puts them. Off means none of the three rows.",
                    area: .icons,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: libraryFlag,
                    title: "Keep reusable pieces in a Library",
                    description: "Adds a Library to the right dock, View ▸ Show Library, with Media, Components, Styles and Systems shelves and a search field. Off means no Library.",
                    area: .library,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: componentsFlag,
                    title: "Make a component out of what you drew",
                    description: "Option Command K turns a group into a named component that sits on the Library's Components shelf. Off means no Make Component.",
                    area: .library,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: stylesFlag,
                    title: "Save a color, a text style or an effect and reuse it",
                    description: "Save a color, a text style or an effect under a name for any layer to wear, and change it once to update them all. Off means colors, text and effects are one-offs.",
                    area: .library,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: sharedLibraryFlag,
                    title: "Use a component you made in every document",
                    description: "A Share across documents switch puts a component on a shelf every document can use, and an edit to it reaches every copy. Off means a component stays in its own document.",
                    area: .library,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: starterComponentsFlag,
                    title: "Components in the Library from the start",
                    description: "The Library starts with five components: a button, a text field, a card, a nav bar and a badge. Off means the shelf holds only components you made.",
                    area: .library,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: colorPickerFlag,
                    title: "One color picker, everywhere a color is chosen",
                    description: "Every swatch opens one color picker with HSL, RGB and HEX, suggested and recent swatches, an eyedropper and gradients. Off means the older picker or the system color panel.",
                    area: .appearance,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: autoLayoutFlag,
                    title: "Groups that arrange their own contents",
                    description: "Make a group a stack or a grid, Layer ▸ Stack Selection, so its contents space and size themselves, with Hug, Fixed and Fill sizes. Off means no Arrangement rows.",
                    area: .layout,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: placementFlag,
                    title: "Say where the pieces sit when something is resized",
                    description: "A Layout section says where pieces sit when a group is resized, like a label staying centred as its button grows. Off means a resize scales everything proportionally.",
                    area: .layout,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: crispZoomFlag,
                    title: "Words stay sharp when you zoom in",
                    description: "Past 100%, the labels, captions and readouts you placed are redrawn sharp at your zoom, while the screenshot stays pixelated. Off means placed text goes soft as you zoom in.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: calloutShapeFlag,
                    title: "Choose a zoom callout\u{2019}s shape before you draw it",
                    description: "Choose Rectangle or Circle for the Zoom Callout before drawing, and the tool remembers it. Off means every callout starts as a rectangle.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: calloutMagnificationFlag,
                    title: "Choose how much a callout magnifies before you draw it",
                    description: "Set how much the next Zoom Callout magnifies before you draw it, and the tool remembers it. Off means every new callout starts at 2×.",
                    area: .measuring,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: canvasGridFlag,
                    title: "A grid to build against",
                    description: "View ▸ Show Grid draws a grid that adapts as you zoom, and Adjust Grid sets where it counts from and pins guides that things snap to. Off means no grid.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: colorDragFlag,
                    title: "Carry a colour from one swatch to another",
                    description: "Drag a colour from one swatch to another, to and from the Library, onto a layer row, or to and from other Mac apps. Off means swatches are click only.",
                    area: .appearance,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: blankCanvasFlag,
                    title: "Start from a blank canvas",
                    description: "File ▸ New Blank Canvas starts a white canvas at a size you pick, such as Desktop, Phone or Square. Off means you can only open, paste or capture a picture.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: blankVideoFlag,
                    title: "Start a video from an empty timeline",
                    description: "File \u{25B8} New Video starts a video from nothing: pick a size and a length, and you get an empty V1 over an empty Audio track, the Library open for Import. Off means a video only starts from a recording.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: designUIStartFlag,
                    title: "Start a UI design from an empty window",
                    description: "An empty window offers Design UI, and File has New UI Design: a 1280 \u{00D7} 800 canvas holding a Login frame laid out as a column, the Library open on Components. Off means you draw the frame yourself.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: frontDoorFlag,
                    title: "New Window opens the front door",
                    description: "New Window opens a small window to start from, with Open, four templates and your recent captures, and a template sets the mode and names what the main button makes. Off means an empty window with its card.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: recentDocumentsFlag,
                    title: "Recent lists the documents you open",
                    description: "The documents you open and save are remembered: the front door's Recent shows them among your captures, and File has Open Recent with Clear Menu. Off means Recent shows captures only and File has no Open Recent.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: proMenuBarFlag,
                    title: "The menu bar reads like a pro editor's",
                    description: "The menus run File, Edit, Image, Layer, Clip and Sequence on a video, then View, Window and Help, with Capture inside File. Off means the old Capture and Video menus, with View before them.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: menuKeysDoWhatTheySayFlag,
                    title: "Every key a menu shows does what it says",
                    description: "Command Delete deletes the layer and Option Delete fills it from anywhere, not only the picture, and the layer menu shows Command J for Duplicate. Off, only the picture answers those keys and Duplicate shows Command D, which is Deselect.",
                    area: .layers,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: copyPicksYourLayerFlag,
                    title: "Copy takes the layer you picked",
                    description: "Command C copies only the picked layer's pixels inside the marquee, and Command Shift C copies everything merged. Off means Command C copies every layer flattened together.",
                    area: .clipboard,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: copyLeavesTheCanvasOutFlag,
                    title: "A copied picture leaves a blank canvas out",
                    description: "Copying a drawing made on a blank canvas leaves the canvas out, the way Export does, while screenshots copy whole. Off means the canvas colour always comes with the copy.",
                    area: .clipboard,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: cutSaysWhatItCannotDoFlag,
                    title: "Say when a piece cannot be taken out or filled in",
                    description: "When cut, delete or fill cannot act on part of a shape or text, a line at the bottom of the canvas says why. Off means cut silently takes the whole layer and the others do nothing.",
                    area: .clipboard,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: pasteHandsYouThePointerFlag,
                    title: "A new picture hands you the pointer",
                    description: "Pasting or dropping a picture hands you the pointer with it picked, so you can drag it straight away; undo gives your tool back. Off means your tool stays in hand.",
                    area: .clipboard,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: layerBoxIsItsPixelsFlag,
                    title: "A layer is the size of the pixels on it",
                    description: "A new layer has no size until you paint on it, then its box grows to fit the paint. Off means a new layer is the size of the picture.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: selectionUndoFlag,
                    title: "Undo puts back a marquee you lost",
                    description: "Command Z undoes drawing, moving or clearing a marquee, in order with your other edits. Off means a marquee is lost the moment it changes.",
                    area: .selecting,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: settingsWindowFlag,
                    title: "Turn a silenced question back on",
                    description: "Adds a Settings window, Command comma, listing every question you silenced with Don't ask again, each with a button to turn it back on. Off means no Settings window.",
                    area: .app,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: panelRowsInOneColumnFlag,
                    title: "Every panel row has its name in one column",
                    description: "Every panel row puts a short grey name in one left column with its control beside it, or under it when too wide. Off means older sections stack names over controls.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: libraryTilesAsCardsFlag,
                    title: "Library tiles are cards",
                    description: "Library tiles are at least 96 points wide, two to a row in a resting dock, with a 16 by 10 picture, so long names read whole. Off means smaller tiles, three to a row.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: dockHeadersFlag,
                    title: "Panel group headings as the mocks draw them",
                    description: "Each panel group has a small capital title, a chip beside it saying what it holds, such as Clip, Media or an effect count, and its buttons at the far edge. Off means title case headings ending in a grip.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: soundOnThePanelGroundFlag,
                    title: "Sound clips on the panel colour",
                    description: "A sound clip on the timeline is drawn in the panel's own colour with a thin edge in its track's colour, so the waveform is the coloured shape. Off means sound clips are green.",
                    area: .motion,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: []),
            Definition(
                flag: FeatureFlag(
                    name: panelWithTheSlideFlag,
                    title: "The panel comes in with the slide",
                    description: "Switching a recording from View to Edit brings the panel's settings in with the slide, at the cost of a slightly less smooth slide. Off means the slide is smooth and the settings fill in just after it lands.",
                    area: .panel,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: []),
            Definition(
                flag: FeatureFlag(
                    name: noticesSayWhatHappenedFlag,
                    title: "Notices say what happened",
                    description: "No line of instructions stands over the canvas for the Pen, Measure or a path, and notices report results with Undo instead of advice. Off means the hint lines and the advice come back.",
                    area: .canvas,
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: panelBuildsWhatYouSeeFlag,
                    title: "The panel builds what you can see",
                    description: "On a video, panel sections far below the bottom of the panel are built when you scroll near them, so clicking from a clip to a cut answers sooner. Off builds every section at once.",
                    area: .panel,
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
