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
    public static let measureDistanceOnRelease = "distance-on-release"

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

    public static let placementFlag = "next-placement"

    public static let autoLayoutFlag = "next-auto-layout"

    public static let colorPickerFlag = "next-color-picker"

    public static let crispZoomFlag = "next-crisp-zoom"

    public static let calloutShapeFlag = "next-callout-shape"

    public static let canvasGridFlag = "next-canvas-grid"

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
                    parameters: [
                        FeatureParameter(name: measureDistanceOnRelease,
                                         label: "Distance lands when you let go",
                                         value: .boolean(false)),
                    ]),
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
                    title: "Every handle says what it does",
                    description: "Rest the pointer on any handle around a selected object and it says what a press would do before you press it. An open hand over the parts that drag on their own (an arrow\'s caption, either end of a line, a measurement\'s number and its two feet), and a closed hand while you drag one. The matching resize arrows over the eight handles round a layer, round the canvas, or round the crop box. A curved arrow over the knob that turns it.",
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
                    name: geometryFieldsFlag,
                    title: "Type a layer's position and size",
                    description: "The inspector gains a Position and Size section: X, Y, W and H for everything you have picked, as numbers you can type. One button can be made exactly 296 by 118, and a whole row of them can be made one width, or lined up on one left edge, in a single move and a single undo. Where the picked layers differ, a field says Mixed rather than a number. Up and down arrow steps a field by 1, Shift and an arrow by 10. A number the app worked out for you, like how tall a paragraph came out or anything on a locked layer, is shown as plain text with no box around it, and clicking it says why it takes nothing. Off means position and size are drag only.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: alignLayersFlag,
                    title: "Line layers up with each other",
                    description: "Two jobs at once. Select two or more layers and an Arrange row appears at the top of the inspector, mirrored in the Layer menu: line their left edges, centres, right edges, tops, middles or bottoms up in one press, and with three or more, space them out evenly across or down so every gap matches. And while you drag a layer, it now sticks to the edges and centres of the other layers as well as the picture\u{2019}s, with a short line showing what it just lined up with; holding Command drags free. Off means dragging pulls to the edges and middle of the picture only, and there is no Arrange row.",
                    isEnabled: false,
                    parameters: []),
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
                    title: "Save a color as a style and reuse it",
                    description: "Save a fill, an outline or a text color under a name, and any layer can wear it. The Fill and Color rows in the inspector grow a small styles button: save what is there as a style, or pick one you already have. Saved styles sit on the Library\u{2019}s Styles shelf, where you rename one, change its color, or take it off the shelf. Changing a style repaints every layer wearing it in one step, which one undo puts back. Needs Keep reusable pieces in a Library. Off means colors are one-offs again and the Styles shelf is empty; styles already in a document keep painting either way.",
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
                    description: "A group can be made a stack or a grid, so the things inside it space themselves instead of being nudged into place one at a time. Pick a group and set Arrangement in the Layout section, or pick several layers and choose Layer \u{25B8} Stack Selection (\u{2303}\u{2318}G) or Grid Selection. A stack lays everything along one axis with a gap you type; a grid fills rows of equal cells with a column count you type. Add a layer, delete one, hide one or drag one past another and everything re-flows on its own. Any group can also be given a size of its own: Width and Height are each Hug or Fixed, the number is typed in W and H like any other layer\u{2019}s, and rows set to Stretch fill it. Hug means the group is as big as what is inside it plus the room at its edges, so a button is as wide as its label and gets wider the moment the label does, with nothing to drag. A piece set to Stretch both ways inside a group is the surface behind the rest: it takes whatever box they made rather than deciding it, which is what a button\u{2019}s fill does. A stack with a size of its own can share the room it has left over between its rows instead of holding one gap: press the switch beside Gap and the first and the last go to the two ends, which is how a bar with a logo at one end and buttons at the other is built. Type a number straight over it to hold one gap again, and it is the number that was there before. Turning a group you arranged by hand into a stack reads the direction and the gap it already has, so nothing moves when you switch it on. Off means the Arrangement rows and the menu items are gone; a group already set to a stack keeps arranging itself.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: placementFlag,
                    title: "Say where the pieces sit when something is resized",
                    description: "The inspector gains a Layout section. A group says how its contents line up \u{2014} left, centre, right or stretch across, top, middle, bottom or stretch down \u{2014} and any one piece inside can say something different for itself, so a button dragged wider keeps its label in the middle while the fill behind it grows. A row that has not been set says which setting it is following from the group it sits in. Text gains an Align control in the Text section for where its words sit inside their own box, and telling text to stretch moves its words to the middle of the box it now fills, so the choice does something you can see. The five Library components arrive already set up this way whether this is on or off. Off means the section is gone and a resize multiplies everything proportionally, which is what a layer with nothing set does anyway.",
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
                    description: "Picking up the Zoom Callout tool puts a Zoom Callout Tool section in the inspector with one choice in it: Rectangle or Circle. The box you drag out previews in the shape you chose and the callout lands in it, and the tool keeps that choice for the next one and after a relaunch. Off means every callout is drawn as a rectangle and the only way to a circle is to draw one first and change it in the callout\u{2019}s own section.",
                    isEnabled: false,
                    parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(
                    name: canvasGridFlag,
                    title: "A grid to build against",
                    description: "Switch on a grid over the whole canvas and build to it: View \u{25B8} Show Grid, or the Grid row in the Canvas section of the panel. It starts four points apart, with every eighth line stronger so you can count without measuring, and both numbers are typable; choose columns on their own or columns and rows. It thins and thickens as you zoom, so the lines are never closer together than you can read and never disappear: zoom out and the fine ones fade away leaving the coarse ones, zoom in and they fade back. The grid is drawn on the canvas, not into the picture, so it never lands in an export, a copied picture or a redline sheet, and it is remembered between launches rather than saved in any document. Off means the canvas has no grid and the View row and the Grid controls are gone.",
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
