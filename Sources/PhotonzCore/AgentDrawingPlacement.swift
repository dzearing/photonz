import CoreGraphics
import Foundation

// add_drawing (`docs/design/ask.md`, "Drawing a thing"): a thing asked for by
// name lands as a clean drawing made of layers, painted for the request by the
// picture model on this Mac and traced (`Scripts/picture-model/`), or from an
// SVG the agent wrote (`SVGArtwork`). Nothing is looked up: no drawing is
// stored and no subject has code of its own. One call is the whole drawing,
// because a model writing one picture at once draws far better than one
// placing twenty shapes blind.

/// What an add_drawing call asks for.
public struct AgentDrawingCall: Hashable, Sendable {
    /// What it is, in a word or two: "dog", "coffee cup".
    public var subject: String
    /// The agent's own drawing; when it is given, nothing is painted.
    public var svg: String?
    /// Make an icon: a square icon frame with the drawing on its keylines.
    public var icon: Bool
    /// Where the drawing goes; centred on the canvas when nil.
    public var frame: CGRect?
    public var name: String?
    /// The look asked for, in the person's words: line art, silhouette,
    /// watercolor, flat. Nil when none was named.
    public var style: String?
    /// The person's own words, when Ask paints the drawing with a picture
    /// model: a subject shortened to "cat" still carries "curled up asleep".
    public var asked: String?
    /// A place or scene that fills the picture with its own sky and ground,
    /// as the planning model judged it; painted edge to edge.
    public var scene: Bool

    public init(subject: String, svg: String? = nil, icon: Bool = false, frame: CGRect? = nil,
                name: String? = nil, style: String? = nil, asked: String? = nil,
                scene: Bool = false) {
        self.style = style
        self.asked = asked
        self.scene = scene
        self.subject = subject
        self.svg = svg
        self.icon = icon
        self.frame = frame
        self.name = name
    }

    /// What the agent is told when the picture model is not there to paint
    /// it and it sent no SVG of its own.
    public static func needsSVG(_ subject: String) -> String {
        "add_drawing: Photonz cannot paint \(subject) on this Mac right now. Call add_drawing again with svg: your own drawing of it as one complete SVG."
    }

    /// The layer's name: the one asked for, else the subject as a person
    /// would write it ("smiley face" is "Smiley face").
    public var layerName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        let words = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = words.first else { return "Drawing" }
        return first.uppercased() + words.dropFirst()
    }
}

/// What the picture model on this Mac is asked to paint for an add_drawing
/// call (`Scripts/picture-model/server.py`): the subject, with the person's
/// words when they say more than it does, and the look they named. The
/// server adds the flat, traceable look itself.
public struct PictureModelRequest: Codable, Hashable, Sendable {
    public var subject: String
    public var style: String?
    /// An icon is painted as a bold glyph with little detail.
    public var icon: Bool
    /// A scene fills the picture edge to edge, its backdrop kept as layers.
    public var scene: Bool

    public init(_ call: AgentDrawingCall) {
        let subject = call.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let asked = (call.asked ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if asked.isEmpty || asked.lowercased() == subject.lowercased() {
            self.subject = subject
        } else {
            self.subject = "\(subject), from the request: \(asked)"
        }
        style = call.style
        icon = call.icon
        // The planning model's word, or the general words for a scene or a
        // time of day in what was asked ("at dusk", "a landscape").
        let words = Set(AgentDrawingWords.words([subject, asked, call.style ?? ""].joined(separator: " ")))
        scene = !call.icon && (call.scene || !words.isDisjoint(with: AgentDrawingWords.sceneWords))
    }
}

/// The words of a drawing request that say how it should look or that it is
/// a whole scene. They name looks, kinds of picture and times of day, never a
/// subject: what the picture is OF is the picture model's or the planning
/// model's to read, whatever it is.
public enum AgentDrawingWords {

    /// The words of `text`, lower case, apostrophes and punctuation gone.
    public static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Words that say a picture is a whole scene with its own sky or ground.
    public static let sceneWords: Set<String> = [
        "landscape", "scene", "scenery", "vista", "view", "panorama", "poster",
        "sunset", "sunrise", "dusk", "dawn", "twilight", "night",
    ]

    /// The words of a request that name a look, in the order typed: what Ask
    /// adds to an add_drawing call's style when the model left them out.
    public static func lookWords(in request: String) -> [String] {
        let typed = words(request)
        let joined = " " + typed.joined(separator: " ") + " "
        var found: [String] = []
        if joined.contains(" line art ") || joined.contains(" line drawing ") { found.append("line art") }
        let looks: Set<String> = ["illustration", "illustrated", "silhouette", "badge", "emblem", "flat", "minimal",
                                  "layered", "painted", "watercolor", "watercolour", "outline", "stencil", "cartoon",
                                  "sketch", "pixel", "isometric", "geometric", "retro", "vintage"]
        for word in typed where looks.contains(word) && !found.contains(word) { found.append(word) }
        return found
    }
}

/// Where a drawing lands and how big it is.
public enum AgentDrawingPlacement {
    /// How much of the canvas's shorter side a drawing with no box spans:
    /// big enough to be the picture, with room round it.
    public static let share: CGFloat = 0.6
    /// The side of an icon frame Ask makes: the biggest an icon frame is.
    public static let iconSide: CGFloat = IconPreviews.largestIconSide

    /// The box a drawing is fitted into: the one asked for, kept on the
    /// canvas (a model sometimes gives the canvas's centre as the corner), or
    /// the middle of the canvas when it named none or none of it is on it.
    public static func box(_ asked: CGRect?, on canvas: CGSize) -> CGRect {
        guard let asked else { return box(on: canvas) }
        let kept = asked.intersection(CGRect(origin: .zero, size: canvas))
        guard !kept.isNull, kept.width >= 16, kept.height >= 16 else { return box(on: canvas) }
        return kept
    }

    /// The box an illustration of `size` fills: fitted into the box asked
    /// for, or centred on the canvas at four fifths of it.
    public static func box(_ asked: CGRect?, fitting size: CGSize, on canvas: CGSize) -> CGRect {
        let room: CGRect
        // A box that is the whole canvas is a model's habit, not a choice:
        // an illustration that reaches every edge has no margin to sit in.
        let canvasArea = canvas.width * canvas.height
        if let asked, asked.width * asked.height < canvasArea * 0.85 {
            room = box(asked, on: canvas)
        } else {
            room = CGRect(x: canvas.width * 0.1, y: canvas.height * 0.1, width: canvas.width * 0.8, height: canvas.height * 0.8)
        }
        guard size.width > 0, size.height > 0 else { return room }
        let scale = min(room.width / size.width, room.height / size.height)
        let fitted = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return CGRect(x: (room.midX - fitted.width / 2).rounded(), y: (room.midY - fitted.height / 2).rounded(),
                      width: fitted.width, height: fitted.height)
    }

    /// The box a drawing fills when the call names none: a square in the
    /// middle of the canvas.
    public static func box(on canvas: CGSize) -> CGRect {
        let side = (min(canvas.width, canvas.height) * share).rounded()
        return CGRect(x: ((canvas.width - side) / 2).rounded(), y: ((canvas.height - side) / 2).rounded(),
                      width: side, height: side)
    }
}

extension PhotonzDocument {

    /// Adds `drawing` and answers the id of what it made: a group named
    /// `name`, or for an icon a square icon frame holding the parts. On a
    /// blank picture an icon's frame IS the picture: the canvas becomes the
    /// frame's square, which is how an icon is set up by hand.
    ///
    /// `blank` says the picture holds nothing anybody made: no layers, or
    /// only the flat locked background a new blank picture is. Only the app
    /// can tell a flat background from a screenshot, so it says; left out,
    /// only a picture with no layers at all is blank.
    @discardableResult
    public mutating func addDrawing(_ drawing: SVGArtwork, named name: String, icon: Bool, box: CGRect?,
                                    blank: Bool? = nil) -> UUID {
        if icon {
            let side = AgentDrawingPlacement.iconSide
            let size = CGSize(width: side, height: side)
            let origin: CGPoint
            if blank ?? layers.isEmpty {
                // The whole picture becomes the icon: its flat background is
                // squeezed to the square with it.
                resize(to: size)
                origin = .zero
            } else if let box {
                origin = box.origin
            } else if hasFrames {
                origin = placementForNewFrame(size: size, visible: CGRect(origin: .zero, size: canvasSize))
            } else {
                // Beside what is there, never over it.
                let used = layers.reduce(CGRect.null) { $0.union($1.localBounds) }
                origin = CGPoint(x: (used.maxX + Self.frameGutter).rounded(), y: max(0, used.minY).rounded())
            }
            let frame = drawing.iconFrame(named: name, side: side, origin: origin)
            addLayer(frame)
            growCanvas(toTakeIn: frame.frame)
            return frame.id
        }
        let group = drawing.group(named: name, fitting: AgentDrawingPlacement.box(box, on: canvasSize))
        addLayerOnFrame(group)
        return group.id
    }
}
