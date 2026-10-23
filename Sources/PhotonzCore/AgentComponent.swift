import CoreGraphics
import Foundation

// add_component (`docs/design/agent-mcp.md`, "Making a component"): an agent
// describes a component as a person would build one, and Photonz builds it in
// one go. The call gives the pieces of its first look (boxes, ovals, words and
// Pen paths, placed inside the component) and how each further look differs
// (a state: hover, pressed, disabled, on), and the result is ONE component in
// the Library holding each look as a named version, the way Layer > Add
// Version would leave it, with the question they answer called State.
//
// It is a tool, not content: which components a kit holds and how each looks
// come from the call, never from anything stored here. Before it, an agent had
// to draw each piece, group, name, make the component, add a version, find the
// new drawing's pieces and recolour them, one call each, which a model on this
// Mac planning blind could not do for a dozen kinds of component and so placed
// the Library's starters instead (the user, 2026-10-20).
//
// The pure half: the typed call and the document change. The app half measures
// words and lands it as one undo step (`AgentDesignWork.swift`).

/// One piece of a component's first look, placed from the component's top left.
public struct AgentComponentPart: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case shape(AnnotationShape)
        case text
        case path
    }

    public var name: String
    public var kind: Kind
    /// A box or oval's frame. Words use its origin, and its width when given
    /// to wrap at; a path is boxed round its points.
    public var frame: CGRect
    public var look: AgentLook
    public var text: String?
    public var fontSize: CGFloat?
    public var weight: TextWeight?
    public var colorHex: String?
    public var alignment: TextAlign?
    /// Words set centred in this part's box, across and down.
    public var centerIn: String?
    public var points: [AgentPathPoint]
    public var closed: Bool

    public init(name: String, kind: Kind, frame: CGRect = .zero, look: AgentLook = AgentLook(),
                text: String? = nil, fontSize: CGFloat? = nil, weight: TextWeight? = nil,
                colorHex: String? = nil, alignment: TextAlign? = nil, centerIn: String? = nil,
                points: [AgentPathPoint] = [], closed: Bool = false) {
        self.name = name
        self.kind = kind
        self.frame = frame
        self.look = look
        self.text = text
        self.fontSize = fontSize
        self.weight = weight
        self.colorHex = colorHex
        self.alignment = alignment
        self.centerIn = centerIn
        self.points = points
        self.closed = closed
    }
}

/// How one piece differs in a look, from the component's top left.
public struct AgentComponentChange: Hashable, Sendable {
    public var part: String
    public var change: AgentLayerChange

    public init(part: String, change: AgentLayerChange) {
        self.part = part
        self.change = change
    }
}

/// One look of a component: its name and how it differs from the first.
public struct AgentComponentLook: Hashable, Sendable {
    public var name: String
    public var changes: [AgentComponentChange]

    public init(name: String, changes: [AgentComponentChange] = []) {
        self.name = name
        self.changes = changes
    }
}

/// A component to make, with every look it has.
public struct AgentNewComponent: Hashable, Sendable {
    public static let defaultLookName = "Default"
    public static let defaultProperty = "State"
    /// Between one look and the next when the call gives no step.
    public static let lookGap: CGFloat = 24

    public var name: String
    /// Where its first look's top left goes, in canvas points.
    public var origin: CGPoint
    /// What the looks answer: State, unless the call says Size or Type.
    public var property: String
    public var parts: [AgentComponentPart]
    /// Never empty: a call naming none has one look called Default.
    public var looks: [AgentComponentLook]
    /// How far right each look sits from the one before; its width plus 24
    /// when nil.
    public var step: CGFloat?
    /// Its name set on the left of its row and each look's name under the
    /// look, the way a sheet of a kit's components reads.
    public var labels: Bool
    /// Room on the left of a labelled row for its name.
    public static let labelColumn: CGFloat = 160
    /// The size labels are set at, and the room under a look for its name.
    public static let labelSize: CGFloat = 13
    public static let captionGap: CGFloat = 8

    public init(name: String, origin: CGPoint, property: String = defaultProperty,
                parts: [AgentComponentPart], looks: [AgentComponentLook] = [], step: CGFloat? = nil,
                labels: Bool = false) {
        self.name = name
        self.origin = origin
        self.property = property
        self.parts = parts
        self.looks = looks.isEmpty ? [AgentComponentLook(name: Self.defaultLookName)] : looks
        self.step = step
        self.labels = labels
    }

    /// Why this cannot be built, or nil when it can.
    public var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "name is empty." }
        if parts.isEmpty { return "give at least one part." }
        var seen: Set<String> = []
        for part in parts {
            guard seen.insert(part.name).inserted else {
                return "two parts are called \(part.name); give each its own name."
            }
            switch part.kind {
            case .text:
                if (part.text ?? "").isEmpty { return "\(part.name) is text and needs its text." }
            case .shape:
                if part.frame.width <= 0 || part.frame.height <= 0 {
                    return "\(part.name) needs a width and a height."
                }
            case .path:
                if part.points.count < 2 { return "\(part.name) is a path and needs two or more points." }
            }
        }
        for part in parts {
            if let target = part.centerIn, !seen.contains(target) {
                return "\(part.name) is centred in \(target), and there is no part called that."
            }
        }
        for part in parts where part.kind == .text && part.centerIn == nil && part.frame.width > 0 {
            let size = part.fontSize ?? 15
            // Generous, so tight labels pass: a letter is about half the size wide.
            if CGFloat((part.text ?? "").count) * size * Self.letterWidth > part.frame.width * 1.15 {
                return "\(part.name)'s words are longer than its box, \(Int(part.frame.width)) wide, and would run past it. Make the box wider or the words shorter."
            }
        }
        if let (a, b) = wordsOverWords {
            return "\(a) and \(b) are words on top of words. Give each its own place (its own y, or its own x), so they sit apart."
        }
        var looked: Set<String> = []
        for look in looks {
            guard looked.insert(look.name).inserted else { return "two looks are called \(look.name)." }
            if look.name != looks.first?.name, look.changes.isEmpty {
                return "the \(look.name) look changes nothing. Give its changes (a fill, a colour, an opacity, a position, its words), or leave the look out."
            }
            for change in look.changes where !seen.contains(change.part) {
                return "the \(look.name) look changes \(change.part), and there is no part called that. The parts are \(parts.map(\.name).joined(separator: ", "))."
            }
        }
        return nil
    }
}

extension AgentNewComponent {
    /// Two parts of words that would land on one another in the first look,
    /// by name, or nil. Sized from their font before anything is measured
    /// (a line half as wide as its size per letter and one and a half sizes
    /// tall), so a planner can refuse the call before it is built: a card's
    /// title and body both centred in the card came out one on the other
    /// (the eval, 2026-10-23).
    static let letterWidth: CGFloat = 0.5

    var wordsOverWords: (String, String)? {
        func spot(_ part: AgentComponentPart) -> CGRect? {
            guard part.kind == .text, let words = part.text, !words.isEmpty else { return nil }
            let size = part.fontSize ?? 15
            let width = min(CGFloat(words.count) * size * Self.letterWidth,
                            part.frame.width > 0 ? part.frame.width : .greatestFiniteMagnitude)
            let height = size * 1.5
            if let target = part.centerIn, let box = parts.first(where: { $0.name == target })?.frame {
                return CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
            }
            let box = part.frame
            let x: CGFloat = switch (box.width > 0, part.alignment) {
            case (false, _), (true, .left?): box.minX
            case (true, .right?): box.maxX - width
            default: box.midX - width / 2
            }
            let y = box.height > 0 ? box.midY - height / 2 : box.minY
            return CGRect(x: x, y: y, width: width, height: height)
        }
        let spots = parts.compactMap { part in spot(part).map { (part.name, $0) } }
        for (index, (name, box)) in spots.enumerated() {
            for (other, otherBox) in spots[(index + 1)...] {
                let shared = box.intersection(otherBox)
                // A little touching at the edges is two lines set close, not one on the other.
                if !shared.isNull, shared.width > 2, shared.height > min(box.height, otherBox.height) / 3 {
                    return (name, other)
                }
            }
        }
        return nil
    }
}

/// What add_component made: the component and the drawing of each look.
public struct AgentMadeComponent: Hashable, Sendable {
    public struct Look: Hashable, Sendable {
        public var name: String
        public var layer: UUID
    }

    public var componentID: UUID
    public var looks: [Look]
    /// The words `labels` set for it: the row's name, then the name of any
    /// look whose state is not its column's.
    public var labels: [UUID] = []
    /// The table every labelled row is laid out as, nil without `labels`.
    public var sheet: AgentSheetLayout?
}

// MARK: - Building it

extension PhotonzDocument {

    /// Builds the component the call describes, every look a named version of
    /// it, in a row from the call's origin. `measure` is the box words need
    /// (the app's text measuring), at a width when they wrap.
    ///
    /// Nothing is left half built: a look whose change cannot land leaves the
    /// document as it was.
    public mutating func agentAddComponent(
        _ spec: AgentNewComponent,
        measure: (TextContent, CGFloat?) -> CGSize
    ) -> Result<AgentMadeComponent, AgentToolError> {
        func fail(_ words: String) -> Result<AgentMadeComponent, AgentToolError> {
            .failure(AgentToolError("add_component: \(words)"))
        }
        if let problem = spec.problem { return fail(problem) }
        var trial = self
        var children: [Layer] = []
        for part in spec.parts {
            children.append(Self.componentPiece(part, measure: measure))
        }
        Self.placeWords(&children, spec: spec, boxes: spec.parts.map(\.frame))
        let group = Layer(name: spec.name, content: .group(GroupContent(children: children)),
                          frame: CGRect(origin: spec.origin, size: .zero))
        trial.addLayer(group)
        guard let componentID = trial.makeComponent(id: group.id, name: spec.name) else {
            return fail("Photonz could not make \(spec.name) a component.")
        }
        let width = children.reduce(CGRect.null) { $0.union($1.localBounds) }.maxX
        // A labelled row steps far enough for its state names too.
        let captions = spec.labels ? spec.looks.map { look in
            measure(AgentText(string: look.name, origin: .zero, fontSize: AgentNewComponent.labelSize).content, nil).width
        }.max() ?? 0 : 0
        let step = spec.step ?? (max(width, captions) + AgentNewComponent.lookGap).rounded()

        var mains: [UUID] = [group.id]
        for look in spec.looks.dropFirst() {
            guard let version = trial.addComponentVersion(componentID: componentID, name: look.name),
                  let main = trial.mainComponent(componentID: componentID, version: version) else {
                return fail("Photonz could not add the \(look.name) look.")
            }
            mains.append(main.id)
        }
        if spec.looks.count > 1 {
            if let first = trial.componentVersions(of: componentID).first {
                trial.renameComponentVersion(componentID: componentID, version: first.id, to: spec.looks[0].name)
            }
            _ = trial.renameComponentVariantProperty(of: componentID, to: spec.property)
        }

        for (index, look) in spec.looks.enumerated() {
            let mainID = mains[index]
            guard var main = trial.layer(id: mainID), var content = main.group else {
                return fail("Photonz lost the \(look.name) look while building it.")
            }
            var pieces = content.children
            // Words move and size by their box, not their frame: the frame is
            // only as big as the words.
            var boxes = spec.parts.map(\.frame)
            for change in look.changes {
                guard let at = spec.parts.firstIndex(where: { $0.name == change.part }), at < pieces.count else { continue }
                var asked = change.change
                if spec.parts[at].kind == .text {
                    let box = boxes[at]
                    boxes[at] = CGRect(x: asked.x ?? box.minX, y: asked.y ?? box.minY,
                                       width: asked.width ?? box.width, height: asked.height ?? box.height)
                    asked.x = nil
                    asked.y = nil
                    asked.width = nil
                    asked.height = nil
                }
                switch AgentDrawing.applying(asked, to: pieces[at], canvas: nil) {
                case .failure(let error):
                    let why = error.message.replacingOccurrences(of: "set_layer: ", with: "")
                    return fail("the \(look.name) look cannot change \(change.part): \(why)")
                case .success(var changed):
                    changed.name = spec.parts[at].name
                    if asked.changesTheWords, let text = changed.text {
                        let size = measure(text, nil)
                        changed.frame.size = CGSize(width: max(size.width, 1), height: max(size.height, 1))
                    }
                    pieces[at] = changed
                }
            }
            Self.placeWords(&pieces, spec: spec, boxes: boxes)
            content.children = pieces
            main.content = .group(content)
            main.frame.origin = CGPoint(x: spec.origin.x + CGFloat(index) * step, y: spec.origin.y)
            trial.updateLayer(id: mainID) { $0 = main }
        }
        let labels = spec.labels ? trial.labelRow(spec, mains: mains, measure: measure) : []
        // Never on top of another drawing: a row that is taken moves down to
        // the next free one, keeping its x, so components asked for in the
        // same place stack into rows the way a sheet of them reads.
        let moving = mains + labels
        let row = moving.compactMap { trial.canvasBounds(of: $0) }.reduce(CGRect.null) { $0.union($1) }
        if !row.isNull {
            let landing = trial.freeRow(for: row, ignoring: Set(moving))
            if landing != row.minY {
                for id in moving { trial.updateLayer(id: id) { $0.frame.origin.y += landing - row.minY } }
            }
        }
        // A labelled row is a row of the sheet: the whole table is laid out
        // again with it (`AgentComponentSheet.swift`).
        let sheet = spec.labels ? trial.agentArrangeSheet(measure: measure) : nil
        self = trial
        return .success(AgentMadeComponent(
            componentID: componentID,
            looks: zip(spec.looks, mains).map { AgentMadeComponent.Look(name: $0.name, layer: $1) },
            labels: spec.labels ? trial.sheetLabels(of: componentID) : labels, sheet: sheet))
    }

    /// Makes room for and sets a labelled row's words: the looks move right
    /// past the name's column, the name sits level with the looks and each
    /// look's name is centred under it. Under, because the editor badges
    /// every component's state above it, and names above sat in those badges
    /// (the walk's window capture, 2026-10-23). Plain
    /// words in the Text tool's look, legibility shadow and all, since they
    /// may sit on any backdrop. Answers the words' ids, the name first.
    mutating func labelRow(_ spec: AgentNewComponent, mains: [UUID],
                           measure: (TextContent, CGFloat?) -> CGSize) -> [UUID] {
        func words(_ string: String, weight: TextWeight, color: String, name: String) -> Layer {
            let content = AgentText(string: string, origin: .zero, fontSize: AgentNewComponent.labelSize,
                                    weight: weight, colorHex: color).content
            var layer = TextBuilder.layer(content: content, at: .zero, naturalSize: measure(content, nil))
            layer.name = name
            return layer
        }
        for id in mains {
            updateLayer(id: id) { $0.frame.origin.x += AgentNewComponent.labelColumn }
        }
        let boxes = mains.compactMap { canvasBounds(of: $0) }
        guard boxes.count == mains.count, let first = boxes.first else { return [] }
        var made: [Layer] = []
        var title = words(spec.name, weight: .semibold, color: AgentDrawing.defaultStrokeHex, name: "\(spec.name) Label")
        title.frame.origin = CGPoint(x: spec.origin.x, y: (first.midY - title.frame.height / 2).rounded())
        made.append(title)
        for (look, box) in zip(spec.looks, boxes) {
            var caption = words(look.name, weight: .regular, color: "#6E6E73", name: "\(spec.name) \(look.name) Label")
            caption.frame.origin = CGPoint(x: (box.midX - caption.frame.width / 2).rounded(),
                                           y: (box.maxY + AgentNewComponent.captionGap).rounded())
            made.append(caption)
        }
        for layer in made { addLayer(layer) }
        return made.map(\.id)
    }

    /// The top of the first row at or below `box` where it covers no other
    /// top-level drawing and stays on the canvas, at the same x; its own top
    /// when there is no such row. A layer covering the whole canvas (a
    /// screenshot, a backdrop) is scenery and does not count.
    func freeRow(for box: CGRect, ignoring: Set<UUID>) -> CGFloat {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let taken = layers.filter { !ignoring.contains($0.id) }.compactMap { canvasBounds(of: $0.id) }
            .filter { !$0.isEmpty && !$0.contains(canvas) }
        let rows = ([box.minY] + taken.map { ($0.maxY + AgentNewComponent.lookGap).rounded() }.filter { $0 > box.minY })
            .sorted()
        for top in rows {
            let spot = CGRect(x: box.minX, y: top, width: box.width, height: box.height)
            if spot.maxY > canvas.maxY { break }
            // The gap is kept above and below, not only the overlap avoided.
            let room = spot.insetBy(dx: 0, dy: -(AgentNewComponent.lookGap - 1))
            if !taken.contains(where: { $0.intersects(room) }) { return top }
        }
        return box.minY
    }

    /// One part as the layer the matching tool would make, inside the component.
    static func componentPiece(_ part: AgentComponentPart, measure: (TextContent, CGFloat?) -> CGSize) -> Layer {
        var layer: Layer
        switch part.kind {
        case .shape(let shape):
            layer = AgentDrawing.layer(for: AgentShape(kind: shape, frame: part.frame, look: part.look, name: part.name))
        case .path:
            // A path's points are measured from its part's top left.
            let points = part.points.map { point -> AgentPathPoint in
                var moved = point
                moved.point = CGPoint(x: point.point.x + part.frame.minX, y: point.point.y + part.frame.minY)
                return moved
            }
            layer = AgentDrawing.layer(for: AgentPath(points: points, closed: part.closed, look: part.look, name: part.name))
        case .text:
            let words = AgentText(string: part.text ?? "", origin: part.frame.origin, fontSize: part.fontSize ?? 15,
                                  weight: part.weight, colorHex: part.colorHex ?? part.look.fill?.hexValue,
                                  alignment: part.alignment, name: part.name, shadow: false)
            let content = words.content
            layer = TextBuilder.layer(content: content, at: part.frame.origin, naturalSize: measure(content, nil))
            layer.style.shadows = []
            var look = part.look
            look.fill = nil
            AgentDrawing.apply(look, keepingPaint: true, to: &layer)
        }
        layer.name = part.name
        return layer
    }

    /// Sits words where their part said: centred in the part named by
    /// `centerIn`; else in their box (`boxes`, the look's own), centred down
    /// it and across it unless aligned left or right; else at their top left.
    static func placeWords(_ pieces: inout [Layer], spec: AgentNewComponent, boxes: [CGRect]) {
        for (index, part) in spec.parts.enumerated() where part.kind == .text && index < pieces.count {
            let size = pieces[index].frame.size
            if let target = part.centerIn,
               let at = spec.parts.firstIndex(where: { $0.name == target }), at < pieces.count {
                let box = AgentDrawing.box(of: pieces[at])
                pieces[index].frame.origin = CGPoint(x: (box.midX - size.width / 2).rounded(),
                                                     y: (box.midY - size.height / 2).rounded())
                continue
            }
            let box = boxes[index]
            let x: CGFloat = switch (box.width > 0, part.alignment) {
            case (false, _), (true, .left?): box.minX
            case (true, .right?): box.maxX - size.width
            default: box.midX - size.width / 2
            }
            let y = box.height > 0 ? box.midY - size.height / 2 : box.minY
            pieces[index].frame.origin = CGPoint(x: x.rounded(), y: y.rounded())
        }
    }
}

// MARK: - The tool

extension AgentTools {

    private static let componentPartWords = "Inside the component, from its top left."

    private static var componentLookProperties: [String: AgentJSON] {
        [
            "fill": ["type": "string", "description": "A box, oval or closed path's inside, #RRGGBB or #RRGGBBAA, or none."],
            "stroke": ["type": "string", "description": "Its edge or a path's line, #RRGGBB or #RRGGBBAA, or none."],
            "strokeWidth": ["type": "number", "minimum": 0, "maximum": 200, "description": "How thick the line is, in points."],
            "cornerRadius": ["type": "number", "minimum": 0, "maximum": 2000, "description": "How round a box's corners are."],
            "opacity": ["type": "number", "minimum": 0, "maximum": 1, "description": "0 is invisible, 1 is solid."],
            "shadow": ["type": "object", "description": "A drop shadow.",
                       "properties": [
                           "radius": ["type": "number", "minimum": 0, "maximum": 200, "description": "How soft. 12 when left out."],
                           "x": ["type": "number", "description": "0 when left out."],
                           "y": ["type": "number", "description": "4 when left out."],
                           "color": ["type": "string", "description": "#RRGGBB. Black when left out."],
                           "opacity": ["type": "number", "minimum": 0, "maximum": 1, "description": "0.3 when left out."],
                       ], "additionalProperties": false],
            "removeShadow": ["type": "boolean", "description": "Take every shadow off."],
            "color": ["type": "string", "description": "Words: their colour, #RRGGBB."],
        ]
    }

    static let componentTools: [AgentTool] = [
        AgentTool(
            name: "add_component",
            description: "Make a new Library component with every look it has: the parts of its first look (boxes, ovals, words, Pen paths) and, for each other look (a state such as Hover, Pressed, Disabled, On, Selected), only what changes. Each look is a named version of the one component, laid in a row from x and y. The answer's layer is the first look. One undo step.",
            inputSchema: schema([
                "document": ["type": "string", "description": "The document's id from list_documents, such as d1. Leave it out to use the document in front."],
                "name": ["type": "string", "description": "What the Library calls it: Button, Toggle, Text Field."],
                "x": ["type": "number", "description": "Left edge of its first look, in canvas points."],
                "y": ["type": "number", "description": "Top edge of its looks, in canvas points."],
                "step": ["type": "number", "minimum": 1, "description": "How far right each look sits from the one before, so looks of different components line up in columns. Its width plus 24 when left out."],
                "property": ["type": "string", "description": "What the looks are: State when left out, or Size, Type."],
                "labels": ["type": "boolean", "description": "true makes it a row of the sheet: every labelled component on the canvas is laid out as one table, its name on the left, each state named once over its column and each look centred in its cell, rows an even gap apart, starting where the first row was asked for. false sets no words and leaves it where x and y say."],
                "parts": ["type": "array", "minItems": 1,
                          "description": .string("Its first look, bottom first. \(componentPartWords)"),
                          "items": ["type": "object",
                                    "properties": .object(componentLookProperties.merging(([
                                        "name": ["type": "string", "description": "What the part is: Background, Label, Knob, Track, Icon."],
                                        "shape": ["type": "string", "enum": ["rectangle", "ellipse", "text", "path"],
                                                  "description": "rectangle (a box, round its corners with cornerRadius), ellipse, text (words), or path (a line or outline through points: a check mark, a chevron)."],
                                        "x": ["type": "number", "description": .string("Left edge. \(componentPartWords)")],
                                        "y": ["type": "number", "description": .string("Top edge. \(componentPartWords)")],
                                        "width": ["type": "number", "minimum": 0, "description": "A box or oval's width. Words: the width of the box they sit in, centred across it unless alignment says left or right."],
                                        "height": ["type": "number", "minimum": 0, "description": "A box or oval's height. Words: the height of the box they sit in, centred down it."],
                                        "text": ["type": "string", "description": "Words: what they say."],
                                        "fontSize": ["type": "number", "minimum": 4, "maximum": 1000, "description": "Words: points. 15 when left out."],
                                        "weight": ["type": "string", "enum": .array(TextWeight.allCases.map { .string($0.rawValue) }),
                                                   "description": "Words: regular, medium, semibold or bold."],
                                        "alignment": ["type": "string", "enum": ["left", "center", "right"], "description": "Words: where lines sit across their width."],
                                        "centerIn": ["type": "string", "description": "Words: the name of the part they sit centred in, across and down, such as Background."],
                                        "points": ["type": "array", "description": "A path: two or more points, measured from the part's x and y.",
                                                   "items": ["type": "object", "properties": [
                                                       "x": ["type": "number"], "y": ["type": "number"],
                                                       "smooth": ["type": "boolean", "description": "Curves through; a corner when left out."],
                                                   ], "required": ["x", "y"], "additionalProperties": false]],
                                        "closed": ["type": "boolean", "description": "A path: join the last point to the first."],
                                    ] as [String: AgentJSON])) { $1 }),
                                    "required": ["name", "shape", "x", "y", "width", "height"], "additionalProperties": false]],
                "firstLook": ["type": "string", "description": "The name of the look the parts draw as given: Default, Off, Rest."],
                "looks": ["type": "array", "minItems": 1,
                          "description": "Every other look (a state such as Hover, Pressed, Disabled, On, Selected), each with what differs from the parts as given.",
                          "items": ["type": "object", "properties": [
                              "name": ["type": "string", "description": "Hover, Pressed, Focused, Disabled, On, Selected, Error."],
                              "changes": ["type": "array", "minItems": 1, "description": "What differs in this look: a fill, a colour, an opacity, a part moved, hidden or reworded.",
                                          "items": ["type": "object",
                                                    "properties": .object(componentLookProperties.merging(([
                                                        "part": ["type": "string", "description": "The part's name."],
                                                        "x": ["type": "number", "description": .string("Move its left edge here. \(componentPartWords)")],
                                                        "y": ["type": "number", "description": "Move its top edge here."],
                                                        "width": ["type": "number", "minimum": 1, "description": "Resize to this width."],
                                                        "height": ["type": "number", "minimum": 1, "description": "Resize to this height."],
                                                        "visible": ["type": "boolean", "description": "false hides it in this look."],
                                                        "text": ["type": "string", "description": "Words: what they say in this look."],
                                                    ] as [String: AgentJSON])) { $1 }),
                                                    "required": ["part"], "additionalProperties": false]],
                          ], "required": ["name", "changes"], "additionalProperties": false]],
            ], required: ["name", "x", "y", "labels", "parts", "firstLook", "looks"])),
    ]

    static let componentToolNames: Set<String> = Set(componentTools.map(\.name))

    static func componentRequest(_ name: String, _ args: [String: AgentJSON],
                                 document: String?) -> Result<AgentRequest, AgentToolError> {
        func fail(_ words: String) -> Result<AgentRequest, AgentToolError> { .failure(AgentToolError("\(name): \(words)")) }
        func number(_ json: AgentJSON?, _ key: String) -> CGFloat? { json?[key]?.doubleValue.map { CGFloat($0) } }
        func look(_ json: AgentJSON, _ what: String) -> Result<AgentLook, AgentToolError> {
            var fields = json.objectValue ?? [:]
            // A shadow nobody could see is no shadow, not a layer effect to carry.
            if fields["shadow"]?["opacity"]?.doubleValue == 0 { fields["shadow"] = nil }
            // Words take their colour as color; a box takes it as fill.
            if fields["fill"] == nil, let color = fields["color"] { fields["fill"] = color }
            return Self.look(fields, name).mapError { AgentToolError($0.message.replacingOccurrences(of: "\(name):", with: "\(name): \(what)")) }
        }

        var parts: [AgentComponentPart] = []
        for item in args["parts"]?.arrayValue ?? [] {
            let partName = (item["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            guard !partName.isEmpty else { return fail("every part needs a name.") }
            let kind: AgentComponentPart.Kind
            switch item["shape"]?.stringValue ?? "" {
            case "text": kind = .text
            case "path": kind = .path
            case "ellipse": kind = .shape(.ellipse)
            default: kind = .shape(.rectangle)
            }
            if case .shape = kind, item["width"] == nil || item["height"] == nil {
                return fail("\(partName) needs a width and a height.")
            }
            let partLook: AgentLook
            switch look(item, "\(partName)'s ") {
            case .success(var found):
                if kind == .text { found.fill = nil }
                partLook = found
            case .failure(let error): return .failure(error)
            }
            var colorHex: String?
            if kind == .text, let word = (item["color"] ?? item["fill"])?.stringValue {
                guard case .hex(let hex)? = AgentInk(word) else {
                    return fail("\(partName)'s color is \(word); give #RRGGBB.")
                }
                colorHex = hex
            }
            let points = (item["points"]?.arrayValue ?? []).compactMap { point -> AgentPathPoint? in
                guard let x = point["x"]?.doubleValue, let y = point["y"]?.doubleValue else { return nil }
                return AgentPathPoint(CGPoint(x: x, y: y), smooth: point["smooth"]?.boolValue ?? false)
            }
            parts.append(AgentComponentPart(
                name: partName, kind: kind,
                frame: CGRect(x: number(item, "x") ?? 0, y: number(item, "y") ?? 0,
                              width: number(item, "width") ?? 0, height: number(item, "height") ?? 0),
                look: partLook, text: item["text"]?.stringValue, fontSize: number(item, "fontSize"),
                weight: item["weight"]?.stringValue.flatMap(TextWeight.init(rawValue:)),
                colorHex: colorHex, alignment: item["alignment"]?.stringValue.flatMap(TextAlign.init(rawValue:)),
                centerIn: item["centerIn"]?.stringValue, points: points, closed: item["closed"]?.boolValue ?? false))
        }

        let firstLook = (args["firstLook"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        var looks = [AgentComponentLook(name: firstLook.isEmpty ? AgentNewComponent.defaultLookName : firstLook)]
        for item in args["looks"]?.arrayValue ?? [] {
            let lookName = (item["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            guard !lookName.isEmpty else { return fail("every look needs a name.") }
            var changes: [AgentComponentChange] = []
            for entry in item["changes"]?.arrayValue ?? [] {
                let part = entry["part"]?.stringValue ?? ""
                var change = AgentLayerChange(x: number(entry, "x"), y: number(entry, "y"),
                                              width: number(entry, "width"), height: number(entry, "height"),
                                              visible: entry["visible"]?.boolValue, text: entry["text"]?.stringValue)
                switch look(entry, "the \(lookName) look's \(part): ") {
                case .success(let found): change.look = found
                case .failure(let error): return .failure(error)
                }
                changes.append(AgentComponentChange(part: part, change: change))
            }
            looks.append(AgentComponentLook(name: lookName, changes: changes))
        }

        let spec = AgentNewComponent(
            name: (args["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces),
            origin: CGPoint(x: number(.object(args), "x") ?? 0, y: number(.object(args), "y") ?? 0),
            property: ComponentNaming.normalized(args["property"]?.stringValue) ?? AgentNewComponent.defaultProperty,
            parts: parts, looks: looks, step: number(.object(args), "step"),
            labels: args["labels"]?.boolValue ?? false)
        if let problem = spec.problem { return fail(problem) }
        return .success(.addComponent(document: document, component: spec))
    }
}
