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

    public static let measureLayerSnapFlag = "next-measure-layer-snap"

    public static let measureReadoutSlideFlag = "next-measure-readout-slide"

    public static let measureRolesFlag = "next-measure-roles"

    public static let measurePanelFlag = "next-measure-panel"

    public static let arrowCaptionsFlag = "next-arrow-captions"

    public static let shapePartsFlag = "next-shape-parts"

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

    public static let alignLayersFlag = "next-align-layers"

    public static let framesFlag = "next-frames"

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

    public static let marqueeIntentFlag = "next-a-box-says-what-it-picks"

    public static let lensFlag = "next-lens"

    public static let blendModeFlag = "next-blend-mode"

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
                    description: "Right after you draw an arrow, type a label and it lands in a pill at the arrow's tail, styled like the measure readout. Return starts another line, Command and Return lands the label, Esc skips it, and dragging again draws the next arrow. Double-click an arrow to add or edit its caption.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: shapePartsFlag,
                    title: "Appearance is what it is, Effects is what you add",
                    description: "The panel splits on one rule. Appearance, straight under Layers, holds what a shape simply HAS, always in the same order: opacity, fill, outline, and a corner radius only where there are corners. Effects, under it, starts EMPTY and is a list you add to from one plus: a shadow, a glow, an extra border, a blur. A shadow and a glow each carry a Kind, so one control throws it behind the layer or casts it into the layer, and a border carries a Position. The same kind can arrive more than once, so two shadows are two rows with their own settings, and a row can be switched off, taken out, or dragged to change what paints over what. Each row\'s own settings sit behind a rule of their own, so a shadow\'s blur can never be mistaken for the layer\'s. A rectangle\'s outline can be taken off for the first time, and a box\'s Thickness row and a picture\'s Border row are both the Outline part now.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: cornerHandlesFlag,
                    title: "Drag a corner to round it",
                    description: "A picked shape with corners wears a small dot just inside each of its four corners. Pull one in and that corner rounds under your hand, live, while the other three stay as they are; pull it back out and the corner squares off again. Hold Option and all four go together. Letting go is one undo step, and the Corner Radius rows in the panel show what you dragged. The dot sits at the centre of the corner's curve, so it travels a point for every point your hand does rather than creeping while you drag, and a shape too small to keep its edge handles does not wear the dots at all.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: edgeGrabFlag,
                    title: "Pull the side of a label to set where it wraps",
                    description: "The outline round a picked object is the handle, not just the small squares on it. Take hold of any part of an edge and pull, and that side moves: the pointer shows the left-right or up-down arrows before you press, so you can see it coming. It matters most on a one line label, which is too short to wear a square in the middle of its side edges — until now the only way to set the width the words wrap at was to drag a corner or type a number. The middle of the object still picks it up and moves it, and a box too small to spare the room keeps its whole body for moving and offers no edges at all.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: grabCueFlag,
                    title: "Every handle says what it does",
                    description: "Rest the pointer on any handle around a selected object and it says what a press would do before you press it. An open hand over the parts that drag on their own (an arrow\'s caption, either end of a line, a measurement\'s number and its two feet), and a closed hand while you drag one. The matching resize arrows over the eight handles round a layer, round the canvas, or round the crop box. A curved arrow over the knob that turns it. Over a screen it says which of the two drags you are about to get: the hand means the screen itself travels, and it is on the screen's name at all times and on the screen's own surface once the screen is picked, while empty room that would sweep a band keeps the plain arrow.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: marqueeIntentFlag,
                    title: "A box says what it picks",
                    description: "There are two boxes you can draw on the picture and they used to look the same. One picks up the layers it encloses, so delete takes those layers away; the other picks a piece of the picture to work on, so delete clears pixels out of the layer you already had. Now they look different, from the moment you start dragging. A box that has caught nothing keeps the familiar crawling dashes. The moment it goes right round something, it stops crawling, its edge becomes one unbroken blue line, and the inside washes blue over what it is about to pick up. Shrink it back off and the dashes come straight back. A box that landed goes on wearing the look it had while you drew it.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureRolesFlag,
                    title: "Measurement roles",
                    description: "Each measurement is a Size or a Spacing callout with its own remembered colors. Adds a Role control to the Measurement section of the panel, a legend on the canvas while the tool is active, and a Show filter in the Measure Tool section of the panel.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measurePanelFlag,
                    title: "Measurements panel",
                    description: "Lists every measurement in the panel with its own eye, name, and value, adds a count to the toolbar, and puts From, To and Distance behind a Details fold in the panel, beside Copy Measurement. The panel menu can show, hide, or clear them all, or copy them as a text spec list.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: measureCenterSnapFlag,
                    title: "Snap to centers",
                    description: "Adds a Snap option to the Measure Tool section of the panel. With Edges and centers, measure points also magnetize to element and gap centers, the midpoint between neighboring edges. Hold Command to drag free.",
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
                    name: measureLayerSnapFlag,
                    title: "Snap to the edges of what you drew",
                    description: "A caliper foot catches the exact edge of any layer on the canvas, not just the edges found in the picture underneath. Measure a box you drew and you get its real size rather than wherever your hand landed on its outline. A known edge wins over one guessed from the picture. Hold Command to drag free.",
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
                    name: geometryFieldsFlag,
                    title: "Type a layer's position and size",
                    description: "The panel gains a Position and Size section: X, Y, W, H and A for everything you have picked, as numbers you can type. A is the angle a layer has been turned to, in degrees, so a shape you turned with the knob reads back a number you can write down, and typing 0 puts it straight again. One button can be made exactly 296 by 118, and a whole row of them can be made one width, or lined up on one left edge, in a single move and a single undo. Where the picked layers differ, a field says Mixed rather than a number. Up and down arrow steps a field by 1, Shift and an arrow by 10. A number the app worked out for you, like how tall a paragraph came out or anything on a locked layer, is shown as plain text with no box around it, and clicking it says why it takes nothing. Off means position, size and angle are drag only.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: alignLayersFlag,
                    title: "Line layers up with each other",
                    description: "Two jobs at once. Select two or more layers and an Arrange row appears at the top of the panel, mirrored in the Layer menu: line their left edges, centres, right edges, tops, middles or bottoms up in one press, and with three or more, space them out evenly across or down so every gap matches. And while you drag a layer, it now sticks to the edges and centres of the other layers as well as the picture\u{2019}s, with a short line showing what it just lined up with; holding Command drags free. Off means dragging pulls to the edges and middle of the picture only, and there is no Arrange row.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolOptionsFlag,
                    title: "Tool options off the tool bar",
                    description: "Picking up the Crop tool or the Magic Wand stops widening the floating tool bar. Crop keeps its aspect locks inside its own tool button and shows Cancel and Crop on the canvas while a crop is live; the wand's tolerance moves to a Magic Wand section in the panel. Off means both tools lay their options out along the bar, which grows it and pushes tools into the overflow menu on a narrow window.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: toolSettingsFlag,
                    title: "Tool settings ride above the tool bar",
                    description: "The settings that belong to the tool in your hand, rather than to anything you have picked, get their own small capsule floating just above the tool bar: the Zoom Callout\u{2019}s shape, the Magic Wand\u{2019}s tolerance, and what Measure snaps to and shows. It is open without pressing anything, it changes as you change tools, and it disappears entirely for a tool with nothing to set, so the arrow leaves the picture clear. It is its own capsule on its own row, so the tool bar never changes width, and it wraps on a narrow window. The same settings stay in the right hand panel and the two are one thing: change either and both move. Off means these settings live only in the panel, so hiding the panel takes them away.",
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
            Definition(
                flag: FeatureFlag(
                    name: layerGroupsFlag,
                    title: "Group what you selected",
                    description: "Select two or more layers and press Command G to make them one thing you can move, hide, lock and delete together; Shift Command G takes it apart again and leaves the pieces exactly where they were. On the canvas a click picks the whole group, and a double click goes inside it so you can pick one piece; Escape comes back out. Off means the Layer menu has no Group or Ungroup rows and a click always picks a single layer. Groups already in a document keep drawing either way.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: lensFlag,
                    title: "A layer that changes what is under it",
                    description: "Adds the Lens tool, K, next to the Zoom Callout. Drag a box over anything and the picture underneath is drawn through it: Blur to soften an address until it cannot be read, Pixelate to break a name into blocks, Greyscale to drain the colour out of a region, Invert to flip it, or Brightness to lift it or push it down. Each one has its own setting, in the capsule over the tool bar before you draw and in the Lens section of the panel after. It is an ordinary layer otherwise: move it, resize it, turn it, round its corners, give it a border or a shadow, fade it, reorder it, undo it. What leaves the app is flattened, so a pixelated region really is pixelated in the picture you export or copy. Off means no Lens tool and no Lens section; a lens already in a document keeps drawing either way.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: blendModeFlag,
                    title: "A layer can say how it mixes with what is under it",
                    description: "Adds a Blending row to the Appearance section, right under Opacity, where Opacity says how much of what is below shows through and Blending says how the two are mixed once it does. Five choices, each with a plain sentence beside it: Normal paints straight over, Multiply darkens the way a highlighter pen does so a tint burns into a screenshot and the detail underneath still shows, Screen lightens, and Darken and Lighten keep whichever of the two is darker or lighter. Moving down the list previews each one on the canvas as you go, and the one you click is a single undo step over every layer you picked. What leaves the app carries it, so a tint really is burnt into the picture you export or copy. A highlight mark has no row, because mixing is what makes it a highlighter. Off means no Blending row; a layer already set to mix keeps drawing either way.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: framesFlag,
                    title: "Build on a frame",
                    description: "A frame is a screen you build on: press F and drag one out at any size, or click once to drop the size you picked last. It carries its name above its top left corner, paints a white surface, and hides anything that hangs off its edge, and several of them sit side by side on one canvas so a document can hold more than one screen. Layer \u{25B8} New Frame picks a size from a short list, Layer \u{25B8} Frame Selection puts a frame around what you already have, and Export offers a single frame as the picture to write. Needs Group what you selected. Off means no frame tool and no frame rows; frames already in a document keep drawing either way.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: libraryFlag,
                    title: "Keep reusable pieces in a Library",
                    description: "Adds a Library to the right dock, under View \u{25B8} Show Library. It is one shelf with four scopes you switch between, Media, Components, Styles and Systems, and a search field that narrows whichever one you are in. Media shows the captures you have taken: click one to see its details, double click or drag it onto the picture to place it. Components, Styles and Systems are empty until there is something to put in them, and each says so. Needs Group what you selected. Off means the right dock exactly as it is today and no Show Library row.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: componentsFlag,
                    title: "Make a component out of what you drew",
                    description: "Draw something, group it, and press Option Command K to turn it into a component: it takes a name, wears a small mark on the canvas and in the layers list so you never mistake it for an ordinary group, and lands on the Library's Components shelf where you can find it again. Renaming it anywhere renames it everywhere, because it only has one name. Placing copies of it, exposing properties and detaching come later. Needs Keep reusable pieces in a Library. Off means no Make Component row and no components on the shelf; components already in a document keep drawing either way.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: stylesFlag,
                    title: "Save a color, a text style or an effect and reuse it",
                    description: "Save a fill, an outline or a text color under a name, and any layer can wear it. The Fill and Color rows in the panel grow a small styles button: save what is there as a style, or pick one you already have. Text goes further: the Style row at the top of the Text section saves the font, size, weight and color together under one name, so changing the heading size across a screen is one edit instead of one per heading. An effect goes the same way: the Style row at the top of a shadow, a glow, a border or a blur saves all of its settings under one name, and the plus on the Effects header puts that name on any other layer. Saved styles sit on the Library\u{2019}s Styles shelf, where you rename one, change it, or take it off the shelf. Changing a style re-sets every layer wearing it in one step, which one undo puts back. Needs Keep reusable pieces in a Library. Off means colors, text and effects are one-offs again and the Styles shelf is empty; styles already in a document keep painting either way.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: sharedLibraryFlag,
                    title: "Use a component you made in every document",
                    description: "A component you make belongs to the document you made it in. The Component section grows a Share across documents switch: turn it on and the component joins a shelf every document on this Mac can reach, so the button, card and nav bar you built for one screen are already in the Library when you start a file tomorrow. Drop one in and it stays linked \u{2014} edit the original in any document and every other document takes the change the next time you look at it, copies and all. The colors it paints from travel with it, and a document that already has a color of that name keeps its own. A document whose shared original has been taken off the shelf keeps its drawing and says the link broke rather than losing the picture. Needs Make a component out of what you drew. Off means components stay in the document they were made in and the shelf holds only what this document has; a component already shared keeps drawing either way.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: starterComponentsFlag,
                    title: "Components in the Library from the start",
                    description: "The Library\u{2019}s Components shelf comes with five ready components on it \u{2014} a button, a text field, a card, a nav bar and a badge \u{2014} so the first thing you do is drag one out instead of building one. Each is an ordinary component: it takes copies, its wording and its parts are adjustable on every copy, and it comes apart. They paint from named styles, so recoloring Accent once repaints every one of them. Dropping one brings it and its colors into the document; a document you never drop one into carries none of it. Needs Make a component out of what you drew. Off means the shelf holds only the components you made yourself; starters already dropped into a document keep working either way.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: colorPickerFlag,
                    title: "One color picker, everywhere a color is chosen",
                    description: "Every swatch in the app opens the same picker, whether it paints a shape\u{2019}s outline, its inside, a shadow, a backdrop, text, a measurement or a tool. It opens with the color you are changing shown beside the one you started from, so you can tell whether you improved it. Inside: a shade and saturation square you drag in, a slider and a number for each channel, and a switch between HSL, RGB and HEX \u{2014} paste \u{201C}#7C4DFF\u{201D}, \u{201C}rgb(124, 77, 255)\u{201D} or \u{201C}hsl(256 100% 65%)\u{201D} into the HEX field and it takes all three. Under that, one row of swatches that switches between nine shades of the color you are on, six colors related to it, the colors this document already uses, and the ones you picked recently. An eyedropper samples any pixel on screen, a live reading says whether the color can be read on white, and Save style puts it in the Library under a name. A shape\u{2019}s fill, its outline and a screen\u{2019}s surface can also hold a gradient rather than one flat color: a top row offers Solid, Linear, Radial and Angular drawn with the colors you are already using, and choosing one brings up a ramp you can add, move, delete and reverse stops on plus a square you drag to aim it. A color that can only ever be flat, like a drop shadow, never shows that row. Off means the color rows open the picker the app shipped with and a few of them open the system color panel instead.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: autoLayoutFlag,
                    title: "Groups that arrange their own contents",
                    description: "A group can be made a stack or a grid, so the things inside it space themselves instead of being nudged into place one at a time. Pick a group and set Arrangement in the Layout section, or pick several layers and choose Layer \u{25B8} Stack Selection (\u{2303}\u{2318}G) or Grid Selection. A stack lays everything along one axis with a gap you type; a grid fills rows of equal cells with a column count you type. Add a layer, delete one, hide one or drag one past another and everything re-flows on its own. Any group can also be given a size of its own: Width and Height are each Hug or Fixed, the number is typed in W and H like any other layer\u{2019}s, and rows set to Stretch fill it. Hug means the group is as big as what is inside it plus the room at its edges, so a button is as wide as its label and gets wider the moment the label does, with nothing to drag. A piece inside a stack or a grid can be the surface behind the rest instead of one of the things being arranged: it is painted to the group\u{2019}s own edges and the others sit on top of it, which is what a button\u{2019}s fill is. Pick it and set Role to Surface behind the rest in the Layout section, or choose Layer \u{25B8} Surface Behind the Rest. Both name it before you pick it, both are one step, and one undo puts it back. One piece in a stack can take whatever room the stack has left over instead of keeping the size it was drawn at, which is how a search field between a logo and a row of buttons is built: pick it and choose Layer \u{25B8} Fill the Row (\u{2325}F), or set Horizontal to Fill the row in the Layout section. Press it again and the piece is handed back the size it had. A stack with a size of its own can share the room it has left over between its rows instead of holding one gap: press the switch beside Gap and the first and the last go to the two ends, which is how a bar with a logo at one end and buttons at the other is built. Type a number straight over it to hold one gap again, and it is the number that was there before. Turning a group you arranged by hand into a stack reads the direction and the gap it already has, so nothing moves when you switch it on. Off means the Arrangement rows and the menu items are gone; a group already set to a stack keeps arranging itself.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: placementFlag,
                    title: "Say where the pieces sit when something is resized",
                    description: "The panel gains a Layout section. A group says how its contents line up \u{2014} left, centre, right or stretch across, top, middle, bottom or stretch down \u{2014} and any one piece inside can say something different for itself, so a button dragged wider keeps its label in the middle while the fill behind it grows. A row that has not been set says which setting it is following from the group it sits in. Text gains an Align control in the Text section for where its words sit inside their own box, and telling text to stretch moves its words to the middle of the box it now fills, so the choice does something you can see. The five Library components arrive already set up this way whether this is on or off. Off means the section is gone and a resize multiplies everything proportionally, which is what a layer with nothing set does anyway.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: crispZoomFlag,
                    title: "Words stay sharp when you zoom in",
                    description: "Zoom past 100% and the labels, captions, measurement readouts and borders you have placed are drawn again at the size you are looking at them, instead of the whole picture being blown up. A label you place reads exactly as crisply as the one you are still typing, at any zoom. The picture underneath is untouched: a screenshot still goes square and blocky past 2x, which is what you want when you are counting pixels. Only the part of the canvas you can see is redrawn, so it costs the same at 800% as at 200%. Off means the whole canvas is stretched from one picture the way it always was, and placed text goes soft as you zoom in.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: calloutShapeFlag,
                    title: "Choose a zoom callout\u{2019}s shape before you draw it",
                    description: "Picking up the Zoom Callout tool puts a Zoom Callout Tool section in the panel with one choice in it: Rectangle or Circle. The box you drag out previews in the shape you chose and the callout lands in it, and the tool keeps that choice for the next one and after a relaunch. Off means every callout is drawn as a rectangle and the only way to a circle is to draw one first and change it in the callout\u{2019}s own section.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: calloutMagnificationFlag,
                    title: "Choose how much a callout magnifies before you draw it",
                    description: "The Zoom Callout tool carries a Magnification slider beside its Shape, in the settings capsule above the tool bar and in the Zoom Callout Tool section of the panel, so you can say how much the next callout blows up what it points at before you drag it out. It starts at 2\u{00D7}, which is what callouts have always been drawn at, and the tool keeps whatever you last set for the next one and after a relaunch. Drawing at the right size the first time also means the callout is placed clear of the picture\u{2019}s other callouts at that size, instead of growing over them when you resize it afterwards. A callout already on the canvas is still resized by its own Magnification slider, and pulling its corners never changes what the tool holds. Off means every new callout comes out at 2\u{00D7} and the only way to a bigger one is to draw it and then resize it.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: canvasGridFlag,
                    title: "A grid to build against",
                    description: "Switch on a grid over the whole canvas and build to it: View \u{25B8} Show Grid, or the Grid row in the Canvas section of the panel. The grid is then worked from the tool bar: a capsule beside the zoom reads the grid's unit and the cell it is working to right now (\"4 \u{2192} 32 pt\"), a slider makes that cell finer or coarser through the sizes real UI is built in, and Adjust Grid takes the canvas over. Spacing, how often a line is bold and columns-or-both stay in the settings the readout opens. It thins and thickens as you zoom, so the lines are never closer together than you can read and never disappear: zoom out and the fine ones fade away leaving the coarse ones, zoom in and they fade back. Inside Adjust Grid you place where the grid counts from — drag the dot at the crossing of its two markers, or nudge it with the arrow keys, catching layer edges and canvas edges on the way — and you pin GUIDES: hover and the grid line nearest the pointer lights yellow, down or across, and clicking pins it there. A pinned guide stays for good, including with the grid switched off, and a drag or a resize catches it exactly the way it catches a grid line, with Command to get away from it. Click a guide to pick it up and move it, backspace to take it off, Clear Guides to take them all off in one undo step; Return keeps everything and Escape puts it all back. Guides and the zero point belong to the DOCUMENT, saved with it and different in every picture; everything else about the grid is an app preference remembered between launches. The grid and its guides are drawn on the canvas, not into the picture, so neither ever lands in an export, a copied picture or a redline sheet. Off means the canvas has no grid and the View row and the Grid controls are gone.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: colorDragFlag,
                    title: "Carry a colour from one swatch to another",
                    description: "Colour swatches are something you can pick a colour up off and drop a colour onto, the way a colour well on a Mac always has been. Drag the Fill swatch onto the Outline swatch and the outline takes that colour, in one step one undo puts back. The swatch about to take it draws a ring around itself before you let go; a swatch that would not change, the one the colour came from or one already wearing it, stays dark and the pointer shows the no entry sign. A swatch wearing a saved colour still takes the drop, and the ring wears the palette mark first to say that letting go stops it following that name. The bar's swatches are handles too: the colour the next shape comes out in can be carried off the bar and dropped on the Library to keep it under a name, and a box's inside and border can pass their colour to each other. A colour you have saved is a handle too: drag its tile off the Library shelf onto any swatch and that swatch paints with it, keeping the name, so it still follows the saved colour the day you recolour it. A swatch that cannot wear a name, a shadow’s colour or the pair the bucket fills with, takes the colour on its own and says so before you let go. Colours travel in and out of other Mac apps too, so a colour dragged from a swatch lands in another app’s colour well and one dragged in from the system Colours panel lands here. Off means the swatches are click only, exactly as before.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: blankCanvasFlag,
                    title: "Start from a blank canvas",
                    description: "You can start a picture from nothing instead of only opening, pasting or capturing one. Choose File \u{25B8} New Blank Canvas from any window, or click Blank canvas on an empty window\u{2019}s card: pick a size (Desktop, Phone, Tablet, Square, or type your own) and you land on a white canvas every tool draws on right away. Asking from a window that already holds a picture leaves that picture alone and opens the canvas in a new window. Off means the File menu row is gone and a new window offers open, capture and paste only.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: copyPicksYourLayerFlag,
                    title: "Copy takes the layer you picked",
                    description: "Copy takes the layer you picked, and a marquee crops it. Pick a layer, drag a marquee over part of it and press Command C: what lands on the clipboard is that layer’s pixels inside the marquee and nothing from the layers around it, trimmed to what is actually drawn there, so pasting it back gives you the piece rather than a big transparent box. A marquee that misses the layer copies nothing and beeps instead of handing back an invisible rectangle. Everything flattened together is still one keystroke away as Edit ▸ Copy Merged on Command Shift C, of the marquee when there is one and of the whole picture when there is not, which is where Photoshop keeps it. Command X follows copy: with a marquee up it takes that layer’s pixels out of the marquee instead of deleting the whole layer. Command J, New Layer via Copy, agrees with it too: with a layer picked and a marquee drawn it makes a new layer out of that layer’s pixels inside the marquee, named after the layer it came from, so the same marquee gives you the same pixels whichever way you take them, and a marquee that misses the layer beeps instead of making an empty layer. With no layer picked, both keys copy everything inside the marquee, since there is nothing to prefer. Off means a marquee beats the layer you picked, Command C hands back every layer flattened together, and Command Shift C is File ▸ Copy Image.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: cutSaysWhatItCannotDoFlag,
                    title: "Say when a piece cannot be taken out or filled in",
                    description: "A marquee only works on a piece of a picture. Drag one over half a rectangle or a piece of text and press Command X and, before this, the whole shape vanished onto the clipboard with nothing on screen to say why; Backspace and Option Backspace did nothing at all, just as quietly. On, all three keys refuse and the canvas says so in one line at the bottom: what did not happen, why, and that clearing the marquee cuts, deletes or fills the whole layer instead. The paint bucket clicked inside the marquee says the same thing rather than going quiet where the key explains itself. A picture that has been cropped or turned gets its own line, since it is pixels and the crop is what is in the way. Taking a piece out of a plain picture and filling one are untouched, and so is working with no marquee up, which still acts on the whole layer. Off means cut silently takes the lot and the other two silently do nothing.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: pasteHandsYouThePointerFlag,
                    title: "A new picture hands you the pointer",
                    description: "Paste something, or drag a picture in from the Finder, and you are left holding the pointer with the new thing picked, so the obvious next move, dragging it where you want it, works straight away. Before this you kept whatever tool you had, and a drag on the thing you just added drew a new shape over it instead of moving it. The marquee you had up is cleared, since the new thing is what you are working on now. Undo hands your tool back: press Command Z and the rectangle, arrow or brush you were using is in your hand again, and redo takes the pointer back up. Pasting several times in a row still steps each copy past the last, each one picked in turn, and undoing the run puts back the tool you started with. A picture let go on a row in the layers list, and one placed off the Library shelf, arrive the same way. Off means paste and drop leave the tool alone, the way they always did.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: selectionUndoFlag,
                    title: "Undo puts back a marquee you lost",
                    description: "A marquee is something you place by hand, so Command Z takes it back like everything else. Draw one, nudge it with the arrow keys, drag the outline somewhere better, invert it or clear it, and each of those is one press to undo and one to put back. Before this, a marquee never entered the undo history at all: press Command Z after spending a minute lining one up and it stepped over your last edit to the picture instead, and the outline was gone for good. Steps interleave, so undo always takes back whatever you did last, paint or outline, in the order you did it. A run of arrow-key nudges counts as one act, the way letting go of a drag does, so holding the key down is still a single press to undo. An edit that consumes the marquee, like grouping layers or New Layer via Copy, still undoes in one press and hands the outline back with it. Off means the marquee stays outside the undo history and is lost the moment it changes.",
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
