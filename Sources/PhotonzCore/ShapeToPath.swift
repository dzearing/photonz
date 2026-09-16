import CoreGraphics
import Foundation

/// Turning a box, an oval or a line into a path, so every point on it becomes
/// yours to move, curve or delete (`docs/design/vector-paths.md`).
///
/// A rectangle is a fixed thing: you can resize it, but you cannot take one
/// corner and pull it somewhere else. This is the one step that stops it being
/// a rectangle and makes it an outline, keeping EXACTLY the look it had, so the
/// ordinary way to draw an icon — rough it out with the shape tools, then pull
/// the points about — works.
///
/// Everything here is geometry on a value. Nothing draws.
public enum ShapeToPath {

    /// How far a quarter circle's handles reach, as a fraction of the radius.
    ///
    /// A quarter circle cannot be written exactly as a cubic, so every drawing
    /// program in the world uses the same approximation: put each handle
    /// `4/3 × (√2 − 1)` of the radius along the tangent, and the curve is out
    /// by about 0.027% of the radius at its worst, which on an 80 point circle
    /// is two hundredths of a point.
    ///
    /// This exact number is what Core Graphics itself draws a rounded rectangle
    /// and an ellipse with: `CGPath(roundedRect:)`, `CGPath(ellipseIn:)` and
    /// `CGPath.addArc(tangent1End:…)` all agree with it to the BIT, measured on
    /// rendered pixels at radius 8, 20 and 60 and on a 180 × 120 oval. That is
    /// what lets a shape survive this conversion pixel for pixel instead of
    /// almost.
    public static let circleHandle: CGFloat = 4.0 / 3.0 * (2.0.squareRoot() - 1)
}

// MARK: - The three outlines

extension PathContent {

    /// The outline of a rectangle, clockwise from its top left corner, in the
    /// same top-left space the shape's own numbers are stated in.
    ///
    /// A square corner is ONE anchor with no handles, so a plain box is four
    /// points and not eight zero-length levers. A round one is two, joined by a
    /// quarter circle, each straight on its far side: a point a straight edge
    /// arrives at and a curve leaves from, which is exactly what a rounded
    /// corner is.
    public static func rectangle(in box: CGRect, radii: CornerRadii = .none) -> PathContent {
        let box = box.standardized
        let radii = radii.fitted(in: box.size)
        var anchors: [PathAnchor] = []

        /// One corner: the point it turns about, the way the outline ARRIVES
        /// there, and the way it LEAVES. A radius of nought is the corner
        /// itself and nothing else.
        func corner(at point: CGPoint, arriving: CGPoint, leaving: CGPoint, radius: CGFloat) {
            guard radius > 0 else {
                anchors.append(PathAnchor(point: point))
                return
            }
            let lever = ShapeToPath.circleHandle * radius
            let start = CGPoint(x: point.x - arriving.x * radius, y: point.y - arriving.y * radius)
            let end = CGPoint(x: point.x + leaving.x * radius, y: point.y + leaving.y * radius)
            anchors.append(PathAnchor(point: start,
                                      handleOut: CGPoint(x: arriving.x * lever, y: arriving.y * lever)))
            anchors.append(PathAnchor(point: end,
                                      handleIn: CGPoint(x: -leaving.x * lever, y: -leaving.y * lever)))
        }

        // Clockwise, in a space where Y grows downwards: right along the top,
        // down the right-hand side, left along the foot, up the left-hand side.
        // The list starts just PAST the top left corner so the closing run is
        // that corner's own curve, exactly as `CornerRadii.path` draws it.
        let up = CGPoint(x: 0, y: -1), right = CGPoint(x: 1, y: 0)
        let down = CGPoint(x: 0, y: 1), left = CGPoint(x: -1, y: 0)
        corner(at: CGPoint(x: box.minX, y: box.minY), arriving: up, leaving: right,
               radius: radii.topLeft)
        // The top left corner's NEAR half belongs at the end of the list, so
        // the outline starts where that corner's curve finishes and the closing
        // run is the curve itself. A square corner is one anchor and is simply
        // the place the outline starts.
        let topLeft = anchors
        anchors = []
        corner(at: CGPoint(x: box.maxX, y: box.minY), arriving: right, leaving: down,
               radius: radii.topRight)
        corner(at: CGPoint(x: box.maxX, y: box.maxY), arriving: down, leaving: left,
               radius: radii.bottomRight)
        corner(at: CGPoint(x: box.minX, y: box.maxY), arriving: left, leaving: up,
               radius: radii.bottomLeft)
        let opens = topLeft.count > 1 ? [topLeft[1]] : topLeft
        let closes = topLeft.count > 1 ? [topLeft[0]] : []
        return PathContent(anchors: opens + anchors + closes, isClosed: true)
    }

    /// The outline of an oval inscribed in `box`: four smooth points on its
    /// compass points, clockwise from the top.
    ///
    /// Each point's handles run along that point's own tangent, and are
    /// `circleHandle` of the radius ON THAT AXIS — half the width across the
    /// top and the foot, half the height at the two sides. Taking one number
    /// for both is the mistake that turns a wide oval into a lozenge.
    public static func ellipse(in box: CGRect) -> PathContent {
        let box = box.standardized
        let across = box.width / 2 * ShapeToPath.circleHandle
        let down = box.height / 2 * ShapeToPath.circleHandle
        let anchors = [
            PathAnchor(point: CGPoint(x: box.midX, y: box.minY),
                       handleIn: CGPoint(x: -across, y: 0), handleOut: CGPoint(x: across, y: 0),
                       kind: .smooth),
            PathAnchor(point: CGPoint(x: box.maxX, y: box.midY),
                       handleIn: CGPoint(x: 0, y: -down), handleOut: CGPoint(x: 0, y: down),
                       kind: .smooth),
            PathAnchor(point: CGPoint(x: box.midX, y: box.maxY),
                       handleIn: CGPoint(x: across, y: 0), handleOut: CGPoint(x: -across, y: 0),
                       kind: .smooth),
            PathAnchor(point: CGPoint(x: box.minX, y: box.midY),
                       handleIn: CGPoint(x: 0, y: down), handleOut: CGPoint(x: 0, y: -down),
                       kind: .smooth)
        ]
        return PathContent(anchors: anchors, isClosed: true)
    }

    /// An open path of two points: what a line becomes.
    public static func line(from start: CGPoint, to end: CGPoint) -> PathContent {
        PathContent(anchors: [PathAnchor(point: start), PathAnchor(point: end)], isClosed: false)
    }
}

// MARK: - What each shape becomes

extension AnnotationContent {

    /// Whether this mark has an OUTLINE that a path could be.
    ///
    /// A box, an oval and a line do: what you see is a shape drawn along a
    /// line, and that line is what a path holds.
    ///
    /// A HIGHLIGHT does too, and it was left out at first for a reason that
    /// turned out not to hold. A wash is a filled box, and the thing that makes
    /// it a highlighter rather than a coloured slab is that it MIXES with what
    /// is under it. That mixing is not lost by becoming a path: it is carried
    /// into the layer's own Blending (`Layer.turnedIntoPath`), where the
    /// picture is identical and it can now be changed rather than only obeyed.
    /// What it buys is a wash that is not stuck being a rectangle, so a run of
    /// words that wraps, or a panel with a notch in it, can be highlighted in
    /// one mark.
    ///
    /// An ARROW does not, and this is the one worth saying out loud. Its head
    /// is part of how it is DRAWN rather than part of its outline: the shaft is
    /// a stroke and the tip is a solid triangle sized off the stroke, so a path
    /// of it would either arrive with no head at all or be one closed
    /// silhouette of the whole arrow, whose points sit on the outside of a
    /// shape nobody thinks of as an outline. Three of its four heads (the open
    /// chevron and the two dots) are separate contours, and a path holds ONE,
    /// so for those the picture could not survive the turn at all. It keeps
    /// "Turn Into Picture", which is the honest answer for a mark whose look is
    /// how it is painted.
    public var turnsIntoAPath: Bool {
        switch shape {
        case .rectangle, .ellipse, .line, .highlight: return true
        case .arrow: return false
        }
    }

    /// The box this shape is drawn in, in the layer's own coordinates.
    var drawnBox: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// This shape written out as a path, wearing the same paints.
    ///
    /// The outline traced is the shape's own BOX, and the stroke keeps the side
    /// of it that it was on, so the picture does not move. A rounded box hands
    /// over the curve you can SEE rather than the number in the panel — those
    /// two part company by half a line width when the stroke is not centred,
    /// and `boxCornerRadii` is the same answer every ring round the shape
    /// already follows.
    public func asPath() -> PathContent? {
        guard turnsIntoAPath else { return nil }
        let box = drawnBox
        switch shape {
        case .rectangle:
            var path = PathContent.rectangle(in: box, radii: boxCornerRadii(in: box.size))
            wear(&path)
            return path
        case .ellipse:
            var path = PathContent.ellipse(in: box)
            wear(&path)
            return path
        case .line:
            var path = PathContent.line(from: start, to: end)
            path.paint = paint
            path.strokeWidth = strokeWidth
            path.strokePosition = .center
            // A line has no inside, so it arrives with no fill rather than with
            // one that would never be painted.
            path.fill = nil
            return path
        case .highlight:
            // A wash is ink and nothing else: the rasterizer fills its box and
            // never draws a line round it at any width. So the path is that
            // box, painted INSIDE in the wash's own colour, with no line on it
            // — one that carried the stroke width a highlight happens to store
            // would grow an edge the wash never had.
            var path = PathContent.rectangle(in: box, radii: .none)
            path.paint = paint
            path.strokeWidth = 0
            path.strokePosition = .center
            path.fill = paint
            return path
        case .arrow:
            return nil
        }
    }

    /// The two paints and the line a closed shape carries across.
    ///
    /// The stroke is nearly always nought: a box's edge became a Border in the
    /// Effects list when the Outline row left Appearance
    /// (`OutlineRetirement.swift`), and that border stays exactly where it is,
    /// still a row you can retune. It is carried anyway so a shape built in
    /// code with a stroke of its own converts to the same picture.
    private func wear(_ path: inout PathContent) {
        path.paint = paint
        path.strokeWidth = strokeWidth
        path.strokePosition = strokePosition
        path.fill = fill
    }
}

// MARK: - The layer

extension Layer {

    /// Whether "Turn Into Path" applies: this layer is a box, an oval or a
    /// line, so it has an outline a path could be.
    ///
    /// Everything else is unavailable rather than silently doing nothing. A
    /// path already IS one, a picture has no outline to find, and an arrow and
    /// a highlight are marks rather than shapes (`turnsIntoAPath`).
    public var canTurnIntoPath: Bool { annotation?.turnsIntoAPath ?? false }

    /// The same layer with its shape written out as a path, or nil where there
    /// is nothing to turn.
    ///
    /// It keeps its id, its name, its slot, its style, its effects and its
    /// transform: the only thing that changes is what the layer is MADE of. The
    /// box is put back round the outline afterwards, which matters for a line:
    /// a line's frame is padded so its round caps have somewhere to be drawn,
    /// and a path pads itself, so the two pads would otherwise stack up.
    public func turnedIntoPath() -> Layer? {
        guard let annotation, annotation.turnsIntoAPath,
              let content = annotation.asPath() else { return nil }
        var turned = self
        turned.content = .path(content)
        // A highlighter mixes with what is under it because of what it IS, not
        // because of anything its style says (`mixingIsFixed`). The instant it
        // stops being a highlight mark nothing is forcing that any more, so the
        // mixing moves into the style it now carries: same picture, and from
        // here on it is a setting rather than a rule.
        if mixingIsFixed { turned.style.blendMode = effectiveBlendMode }
        return PathBuilder.refit(turned, content: content)
    }
}

// MARK: - The question it asks first

/// The question asked before a shape becomes a path.
///
/// It asks for the same reason `RasterizePrompt` does: what the command takes
/// away is invisible. The instant after, the picture is identical — same
/// outline, same colour, same place — and what is gone is that it was a
/// RECTANGLE: the Corner Radius control has nothing left to act on, because
/// there is no longer a corner, only eight points that happen to sit where one
/// was. A person who reaches for that control a week later has lost the number
/// they typed. One sentence up front is the whole difference, and "Don't ask
/// again" is there so it costs nothing after the first time
/// (`SilencedQuestions`).
///
/// Pure copy: it holds no layer and touches no document, so the words can be
/// read in a test without an app around them.
public struct TurnIntoPathPrompt: Hashable, Sendable {

    /// What the layer is, in the noun a person would use for it, because what
    /// changes is different: a box loses its corner radius, an oval loses
    /// nothing but the promise of being round, a line loses being two points
    /// you drag by the ends, and a highlighter keeps its mixing but stops
    /// being forced into it.
    public enum Subject: Hashable, Sendable {
        case rectangle
        case ellipse
        case line
        case highlight
    }

    /// The name the layer wears in the layers panel, so the question is about
    /// the thing they picked rather than about "a layer". Empty when it has
    /// none.
    public var name: String
    public var subject: Subject

    public init(name: String, subject: Subject) {
        self.name = name
        self.subject = subject
    }

    /// The question this layer would raise, or nil when there is nothing to
    /// turn. The yes/no half is `Layer.canTurnIntoPath` and nothing else, so
    /// the question can never appear over a layer the command would refuse.
    public init?(layer: Layer) {
        guard layer.canTurnIntoPath, let shape = layer.annotation?.shape else { return nil }
        switch shape {
        case .rectangle: self.init(name: layer.name, subject: .rectangle)
        case .ellipse: self.init(name: layer.name, subject: .ellipse)
        case .line: self.init(name: layer.name, subject: .line)
        case .highlight: self.init(name: layer.name, subject: .highlight)
        case .arrow: return nil
        }
    }

    /// What the menu row says, in both the Layer menu and the layer's own row
    /// menu. The ellipsis is the macOS promise that a question comes next.
    public static let menuItem = "Turn Into Path\u{2026}"

    /// The checkbox on the question. The same words "Turn Into Picture" wears,
    /// so it reads as the same control it is everywhere else.
    public static let suppression = RasterizePrompt.suppression

    private var noun: String {
        switch subject {
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        case .line: return "line"
        case .highlight: return "highlight"
        }
    }

    /// The question itself, naming the layer when it has a name.
    public var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Turn this \(noun) into a path?" }
        return "Turn \u{201C}\(trimmed)\u{201D} into a path?"
    }

    /// Why you would say yes, then what it costs, then the way back. In that
    /// order: the gain is what they came for, and the cost is the part they
    /// cannot see.
    public var message: String {
        let lost: String
        switch subject {
        case .rectangle:
            lost = "It stops being a rectangle, so the Corner Radius control goes"
        case .ellipse:
            lost = "It stops being an ellipse, so dragging it will no longer keep it oval"
        case .line:
            lost = "It stops being a line, so it no longer has two ends to drag"
        case .highlight:
            lost = "It goes on mixing with what is under it, but as a setting "
                + "under Blending rather than a rule, so it can be turned off"
        }
        return "Every point on it becomes yours to move, curve or delete. "
            + "\(lost). Undo puts it back."
    }

    /// The button, carrying the verb: a person reading only the buttons still
    /// knows which one does the thing.
    public var confirm: String { "Turn Into Path" }

    public var cancel: String { "Cancel" }
}
