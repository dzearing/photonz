import CoreGraphics
import Foundation

// add_drawing (`docs/design/ask.md`, "Drawing a thing"): a thing asked for by
// name lands as a clean drawing made of layers, from the built-in drawing set
// (`DrawingLibrary`) or from an SVG the agent wrote (`SVGArtwork`). One call
// is the whole drawing, because a model writing one picture at once draws far
// better than one placing twenty shapes blind.

/// What an add_drawing call asks for.
public struct AgentDrawingCall: Hashable, Sendable {
    /// What it is, in a word or two: "dog", "coffee cup".
    public var subject: String
    /// The agent's own drawing, used when the set has none (or `builtIn` is off).
    public var svg: String?
    /// Make an icon: a square icon frame with the drawing on its keylines.
    public var icon: Bool
    /// Where the drawing goes; centred on the canvas when nil.
    public var frame: CGRect?
    public var name: String?
    /// Use the built-in drawing when the set has one.
    public var builtIn: Bool
    /// The look an illustration is drawn in, in the person's words: line
    /// art, silhouette, badge, sunset, flat, or just illustration.
    public var style: String?

    public init(subject: String, svg: String? = nil, icon: Bool = false, frame: CGRect? = nil,
                name: String? = nil, builtIn: Bool = true, style: String? = nil) {
        self.style = style
        self.subject = subject
        self.svg = svg
        self.icon = icon
        self.frame = frame
        self.name = name
        self.builtIn = builtIn
    }

    /// The illustration this asks for, or nil when it asks for a thing: a
    /// scene (mountains, a forest, a lighthouse, a skyline) or a named style
    /// is drawn by the illustrator (`Illustrator`), never by the model.
    public var illustration: IllustrationBrief? {
        IllustrationBrief.make(subject: subject, style: style, icon: icon)
    }

    /// What the agent is told when the set has no drawing of the thing and it
    /// sent no SVG of its own.
    public static func noBuiltIn(_ subject: String) -> String {
        "add_drawing: Photonz has no drawing of \(subject). Call add_drawing again with svg: your own drawing of it as one complete SVG."
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
