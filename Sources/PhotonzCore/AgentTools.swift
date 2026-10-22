import CoreGraphics
import Foundation

/// One tool the app offers an agent over the MCP channel
/// (`docs/design/agent-mcp.md`): its name, what it does in a sentence or two,
/// and the JSON schema its arguments are checked against.
public struct AgentTool: Hashable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: AgentJSON

    /// The tool as `tools/list` lists it.
    public var listing: AgentJSON {
        ["name": .string(name), "description": .string(description), "inputSchema": inputSchema]
    }
}

/// What an agent asked for, checked and typed: the only thing the app is ever
/// handed to act on.
public enum AgentRequest: Hashable, Sendable {
    public enum OpenTarget: Hashable, Sendable {
        case path(String)
        /// An item of History by its place in `list_history`, newest first.
        case history(index: Int)
    }

    case listDocuments
    case listHistory(limit: Int)
    case openDocument(OpenTarget)
    case readDocument(document: String?, layer: String?)
    case renderPicture(document: String?, layer: String?, region: CGRect?, maxSize: Int)
    case videoFrame(document: String?, atMS: Int, region: CGRect?, maxSize: Int)
    case contactSheet(document: String?, fromMS: Int?, toMS: Int?, count: Int, columns: Int?, cellWidth: Int)
    case undo(document: String?, steps: Int)
    case redo(document: String?, steps: Int)
    /// The command table, with whether each can run now on the document.
    case listCommands(document: String?, area: AppCommand.Area?, readyOnly: Bool)
    /// One command by name, its arguments already checked.
    case runCommand(document: String?, call: AppCommandCall)
    // Slice 3: pictures (`AgentDrawing.swift`).
    case newPicture(width: Int, height: Int)
    case addShape(document: String?, shape: AgentShape)
    case addPath(document: String?, path: AgentPath)
    case addDrawing(document: String?, drawing: AgentDrawingCall)
    case addText(document: String?, text: AgentText)
    case setLayer(document: String?, layer: String, change: AgentLayerChange)
    case findElements(document: String?, region: CGRect?, limit: Int)
    case addMeasurement(document: String?, measurement: AgentMeasurement)
    case findMeasurements(document: String?, region: CGRect?)
    case markMeasurements(document: String?, region: CGRect?, marks: [String])
    case findMisalignments(document: String?, region: CGRect?)
    case markMisalignments(document: String?, region: CGRect?, findings: [String])
    case listComponents(document: String?)
    case placeComponent(document: String?, component: String, center: CGPoint)
    case export(document: String?, format: AgentExportFormat, path: String, scale: Double, background: Bool)
    // Slice 4: video (`AgentVideo.swift`).
    case newVideo(AgentNewVideo)
    case addClip(document: String?, clip: AgentClipSource, atMS: Int?, track: String?)
    case cut(document: String?, atMS: Int, clip: String?)
    case trim(document: String?, clip: String, keepFromMS: Int?, keepToMS: Int?, ripple: Bool)
    case moveClip(document: String?, clip: String, toMS: Int?, track: String?)
    /// Nil `kind` is a plain cut.
    case setTransition(document: String?, atMS: Int, kind: ClipTransitionKind?, lengthMS: Int?)
    case addTitle(document: String?, title: AgentTitle)
    case listTitles(document: String?)
    case recommendedZooms(document: String?, clip: String?)
    case applyZooms(document: String?, clip: String?)
    case setPlayhead(document: String?, atMS: Int)
    case exportVideo(document: String?, path: String, size: VideoExportSize, quality: VideoExportQuality)
    // Design systems (`AgentDesign.swift`)
    case listStyles(document: String?)
    case addStyle(document: String?, style: AgentNewStyle)
    case applyStyle(document: String?, style: String, layers: [String], part: AgentStylePart?)
    case setLayout(document: String?, layer: String, change: AgentLayoutChange)
}

/// Why a call was refused, in one sentence a model can act on.
public struct AgentToolError: Error, Hashable, Sendable {
    public let message: String
    /// No tool has the name asked for, which is a protocol error rather than
    /// a tool's own.
    public let isUnknownTool: Bool

    public init(_ message: String, isUnknownTool: Bool = false) {
        self.message = message
        self.isUnknownTool = isUnknownTool
    }
}

/// The tools of the agent channel and the checking of a call against them.
///
/// The first slice of the MCP ask: reach the app, read the open document, see
/// it, and step back. The second runs every command of the menus by name
/// (`AppCommandTable`). The third draws: shapes, paths, text, the Measure
/// tool's own measurements and Library components, and exports the result
/// (`AgentDrawing.swift`). The fourth cuts a video from History recordings
/// with titles, transitions and recommended zooms, and writes an MP4
/// (`AgentVideo.swift`). The fifth builds a design system: named colours and
/// type on the Styles shelf, and the spacing groups keep (`AgentDesign.swift`).
public enum AgentTools {

    /// How big a picture comes back unless asked otherwise: big enough to read
    /// a screenshot's text, small enough not to fill a model's context.
    public static let defaultMaxSize = 1024
    public static let largestMaxSize = 2048
    public static let defaultCellWidth = 320
    public static let defaultSheetCount = 12
    public static let mostSheetFrames = 48

    // MARK: Schema pieces

    private static let documentProperty: AgentJSON = [
        "type": "string",
        "description": "The document's id from list_documents, such as d1. Leave it out to use the document in front.",
    ]

    private static let maxSizeProperty: AgentJSON = [
        "type": "integer", "minimum": 64, "maximum": .number(Double(largestMaxSize)),
        "description": "The longest side of the picture in pixels. 1024 when left out.",
    ]

    private static let regionProperty: AgentJSON = [
        "type": "object",
        "description": "Only this part of the canvas, in document points from the top left.",
        "properties": [
            "x": ["type": "number", "description": "Left edge."],
            "y": ["type": "number", "description": "Top edge."],
            "width": ["type": "number", "minimum": 1, "description": "Width."],
            "height": ["type": "number", "minimum": 1, "description": "Height."],
        ],
        "required": ["x", "y", "width", "height"],
        "additionalProperties": false,
    ]

    private static func pointProperty(_ words: String) -> AgentJSON {
        ["type": "object", "description": .string(words),
         "properties": ["x": ["type": "number", "description": "Across, from the left."],
                        "y": ["type": "number", "description": "Down, from the top."]],
         "required": ["x", "y"], "additionalProperties": false]
    }

    private static func boxProperty(_ words: String) -> AgentJSON {
        var box = regionProperty.objectValue ?? [:]
        box["description"] = .string(words)
        return .object(box)
    }

    private static let inkWords = "A colour as #RRGGBB or #RRGGBBAA, or none to take it away."

    /// The paint and finish every drawing tool and set_layer share.
    private static let lookProperties: [String: AgentJSON] = [
        "fill": ["type": "string", "description": .string("The inside of a box, oval or closed path, or the colour of words. " + inkWords)],
        "stroke": ["type": "string", "description": .string("The line: a box's edge, a path's outline, a line or arrow's colour. " + inkWords)],
        "strokeWidth": ["type": "number", "minimum": 0, "maximum": 200, "description": "How thick the line is, in points."],
        "cornerRadius": ["type": "number", "minimum": 0, "maximum": 2000, "description": "How round a box's corners are, in points."],
        "opacity": ["type": "number", "minimum": 0, "maximum": 1, "description": "0 is invisible, 1 is solid."],
        "shadow": ["type": "object", "description": "A drop shadow. Left out, a new layer has none (words get the app's own legibility shadow).",
                   "properties": [
                       "radius": ["type": "number", "minimum": 0, "maximum": 200, "description": "How soft, in points. 12 when left out."],
                       "x": ["type": "number", "description": "How far right it falls. 0 when left out."],
                       "y": ["type": "number", "description": "How far down it falls. 4 when left out."],
                       "color": ["type": "string", "description": "#RRGGBB. Black when left out."],
                       "opacity": ["type": "number", "minimum": 0, "maximum": 1, "description": "0.3 when left out."],
                   ], "additionalProperties": false],
        "removeShadow": ["type": "boolean", "description": "Take every shadow off."],
    ]

    private static func stepsProperty(_ verb: String) -> AgentJSON {
        ["type": "integer", "minimum": 1, "maximum": 50,
         "description": .string("How many steps to \(verb). 1 when left out.")]
    }

    private static func schema(_ properties: [String: AgentJSON], required: [String] = []) -> AgentJSON {
        ["type": "object", "properties": .object(properties),
         "required": .array(required.map(AgentJSON.string)), "additionalProperties": false]
    }

    // MARK: The tools

    public static let all: [AgentTool] = [
        AgentTool(
            name: "list_documents",
            description: "The documents open in Photonz: id, title, file, picture or video, size, length, whether it is in front, and whether it can undo or redo.",
            inputSchema: schema([:])),
        AgentTool(
            name: "list_history",
            description: "The screenshots and recordings in Photonz History, newest first, with the index open_document takes.",
            inputSchema: schema([
                "limit": ["type": "integer", "minimum": 1, "maximum": 100,
                          "description": "How many to list. 20 when left out."],
            ])),
        AgentTool(
            name: "open_document",
            description: "Open a picture, recording or .photonz file in its own window, by path or by its index in list_history. Answers with the new document's id once it is open.",
            inputSchema: schema([
                "path": ["type": "string", "description": "An absolute path to the file."],
                "historyIndex": ["type": "integer", "minimum": 0,
                                 "description": "The item's index in list_history; 0 is the newest."],
            ])),
        AgentTool(
            name: "read_document",
            description: "The document as structured data: canvas, layers top first with frames (a group's is the box it covers; the layers inside a group are measured from the group's top left), text, styles and a group's layout, and on a video the tracks with each clip's times, the cuts with their transitions, markers and the playhead. Times are in seconds.",
            inputSchema: schema([
                "document": documentProperty,
                "layer": ["type": "string", "description": "Only this layer and everything inside it, listed in full. Use it for a group or component when the whole read stops listing (past 400 layers)."],
            ])),
        AgentTool(
            name: "render_picture",
            description: "A PNG of the canvas as it is now (a video at its playhead), or of one layer alone in place, or of one region. Use it to check your work.",
            inputSchema: schema([
                "document": documentProperty,
                "layer": ["type": "string", "description": "A layer id from read_document, drawn alone where it sits."],
                "region": regionProperty,
                "maxSize": maxSizeProperty,
            ])),
        AgentTool(
            name: "video_frame",
            description: "A PNG of a video document at a moment, drawn the way export draws it.",
            inputSchema: schema([
                "document": documentProperty,
                "seconds": ["type": "number", "minimum": 0, "description": "The moment, in seconds from the start."],
                "region": regionProperty,
                "maxSize": maxSizeProperty,
            ], required: ["seconds"])),
        AgentTool(
            name: "contact_sheet",
            description: "One PNG holding frames spread evenly across a stretch of a video, each labelled with its time, to see a whole edit at a glance.",
            inputSchema: schema([
                "document": documentProperty,
                "fromSeconds": ["type": "number", "minimum": 0, "description": "Where the stretch starts. The start of the video when left out."],
                "toSeconds": ["type": "number", "minimum": 0, "description": "Where it ends. The end of the video when left out."],
                "count": ["type": "integer", "minimum": 1, "maximum": .number(Double(mostSheetFrames)),
                          "description": "How many frames. 12 when left out."],
                "columns": ["type": "integer", "minimum": 1, "maximum": 12,
                            "description": "How many frames across. Chosen to make the sheet roughly square when left out."],
                "cellWidth": ["type": "integer", "minimum": 64, "maximum": 640,
                              "description": "Each frame's width in pixels. 320 when left out."],
            ])),
        AgentTool(
            name: "undo",
            description: "Undo the last step in the document, exactly as Edit > Undo does, whether a person or an agent made it.",
            inputSchema: schema(["document": documentProperty, "steps": stepsProperty("undo")])),
        AgentTool(
            name: "redo",
            description: "Redo what undo took back, exactly as Edit > Redo does.",
            inputSchema: schema(["document": documentProperty, "steps": stepsProperty("redo")])),
        AgentTool(
            name: "list_commands",
            description: "The commands of the menu bar and the right-click menus, by name: their menu, what they need, the arguments they take, and whether each can run right now on the document.",
            inputSchema: schema([
                "document": documentProperty,
                "area": ["type": "string", "enum": .array(AppCommand.Area.allCases.map { .string($0.rawValue) }),
                         "description": "Only commands about this: timeline, layers, edit, measure or view."],
                "readyOnly": ["type": "boolean", "description": "Only the commands that can run right now."],
            ])),
        AgentTool(
            name: "run_command",
            description: "Run one command from list_commands by name, as its menu row does. It can pick a playhead time, layers, a piece or a track first. One run is one undo step.",
            inputSchema: schema([
                "document": documentProperty,
                "command": ["type": "string", "description": "The command's name from list_commands, such as split_at_playhead."],
                "arguments": ["type": "object", "description": "The command's arguments, as list_commands gives them."],
            ], required: ["command"])),
    ] + drawingTools + videoTools + designTools

    /// Slice 3: build a picture out of real layers and export it.
    static let drawingTools: [AgentTool] = [
        AgentTool(
            name: "new_picture",
            description: "Open a new blank picture in its own window, as File > New does, and answer with its id. Every drawing tool then works on it.",
            inputSchema: schema([
                "width": ["type": "integer", "minimum": 16, "maximum": 8000, "description": "Width in points."],
                "height": ["type": "integer", "minimum": 16, "maximum": 8000, "description": "Height in points."],
            ], required: ["width", "height"])),
        AgentTool(
            name: "add_shape",
            description: "Draw a shape with the shape tool: a rectangle, ellipse or highlight in a frame, or a line or arrow between two points. It is an ordinary layer a person can edit. One undo step. run_command combine_shapes joins several into one outline.",
            inputSchema: schema(lookProperties.merging([
                "document": documentProperty,
                "shape": ["type": "string", "enum": .array(AnnotationShape.allCases.map { .string($0.rawValue) }),
                          "description": "rectangle, ellipse, highlight, line or arrow."],
                "frame": boxProperty("Where a rectangle, ellipse or highlight sits, in canvas points from the top left."),
                "from": pointProperty("Where a line or arrow starts (an arrow's tail)."),
                "to": pointProperty("Where a line or arrow ends (an arrow's head)."),
                "name": ["type": "string", "description": "The layer's name in the Layers list."],
            ]) { $1 }, required: ["shape"])),
        AgentTool(
            name: "add_path",
            description: "Draw a path with the Pen: points in order in canvas points, each a corner or smooth, open or closed. A closed path with nothing said is filled. One undo step.",
            inputSchema: schema(lookProperties.merging([
                "document": documentProperty,
                "points": ["type": "array", "description": "Two or more points, in the order the outline runs through them.",
                           "items": ["type": "object", "properties": [
                               "x": ["type": "number", "description": "Across, from the left."],
                               "y": ["type": "number", "description": "Down, from the top."],
                               "smooth": ["type": "boolean", "description": "A smooth point curves through; left out it is a corner."],
                               "handleIn": pointProperty("The curve arriving here, as an offset from the point. Worked out for a smooth point when left out."),
                               "handleOut": pointProperty("The curve leaving here, as an offset from the point."),
                               "cornerRadius": ["type": "number", "minimum": 0, "description": "Round this corner, in points."],
                           ], "required": ["x", "y"], "additionalProperties": false]],
                "closed": ["type": "boolean", "description": "Join the last point back to the first. Open when left out."],
                "name": ["type": "string", "description": "The layer's name in the Layers list."],
            ]) { $1 }, required: ["points"])),
        AgentTool(
            name: "add_drawing",
            description: "Draw a thing (a dog, a coffee cup, a smiley face) or a scene (the sun over mountains, a lighthouse on a cliff) as one drawing of editable layers, grouped and named. With its picture model running, Photonz paints it for the request and traces it into layers; otherwise it draws the svg you give. Nothing is looked up. Better than many add_shape and add_path calls. One undo step.",
            inputSchema: schema([
                "document": documentProperty,
                "subject": ["type": "string", "description": "What it is, in a word or two: dog, coffee cup, smiley face, sun over mountains."],
                "svg": ["type": "string", "description": "Your own drawing of it as one complete SVG, needed when Photonz cannot paint it (its picture model is not running); when given, nothing is painted: a viewBox, a few flat colours, curves and ellipses where the thing is round, every part touching the part it belongs to, an id on each shape naming its part (head, left-ear, body). No text."],
                "icon": ["type": "boolean", "description": "Make it an icon: a 512 point square icon frame with the drawing on its keylines. On a blank picture the picture becomes that frame."],
                "frame": boxProperty("Where the drawing goes, fitted and centred in this box. Centred on the canvas, 60 per cent of its shorter side, when left out."),
                "name": ["type": "string", "description": "The group's name in the Layers list. The subject when left out."],
                "style": ["type": "string", "description": "The look asked for, in the person's words (line art, silhouette, watercolor, flat). Leave it out when none was named."],
                "asked": ["type": "string", "description": "The person's own words for the drawing, when they say more than the subject does (what it is doing, where). Used when Photonz paints the drawing with its picture model."],
                "scene": ["type": "boolean", "description": "true when the drawing is a place or a scene that fills the picture with its own sky or ground (a landscape, a skyline, a beach at sunset), so it is painted edge to edge. Used when Photonz paints the drawing."],
                "plan": ["type": "array", "items": ["type": "string"], "description": "Only when the request names more than the thing: one to four short statements someone looking at the picture can answer yes or no, for each pose, action, view, mood and relationship the request names, and when two things act together which parts touch (its paws on the keys) and what is in front. Nothing the request did not ask for. Painted from, and checked against the drawing once it is made."],
            ], required: ["subject"])),
        AgentTool(
            name: "add_text",
            description: "Set words with the Text tool, their top left at x and y. The box is measured to fit them. One undo step.",
            inputSchema: schema([
                "document": documentProperty,
                "text": ["type": "string", "description": "The words. A new line is a line break."],
                "x": ["type": "number", "description": "Left edge, in canvas points."],
                "y": ["type": "number", "description": "Top edge, in canvas points."],
                "fontSize": ["type": "number", "minimum": 4, "maximum": 1000, "description": "In points. 24 when left out."],
                "fontName": ["type": "string", "description": "A font family on this Mac. SF Pro when left out."],
                "weight": ["type": "string", "enum": .array(TextWeight.allCases.map { .string($0.rawValue) }),
                           "description": "regular, medium, semibold or bold."],
                "color": ["type": "string", "description": "#RRGGBB. Near black when left out."],
                "alignment": ["type": "string", "enum": ["left", "center", "right"], "description": "Where lines sit across the box."],
                "width": ["type": "number", "minimum": 8, "description": "Wrap the words at this width, in points."],
                "name": ["type": "string", "description": "The layer's name in the Layers list."],
                "shadow": ["type": "boolean", "description": "The soft legibility shadow the Text tool puts under words. On when left out; turn it off for an icon, since an SVG can only carry shadowed words as a picture."],
            ], required: ["text", "x", "y"])),
        AgentTool(
            name: "set_layer",
            description: "Change a layer as the inspector would: its frame, name, visibility, paint, line, corners, opacity, shadow, and a text layer's words and size. Leave out what stays. One undo step.",
            inputSchema: schema(lookProperties.merging([
                "document": documentProperty,
                "layer": ["type": "string", "description": "The layer's id from read_document."],
                "x": ["type": "number", "description": "Move its left edge here."],
                "y": ["type": "number", "description": "Move its top edge here."],
                "width": ["type": "number", "minimum": 1, "description": "Resize to this width."],
                "height": ["type": "number", "minimum": 1, "description": "Resize to this height."],
                "name": ["type": "string", "description": "Rename it."],
                "visible": ["type": "boolean", "description": "Show or hide it."],
                "text": ["type": "string", "description": "A text layer's new words."],
                "fontSize": ["type": "number", "minimum": 4, "maximum": 1000, "description": "A text layer's new size."],
                "flip": ["type": "string", "enum": ["horizontal", "vertical", "both"],
                         "description": "Mirror it about its own middle, as Edit > Transform > Flip does: horizontal left to right, vertical top to bottom. Each call flips again, so twice puts it back. Mirror Across Center makes a mirrored copy instead."],
            ]) { $1 }, required: ["layer"])),
        AgentTool(
            name: "find_elements",
            description: "The boxes the Measure tool sees in the picture (buttons, fields, cards, rows, icons, lines of text) and every drawn layer, largest first, in canvas points. Use them to place measurements.",
            inputSchema: schema([
                "document": documentProperty,
                "region": regionProperty,
                "limit": ["type": "integer", "minimum": 1, "maximum": 200, "description": "How many. 40 when left out."],
            ])),
        AgentTool(
            name: "add_measurement",
            description: "Place a measurement with the Measure tool: size (width and height of a box, or of the element at a point), gap (between two boxes, or around a point), or distance (between two points on the edges measured; the app draws its readout clear of them). An editable layer, one undo step.",
            inputSchema: schema([
                "document": documentProperty,
                "kind": ["type": "string", "enum": ["size", "gap", "distance"], "description": "size, gap or distance."],
                "box": boxProperty("size: the box to measure, such as one from find_elements."),
                "boxes": ["type": "array", "description": "gap: the two boxes whose space between is measured.",
                          "items": boxProperty("One of the two boxes.")],
                "at": pointProperty("size or gap: measure what the tool finds here, as a click would."),
                "level": ["type": "integer", "minimum": 0, "maximum": 6,
                          "description": "size at a point: 0 is the element under it, 1 the thing holding that, and so on."],
                "from": pointProperty("distance: one end, on the first edge measured."),
                "to": pointProperty("distance: the other end, on the second edge."),
                "axis": ["type": "string", "enum": ["horizontal", "vertical"],
                         "description": "distance: which way it reads. The longer way when left out."],
            ], required: ["kind"])),
        AgentTool(
            name: "find_measurements",
            description: "The redline a designer would hand a developer for a UI screenshot, chosen in code off its pixels: one size of each kind of control (a repeated switch or field is measured once, on the first), then the spacing that defines the layout (margin, padding, row height, section gap, the gap between neighbouring controls, a button's label inset). Each mark has an id, what it is and its reading in points.",
            inputSchema: schema([
                "document": documentProperty,
                "region": regionProperty,
            ])),
        AgentTool(
            name: "mark_measurements",
            description: "Lays marks from find_measurements on the picture with the Measure tool: a size as one group of a width and a height, spacing as one caliper, every readout placed clear of words, controls and the other readouts. One editable layer a mark, one undo step.",
            inputSchema: schema([
                "document": documentProperty,
                "region": regionProperty,
                "marks": ["type": "array", "minItems": 1,
                          "description": "The ids from find_measurements to lay, such as r1. Normally all of them.",
                          "items": ["type": "string"]],
            ], required: ["marks"])),
        AgentTool(
            name: "find_misalignments",
            description: "Checks a UI screenshot for what a designer would mark as inconsistent: edges that almost line up but miss by 1 to 8 points, uneven gaps in a repeated run, padding or border widths that differ between matching things. Every number is measured off the pixels. Each finding has an id, what is off with both numbers, and its box.",
            inputSchema: schema([
                "document": documentProperty,
                "region": regionProperty,
            ])),
        AgentTool(
            name: "mark_misalignments",
            description: "Marks findings from find_misalignments on the picture as redlines in the Measure tool's look: a guide where edges should line up, a caliper across a gap, padding or border that differs, each readout carrying the measured numbers. One editable layer a finding, one undo step.",
            inputSchema: schema([
                "document": documentProperty,
                "region": regionProperty,
                "findings": ["type": "array", "minItems": 1,
                             "description": "The ids from find_misalignments to mark, such as m1. Every finding worth showing.",
                             "items": ["type": "string"]],
            ], required: ["findings"])),
        AgentTool(
            name: "list_components",
            description: "The components in the Library: the document's own, the shared shelf's and the app's starters, with the id place_component takes.",
            inputSchema: schema(["document": documentProperty])),
        AgentTool(
            name: "place_component",
            description: "Place a copy of a Library component, centred on a point, as dragging its tile does. One undo step.",
            inputSchema: schema([
                "document": documentProperty,
                "component": ["type": "string", "description": "Its id or its name from list_components."],
                "x": ["type": "number", "description": "Centre, across."],
                "y": ["type": "number", "description": "Centre, down."],
            ], required: ["component", "x", "y"])),
        AgentTool(
            name: "export",
            description: "Write the document to a file as File > Export does: a picture as PNG, or SVG with shapes, paths and text kept as vectors; a video as MP4, everything on the timeline drawn as it plays, with its sound. Answers once the file is written.",
            inputSchema: schema([
                "document": documentProperty,
                "format": ["type": "string", "enum": .array(AgentExportFormat.allCases.map { .string($0.rawValue) }),
                           "description": "png or svg for a picture, mp4 for a video."],
                "path": ["type": "string", "description": "An absolute path to write, ending .png, .svg or .mp4."],
                "scale": ["type": "number", "minimum": .number(0.1), "maximum": 8, "description": "PNG only: 2 doubles the pixels. 1 when left out."],
                "background": ["type": "boolean", "description": "PNG and SVG: keep the canvas colour behind the drawing. True when left out; false leaves it see-through."],
                "size": ["type": "string", "enum": .array(AgentVideoSize.allCases.map { .string($0.rawValue) }),
                         "description": "MP4 only: full keeps the video's own frame; 1080p, 720p and 480p shrink a bigger one. full when left out."],
                "quality": ["type": "string", "enum": .array(VideoExportQuality.allCases.map { .string($0.rawValue) }),
                            "description": "MP4 only: high (smoothest, biggest), standard or small. high when left out."],
            ], required: ["format", "path"])),
    ]

    public static func tool(named name: String) -> AgentTool? { all.first { $0.name == name } }

    // MARK: Checking a call

    /// A call checked against its tool's schema and made into a request, or
    /// the sentence saying what was wrong with it.
    public static func request(tool name: String, arguments: AgentJSON?) -> Result<AgentRequest, AgentToolError> {
        guard let tool = tool(named: name) else {
            return .failure(AgentToolError("There is no tool called \(name).", isUnknownTool: true))
        }
        let given = arguments ?? .object([:])
        if let problem = AgentSchema.problem(with: given, against: tool.inputSchema, at: "") {
            return .failure(AgentToolError("\(name): \(problem)"))
        }
        let args = given.objectValue ?? [:]
        let document = args["document"]?.stringValue
        let maxSize = args["maxSize"]?.intValue ?? defaultMaxSize
        switch name {
        case "list_documents":
            return .success(.listDocuments)
        case "list_history":
            return .success(.listHistory(limit: args["limit"]?.intValue ?? 20))
        case "open_document":
            switch (args["path"]?.stringValue, args["historyIndex"]?.intValue) {
            case (let path?, nil):
                return .success(.openDocument(.path(path)))
            case (nil, let index?):
                return .success(.openDocument(.history(index: index)))
            default:
                return .failure(AgentToolError("open_document: give either path or historyIndex, not both and not neither."))
            }
        case "read_document":
            return .success(.readDocument(document: document, layer: args["layer"]?.stringValue))
        case "render_picture":
            return .success(.renderPicture(document: document, layer: args["layer"]?.stringValue,
                                           region: region(args["region"]), maxSize: maxSize))
        case "video_frame":
            let seconds = args["seconds"]?.doubleValue ?? 0
            return .success(.videoFrame(document: document, atMS: ms(seconds),
                                        region: region(args["region"]), maxSize: maxSize))
        case "contact_sheet":
            let from = args["fromSeconds"]?.doubleValue.map(ms)
            let to = args["toSeconds"]?.doubleValue.map(ms)
            if let from, let to, to < from {
                return .failure(AgentToolError("contact_sheet: toSeconds comes before fromSeconds."))
            }
            return .success(.contactSheet(document: document, fromMS: from, toMS: to,
                                          count: args["count"]?.intValue ?? defaultSheetCount,
                                          columns: args["columns"]?.intValue,
                                          cellWidth: args["cellWidth"]?.intValue ?? defaultCellWidth))
        case "undo":
            return .success(.undo(document: document, steps: args["steps"]?.intValue ?? 1))
        case "redo":
            return .success(.redo(document: document, steps: args["steps"]?.intValue ?? 1))
        case "list_commands":
            return .success(.listCommands(document: document,
                                          area: args["area"]?.stringValue.flatMap(AppCommand.Area.init(rawValue:)),
                                          readyOnly: args["readyOnly"]?.boolValue ?? false))
        case "run_command":
            return AppCommandTable.call(args["command"]?.stringValue ?? "", arguments: args["arguments"])
                .map { .runCommand(document: document, call: $0) }
        case "new_picture", "add_shape", "add_path", "add_drawing", "add_text", "set_layer", "find_elements",
             "add_measurement", "find_measurements", "mark_measurements", "find_misalignments", "mark_misalignments",
             "list_components", "place_component", "export":
            return drawingRequest(name, args, document: document)
        case _ where videoToolNames.contains(name):
            return videoRequest(name, args, document: document)
        case _ where designToolNames.contains(name):
            return designRequest(name, args, document: document)
        default:
            return .failure(AgentToolError("There is no tool called \(name).", isUnknownTool: true))
        }
    }

    private static func ms(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }

    private static func point(_ json: AgentJSON?) -> CGPoint? {
        guard let json, let x = json["x"]?.doubleValue, let y = json["y"]?.doubleValue else { return nil }
        return CGPoint(x: x, y: y)
    }

    private static func cg(_ json: AgentJSON?) -> CGFloat? { json?.doubleValue.map { CGFloat($0) } }

    private static func ink(_ json: AgentJSON?, _ tool: String, _ name: String) -> Result<AgentInk?, AgentToolError> {
        guard let word = json?.stringValue else { return .success(nil) }
        guard let ink = AgentInk(word) else {
            return .failure(AgentToolError("\(tool): \(name) is \(word); give a colour as #RRGGBB or #RRGGBBAA, or none."))
        }
        return .success(ink)
    }

    private static func look(_ args: [String: AgentJSON], _ tool: String) -> Result<AgentLook, AgentToolError> {
        Result {
            var look = AgentLook()
            look.fill = try ink(args["fill"], tool, "fill").get()
            look.stroke = try ink(args["stroke"], tool, "stroke").get()
            look.strokeWidth = cg(args["strokeWidth"])
            look.cornerRadius = cg(args["cornerRadius"])
            look.opacity = args["opacity"]?.doubleValue
            if args["removeShadow"]?.boolValue == true {
                look.shadow = AgentShadow.none
            } else if let shadow = args["shadow"] {
                let color = shadow["color"]?.stringValue ?? "#000000"
                guard case .hex(let hex)? = AgentInk(color) else {
                    throw AgentToolError("\(tool): shadow.color is \(color); give a colour as #RRGGBB.")
                }
                look.shadow = .drop(ShadowStyle(radius: cg(shadow["radius"]) ?? 12,
                                                offset: CGSize(width: cg(shadow["x"]) ?? 0, height: cg(shadow["y"]) ?? 4),
                                                colorHex: hex, opacity: shadow["opacity"]?.doubleValue ?? 0.3))
            }
            return look
        }.mapError { $0 as? AgentToolError ?? AgentToolError("\(tool): \($0.localizedDescription)") }
    }

    private static func drawingRequest(_ name: String, _ args: [String: AgentJSON],
                                       document: String?) -> Result<AgentRequest, AgentToolError> {
        func fail(_ words: String) -> Result<AgentRequest, AgentToolError> { .failure(AgentToolError("\(name): \(words)")) }
        switch name {
        case "new_picture":
            return .success(.newPicture(width: args["width"]?.intValue ?? 0, height: args["height"]?.intValue ?? 0))
        case "add_shape":
            guard let kind = args["shape"]?.stringValue.flatMap(AnnotationShape.init(rawValue:)) else { return fail("shape is required.") }
            return look(args, name).flatMap { look in
                var shape = AgentShape(kind: kind, look: look, name: args["name"]?.stringValue)
                switch kind {
                case .rectangle, .ellipse, .highlight:
                    guard let frame = region(args["frame"]) else { return fail("a \(kind.rawValue) needs a frame.") }
                    guard frame.width >= 1, frame.height >= 1 else { return fail("the frame needs a width and height of at least 1.") }
                    shape.frame = frame
                case .line, .arrow:
                    guard let from = point(args["from"]), let to = point(args["to"]) else {
                        return fail("a \(kind.rawValue) needs from and to.")
                    }
                    guard from != to else { return fail("from and to are the same point.") }
                    shape.from = from
                    shape.to = to
                }
                return .success(.addShape(document: document, shape: shape))
            }
        case "add_path":
            let points: [AgentPathPoint] = (args["points"]?.arrayValue ?? []).compactMap { json in
                guard let at = point(json) else { return nil }
                return AgentPathPoint(at, smooth: json["smooth"]?.boolValue ?? false,
                                      handleIn: point(json["handleIn"]), handleOut: point(json["handleOut"]),
                                      cornerRadius: cg(json["cornerRadius"]) ?? 0)
            }
            guard points.count >= 2 else { return fail("a path needs at least two points.") }
            let closed = args["closed"]?.boolValue ?? false
            if closed, points.count < 3 { return fail("a closed path needs at least three points.") }
            return look(args, name).map {
                .addPath(document: document, path: AgentPath(points: points, closed: closed, look: $0,
                                                             name: args["name"]?.stringValue))
            }
        case "add_drawing":
            let subject = (args["subject"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subject.isEmpty else { return fail("subject is empty: say what to draw, in a word or two.") }
            if let frame = region(args["frame"]), frame.width < 1 || frame.height < 1 {
                return fail("the frame needs a width and height of at least 1.")
            }
            let svg = args["svg"]?.stringValue.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            return .success(.addDrawing(document: document, drawing: AgentDrawingCall(
                subject: subject, svg: svg, icon: args["icon"]?.boolValue ?? false, frame: region(args["frame"]),
                name: args["name"]?.stringValue,
                style: args["style"]?.stringValue.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
                asked: args["asked"]?.stringValue, scene: args["scene"]?.boolValue ?? false,
                plan: AgentDrawingCall.statements(args["plan"]))))
        case "add_text":
            let words = args["text"]?.stringValue ?? ""
            guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail("text is empty.") }
            var color: String?
            if let said = args["color"]?.stringValue {
                guard case .hex(let hex)? = AgentInk(said) else { return fail("color is \(said); give a colour as #RRGGBB.") }
                color = hex
            }
            return .success(.addText(document: document, text: AgentText(
                string: words, origin: CGPoint(x: args["x"]?.doubleValue ?? 0, y: args["y"]?.doubleValue ?? 0),
                fontSize: cg(args["fontSize"]) ?? 24, fontName: args["fontName"]?.stringValue,
                weight: args["weight"]?.stringValue.flatMap(TextWeight.init(rawValue:)), colorHex: color,
                alignment: args["alignment"]?.stringValue.flatMap(TextAlign.init(rawValue:)),
                width: cg(args["width"]), name: args["name"]?.stringValue,
                shadow: args["shadow"]?.boolValue ?? true)))
        case "set_layer":
            let layer = args["layer"]?.stringValue ?? ""
            let flip: Set<FlipAxis>
            switch args["flip"]?.stringValue {
            case nil: flip = []
            case "both": flip = [.horizontal, .vertical]
            case let word?:
                guard let axis = FlipAxis(rawValue: word) else {
                    return fail("flip is horizontal, vertical or both.")
                }
                flip = [axis]
            }
            return look(args, name).flatMap { look in
                let change = AgentLayerChange(x: cg(args["x"]), y: cg(args["y"]), width: cg(args["width"]),
                                              height: cg(args["height"]), name: args["name"]?.stringValue,
                                              visible: args["visible"]?.boolValue, look: look,
                                              text: args["text"]?.stringValue, fontSize: cg(args["fontSize"]),
                                              flip: flip)
                guard change != AgentLayerChange() else { return fail("say what to change.") }
                return .success(.setLayer(document: document, layer: layer, change: change))
            }
        case "find_elements":
            return .success(.findElements(document: document, region: region(args["region"]),
                                          limit: args["limit"]?.intValue ?? AgentElementScan.defaultLimit))
        case "add_measurement":
            switch args["kind"]?.stringValue {
            case "size":
                if let box = region(args["box"]) { return .success(.addMeasurement(document: document, measurement: .size(box))) }
                if let at = point(args["at"]) {
                    return .success(.addMeasurement(document: document,
                                                    measurement: .sizeAt(at, level: args["level"]?.intValue ?? 0)))
                }
                return fail("size needs a box or a point to measure at.")
            case "gap":
                let boxes = (args["boxes"]?.arrayValue ?? []).compactMap { region($0) }
                if !boxes.isEmpty {
                    guard boxes.count == 2 else { return fail("gap takes exactly two boxes.") }
                    return .success(.addMeasurement(document: document, measurement: .gap(boxes[0], boxes[1])))
                }
                if let at = point(args["at"]) { return .success(.addMeasurement(document: document, measurement: .gapAt(at))) }
                return fail("gap needs two boxes or a point to measure at.")
            case "distance":
                guard let from = point(args["from"]), let to = point(args["to"]) else { return fail("distance needs from and to.") }
                let axis = args["axis"]?.stringValue.flatMap(MeasureMode.init(rawValue:))
                    ?? (abs(to.x - from.x) >= abs(to.y - from.y) ? .horizontal : .vertical)
                let length = axis == .horizontal ? abs(to.x - from.x) : abs(to.y - from.y)
                guard length > 0 else { return fail("from and to are at the same place along that axis.") }
                return .success(.addMeasurement(document: document, measurement: .distance(from: from, to: to, axis: axis)))
            default:
                return fail("kind is required.")
            }
        case "find_measurements":
            return .success(.findMeasurements(document: document, region: region(args["region"])))
        case "mark_measurements":
            let ids = (args["marks"]?.arrayValue ?? []).compactMap(\.stringValue)
            guard !ids.isEmpty else { return fail("marks needs at least one id from find_measurements.") }
            return .success(.markMeasurements(document: document, region: region(args["region"]), marks: ids))
        case "find_misalignments":
            return .success(.findMisalignments(document: document, region: region(args["region"])))
        case "mark_misalignments":
            let ids = (args["findings"]?.arrayValue ?? []).compactMap(\.stringValue)
            guard !ids.isEmpty else { return fail("findings needs at least one id from find_misalignments.") }
            return .success(.markMisalignments(document: document, region: region(args["region"]), findings: ids))
        case "list_components":
            return .success(.listComponents(document: document))
        case "place_component":
            return .success(.placeComponent(document: document, component: args["component"]?.stringValue ?? "",
                                            center: CGPoint(x: args["x"]?.doubleValue ?? 0, y: args["y"]?.doubleValue ?? 0)))
        case "export":
            guard let format = args["format"]?.stringValue.flatMap(AgentExportFormat.init(rawValue:)) else {
                return fail("format is required.")
            }
            let path = (args["path"]?.stringValue ?? "") as NSString
            guard path.expandingTildeInPath.hasPrefix("/") else { return fail("path must be absolute.") }
            guard path.pathExtension.lowercased() == format.rawValue else {
                return fail("a \(format.rawValue) file's path ends .\(format.rawValue).")
            }
            if format == .mp4 { return videoExportRequest(args, document: document, path: path.expandingTildeInPath) }
            if args["size"] != nil || args["quality"] != nil { return fail("size and quality are for an MP4.") }
            if format == .svg, args["scale"] != nil { return fail("scale only applies to a PNG.") }
            return .success(.export(document: document, format: format, path: path.expandingTildeInPath,
                                    scale: args["scale"]?.doubleValue ?? 1,
                                    background: args["background"]?.boolValue ?? true))
        default:
            return .failure(AgentToolError("There is no tool called \(name).", isUnknownTool: true))
        }
    }

    private static func region(_ json: AgentJSON?) -> CGRect? {
        guard let json, let x = json["x"]?.doubleValue, let y = json["y"]?.doubleValue,
              let width = json["width"]?.doubleValue, let height = json["height"]?.doubleValue else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// The small part of JSON Schema the tools use: types, required properties,
/// no extra properties, numeric bounds, and anyOf.
enum AgentSchema {
    static func problem(with value: AgentJSON, against schema: AgentJSON, at path: String) -> String? {
        let name = path.isEmpty ? "the arguments" : path
        // One of several shapes (a padding that is one number or four sides,
        // a size that is points or hug): it has to fit at least one.
        if let options = schema["anyOf"]?.arrayValue {
            guard options.allSatisfy({ problem(with: value, against: $0, at: path) != nil }) else { return nil }
            let said = options.map { option -> String in
                if let words = option["enum"]?.arrayValue?.compactMap(\.stringValue), !words.isEmpty {
                    return words.joined(separator: " or ")
                }
                let type = option["type"]?.stringValue ?? "value"
                return "\(article(type)) \(type)"
            }
            return "\(name) should be \(said.joined(separator: " or "))."
        }
        if let type = schema["type"]?.stringValue, !matches(value, type) {
            return "\(name) should be \(article(type)) \(type), not \(article(value.typeName)) \(value.typeName)."
        }
        if let minimum = schema["minimum"]?.doubleValue, let number = value.doubleValue, number < minimum {
            return "\(name) is \(format(number)); it can be no less than \(format(minimum))."
        }
        if let maximum = schema["maximum"]?.doubleValue, let number = value.doubleValue, number > maximum {
            return "\(name) is \(format(number)); it can be no more than \(format(maximum))."
        }
        if let choices = schema["enum"]?.arrayValue, !choices.contains(value) {
            let said = choices.map { $0.stringValue ?? $0.doubleValue.map(format) ?? "?" }.joined(separator: ", ")
            return "\(name) should be one of \(said)."
        }
        if let items = schema["items"], let array = value.arrayValue {
            for (index, item) in array.enumerated() {
                if let problem = problem(with: item, against: items, at: "\(name)[\(index)]") { return problem }
            }
        }
        guard let object = value.objectValue else { return nil }
        let properties = schema["properties"]?.objectValue ?? [:]
        for required in schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        where object[required] == nil {
            return "\(join(path, required)) is required."
        }
        if schema["additionalProperties"] == .bool(false) {
            let known = properties.keys.sorted().joined(separator: ", ")
            for key in object.keys.sorted() where properties[key] == nil {
                return known.isEmpty
                    ? "\(join(path, key)) is not an argument; this tool takes none."
                    : "\(join(path, key)) is not an argument; the arguments are \(known)."
            }
        }
        for key in object.keys.sorted() {
            guard let value = object[key], let property = properties[key] else { continue }
            if let problem = problem(with: value, against: property, at: join(path, key)) { return problem }
        }
        return nil
    }

    private static func matches(_ value: AgentJSON, _ type: String) -> Bool {
        switch type {
        case "integer": value.intValue != nil
        case "number": value.doubleValue != nil
        default: value.typeName == type || (type == "number" && value.typeName == "integer")
        }
    }

    private static func join(_ path: String, _ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    private static func article(_ word: String) -> String {
        ["a", "e", "i", "o", "u"].contains(word.prefix(1)) ? "an" : "a"
    }

    private static func format(_ number: Double) -> String {
        number.rounded() == number ? String(Int(number)) : String(number)
    }
}
