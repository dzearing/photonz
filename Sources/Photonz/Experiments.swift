import Observation
import PhotonzCore
import SwiftUI

/// App-level access to the Experiments settings: which release this launch is
/// running, and every release's feature flags.
///
/// Two Photonz experiences live in one binary. A release's own code lives in
/// `Sources/Photonz/Releases/<Release>/` and is reached through
/// `ReleaseExperience`, which owns the only switch over `Release` in the app.
/// Smaller differences hide behind a feature flag
/// (`Experiments.shared.isEnabled(…)`) instead of a fork. See
/// `Sources/Photonz/Releases/README.md` and `docs/design/experiments.md`.
///
/// Release switching takes a relaunch: the choice reaches AppKit surfaces built
/// outside SwiftUI's environment (the menu-bar agent, the capture overlay, the
/// floating panels), and windows opened under one release shouldn't half-morph
/// into the other. Flag edits inside the running release apply live, because
/// this object is observable and call sites read it when they draw.
@MainActor
@Observable
final class Experiments {
    /// The app-wide instance. A singleton on purpose: AppKit surfaces that
    /// never see the SwiftUI environment still have to read flags.
    static let shared = Experiments()

    /// The release this process is running. Fixed at launch.
    let release: Release

    /// The release that will be running after the next launch. Setting it
    /// persists right away, so the choice survives a crash or a plain quit.
    var selectedRelease: Release {
        didSet {
            guard selectedRelease != oldValue else { return }
            store.selectedRelease = selectedRelease
        }
    }

    /// True while the chosen release isn't the one on screen.
    var needsRelaunch: Bool { selectedRelease != release }

    private let store: ExperimentsStore
    private var settingsByRelease: [Release: FeatureFlagSettings]

    init(store: ExperimentsStore = ExperimentsStore(defaults: UserDefaultsExperimentsDefaults())) {
        self.store = store
        let selected = store.selectedRelease
        release = selected
        selectedRelease = selected
        settingsByRelease = Dictionary(uniqueKeysWithValues:
            Release.allCases.map { ($0, store.settings(for: $0)) })
    }

    // MARK: - Reading (the running release)

    var activeSettings: FeatureFlagSettings { settings(for: release) }

    func isEnabled(_ flag: String) -> Bool { activeSettings.isEnabled(flag) }

    func number(_ flag: String, _ parameter: String) -> Double? {
        activeSettings.number(flag, parameter)
    }

    func string(_ flag: String, _ parameter: String) -> String? {
        activeSettings.string(flag, parameter)
    }

    func boolean(_ flag: String, _ parameter: String) -> Bool? {
        activeSettings.boolean(flag, parameter)
    }

    func selection(_ flag: String, _ parameter: String) -> String? {
        activeSettings.selection(flag, parameter)
    }

    // MARK: - Reading & editing (any release)

    func settings(for release: Release) -> FeatureFlagSettings {
        settingsByRelease[release] ?? FeatureCatalog.defaultSettings(for: release)
    }

    func setEnabled(_ enabled: Bool, flag: String, in release: Release) {
        store.setEnabled(enabled, flag: flag, in: release)
        settingsByRelease[release] = store.settings(for: release)
    }

    func setParameter(_ parameter: String, of flag: String,
                      to value: FeatureParameterValue, in release: Release) {
        store.setParameter(parameter, of: flag, to: value, in: release)
        settingsByRelease[release] = store.settings(for: release)
    }

    /// Puts one release back to the shipped defaults. Other releases are
    /// untouched.
    func resetToDefaults(for release: Release) {
        store.resetToDefaults(for: release)
        settingsByRelease[release] = store.settings(for: release)
    }
}

// MARK: - Flag readers
//
// One place per flag where the raw names and fallbacks live, so call sites stay
// a single readable line. Fallbacks matter: a flag can be off, retired, or
// half-configured, and the app has to behave exactly like stock Photonz then.

extension Experiments {
    /// `release-tag-in-window-title`: returns the title with the release tag
    /// attached, or the title untouched when the flag is off.
    func decorated(windowTitle: String) -> String {
        guard isEnabled(FeatureCatalog.releaseTagFlag) else { return windowTitle }
        let tag = string(FeatureCatalog.releaseTagFlag, FeatureCatalog.releaseTagLabel) ?? release.title
        let placementName = selection(FeatureCatalog.releaseTagFlag, FeatureCatalog.releaseTagPlacement) ?? ""
        let uppercase = boolean(FeatureCatalog.releaseTagFlag, FeatureCatalog.releaseTagUppercase) ?? false
        return ReleaseTag.decorate(windowTitle, tag: tag,
                                   placement: ReleaseTag.Placement(name: placementName) ?? .suffix,
                                   uppercase: uppercase)
    }

    /// `capture-toast-timing`: how long a post-capture toast holds before it
    /// starts fading.
    var captureToastHoldSeconds: Double {
        guard isEnabled(FeatureCatalog.captureToastTimingFlag) else {
            return FeatureCatalog.captureToastHoldSeconds
        }
        return number(FeatureCatalog.captureToastTimingFlag, FeatureCatalog.captureToastHold)
            ?? FeatureCatalog.captureToastHoldSeconds
    }

    /// `next-capture-toast-edit`: whether the capture toast shows its Edit
    /// button (with the key) all the time instead of only while hovered.
    /// Exists only in the Next release's catalog, so Current always reads
    /// false and keeps the hover-only pencil.
    var captureToastEditEnabled: Bool { isEnabled(FeatureCatalog.captureToastEditFlag) }

    /// `next-measure-modes`: whether the Measure tool offers Distance, Size and
    /// Gap as modes you pick. Exists only in the Next release's catalog, so
    /// Current always reads false and keeps the plain two-point caliper.
    var measureModesEnabled: Bool { isEnabled(FeatureCatalog.measureModesFlag) }

    /// `next-measure-modes` / distance-on-release: whether a Distance caliper
    /// lands the moment you let go of the drag, with its number placed the way
    /// Gap places its own, instead of waiting for a third click. Off means the
    /// three-click flow. Reads false whenever Measure modes itself is off.
    var measureDistanceLandsOnRelease: Bool {
        measureModesEnabled
            && boolean(FeatureCatalog.measureModesFlag,
                       FeatureCatalog.measureDistanceOnRelease) == true
    }

    /// `next-measure-align`: whether the Measure tool offers its Alignment
    /// mode (drag a guide along an edge to check everything it crosses).
    /// Exists only in the Next release's catalog, so Current always reads false.
    var measureAlignEnabled: Bool { isEnabled(FeatureCatalog.measureAlignFlag) }

    /// `next-measure-align`: how far (px) an edge may sit from the reference
    /// line and still count as aligned.
    var measureAlignTolerance: CGFloat {
        CGFloat(number(FeatureCatalog.measureAlignFlag, FeatureCatalog.measureAlignTolerance) ?? 1)
    }

    /// `next-measure-center-snap`: whether the Measure tool offers its Snap
    /// option (Edges / Edges and centers) and center snapping at all. Exists
    /// only in the Next release's catalog, so Current always reads false.
    var measureCenterSnapEnabled: Bool { isEnabled(FeatureCatalog.measureCenterSnapFlag) }

    /// `next-measure-guide-snap`: whether measurements magnetize to each other
    /// — a dragged readout chip lines up with the other chips, a dragged foot
    /// with the other calipers' feet and lines. Exists only in the Next
    /// release's catalog, so Current always reads false.
    var measureGuideSnapEnabled: Bool { isEnabled(FeatureCatalog.measureGuideSnapFlag) }

    /// `next-measure-readout-slide`: whether dragging a readout also slides it
    /// along its own measuring line, instead of only across it.
    var measureReadoutSlideEnabled: Bool { isEnabled(FeatureCatalog.measureReadoutSlideFlag) }

    /// `next-measure-roles`: whether measurements carry Size/Spacing roles —
    /// the inspector's Role control, per-role remembered colors, the canvas
    /// legend, and the tool options' Show filter. Exists only in the Next
    /// release's catalog, so Current always reads false.
    var measureRolesEnabled: Bool { isEnabled(FeatureCatalog.measureRolesFlag) }

    /// `next-measure-panel`: whether the layers panel grows its Measurements
    /// group (rows, count pill, panel menu) and the measure inspector its
    /// From/To/Distance grid and Export section. Exists only in the Next
    /// release's catalog, so Current always reads false.
    var measurePanelEnabled: Bool { isEnabled(FeatureCatalog.measurePanelFlag) }

    /// `next-arrow-captions`: whether drawing an arrow offers an inline caption
    /// (and arrows are double-clickable to edit one). Exists only in the Next
    /// release's catalog, so Current always reads false.
    var arrowCaptionsEnabled: Bool { isEnabled(FeatureCatalog.arrowCaptionsFlag) }

    /// `next-grab-cue`: whether the pointer turns into a hand over a pill that
    /// drags on its own (an arrow's caption, a measurement's number). Exists
    /// only in the Next release's catalog, so Current always reads false.
    var grabCueEnabled: Bool { isEnabled(FeatureCatalog.grabCueFlag) }

    /// `next-tool-options`: whether the Crop tool and the Magic Wand keep their
    /// options off the floating tool bar (D15) — crop aspect in the crop
    /// button's flyout, crop actions on the canvas, wand tolerance in the
    /// inspector. Exists only in the Next release's catalog, so Current always
    /// reads false and keeps both option rows in the bar.
    var toolOptionsEnabled: Bool { isEnabled(FeatureCatalog.toolOptionsFlag) }

    /// `next-callout-shape`: whether the Zoom Callout tool carries its own
    /// Shape choice while it is in hand, remembered between callouts, so a
    /// circle is one choice rather than a rectangle you go back and fix.
    /// Exists only in the Next release's catalog, so Current always reads
    /// false and every callout is drawn as a rectangle.
    var calloutShapeEnabled: Bool { isEnabled(FeatureCatalog.calloutShapeFlag) }

    /// `next-tool-groups`: whether the floating tool bar lays its tools out
    /// as families (`ToolBarLayout.families`), with Line / Rectangle / Ellipse
    /// sharing one Shapes button and Resize Image riding in the Crop flyout.
    /// Exists only in the Next release's catalog, so Current always reads
    /// false and keeps one button per tool.
    var toolGroupsEnabled: Bool { isEnabled(FeatureCatalog.toolGroupsFlag) }

    /// `next-tool-bar-feedback`: whether the floating tool bar's buttons (and
    /// the inspector toggle) show the shared hover fill and pressed shrink of
    /// `IconActionButtonStyle`. Exists only in the Next release's catalog, so
    /// Current always reads false and its buttons sit still until clicked.
    var toolBarFeedbackEnabled: Bool { isEnabled(FeatureCatalog.toolBarFeedbackFlag) }

    /// `next-tool-tips`: whether the floating tool bar's buttons explain
    /// themselves with the design-language tooltip (`HintTooltip.swift`: name
    /// plus key, rest-gated, placed above the control) instead of the system
    /// help tag. Exists only in the Next release's catalog, so Current always
    /// reads false and keeps `.help`.
    var toolTipsEnabled: Bool { isEnabled(FeatureCatalog.toolTipsFlag) }

    /// `next-blank-canvas`: whether an empty window offers Blank canvas
    /// alongside open, capture and paste. Exists only in the Next release's
    /// catalog, so Current always reads false and its empty window is
    /// unchanged.
    var blankCanvasEnabled: Bool { isEnabled(FeatureCatalog.blankCanvasFlag) }

    /// `next-layer-groups`: whether ⌘G / ⇧⌘G exist, and whether a click on the
    /// canvas picks a whole group (with double click going inside it and Escape
    /// coming back out). Exists only in the Next release's catalog, so Current
    /// always reads false and its clicks pick a single layer as they always
    /// did. The model and the renderer are never flagged: a document that
    /// already holds groups opens and draws correctly either way.
    var layerGroupsEnabled: Bool { isEnabled(FeatureCatalog.layerGroupsFlag) }
    /// The same flag, read by the layers list: whether a group row offers a
    /// twist-open control and can swallow what you drag onto it. Off, the list
    /// is the flat one it always was.
    var layersListShowsGroups: Bool { layerGroupsEnabled }

    /// `next-frames`: whether the frame tool, the two Layer rows and the
    /// export scope exist. A frame is a group with a size, so this needs
    /// groups: with them off there is no way in to a frame and the switch
    /// reads as off. Frames already in a document draw either way — turning a
    /// flag off takes away a way in, never a document's contents.
    var framesEnabled: Bool {
        layerGroupsEnabled && isEnabled(FeatureCatalog.framesFlag)
    }

    /// `next-library`: whether the right dock offers the Library shelf and the
    /// View menu its Show Library row. The Library exists to hold reusable
    /// pieces, and the first of those is a group you promote, so this needs
    /// groups: with them off there is no way in and the switch reads as off.
    var libraryEnabled: Bool {
        layerGroupsEnabled && isEnabled(FeatureCatalog.libraryFlag)
    }

    /// `next-components`: whether Layer > Make Component exists, whether a
    /// main wears its mark on the canvas and in the layers list, and whether
    /// the Library's Components scope has anything in it. A component is
    /// something you fetch off the shelf, so this needs the Library: with it
    /// off there is no way in and the switch reads as off. Components already
    /// in a document draw either way. Turning a flag off takes away a way in,
    /// never a document's contents.
    var componentsEnabled: Bool {
        libraryEnabled && isEnabled(FeatureCatalog.componentsFlag)
    }

    /// `next-styles`: whether a color can be saved under a name, whether the
    /// inspector's color rows offer the styles button, and whether the
    /// Library's Styles scope has anything in it. A style is something you
    /// fetch off the shelf, so this needs the Library: with it off there is no
    /// way in and the switch reads as off. Colors already pointing at a style
    /// keep drawing either way, because turning a flag off takes away a way
    /// in, never a document's contents.
    var colorStylesEnabled: Bool {
        libraryEnabled && isEnabled(FeatureCatalog.stylesFlag)
    }

    /// `next-color-picker`: whether every color row opens the app's designed
    /// picker. It stands on its own rather than on the styles flag: naming a
    /// color and picking one are two different questions, and someone who
    /// turns naming off still wants one picker rather than three.
    var designedColorPickerEnabled: Bool { isEnabled(FeatureCatalog.colorPickerFlag) }

    /// Whether the canvas redraws what you can see at the zoom you are looking
    /// at it through, so placed words stay as sharp as the ones being typed.
    var crispZoomEnabled: Bool { isEnabled(FeatureCatalog.crispZoomFlag) }

    /// `next-starter-components`: whether the Components shelf arrives with the
    /// app's own five on it. They are components, so this needs components:
    /// with them off there is no shelf to stock and the switch reads as off.
    /// Starters already dropped into a document keep drawing and keep updating
    /// their copies either way, because turning a flag off takes away a way in,
    /// never a document's contents.
    var starterComponentsEnabled: Bool {
        componentsEnabled && isEnabled(FeatureCatalog.starterComponentsFlag)
    }

    /// `next-window-capture`: whether the region-capture overlay highlights
    /// the window under the pointer and captures it on a click. Exists only in
    /// the Next release's catalog, so Current always reads false and its
    /// overlay stays drag only.
    var windowCaptureEnabled: Bool { isEnabled(FeatureCatalog.windowCaptureFlag) }

    /// `next-window-capture`: whether a clicked window is captured with its
    /// shadow (the built-in capture's default) or as its bare bounds. Option
    /// while clicking gives the other choice either way.
    var windowCaptureIncludesShadow: Bool {
        boolean(FeatureCatalog.windowCaptureFlag, FeatureCatalog.windowCaptureShadow) ?? true
    }

    /// `next-geometry-fields`: whether the inspector offers the selected
    /// layer's position and size as typed numbers. Exists only in the Next
    /// release's catalog, so Current always reads false and stays drag only.
    var geometryFieldsEnabled: Bool { isEnabled(FeatureCatalog.geometryFieldsFlag) }

    /// `next-readout-fields`: whether a Position and Size number that was
    /// worked out for you drops the rounded box the typeable numbers wear.
    /// Off puts the box back, which is where this started. Clicking one to be
    /// told why it takes nothing is NOT flagged: that answers a click that
    /// used to be answered by silence, and it is right in either look.
    var readoutFieldsEnabled: Bool { isEnabled(FeatureCatalog.readoutFieldsFlag) }

    /// `next-align-layers`: whether the Arrange row and the Layer menu's align
    /// and space commands exist, and whether a dragged layer sticks to the
    /// other layers as well as to the picture. Exists only in the Next
    /// release's catalog, so Current keeps canvas-only snapping and no Arrange
    /// row. Nothing about it is stored in a document, so a document arranged
    /// with it on is an ordinary document.
    var alignLayersEnabled: Bool { isEnabled(FeatureCatalog.alignLayersFlag) }

    /// `next-placement`: whether the Layout section exists, so a group can say
    /// how its contents line up and one piece inside can say something
    /// different for itself. The RULE itself is not flagged: a layer with
    /// nothing set resizes proportionally exactly as it always did, so with
    /// this off a document already carrying placements keeps honouring them
    /// and only the way to change them is gone.
    var placementEnabled: Bool { isEnabled(FeatureCatalog.placementFlag) }

    /// `next-auto-layout`: whether a group can be made a stack or a grid, so
    /// the things inside it space themselves. Like placement, the RULE is not
    /// flagged: a group already set to a stack keeps arranging itself with
    /// this off, and only the Arrangement rows and the two menu items go.
    var autoLayoutEnabled: Bool { isEnabled(FeatureCatalog.autoLayoutFlag) }

    /// `next-canvas-grid`: whether the canvas can show a grid to build
    /// against. It is a view preference, not document content, so a document
    /// made with it on is byte for byte an ordinary document, and turning the
    /// flag off only takes away the View row and the Grid controls.
    var canvasGridEnabled: Bool { isEnabled(FeatureCatalog.canvasGridFlag) }

    /// `capture-toast-timing`: how long that fade takes.
    var captureToastFadeSeconds: Double {
        guard isEnabled(FeatureCatalog.captureToastTimingFlag) else {
            return FeatureCatalog.captureToastFadeSeconds
        }
        return number(FeatureCatalog.captureToastTimingFlag, FeatureCatalog.captureToastFade)
            ?? FeatureCatalog.captureToastFadeSeconds
    }
}
