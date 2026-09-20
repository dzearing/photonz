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

    /// `next-measure-layer-snap`: whether a caliper foot catches the exact edge
    /// of a layer on the canvas, rather than only the edges detected in the
    /// picture underneath. Exists only in the Next release's catalog, so
    /// Current always reads false.
    var measureLayerSnapEnabled: Bool { isEnabled(FeatureCatalog.measureLayerSnapFlag) }

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

    /// `next-shape-parts`: whether the panel shows one list of the parts a
    /// layer paints — Fill, Outline, Shadow — each with its own switch, colour
    /// and settings, in place of the scattered Color, Effects, shape and
    /// Shadow rows. Exists only in the Next release's catalog, so Current
    /// always reads false.
    var shapePartsEnabled: Bool { isEnabled(FeatureCatalog.shapePartsFlag) }

    /// `next-panel-sections`: whether the panel leaves out the sections that
    /// answer for a job the document is not doing, and carries a Sections row
    /// at its foot for saying which of them you want anyway. Exists only in the
    /// Next release's catalog, so Current always reads false.
    var panelSectionsEnabled: Bool { isEnabled(FeatureCatalog.panelSectionsFlag) }

    /// `next-blend-mode`: whether the Appearance section carries a Blending row
    /// under Opacity, so a layer can say how it mixes with what is under it
    /// rather than always painting straight over. Exists only in the Next
    /// release's catalog, so Current always reads false.
    var blendModeEnabled: Bool { isEnabled(FeatureCatalog.blendModeFlag) }

    /// `next-corner-handles`: whether a picked shape with corners wears a dot
    /// just inside each corner that rounds that corner when you pull it.
    /// Exists only in the Next release's catalog, so Current always reads
    /// false and rounding stays something you type in the panel.
    var cornerHandlesEnabled: Bool { isEnabled(FeatureCatalog.cornerHandlesFlag) }

    /// `next-edge-grab`: whether the whole run of a picked object's edge
    /// resizes it, rather than only the small square in the middle of that
    /// edge. Exists only in the Next release's catalog, so Current always
    /// reads false and a short box still has no side handle to pull.
    var edgeGrabEnabled: Bool { isEnabled(FeatureCatalog.edgeGrabFlag) }

    /// `next-grab-cue`: whether the pointer turns into a hand over a pill that
    /// drags on its own (an arrow's caption, a measurement's number). Exists
    /// only in the Next release's catalog, so Current always reads false.
    var grabCueEnabled: Bool { isEnabled(FeatureCatalog.grabCueFlag) }

    /// `next-a-box-says-what-it-picks`: whether a rubber band on the canvas
    /// shows, while it is being drawn, whether it is picking up layers or
    /// picking a piece of the picture. Exists only in the Next release's
    /// catalog, so Current always reads false and both boxes keep the ants.
    var marqueeIntentEnabled: Bool { isEnabled(FeatureCatalog.marqueeIntentFlag) }

    /// `next-tool-options`: whether the Crop tool and the Magic Wand keep their
    /// options off the floating tool bar (D15) — crop aspect in the crop
    /// button's flyout, crop actions on the canvas, wand tolerance in the
    /// inspector. Exists only in the Next release's catalog, so Current always
    /// reads false and keeps both option rows in the bar.
    var toolOptionsEnabled: Bool { isEnabled(FeatureCatalog.toolOptionsFlag) }

    /// `next-tool-settings`: whether the settings belonging to the tool in
    /// hand also ride in their own small capsule above the floating tool bar,
    /// so hiding the right hand panel does not take them away. Exists only in
    /// the Next release's catalog, so Current always reads false and the
    /// settings live in the panel alone.
    var toolSettingsEnabled: Bool { isEnabled(FeatureCatalog.toolSettingsFlag) }

    /// Which of the capsule's settings this release has switched on, so the
    /// pure policy in `ToolSettingsBar` can decide what the capsule carries
    /// without reaching for the flag store itself.
    var toolSettingsAvailability: ToolSettingsBar.Availability {
        ToolSettingsBar.Availability(calloutShape: calloutShapeEnabled,
                                     calloutMagnification: calloutMagnificationEnabled,
                                     measureSnap: measureCenterSnapEnabled,
                                     measureShow: measureRolesEnabled)
    }

    /// `next-callout-shape`: whether the Zoom Callout tool carries its own
    /// Shape choice while it is in hand, remembered between callouts, so a
    /// circle is one choice rather than a rectangle you go back and fix.
    /// Exists only in the Next release's catalog, so Current always reads
    /// false and every callout is drawn as a rectangle.
    var calloutShapeEnabled: Bool { isEnabled(FeatureCatalog.calloutShapeFlag) }

    /// `next-callout-magnification`: whether the Zoom Callout tool also carries
    /// how much the NEXT callout magnifies, remembered between callouts, so a
    /// 4× callout is a choice made before the drag rather than a 2× one
    /// you go back and resize. Exists only in the Next release's catalog, so
    /// Current always reads false and every callout starts at 2×.
    var calloutMagnificationEnabled: Bool { isEnabled(FeatureCatalog.calloutMagnificationFlag) }

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

    /// Help ▸ guided tutorials (Next, `next-tutorials`).
    var tutorialsEnabled: Bool { isEnabled(FeatureCatalog.tutorialsFlag) }

    /// `next-settings-window`: the Settings window, and with it the one place
    /// that lists the questions you have told the app to stop asking and turns
    /// any of them back on. Exists only in the Next release's catalog, so
    /// Current reads false and has no Settings row anywhere.
    var settingsWindowEnabled: Bool { isEnabled(FeatureCatalog.settingsWindowFlag) }

    /// `next-setup-takes-no-for-an-answer`: whether closing the first run setup
    /// window without granting Screen Recording is remembered as a no, so the
    /// window stops opening itself at every launch. Exists only in the Next
    /// release's catalog, so Current always reads false and keeps coming back
    /// until the permission is on.
    var setupTakesNoForAnAnswer: Bool {
        isEnabled(FeatureCatalog.setupTakesNoForAnAnswerFlag)
    }

    /// Separate into Layers, on a picture's row menu and in the Layer menu
    /// (Next, `next-separate-into-layers`). Exists only in the Next release's
    /// catalog, so Current never offers the command.
    var separateIntoLayersEnabled: Bool { isEnabled(FeatureCatalog.separateIntoLayersFlag) }

    /// `next-double-click-reads-a-label`: whether double clicking a separated
    /// run of text reads the words and opens them for typing, instead of only
    /// picking the picture. Needs the separation itself to be on, since there
    /// are no runs without it.
    var doubleClickReadsALabelEnabled: Bool {
        separateIntoLayersEnabled && isEnabled(FeatureCatalog.doubleClickReadsALabelFlag)
    }

    /// `next-read-every-label`: whether the line a separation raises offers to
    /// read the words in every run it found, and whether Turn into Text acts on
    /// everything picked instead of one row. Needs the separation itself to be
    /// on, since there are no runs without it.
    var readEveryLabelEnabled: Bool {
        separateIntoLayersEnabled && isEnabled(FeatureCatalog.readEveryLabelFlag)
    }

    /// `next-what-a-separation-left-behind`: whether the picture's own row in
    /// the layers list keeps the count the notice pill faded away with, and
    /// offers the next batch beside it (`SeparationLeftover`). Session chrome
    /// only: it is held against the patched bitmap, never written into the
    /// document, so it costs no undo step and undo takes it away with the
    /// separation.
    var whatIsLeftInThePictureEnabled: Bool {
        isEnabled(FeatureCatalog.whatIsLeftInThePictureFlag)
    }

    /// New Layer via Cut, ⇧⌘J and the Layer menu row under New Layer via Copy
    /// (Next, `next-new-layer-via-cut`). Exists only in the Next release's
    /// catalog, so Current never offers the command.
    var newLayerViaCutEnabled: Bool { isEnabled(FeatureCatalog.newLayerViaCutFlag) }

    /// Copy Look and Paste Look, in the Layer menu and on a layer's right
    /// click menu (Next, `next-copy-a-look`). Exists only in the Next
    /// release's catalog, so Current never offers the commands.
    var copyALookEnabled: Bool { isEnabled(FeatureCatalog.copyALookFlag) }

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

    /// `next-canvas-menu`: whether a right click on the picture raises a menu
    /// — the layer menu on whatever is under the pointer, or the canvas's own
    /// commands on bare picture. Off, a right click on the canvas does nothing,
    /// which is what Current does and what Next did before this.
    var canvasMenuEnabled: Bool { isEnabled(FeatureCatalog.canvasMenuFlag) }

    /// `next-layers-follow-pick`: whether picking a layer brings its row into
    /// view in the layers list. Only the SCROLL is flagged — opening the groups
    /// above a picked layer is what the list has always done, in both releases,
    /// and a row that is already on screen never moves either way.
    var layersFollowPick: Bool { isEnabled(FeatureCatalog.layersFollowPickFlag) }

    /// `next-lens`: whether the Lens tool, its capsule settings and the Lens
    /// section of the panel exist. The model and the renderer are never
    /// flagged: a document that already holds a lens opens and draws correctly
    /// either way, because turning a flag off takes away a way IN, never a
    /// document's contents.
    ///
    /// It also decides which of the two the bar and the panel show, because the
    /// Lens absorbed the Zoom Callout rather than sitting beside it: with it ON
    /// the callout is the Lens set to Magnify, so there is one slot and one Lens
    /// section; with it OFF the Zoom Callout tool and the Zoom Callout section
    /// are back, exactly as Current has them (`LensKind`).
    var lensEnabled: Bool { isEnabled(FeatureCatalog.lensFlag) }

    /// `next-pen`: whether the Pen tool exists at all — the slot at the end of
    /// the drawing family, the letter P, and the gesture that lays a path down.
    /// The model and the renderer are never flagged: a document that already
    /// holds a path opens and draws correctly either way, because turning a
    /// flag off takes away a way IN, never a document's contents.
    var penEnabled: Bool { isEnabled(FeatureCatalog.penFlag) }

    /// `next-line-ends`: whether a line and an arrow are asked what their two
    /// ends look like, under Outline beside the Thickness. The model and the
    /// renderer are never flagged, for the reason the Pen gives above: a
    /// document holding a square-ended line draws it either way.
    var lineEndsEnabled: Bool { isEnabled(FeatureCatalog.lineEndsFlag) }

    /// The mark under the pointer saying where a press would put the first
    /// point of a shape (`CanvasDrawLanding`).
    var drawLandingEnabled: Bool { isEnabled(FeatureCatalog.drawLandingFlag) }

    /// The pill that rides under a drag saying where it is going or how big it
    /// is becoming (`CanvasDragReadout`).
    var dragReadoutEnabled: Bool { isEnabled(FeatureCatalog.dragReadoutFlag) }

    /// `next-motion`: whether the Motion section exists under Effects, with the
    /// plus that tells a layer to change one of its properties over time, and
    /// whether the canvas plays it. The model is never flagged: a document that
    /// already holds a motion opens and reads correctly either way, because
    /// turning a flag off takes away a way IN, never a document's contents. It
    /// does take away the PLAYING, which is the one thing a way in cannot be:
    /// a canvas quietly animating with no section to switch it off would be a
    /// picture nobody could stop.
    var motionEnabled: Bool { isEnabled(FeatureCatalog.motionFlag) }

    /// `next-cut-a-recording`: whether a recording can be cut into pieces at the
    /// playhead and a piece thrown away. It takes away a way IN, never a
    /// recording's contents: a recording already saved with a cut in it plays
    /// its kept pieces either way, because by then the cut is baked into the
    /// stored file and there is nothing left to switch off.
    var cutRecordingEnabled: Bool { isEnabled(FeatureCatalog.cutRecordingFlag) }

    /// `next-a-recording-is-a-document`: whether opening a recording opens the
    /// ordinary editor window, with the recording as a layer in it and a
    /// timeline across the bottom, rather than the small video window.
    ///
    /// It takes away a way IN and never a document's contents: turning it off
    /// puts the old window back, and the recording on disk is the same file it
    /// always was, because nothing about a clip is written into pixels.
    var recordingIsADocument: Bool { isEnabled(FeatureCatalog.recordingIsADocumentFlag) }

    /// `next-saving-a-recording-says-so`: whether saving a recording reports
    /// itself in the bottom-right toast stack — a progress bar once the save
    /// has run past `SaveFeedback.quietWindow`, and a named confirmation when
    /// it lands. Off, a save is silent and the controller's spinner is all
    /// there is.
    var savingARecordingSaysSo: Bool {
        isEnabled(FeatureCatalog.savingARecordingSaysSoFlag)
    }

    /// `next-recording-export-sheet`: whether saving a copy of a recording goes
    /// through the Export sheet every picture already goes through, rather than
    /// a bare save box with the format decided by which menu item was picked.
    /// Off puts the three Export items back in the Video menu and sends Save As
    /// straight to the save box.
    var recordingExportSheetEnabled: Bool {
        isEnabled(FeatureCatalog.recordingExportSheetFlag)
    }

    /// `next-motion-strip`: whether the timing strip runs across the bottom of
    /// the window. It NEEDS the Motion list, because with no way to tell a
    /// layer to move there is never anything to draw a bar for: a strip that
    /// could only ever be empty is a strip that never appears, which is worse
    /// than no strip at all because the switch for it would look broken.
    var motionStripEnabled: Bool {
        motionEnabled && isEnabled(FeatureCatalog.motionStripFlag)
    }

    /// `next-reshape-a-path`: whether a selected path shows its anchors and
    /// lets them be dragged, converted, added and taken out. It needs the Pen,
    /// because without one there is no way to draw a path to reshape. A path
    /// already in a document draws either way: a flag takes away a way in,
    /// never a document's contents.
    var reshapePathEnabled: Bool {
        penEnabled && isEnabled(FeatureCatalog.reshapePathFlag)
    }

    /// `next-export-svg`: whether Export offers SVG beside the three picture
    /// formats. It needs the Pen, because the shapes worth exporting as
    /// vectors are the ones the Pen draws: with the Pen off the switch reads
    /// as off and Export is the three-way picker it always was. The writer
    /// itself is never flagged, so a document exported either way is the same
    /// file.
    var svgExportEnabled: Bool {
        penEnabled && isEnabled(FeatureCatalog.svgExportFlag)
    }

    /// `next-export-quality`: whether Export offers a quality for the formats
    /// that have one and says what the file will weigh at it. It needs nothing
    /// else: JPEG and HEIC have been in the picker since the first build, and
    /// the encoder has taken a quality all along. Off means Export writes what
    /// it always wrote, at the quality it always used.
    var exportQualityEnabled: Bool { isEnabled(FeatureCatalog.exportQualityFlag) }

    /// `next-export-webp`: whether Export offers WebP beside the three formats
    /// macOS can write. It needs the quality slider, because WebP's whole range
    /// hangs off it: the slider is how a lossy WebP is tuned and, at the top,
    /// how a lossless one is asked for. Without that control WebP would be a
    /// fourth button that always wrote the same file, so with the quality
    /// switch off this reads as off too.
    var webPExportEnabled: Bool {
        exportQualityEnabled && isEnabled(FeatureCatalog.webPExportFlag)
    }

    /// `next-export-animated-svg`: whether Export asks where the file is
    /// going and writes the motion into an SVG bound for a web page. It needs
    /// both parents: with no SVG there is nothing to animate, and with no
    /// Motion list there is never anything moving to carry, so the question
    /// would be asked about a difference nobody could make.
    var animatedSVGExportEnabled: Bool {
        svgExportEnabled && motionEnabled
            && isEnabled(FeatureCatalog.animatedSVGExportFlag)
    }

    /// `next-a-row-says-its-words`: whether a piece of text nobody has named by
    /// hand wears its own words in the layers list instead of "Text 9". It
    /// takes away nothing and writes nothing down — the name is read off the
    /// layer as the list is built (`Layer.displayName`) — so a document made
    /// with it on is byte for byte an ordinary document and turning it off puts
    /// every row back to the number it had.
    var rowSaysItsWordsEnabled: Bool { isEnabled(FeatureCatalog.rowSaysItsWordsFlag) }

    /// `next-a-separated-row-says-its-words`: whether a run of text Separate
    /// into Layers lifted off a screenshot wears the words READ off its picture
    /// (`EditorState+RunWords`). It is the same row rule one step further on,
    /// so it needs that rule and it needs there to be separated pieces at all.
    var separatedRowSaysItsWordsEnabled: Bool {
        separateIntoLayersEnabled && rowSaysItsWordsEnabled
            && isEnabled(FeatureCatalog.separatedRowSaysItsWordsFlag)
    }

    /// `next-find-a-layer`: whether a find field sits over the layers list, so
    /// one label in a hundred and forty is reached by typing rather than by
    /// scrolling. It reads the names the list is ALREADY showing, so what you
    /// can search for is exactly what you can see.
    var findALayerEnabled: Bool { isEnabled(FeatureCatalog.findALayerFlag) }

    /// `next-a-separation-arrives-shut`: whether a separation big enough to
    /// fill the layers list arrives inside one shut group instead of as a
    /// hundred and forty loose rows. Built to be compared against
    /// `findALayerEnabled` rather than to ship beside it, which is why it
    /// starts off.
    var separationArrivesShutEnabled: Bool {
        layerGroupsEnabled && isEnabled(FeatureCatalog.separationArrivesShutFlag)
    }

    /// `next-turn-into-path`: whether a box, an oval or a line can be turned
    /// into a path from the two menus. It needs the reshaping work, because
    /// converting a shape you then cannot edit is a command with no payoff: the
    /// whole point is the points. A layer already turned draws either way, so
    /// the flag takes away a way IN, never a document's contents.
    var turnIntoPathEnabled: Bool {
        reshapePathEnabled && isEnabled(FeatureCatalog.turnIntoPathFlag)
    }

    /// `next-frames`: whether the frame tool, the two Layer rows and the
    /// export scope exist. A frame is a group with a size, so this needs
    /// groups: with them off there is no way in to a frame and the switch
    /// reads as off. Frames already in a document draw either way — turning a
    /// flag off takes away a way in, never a document's contents.
    var framesEnabled: Bool {
        layerGroupsEnabled && isEnabled(FeatureCatalog.framesFlag)
    }

    /// `next-icon-frames`: whether the size lists offer the icon sizes, and
    /// whether a frame made from a picked size brings the camera with it. An
    /// icon size is a frame size, so this needs frames: with them off there is
    /// no size list to put the icons in and the switch reads as off.
    var iconFramesEnabled: Bool {
        framesEnabled && isEnabled(FeatureCatalog.iconFramesFlag)
    }

    /// `next-icon-previews`: whether working in an icon frame puts the row of
    /// small previews in the corner of the canvas. There is nothing to preview
    /// without icon frames, so this needs them and reads as off without them.
    var iconPreviewsEnabled: Bool {
        iconFramesEnabled && isEnabled(FeatureCatalog.iconPreviewsFlag)
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

    /// `next-color-drag`: whether a colour swatch can be picked up and dropped
    /// on another one. It stands on its own rather than on the picker flag,
    /// because the swatch a colour is carried between is the row's own swatch
    /// in both releases: what changes here is whether it is a handle.
    var colorDragEnabled: Bool { isEnabled(FeatureCatalog.colorDragFlag) }

    /// Whether a saved text style can be carried off the Library shelf and let
    /// go on text. Both switches, because carrying one needs somewhere to
    /// carry it FROM (the shelf, which is what `next-styles` puts there) and a
    /// gesture to carry it WITH (which is what `next-color-drag` turns on).
    ///
    /// One place, because the shelf tile, the layers row and the picture all
    /// have to agree: a tile that cannot be picked up must never be met by a
    /// row that would have taken it.
    var textStyleDragEnabled: Bool { colorStylesEnabled && colorDragEnabled }

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

    /// `next-shared-library`: whether a component can be put on a shelf every
    /// document on this Mac can reach, and whether the Components shelf offers
    /// what is on it. A shared component is still a component, so this needs
    /// components: with them off there is no way in and the switch reads as
    /// off. A component already shared keeps drawing either way, because
    /// turning a flag off takes away a way in, never a document's contents.
    var sharedLibraryEnabled: Bool {
        componentsEnabled && isEnabled(FeatureCatalog.sharedLibraryFlag)
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

    /// `next-undo-puts-back-your-marquee`: whether a selection is part of the
    /// undo history at all. Off, nothing about a marquee is recorded and
    /// nothing about one is restored, which is exactly how it behaved before.
    var selectionUndoEnabled: Bool { isEnabled(FeatureCatalog.selectionUndoFlag) }

    /// Whether a layer's box is the pixels it actually has: a new layer with
    /// nothing on it has no size, and filling a marquee box leaves the layer
    /// exactly that box.
    var layerBoxIsItsPixelsEnabled: Bool {
        isEnabled(FeatureCatalog.layerBoxIsItsPixelsFlag)
    }

    /// `next-copy-picks-your-layer`: whether the layer you picked survives a
    /// marquee. On, ⌘C takes that layer's pixels inside the marquee and ⇧⌘C
    /// is Copy Merged; off, the marquee supersedes the layer and ⌘C hands back
    /// every layer flattened together (`CopyRoute`).
    var copyPicksYourLayerEnabled: Bool { isEnabled(FeatureCatalog.copyPicksYourLayerFlag) }

    /// `next-cut-says-what-it-cannot-do`: whether ⌘X, ⌫, ⌥⌫ and the bucket
    /// refuse, out loud, when the marquee is over a layer no piece can be
    /// taken out of or filled in (`RegionSliceRefusal`). Off, cut silently
    /// takes the whole layer and the rest silently do nothing.
    var cutSaysWhatItCannotDoEnabled: Bool {
        isEnabled(FeatureCatalog.cutSaysWhatItCannotDoFlag)
    }

    /// `next-paste-hands-you-the-pointer`: whether a paste leaves the pointer
    /// in hand with the pasted layer picked, and whether undoing that paste
    /// gives the tool you were using back (`PasteToolReturn`).
    var pasteHandsYouThePointerEnabled: Bool {
        isEnabled(FeatureCatalog.pasteHandsYouThePointerFlag)
    }

    /// `capture-toast-timing`: how long that fade takes.
    var captureToastFadeSeconds: Double {
        guard isEnabled(FeatureCatalog.captureToastTimingFlag) else {
            return FeatureCatalog.captureToastFadeSeconds
        }
        return number(FeatureCatalog.captureToastTimingFlag, FeatureCatalog.captureToastFade)
            ?? FeatureCatalog.captureToastFadeSeconds
    }
}
