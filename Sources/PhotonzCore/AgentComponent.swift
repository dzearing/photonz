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
    /// Hidden in the first look, for a later look to show: a check mark only
    /// On shows.
    public var hidden: Bool

    public init(name: String, kind: Kind, frame: CGRect = .zero, look: AgentLook = AgentLook(),
                text: String? = nil, fontSize: CGFloat? = nil, weight: TextWeight? = nil,
                colorHex: String? = nil, alignment: TextAlign? = nil, centerIn: String? = nil,
                points: [AgentPathPoint] = [], closed: Bool = false, hidden: Bool = false) {
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
        self.hidden = hidden
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
        if let (words, box) = wordsHalfOn {
            return "\(words)'s words run over the edge of \(box). Set them wholly inside \(box) (a wider \(box), shorter words or a smaller size) or wholly off it."
        }
        if let (words, behind) = unreadableWords {
            let backdrop = behind.map { "on \($0)" } ?? "on the canvas"
            return "\(words)'s colour is too close to what is behind it (\(backdrop)) to read. Set its words in a colour that stands out from it: dark on a light ground, light on a dark one."
        }
        if let part = unseenSurface {
            return "\(part) is the canvas's own white with no edge or shadow, so nobody could see it. Give it a fill a step darker than the canvas, a 1 point edge, or a soft shadow."
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
        for look in looks.dropFirst() {
            let shown = inLook(look)
            if let (a, b) = shown.wordsOverWords {
                return "in the \(look.name) look, \(a) and \(b) are words on top of words. Move them so each keeps its own place in every look."
            }
            if let (words, box) = shown.wordsHalfOn {
                return "in the \(look.name) look, \(words)'s words run over the edge of \(box). Keep them wholly inside \(box) or wholly off it in every look."
            }
            if let (words, behind) = shown.unreadableWords {
                return "in the \(look.name) look, \(words)'s colour is too close to what is behind it (\(behind.map { "on \($0)" } ?? "on the canvas")) to read. Give \(words) a colour in that look that stands out from it."
            }
        }
        for look in looks.dropFirst() {
            if let small = tooSmallToSee(look) {
                return "the \(look.name) look is hard to tell from \(looks[0].name): \(small) is a shade too small to see. Make the difference plain (a fill clearly darker or lighter, an edge, a part shown or hidden), or leave the look out."
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
        let spots = parts.compactMap { part in wordsSpot(part).map { (part.name, $0) } }
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

    /// Words that sit half on a box of the first look, the words' name then
    /// the box's: a segmented control's second label running out past its
    /// track, a tab's icon on top of its name, a card's line past the card
    /// (the eval, 2026-10-23). Words belong wholly inside a box or wholly
    /// off it. The words are sized from their font as `wordsOverWords` sizes
    /// them, trimmed a little so words set close to an edge are not caught.
    var wordsHalfOn: (String, String)? {
        for part in parts {
            guard let spot = wordsSpot(part) else { continue }
            let size = part.fontSize ?? 15
            let words = spot.insetBy(dx: spot.width * 0.06, dy: size * 0.25)
            for box in parts {
                // A box with nothing said is drawn filled; one painted none with no edge is not drawn.
                let drawn = box.look.fill?.hexValue != nil || box.look.stroke?.hexValue != nil
                    || (box.look.fill == nil && box.look.stroke == nil)
                guard case .shape = box.kind, drawn, !box.hidden else { continue }
                let shared = words.intersection(box.frame)
                if shared.isNull || shared.width <= 1 || shared.height <= 1 { continue }
                if !box.frame.insetBy(dx: -1, dy: -1).contains(words) { return (part.name, box.name) }
            }
        }
        return nil
    }

    /// The component as a later look draws it: each part moved, sized,
    /// reworded, repainted, shown or hidden as the look's changes say, so
    /// what is checked on the first look can be checked on every look.
    func inLook(_ look: AgentComponentLook) -> AgentNewComponent {
        var shown = self
        for change in look.changes {
            guard let at = shown.parts.firstIndex(where: { $0.name == change.part }) else { continue }
            let asked = change.change
            var part = shown.parts[at]
            part.frame = CGRect(x: asked.x ?? part.frame.minX, y: asked.y ?? part.frame.minY,
                                width: asked.width ?? part.frame.width, height: asked.height ?? part.frame.height)
            if let words = asked.text { part.text = words }
            if let size = asked.fontSize { part.fontSize = size }
            if let visible = asked.visible { part.hidden = !visible }
            if let fill = asked.look.fill {
                if part.kind == .text { part.colorHex = fill.hexValue } else { part.look.fill = fill }
            }
            if let stroke = asked.look.stroke { part.look.stroke = stroke }
            shown.parts[at] = part
        }
        shown.looks = [look]
        return shown
    }

    /// Where a part's words will sit in the first look, sized from their
    /// font, or nil for a part that is not words.
    func wordsSpot(_ part: AgentComponentPart) -> CGRect? {
        guard part.kind == .text, !part.hidden, let words = part.text, !words.isEmpty else { return nil }
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
}

// MARK: - Looks a person can see

extension AgentNewComponent {
    /// Two looks' colours read as one below this contrast ratio between
    /// them, unless a channel moves by `leastHueStep`: a badge's Hover drawn
    /// #FF453A over its #FF3B30 (1.04) was a look nobody could tell from
    /// Default (the eval, 2026-10-23). A hover a step darker (#2563EB to
    /// #1D4ED8, 1.38; #007AFF to #0062CC, 1.42) is plain, and was refused
    /// while this was measured on the largest channel alone.
    static let leastLookContrast = 1.2
    /// A colour that moves this far on one channel, out of 255, is a new
    /// colour however alike the two are in lightness (grey to green).
    static let leastHueStep = 48.0
    /// Two colours closer than this, on their largest channel, are one
    /// colour: what `drawnLike` counts as the same paint.
    static let sameColourStep = 20.0
    /// A surface closer than this to the canvas is the canvas: #F2F2F7 on
    /// white (13 apart) is a grey a person sees, #FAFAFA (5) is not.
    static let surfaceStep = 10.0
    /// An opacity changed by less than this reads as no change.
    static let leastOpacityStep = 0.15
    /// What a new picture's canvas is, and so what a surface must stand out
    /// from. Sheets are made on a new picture, which is white; a component
    /// on a dark backdrop it drew itself is not checked against that.
    static let canvasColour = "#FFFFFF"

    /// Whether a person tells the two colours apart, or nil when either is
    /// not a colour.
    static func plainlyApart(_ a: String?, _ b: String?) -> Bool? {
        guard let a, let b, let one = RGBA(hex: a), let two = RGBA(hex: b), let step = apart(a, b) else { return nil }
        return step >= leastHueStep || RGBA.contrast(one.linearLuminance, two.linearLuminance) >= leastLookContrast
    }

    /// How far apart two colours are, on their largest channel out of 255,
    /// or nil when either is not a colour.
    static func apart(_ a: String?, _ b: String?) -> Double? {
        guard let a, let b, let one = RGBA(hex: a), let two = RGBA(hex: b) else { return nil }
        return max(abs(one.r - two.r), abs(one.g - two.g), abs(one.b - two.b), abs(one.a - two.a)) * 255
    }

    /// A look's change put in words when every change in it is too small to
    /// see ("Background #FF3B30 to #FF453A"), or nil when any change shows.
    /// Changes it cannot weigh (a radius, a shadow) count as showing.
    func tooSmallToSee(_ look: AgentComponentLook) -> String? {
        var small: [String] = []
        for change in look.changes {
            guard let part = parts.first(where: { $0.name == change.part }) else { return nil }
            let asked = change.change
            if let visible = asked.visible, visible == part.hidden { return nil }
            if asked.fontSize != nil || !asked.flip.isEmpty { return nil }
            if let words = asked.text, words != part.text { return nil }
            let moved = [(asked.x, part.frame.minX), (asked.y, part.frame.minY),
                         (asked.width, part.frame.width), (asked.height, part.frame.height)]
            if moved.contains(where: { asked, was in asked.map { abs($0 - was) >= 1 } ?? false }) { return nil }
            let new = asked.look
            if new.cornerRadius != nil || new.shadow != nil { return nil }
            if let width = new.strokeWidth, abs(width - (part.look.strokeWidth ?? 0)) >= 1 { return nil }
            if let opacity = new.opacity {
                let was = part.look.opacity ?? 1
                if abs(opacity - was) >= Self.leastOpacityStep { return nil }
                small.append("\(part.name)'s opacity \(Self.number(was)) to \(Self.number(opacity))")
            }
            let fillWas = part.kind == .text ? part.colorHex : part.look.fill?.hexValue
            for (ink, was) in [(new.fill, fillWas), (new.stroke, part.look.stroke?.hexValue)] {
                guard let ink else { continue }
                guard let plain = Self.plainlyApart(ink.hexValue, was) else {
                    if ink.hexValue != was { return nil }
                    continue
                }
                if plain { return nil }
                small.append("\(part.name) \(was ?? "") to \(ink.hexValue ?? "")")
            }
        }
        return small.isEmpty ? nil : small.joined(separator: " and ")
    }

    /// How far a widened shade is first set from the first look's, out of
    /// 255; it goes further, a step at a time, until the two are plain.
    static let plainColourStep = 32.0
    /// The hairline a surface the canvas's colour is given: that colour,
    /// this much darker.
    static let hairlineShade = 0.12

    /// add_component's arguments with what nobody could see made plain: a
    /// look whose every change is a shade too small has its shades widened
    /// (the same way, further), and a surface the canvas's colour with no
    /// edge gets a hairline. For Ask's planner: a small model told why a
    /// call was refused sent it back unchanged for every round left (the
    /// eval, 2026-10-23), while an agent that can read the refusal is still
    /// given it (`problem`). Anything else is left as the model gave it.
    public static func madePlain(_ arguments: AgentJSON) -> AgentJSON {
        guard var args = arguments.objectValue else { return arguments }
        func spec() -> AgentNewComponent? {
            if case .success(let found) = AgentTools.componentSpec("add_component", args) { return found }
            return nil
        }
        func named(_ json: AgentJSON) -> String {
            (json["name"]?.stringValue ?? json["part"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        }
        var edged: Set<String> = []
        while let found = spec(), let surface = found.unseenSurface, edged.insert(surface).inserted,
              var parts = args["parts"]?.arrayValue,
              let at = parts.firstIndex(where: { named($0) == surface }), var part = parts[at].objectValue {
            let canvas = RGBA(hex: canvasColour) ?? RGBA(r: 1, g: 1, b: 1)
            part["stroke"] = .string(RGBA(r: canvas.r * (1 - hairlineShade), g: canvas.g * (1 - hairlineShade),
                                          b: canvas.b * (1 - hairlineShade)).hexString)
            part["strokeWidth"] = .number(1)
            parts[at] = .object(part)
            args["parts"] = .array(parts)
        }
        var recoloured: Set<String> = []
        while let found = spec(), let (words, _) = found.unreadableWords, recoloured.insert(words).inserted,
              let part = found.parts.first(where: { $0.name == words }),
              case .some(.some(let behind)) = found.wordsBackdrop(part), let ground = RGBA(hex: behind.colour),
              var parts = args["parts"]?.arrayValue,
              let at = parts.firstIndex(where: { named($0) == words }), var said = parts[at].objectValue {
            said["color"] = .string(readable(near: part.colorHex ?? defaultWordColour, on: ground))
            said["fill"] = nil
            parts[at] = .object(said)
            args["parts"] = .array(parts)
        }
        guard let found = spec(), var looks = args["looks"]?.arrayValue else { return .object(args) }
        // Words a later look leaves unreadable get, in that look, the shade
        // nearest their own that reads.
        for (index, look) in found.looks.enumerated().dropFirst() where index - 1 < looks.count {
            var shown = found.inLook(look)
            var fixed: Set<String> = []
            while let (words, _) = shown.unreadableWords, fixed.insert(words).inserted,
                  let part = shown.parts.first(where: { $0.name == words }),
                  case .some(.some(let behind)) = shown.wordsBackdrop(part), let ground = RGBA(hex: behind.colour),
                  var said = looks[index - 1].objectValue {
                let colour = readable(near: part.colorHex ?? defaultWordColour, on: ground)
                var changes = said["changes"]?.arrayValue ?? []
                if let at = changes.firstIndex(where: { named($0) == words }), var change = changes[at].objectValue {
                    change["color"] = .string(colour)
                    change["fill"] = nil
                    changes[at] = .object(change)
                } else {
                    changes.append(["part": .string(words), "color": .string(colour)])
                }
                said["changes"] = .array(changes)
                looks[index - 1] = .object(said)
                if let at = shown.parts.firstIndex(where: { $0.name == words }) { shown.parts[at].colorHex = colour }
            }
        }
        for (index, look) in found.looks.enumerated().dropFirst() where index - 1 < looks.count {
            guard found.tooSmallToSee(look) != nil, var said = looks[index - 1].objectValue,
                  var changes = said["changes"]?.arrayValue else { continue }
            for (at, entry) in changes.enumerated() {
                guard var change = entry.objectValue,
                      let part = found.parts.first(where: { $0.name == named(entry) }) else { continue }
                let fillWas = part.kind == .text ? part.colorHex : part.look.fill?.hexValue
                for (key, was) in [("fill", fillWas), ("color", fillWas), ("stroke", part.look.stroke?.hexValue)] {
                    guard let was, let new = change[key]?.stringValue, plainlyApart(new, was) == false else { continue }
                    change[key] = .string(widened(new, from: was))
                }
                if let opacity = change["opacity"]?.doubleValue {
                    let was = part.look.opacity ?? 1
                    if abs(opacity - was) < leastOpacityStep { change["opacity"] = .number(max(0.3, was - 0.4)) }
                }
                changes[at] = .object(change)
            }
            said["changes"] = .array(changes)
            looks[index - 1] = .object(said)
        }
        args["looks"] = .array(looks)
        return .object(args)
    }

    /// Shades words are set in when theirs cannot be read: near black, the
    /// system's secondary grey and white.
    static let readableShades = ["#1C1C1E", "#8E8E93", "#FFFFFF"]
    /// How far a shade picked for words stands out from what is behind them.
    static let pickedWordContrast = 3.0

    /// The shade nearest `asked` that reads on `ground`: grey for words
    /// that were white on white, black when grey would not read either.
    static func readable(near asked: String, on ground: RGBA) -> String {
        let wanted = RGBA(hex: asked) ?? RGBA(r: 0, g: 0, b: 0)
        func distance(_ hex: String) -> Double {
            guard let shade = RGBA(hex: hex) else { return .infinity }
            return abs(shade.r - wanted.r) + abs(shade.g - wanted.g) + abs(shade.b - wanted.b)
        }
        func contrast(_ hex: String) -> Double {
            RGBA(hex: hex).map { RGBA.contrast($0.linearLuminance, ground.linearLuminance) } ?? 0
        }
        let reads = readableShades.filter { contrast($0) >= pickedWordContrast }
        return reads.min { distance($0) < distance($1) }
            ?? readableShades.max { contrast($0) < contrast($1) } ?? "#000000"
    }

    /// `new` moved on from `was` the way it already leans, until the two are
    /// plain to the eye; a step darker when it does not lean, and the
    /// other way when that way runs out of room.
    static func widened(_ new: String, from was: String) -> String {
        guard let base = RGBA(hex: was), let asked = RGBA(hex: new) else { return new }
        var lean = [asked.r - base.r, asked.g - base.g, asked.b - base.b]
        if lean.map(abs).max() ?? 0 < 0.5 / 255 { lean = [-1, -1, -1] }
        let biggest = lean.map(abs).max() ?? 1
        func going(_ sign: Double, _ step: Double) -> String {
            let scale = step / 255 / biggest
            return RGBA(r: min(max(base.r + sign * lean[0] * scale, 0), 1), g: min(max(base.g + sign * lean[1] * scale, 0), 1),
                        b: min(max(base.b + sign * lean[2] * scale, 0), 1)).hexString
        }
        for step in stride(from: plainColourStep, through: 160, by: 16) {
            for sign in [1.0, -1.0] where plainlyApart(going(sign, step), was) == true { return going(sign, step) }
        }
        return going(1, 160)
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    /// Below this contrast ratio words cannot be read against what is
    /// behind them: white on a white canvas is 1, grey #8E8E93 on white is
    /// about 3.3 and reads.
    static let leastWordContrast = 1.6
    /// Words given no colour are set near black.
    static let defaultWordColour = "#000000"

    /// What a part's words sit on in the first look, and its colour: the
    /// topmost painted box drawn before them that holds their middle (a box
    /// painted none is looked through), else the canvas (name nil). Nil when
    /// the box is drawn in the default colour, which is not known here.
    func wordsBackdrop(_ part: AgentComponentPart) -> (name: String?, colour: String)?? {
        guard let spot = wordsSpot(part), let index = parts.firstIndex(where: { $0.name == part.name }) else { return nil }
        let middle = CGPoint(x: spot.midX, y: spot.midY)
        for box in parts[..<index].reversed() {
            guard case .shape = box.kind, !box.hidden, box.frame.contains(middle) else { continue }
            if box.look.fill == nil && box.look.stroke == nil { return .some(nil) }
            guard let fill = box.look.fill?.hexValue, (RGBA(hex: fill)?.a ?? 1) >= 0.5 else { continue }
            return (box.name, fill)
        }
        return (nil, Self.canvasColour)
    }

    /// Words of the first look nobody could read against what is behind
    /// them, by name, and the box behind them (nil for the canvas): a
    /// checkbox's label set white beside it on a white canvas (the eval,
    /// 2026-10-23). Words are always legible (the user, 2026-09-30).
    var unreadableWords: (String, String?)? {
        for part in parts where part.kind == .text {
            guard case .some(.some(let behind)) = wordsBackdrop(part),
                  let ink = RGBA(hex: part.colorHex ?? Self.defaultWordColour),
                  let ground = RGBA(hex: behind.colour) else { continue }
            if RGBA.contrast(ink.linearLuminance, ground.linearLuminance) < Self.leastWordContrast {
                return (part.name, behind.name)
            }
        }
        return nil
    }

    /// The first box of the first look painted the canvas's own colour with
    /// no edge and no shadow, sitting on nothing else of the component, by
    /// name: a card or a dialog drawn white on a white canvas showed its words
    /// floating with no card at all (the eval, 2026-10-23). White on top of
    /// another part (a toggle's knob on its track) is seen against that part.
    var unseenSurface: String? {
        for (index, part) in parts.enumerated() {
            guard case .shape = part.kind, !part.hidden, let fill = part.look.fill?.hexValue,
                  let distance = Self.apart(fill, Self.canvasColour), distance < Self.surfaceStep else { continue }
            let edged = part.look.stroke?.hexValue != nil && (part.look.strokeWidth ?? 1) > 0
            if edged { continue }
            if case .drop? = part.look.shadow { continue }
            let onAnother = parts[..<index].contains { under in
                guard case .shape = under.kind else { return false }
                return under.frame.intersects(part.frame)
            }
            if !onAnother { return part.name }
        }
        return nil
    }

    /// Whether this is drawn as the other is, whatever it is called: the
    /// same pieces in the same order, the same sizes give or take a few
    /// points and the same paint. A sheet showing a Toggle and a Switch drawn
    /// alike read as one control twice (the eval, 2026-10-23).
    public func drawnLike(_ other: AgentNewComponent) -> Bool {
        guard parts.count == other.parts.count, !parts.isEmpty else { return false }
        func same(_ a: String?, _ b: String?) -> Bool {
            a == b || (Self.apart(a, b).map { $0 < Self.sameColourStep } ?? false)
        }
        return zip(parts, other.parts).allSatisfy { one, two in
            one.kind == two.kind
                && abs(one.frame.width - two.frame.width) <= 3 && abs(one.frame.height - two.frame.height) <= 3
                && same(one.look.fill?.hexValue, two.look.fill?.hexValue)
                && same(one.look.stroke?.hexValue, two.look.stroke?.hexValue)
                && same(one.colorHex, two.colorHex)
                && one.points.count == two.points.count
        }
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
        if part.hidden { layer.isVisible = false }
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
                                        "visible": ["type": "boolean", "description": "false hides it in the first look, for a later look to show with visible true: a check mark only On shows."],
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
                                                        "visible": ["type": "boolean", "description": "false hides it in this look; true shows a part the first look hides."],
                                                        "text": ["type": "string", "description": "Words: what they say in this look."],
                                                    ] as [String: AgentJSON])) { $1 }),
                                                    "required": ["part"], "additionalProperties": false]],
                          ], "required": ["name", "changes"], "additionalProperties": false]],
            ], required: ["name", "x", "y", "labels", "parts", "firstLook", "looks"])),
    ]

    static let componentToolNames: Set<String> = Set(componentTools.map(\.name))

    static func componentRequest(_ name: String, _ args: [String: AgentJSON],
                                 document: String?) -> Result<AgentRequest, AgentToolError> {
        componentSpec(name, args).flatMap { spec in
            if let problem = spec.problem { return .failure(AgentToolError("\(name): \(problem)")) }
            return .success(.addComponent(document: document, component: spec))
        }
    }

    /// The component a call describes, read but not yet checked.
    static func componentSpec(_ name: String, _ args: [String: AgentJSON]) -> Result<AgentNewComponent, AgentToolError> {
        func fail(_ words: String) -> Result<AgentNewComponent, AgentToolError> { .failure(AgentToolError("\(name): \(words)")) }
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
                centerIn: item["centerIn"]?.stringValue, points: points, closed: item["closed"]?.boolValue ?? false,
                hidden: item["visible"]?.boolValue == false))
        }
        // A part a later look shows with visible true, and the call never
        // said, starts hidden: that look is the one that shows it.
        let shown = Set((args["looks"]?.arrayValue ?? []).flatMap { look in
            (look["changes"]?.arrayValue ?? []).compactMap { change in
                change["visible"]?.boolValue == true ? change["part"]?.stringValue : nil
            }
        })
        for (index, item) in (args["parts"]?.arrayValue ?? []).enumerated()
        where index < parts.count && item["visible"] == nil && shown.contains(parts[index].name) {
            parts[index].hidden = true
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
        return .success(spec)
    }
}
