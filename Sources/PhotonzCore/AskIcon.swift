import CoreGraphics
import Foundation

// An icon request (`docs/design/ask.md`, "An icon"): chosen from the general
// words for an icon, never from a subject. The model draws it itself as a few
// clean shapes on an icon grid, the way it knows SF Symbols, Material Symbols
// and Lucide are drawn, and it lands as real shape and path layers: an icon is
// never painted by the picture model and traced, which is how "a balloon icon"
// became a stick figure holding balloons (the user, 2026-11-04).

public enum AskIcon {

    /// The looks a person names for an icon.
    public enum Look: String, Hashable, Sendable {
        case outline, filled, duotone
    }

    static let iconWords: Set<String> = ["icon", "icons", "glyph", "glyphs", "favicon", "favicons", "pictogram", "pictograms"]
    static let outlineWords: Set<String> = ["outline", "outlined", "outlines", "stroked", "linear"]
    static let filledWords: Set<String> = ["filled", "fill", "solid"]
    static let duotoneWords: Set<String> = ["duotone", "duotones", "twotone"]

    /// Whether `request` asks for an icon.
    public static func asked(in request: String) -> Bool {
        !iconWords.isDisjoint(with: AgentDrawingWords.words(request))
    }

    /// Whether it is the big square tile an app is known by.
    public static func isAppIcon(_ request: String) -> Bool {
        let typed = " " + AgentDrawingWords.words(request).joined(separator: " ") + " "
        return [" app icon ", " app icons ", " application icon ", " dock icon "].contains { typed.contains($0) }
    }

    /// The side the icon is drawn at.
    public static func side(for request: String) -> CGFloat {
        isAppIcon(request) ? AgentDrawingPlacement.appIconSide : AgentDrawingPlacement.iconSide
    }

    /// The look the person's words name, or nil when they name none.
    public static func look(in request: String) -> Look? {
        let typed = AgentDrawingWords.words(request)
        let words = Set(typed)
        if !words.isDisjoint(with: duotoneWords) || " \(typed.joined(separator: " ")) ".contains(" two tone ") { return .duotone }
        if !words.isDisjoint(with: outlineWords) { return .outline }
        if !words.isDisjoint(with: filledWords) { return .filled }
        return nil
    }

    // MARK: Designed in words first

    /// The most a design may write: it is under a hundred words.
    public static let mostDesignTokens = 400

    /// What the model is asked before it draws. A small model writing an SVG
    /// straight off keeps the object whole and adds rays (a balloon popping
    /// came out as a sun, through three changes to the rules, 2026-11-04);
    /// thinking first tore the balloon open but took eight minutes. Saying
    /// the design in a few lines gets most of that in ten seconds. An object
    /// simply at rest skips it: rough coordinates replace the form the model
    /// knows, and a rocket fell from 92 to 72 as stacked triangles (the eval,
    /// 2026-11-05). It holds for any subject: nothing here knows what the icon
    /// is of.
    static let designAsk = """
        If the request names only an object, or an idea an object stands for, with nothing happening to the object, \
        reply only: at rest. Otherwise, before drawing, design this icon in words, under 100 words, no SVG yet. Say: \
        1) the one object, and every \
        part that makes it recognisable at rest, all of which stay in the icon; 2) if something is happening to it, \
        what that does to the object: which part of its outline is missing, open, torn, tilted or moved, and where \
        on the 24 grid; 3) each part as a shape with rough coordinates on the 24 grid, the whole icon about 20 \
        across and inside 2 to 22. Any marks showing the action start 2 clear of the object and point away from it, \
        at least 3 apart everywhere, so they never meet at a point.
        """

    /// What follows the design in the talk. A request that changes an icon
    /// already there has no use for one, so it is not told to draw.
    public static let drawTheDesign = """
        Draw exactly that design, every part it names, unless this request changes an icon that is already there. \
        \(smallParts)
        """

    /// How small parts stay clean, for an icon drawn from a design or whole
    /// to be torn; an icon at rest plans without it.
    static let smallParts = """
        A line of 2 clogs anything small: a part under 4 across is one straight line or a solid shape with \
        stroke="none", never a small outline or a wiggle, and a curve bends once.
        """

    /// The body of the one call that designs the icon: no tools, no document.
    public static func designBody(model: String, request: String) -> AgentJSON {
        ["model": .string(model), "stream": false, "think": false, "keep_alive": "30m",
         "messages": [["role": "system", "content": .string("You design icons.\n\(AskConversation.iconRules)")],
                      ["role": "user", "content": .string("\(request)\n\n\(designAsk)")]],
         "options": ["temperature": 0, "num_predict": .number(Double(mostDesignTokens))]]
    }

    /// The design in `answer`, or nil when it holds none, which only costs
    /// the icon its head start.
    public static func design(fromAnswer answer: String) -> String? {
        let words = AskConversation.withoutThinking(answer).trimmingCharacters(in: .whitespacesAndNewlines)
        let atRest = words.lowercased().trimmingCharacters(in: .punctuationCharacters) == "at rest"
        return words.isEmpty || atRest || words.contains("<svg") ? nil : words
    }

    /// Whether `plan` draws an icon.
    public static func isIn(_ plan: AskPlan) -> Bool {
        plan.steps.contains { $0.tool == "add_drawing" && $0.arguments["icon"]?.boolValue == true }
    }

    /// The side a new picture needs for the first icon in `plan` that has no
    /// place of its own, or nil when nothing in it is such an icon.
    public static func side(of plan: AskPlan) -> CGFloat? {
        guard let step = plan.steps.first(where: {
            $0.tool == "add_drawing" && $0.arguments["icon"]?.boolValue == true && $0.arguments["frame"] == nil
        }) else { return nil }
        return step.arguments["side"]?.doubleValue.map { CGFloat($0) } ?? AgentDrawingPlacement.iconSide
    }

    /// What the icons already in the document look like, as a line for the
    /// model, or nil when it holds none. Read from the frames an icon is drawn
    /// in, and scaled to the 24 point grid the model draws on.
    public static func documentLook(_ read: String) -> String? {
        guard let json = try? AgentJSON.parse(Data(read.utf8)) else { return nil }
        var strokes: [(width: Double, ink: String)] = []
        var fills: [String] = []
        func walk(_ layers: [AgentJSON], side: Double?) {
            for layer in layers {
                var inside = side
                if layer["kind"]?.stringValue == "frame", let width = layer["frame"]?["width"]?.doubleValue,
                   width == layer["frame"]?["height"]?.doubleValue,
                   IconPreviews.isIconSize(CGSize(width: width, height: width)) {
                    inside = width
                }
                if let inside, let path = layer["path"] {
                    if let width = path["strokeWidth"]?.doubleValue, width > 0, let ink = path["stroke"]?.stringValue {
                        strokes.append((width * 24 / inside, ink))
                    } else if let fill = path["fill"]?.stringValue {
                        fills.append(fill)
                    }
                }
                walk(layer["children"]?.arrayValue ?? [], side: inside)
            }
        }
        walk(json["layers"]?.arrayValue ?? [], side: nil)
        if let line = strokes.first {
            let weight = (line.width * 2).rounded() / 2
            let shown = weight == weight.rounded() ? String(Int(weight)) : String(weight)
            return "This document's icons are outlines in \(line.ink), stroke-width \(shown) on the 24 grid: draw this one the same unless the request names another look."
        }
        if let fill = fills.first {
            return "This document's icons are filled shapes in \(fill): draw this one the same unless the request names another look."
        }
        return nil
    }
}

/// Whether what the model drew is an icon: read from the SVG before it lands,
/// and sent back with what to change. General rules of the craft, true of any
/// subject; nothing here knows what the icon is of.
public enum AskIconCheck {

    /// An icon is a few shapes. A traced picture is dozens.
    public static let mostParts = 12
    /// An app icon also has its tile.
    public static let mostPartsOnATile = 16
    /// After this many goes it lands as it is: a rough icon beats none.
    public static let mostSendBacks = 2
    /// A line under this share of the drawing is under a pixel at 16 px.
    static let thinnestLine: CGFloat = 1.0 / 20
    /// Line weights this close are one weight.
    static let sameWeight: CGFloat = 1.15
    /// An id that names the kind of shape, not the part it is.
    static let genericName = #"^(path|shape|layer|rect|rectangle|circle|ellipse|oval|line|group|polygon|polyline)[ _-]*\d*$"#

    public static func problems(_ art: SVGArtwork, look: AskIcon.Look?, appIcon: Bool) -> [String] {
        var said: [String] = []
        let box = art.bounds
        let side = max(box.width, box.height)
        guard side > 0 else { return said }
        if let view = art.viewBox, abs(view.width - view.height) > 0.01 {
            said.append("Its viewBox is not square.")
        }
        let most = appIcon ? mostPartsOnATile : mostParts
        if art.parts.count > most {
            said.append("It has \(art.parts.count) parts; an icon is a few simple shapes, \(most) at most.")
        }
        let nameless = art.parts.filter { part in
            guard let name = part.name else { return true }
            return name.lowercased().range(of: genericName, options: .regularExpression) != nil
        }
        if !nameless.isEmpty {
            said.append("Give every shape an id naming the part it is, not the kind of shape.")
        }
        let weights = art.parts.filter { $0.stroke != nil && $0.strokeWidth > 0 }.map(\.strokeWidth)
        if let thinnest = weights.min(), let thickest = weights.max() {
            if thickest / thinnest > sameWeight { said.append("Use one line weight on every line.") }
            if thinnest / side < thinnestLine { said.append("Its lines disappear at 16 px: make them heavier.") }
        }
        let radii = art.parts.compactMap { part -> CGFloat? in
            if case .rect(_, let radius) = part.shape, radius > 0 { return radius }
            return nil
        }
        if let least = radii.min(), let most = radii.max(), most / least > sameWeight, !appIcon {
            said.append("Use one corner radius on every box.")
        }
        if !appIcon, art.parts.contains(where: { ($0.fillPaint?.kind ?? .solid) != .solid }) {
            said.append("Use flat colour, no gradients.")
        }
        let inks = Set(art.parts.flatMap { part in [part.fill, part.stroke].compactMap { $0?.uppercased() } })
        if !appIcon, look != .duotone, inks.count > 3 {
            said.append("Use one colour, two or three at most.")
        }
        func big(_ part: SVGArtwork.Part) -> Bool {
            guard part.fill != nil else { return false }
            let own = SVGArtwork.shapeBounds(part.shape)
            return own.width * own.height >= (side / 3) * (side / 3)
        }
        switch look {
        case .outline? where art.parts.contains(where: big):
            said.append("An outline icon has no filled shapes: set fill=\"none\" and draw it with lines.")
        case .filled? where !art.parts.contains(where: big):
            said.append("A filled icon is solid shapes: fill them, not lines.")
        case .duotone? where inks.count != 2 && Set(art.parts.map(\.opacity)).count < 2:
            said.append("A duotone icon has two tones of one colour: a light one behind and a dark one in front.")
        default:
            break
        }
        return said
    }
}
